// 卡片数据的纯函数构建：主应用推送与卡片扩展渲染共用同一套取舍规则。
// 这里只做字符串、数字与字符串数组的扁平化输出，卡片侧不解析业务模型。
import { AppData, Task } from '../model/PlanerModel';
import { formatFull, formatMonthDay, formatRange, todayKey, taskDelayText } from '../model/PlanerEngine';
import { Palette, paletteFor } from '../theme/Theme';
import { CardGradient, cardGradient, cardSecondaryColor } from '../theme/CardAppearance';

export enum CardSize {
  SMALL = 'small',
  MEDIUM = 'medium',
  LARGE = 'large'
}

// 三种规格同时可见的条目数（小卡三条、中卡四条、大卡八条）；列表可滚动，总条数不截断。
export function visibleTaskCount(size: CardSize): number {
  if (size === CardSize.LARGE) return 8;
  if (size === CardSize.MEDIUM) return 4;
  return 3;
}

// form_config 的尺寸字符串按“行*列”书写；列数决定信息量档位。
export function cardSizeForDimension(dimension: string): CardSize {
  if (dimension === '4*4' || dimension === '6*4') return CardSize.LARGE;
  if (dimension === '2*4' || dimension === '2*3' || dimension === '3*3') return CardSize.MEDIUM;
  return CardSize.SMALL;
}

// 拖拽改尺寸后按卡片实际几何重新取档，避免沿用添加时的旧规格。
export function cardSizeForRect(width: number, height: number): CardSize {
  if (height > 200) return CardSize.LARGE;
  if (width > 260) return CardSize.MEDIUM;
  return CardSize.SMALL;
}

function metaFor(task: Task, showGroups: boolean): string {
  if (task.completed) return '已完成';
  const parts: string[] = [];
  if (showGroups && task.group) parts.push(task.group);
  if (task.progress !== null) parts.push(task.progress.toString() + '%');
  return parts.join(' · ');
}

// 兼容旧卡片缓存的单色回退，新卡片使用下发的主题渐变；不使用系统模糊赋色。
function panelColor(palette: Palette, dark: boolean): string {
  return (dark ? '#EB' : '#F2') + palette.panel.substring(1);
}

export function buildCardData(data: AppData, size: CardSize, dark: boolean): Record<string, Object> {
  const palette: Palette = paletteFor(data.settings.colorPreset, dark);
  const tasks: Task[] = data.todayTasks;
  const total: number = tasks.length;
  const done: number = tasks.filter((task: Task): boolean => task.completed).length;
  const pendingCount: number = total - done;
  const isToday: boolean = data.currentDate === todayKey();
  const ids: string[] = [];
  const texts: string[] = [];
  const metas: string[] = [];
  const marks: string[] = [];
  const delays: string[] = [];
  // 保持用户既有排序：勾选完成后条目留在原位，不重排到末尾。
  // 卡片列表可滚动，因此不再按尺寸截断条数。
  tasks.forEach((task: Task): void => {
    ids.push(task.id);
    texts.push(task.text);
    const meta = metaFor(task, data.settings.showGroups);
    const delay = taskDelayText(task, todayKey(), todayKey());
    delays.push(delay);
    metas.push([delay, meta].filter((text: string): boolean => text.length > 0).join(' · '));
    marks.push(task.completed ? '1' : '0');
  });

  // 未来日程：大卡直接展示条目（含起止日期），其余尺寸只用汇总数字。
  const futureIds: string[] = [];
  const futureTexts: string[] = [];
  const futureRanges: string[] = [];
  const futureMarks: string[] = [];
  data.futureTasks.forEach((task: Task): void => {
    futureIds.push(task.id);
    futureTexts.push(task.text);
    futureMarks.push(task.completed ? '1' : '0');
    // formatRange 在有起始日期时输出“起-止”，否则只给截止日；都没有则标注未排期。
    const range: string = formatRange(task.startDate, task.dueDate);
    futureRanges.push(range.length > 0 ? range : '未排期');
  });

  let headline: string = '';
  if (total === 0) headline = isToday ? '今天还没有日程' : '该日还没有日程';
  else if (pendingCount === 0) headline = '日程已全部完成';
  else headline = (isToday ? '今天还有 ' : '还有 ') + pendingCount.toString() + ' 项待完成';

  const payload: Record<string, Object> = {};
  payload['size'] = size as string;
  payload['dateText'] = formatFull(data.currentDate);
  payload['headline'] = headline;
  payload['doneText'] = done.toString() + ' / ' + total.toString();
  payload['total'] = total;
  payload['done'] = done;
  payload['progress'] = total === 0 ? 0 : Math.round(done * 100 / total);
  payload['ids'] = ids;
  payload['texts'] = texts;
  payload['metas'] = metas;
  payload['marks'] = marks;
  payload['delays'] = delays;
  payload['futureCount'] = data.futureTasks.length;
  payload['futureIds'] = futureIds;
  payload['futureTexts'] = futureTexts;
  payload['futureRanges'] = futureRanges;
  payload['futureMarks'] = futureMarks;
  payload['retainCompletedFutureUntilDue'] = data.settings.retainCompletedFutureUntilDue;
  payload['futureText'] = data.futureTasks.length > 0 ?
    '未来 ' + data.futureTasks.length.toString() + ' 项' : '未来暂无安排';
  payload['cPanel'] = panelColor(palette, dark);
  const gradient: CardGradient = cardGradient(palette, dark);
  payload['cGradientStart'] = gradient.start;
  payload['cGradientMiddle'] = gradient.middle;
  payload['cGradientEnd'] = gradient.end;
  payload['cText'] = palette.text;
  payload['cSoft'] = cardSecondaryColor(palette, dark);
  payload['cFaint'] = palette.textFaint;
  payload['cAccent'] = palette.accent;
  payload['cAccentSoft'] = palette.accentSoft;
  payload['cSuccess'] = palette.success;
  payload['cBorder'] = palette.border;
  payload['isDark'] = dark;
  // 跟随系统时卡片改用 dark 资源目录自适应取色：卡片渲染进程在系统深浅切换时自动换色，
  // 不依赖提供方进程存活；静态色值仅在手写浅色 / 深色模式下使用。
  payload['followSystem'] = data.settings.themeMode === 'system';
  payload['preset'] = data.settings.colorPreset;
  return payload;
}
