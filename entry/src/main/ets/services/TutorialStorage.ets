import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { normalizeTutorial, TutorialProgress } from '../tutorial/TutorialConfig';

// 首次使用标记独立于日程数据；串行写入，失败可重试。
export class TutorialStorage {
  private store: preferences.Preferences | undefined = undefined;
  private pending: Promise<void> = Promise.resolve();

  async load(context: common.UIAbilityContext): Promise<TutorialProgress> {
    try {
      const store = await preferences.getPreferences(context, { name: 'planer_tutorial' });
      const value = await store.get('progress', '');
      let progress = new TutorialProgress();
      if (typeof value === 'string' && value.length > 0) {
        try { progress = normalizeTutorial(JSON.parse(value) as TutorialProgress); }
        catch (error) { console.warn('教程进度格式失效，从开头重新引导。'); }
      }
      this.store = store;
      return progress;
    } catch (error) {
      throw new Error('读取教程进度失败：' + String(error));
    }
  }

  async save(progress: TutorialProgress): Promise<void> {
    const store = this.store;
    if (!store) throw new Error('教程存储尚未就绪');
    const serialized = JSON.stringify(normalizeTutorial(progress));
    const operation = this.pending.then(async (): Promise<void> => {
      await store.put('progress', serialized);
      await store.flush();
    });
    this.pending = operation.catch((): void => {});
    await operation;
  }
}
