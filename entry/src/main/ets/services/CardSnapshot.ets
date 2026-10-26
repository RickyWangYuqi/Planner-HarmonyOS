// 卡片侧的只读快照：直接读取应用沙箱的 data.json，不写回、不加锁。
// 卡片扩展与主应用同属一个应用沙箱，读取失败时回落到空数据，避免展示过期内容。
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { AppAction, AppData } from '../model/PlanerModel';
import { freshData, normalizeData, reduce, todayKey, realDateOf } from '../model/PlanerEngine';

export class CardSnapshot {
  static load(context: common.Context): AppData {
    const dataPath = context.filesDir + '/data.json';
    try {
      if (!fileIo.accessSync(dataPath)) return freshData();
      const text = fileIo.readTextSync(dataPath);
      const raw = JSON.parse(text) as AppData;
      if (!raw || raw.version !== 1) return freshData();
      return CardSnapshot.alignToToday(normalizeData(raw));
    } catch (error) {
      console.warn('卡片读取日程失败：' + String(error));
      return freshData();
    }
  }

  // 应用长时间未打开时，卡片按同一套日期规则在内存中顺延到真实今天：
  // 已完成归档、未完成顺延、到期未来日程进入当日，与用户下次打开应用看到的一致。
  private static alignToToday(data: AppData): AppData {
    const today: string = todayKey();
    let next = data;
    if (today > realDateOf(data)) {
      const action = new AppAction('ROLLOVER_TO');
      action.key = today;
      next = reduce(data, action);
    }
    if (next.currentDate !== today) {
      const select = new AppAction('SELECT_DATE');
      select.key = today;
      next = reduce(next, select);
    }
    return next;
  }
}
