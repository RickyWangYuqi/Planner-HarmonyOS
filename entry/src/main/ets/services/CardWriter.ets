// 卡片内的状态操作：卡片点按勾选后由卡片扩展写回同一份 data.json。
// 写入沿用应用内存储的原子替换策略（独立临时文件 → 校验 → 替换 → 保留备份），
// 主应用回到前台时会检测到文件变化并采纳，避免两处状态长期分叉。
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { AppAction, AppData, Task } from '../model/PlanerModel';
import { reduce } from '../model/PlanerEngine';
import { CardSnapshot } from './CardSnapshot';

export class CardWriter {
  // 当日勾选与主应用共用 reducer。
  static async toggleToday(context: common.Context, id: string): Promise<boolean> {
    const data: AppData = CardSnapshot.load(context);
    const task: Task | undefined = data.todayTasks.find((item: Task): boolean => item.id === id);
    if (!task) return false;
    const action = new AppAction('TOGGLE_TODAY');
    action.id = id;
    const next: AppData = reduce(data, action);
    await CardWriter.write(context.filesDir + '/data.json', next);
    return true;
  }

  // 未来日程完成 / 取消均由共享 reducer 决定是否保留，读取同一份持久化设置。
  static async completeFuture(context: common.Context, id: string): Promise<boolean> {
    const data: AppData = CardSnapshot.load(context);
    const task: Task | undefined = data.futureTasks.find((item: Task): boolean => item.id === id);
    if (!task) return false;
    const action = new AppAction('COMPLETE_FUTURE');
    action.id = id;
    const next: AppData = reduce(data, action);
    await CardWriter.write(context.filesDir + '/data.json', next);
    return true;
  }

  private static async write(dataPath: string, data: AppData): Promise<void> {
    const serialized: string = JSON.stringify(data);
    // 独立临时文件，避免与主应用正在进行的 .tmp 写入互相覆盖。
    const temporaryPath: string = dataPath + '.card.tmp';
    let temporaryFile: fileIo.File | null = null;
    try {
      temporaryFile = await fileIo.open(temporaryPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      await fileIo.write(temporaryFile.fd, serialized);
      await fileIo.fsync(temporaryFile.fd);
      await fileIo.close(temporaryFile);
      temporaryFile = null;
      if (await fileIo.readText(temporaryPath) !== serialized) {
        throw new Error('卡片写入未完整落盘');
      }
      if (await fileIo.access(dataPath)) {
        const backupTemporaryPath: string = dataPath + '.bak.tmp';
        await fileIo.copyFile(dataPath, backupTemporaryPath);
        await fileIo.rename(backupTemporaryPath, dataPath + '.bak');
      }
      await fileIo.rename(temporaryPath, dataPath);
    } catch (error) {
      if (temporaryFile !== null) {
        try {
          await fileIo.close(temporaryFile);
        } catch (closeError) {
          console.error('关闭卡片临时文件失败：' + String(closeError));
        }
      }
      throw new Error('卡片勾选写入失败：' + String(error));
    }
  }
}
