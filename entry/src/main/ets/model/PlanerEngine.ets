// 纯业务状态转换：所有变更先复制数据，界面与持久化共享同一套规则。
import { AppAction, AppData, HistoryEntry, Settings, Task } from './PlanerModel';
import { applyCheckInAction, normalizeCheckIns, skipCheckInTask, syncCheckInCompletion, syncCheckIns } from './CheckInEngine';
import { CheckInItem, CheckInRecord } from './CheckInModel';

export function toKey(date: Date): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

export function todayKey(): string {
  return toKey(new Date());
}

export function fromKey(key: string): Date {
  const pieces = key.split('-');
  return new Date(Number(pieces[0]), Number(pieces[1]) - 1, Number(pieces[2]));
}

export function addDays(key: string, count: number): string {
  const date = fromKey(key);
  date.setDate(date.getDate() + count);
  return toKey(date);
}

export function compareKeys(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}

export function formatMonthDay(key: string): string {
  const date = fromKey(key);
  return `${date.getMonth() + 1}月${date.getDate()}日`;
}

export function formatFull(key: string): string {
  const weekdays: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  return `${formatMonthDay(key)} · ${weekdays[fromKey(key).getDay()]}`;
}

export function formatRange(startDate: string | null, dueDate: string | null): string {
  if (!dueDate) return '';
  return startDate && startDate !== dueDate
    ? `${formatMonthDay(startDate)}-${formatMonthDay(dueDate)}` : formatMonthDay(dueDate);
}

// 业务时钟不随日历预览前进；缺少新字段的旧数据从安全日期迁移。
export function realDateOf(data: AppData): string {
  return data.lastRolloverDate || data.currentDate;
}

function calendarDays(from: string, to: string): number {
  const a = from.split('-');
  const b = to.split('-');
  return Math.max(0, Math.floor((Date.UTC(Number(b[0]), Number(b[1]) - 1, Number(b[2])) -
    Date.UTC(Number(a[0]), Number(a[1]) - 1, Number(a[2]))) / 86400000));
}

export function taskDelayText(task: Task, viewedDate: string, realDate: string): string {
  if (task.completed || !viewedDate || !realDate) return '';
  const scheduled = task.scheduledDate || task.dueDate;
  if (!scheduled) return '';
  const actual = calendarDays(scheduled, realDate);
  if (actual > 0) return '延期 ' + actual.toString() + ' 天';
  const preview = calendarDays(scheduled, viewedDate);
  return viewedDate > realDate && preview > 0 ? '预计延期 ' + preview.toString() + ' 天' : '';
}

export function freshData(): AppData {
  const data = new AppData();
  data.currentDate = todayKey();
  return data;
}

function addTaskGroups(data: AppData): void {
  data.todayTasks.concat(data.futureTasks).forEach((task: Task): void => {
    if (task.group && !data.groups.includes(task.group)) data.groups.push(task.group);
  });
}

export function normalizeData(raw: AppData): AppData {
  const data = freshData();
  if (!raw) return data;
  data.version = typeof raw.version === 'number' ? raw.version : 1;
  data.currentDate = typeof raw.currentDate === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(raw.currentDate)
    ? raw.currentDate : todayKey();
  data.lastRolloverDate = typeof raw.lastRolloverDate === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(raw.lastRolloverDate) ? raw.lastRolloverDate : (data.currentDate < todayKey() ? data.currentDate : todayKey());
  data.todayTasks = Array.isArray(raw.todayTasks) ? raw.todayTasks.map((task: Task): Task => Task.copy(task)) : [];
  data.futureTasks = Array.isArray(raw.futureTasks) ? raw.futureTasks.map((task: Task): Task => Task.copy(task)) : [];
  data.todayTasks.forEach((task: Task): void => {
    if (!task.scheduledDate) task.scheduledDate = task.dueDate && task.dueDate <= data.lastRolloverDate ? task.dueDate : data.lastRolloverDate;
  });
  data.futureTasks.forEach((task: Task): void => {
    if (!task.scheduledDate) task.scheduledDate = task.dueDate;
  });
  data.settings = Settings.copy(raw.settings);
  data.todayAnchorId = typeof raw.todayAnchorId === 'string' ? raw.todayAnchorId : null;
  if (Array.isArray(raw.groups)) {
    raw.groups.forEach((group: string): void => {
      if (typeof group === 'string' && group.trim() && !data.groups.includes(group.trim())) data.groups.push(group.trim());
    });
  }
  if (Array.isArray(raw.history)) {
    raw.history.forEach((entry: HistoryEntry): void => {
      if (entry.date && Array.isArray(entry.tasks) && entry.tasks.length > 0) {
        const copy = new HistoryEntry();
        copy.date = entry.date;
        copy.tasks = entry.tasks.map((task: Task): Task => Task.copy(task));
        data.history.push(copy);
      }
    });
  }
  normalizeCheckIns(data, raw);
  // 历史不参与分组目录迁移，避免已删除的标签在重启后复活。
  addTaskGroups(data);
  return settle(data);
}

export function settleGroupList(tasks: Task[]): Task[] {
  let previous: string = '\u0000';
  const seen: string[] = [];
  const rightIndices = new Map<string, number>();
  let duplicate: boolean = false;
  tasks.forEach((task: Task, index: number): void => {
    const group: string = task.group || '';
    if (group !== previous) {
      if (seen.includes(group)) duplicate = true;
      else seen.push(group);
      previous = group;
    }
    rightIndices.set(group, index);
  });
  if (!duplicate) return tasks;
  seen.sort((left: string, right: string): number => (rightIndices.get(left) || 0) - (rightIndices.get(right) || 0));
  let result: Task[] = [];
  seen.forEach((group: string): void => {
    result = result.concat(tasks.filter((task: Task): boolean => (task.group || '') === group));
  });
  return result;
}

function settle(data: AppData): AppData {
  addTaskGroups(data);
  if (data.settings.showGroups) {
    data.todayTasks = settleGroupList(data.todayTasks);
    data.futureTasks = settleGroupList(data.futureTasks);
  }
  return data;
}

function insertFuture(data: AppData, task: Task): void {
  const due = task.dueDate || '';
  const position = data.futureTasks.findIndex((other: Task): boolean => (other.dueDate || '') > due);
  data.futureTasks.splice(position < 0 ? data.futureTasks.length : position, 0, task);
}

function archive(data: AppData, date: string, task: Task): void {
  let entry = data.history.find((item: HistoryEntry): boolean => item.date === date);
  if (!entry) {
    entry = new HistoryEntry();
    entry.date = date;
    data.history.push(entry);
  }
  entry.tasks.push(task);
}

function removeHistory(data: AppData, date: string, id: string): void {
  data.history.forEach((entry: HistoryEntry): void => {
    if (entry.date === date) entry.tasks = entry.tasks.filter((task: Task): boolean => task.id !== id);
  });
  data.history = data.history.filter((entry: HistoryEntry): boolean => entry.tasks.length > 0);
}

// 保留完成时间，按截止日归入历史；未开启保留时沿用点击当天立即归档。
function archiveFuture(data: AppData, task: Task, date: string, timestamp: string): void {
  task.plannedDate = task.dueDate || data.currentDate;
  task.archivedAt = timestamp;
  data.futureTasks = data.futureTasks.filter((item: Task): boolean => item.id !== task.id);
  archive(data, date, task);
}

function rollover(data: AppData, target: string): void {
  const previous = realDateOf(data);
  if (target <= previous) return;
  const now = new Date().toISOString();
  const completed = data.todayTasks.filter((task: Task): boolean => task.completed &&
    (task.completedDate || previous) < target);
  completed.forEach((task: Task): void => {
    const day = task.completedDate || previous;
    task.plannedDate = task.scheduledDate || day;
    task.archivedAt = now;
    archive(data, day, task);
  });
  data.todayTasks = data.todayTasks.filter((task: Task): boolean => !completed.includes(task));
  if (data.settings.retainCompletedFutureUntilDue) {
    data.futureTasks.filter((task: Task): boolean => task.completed && !!task.dueDate && task.dueDate < target)
      .forEach((task: Task): void => archiveFuture(data, task, task.dueDate || previous, now));
  }
  const pulled = data.futureTasks.filter((task: Task): boolean => !!task.dueDate && task.dueDate <= target &&
    !(data.settings.retainCompletedFutureUntilDue && task.completed));
  data.todayTasks = data.todayTasks.concat(pulled);
  data.futureTasks = data.futureTasks.filter((task: Task): boolean => !task.dueDate || task.dueDate > target ||
    (data.settings.retainCompletedFutureUntilDue && task.completed));
  data.lastRolloverDate = target;
  if (data.currentDate < target) data.currentDate = target;
}

// 预览只迁移可见分区，不代表真实时间经过，不触发任何跨日归档。
function selectDate(data: AppData, target: string): void {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(target) || target < realDateOf(data)) return;
  if (target < data.currentDate) {
    rollback(data, target);
    return;
  }
  const pulled = data.futureTasks.filter((task: Task): boolean => !!task.dueDate && task.dueDate <= target &&
    !(data.settings.retainCompletedFutureUntilDue && task.completed));
  data.todayTasks = data.todayTasks.concat(pulled);
  data.futureTasks = data.futureTasks.filter((task: Task): boolean => !pulled.includes(task));
  data.currentDate = target;
}

function rollback(data: AppData, target: string): void {
  if (target >= data.currentDate) return;
  const back = data.todayTasks.filter((task: Task): boolean => !task.checkInId && !!task.dueDate && task.dueDate > target);
  data.todayTasks = data.todayTasks.filter((task: Task): boolean => !!task.checkInId || !task.dueDate || task.dueDate <= target);
  back.forEach((task: Task): void => insertFuture(data, task));
  data.currentDate = target;
}

function applyProgress(task: Task, progress: number | null | undefined, date: string): void {
  if (progress === undefined) return;
  if (progress === null) {
    task.progress = null;
    return;
  }
  task.progress = Math.max(0, Math.min(100, Math.round(progress)));
  task.completed = task.progress >= 100;
  task.completedAt = task.completed ? new Date().toISOString() : null;
  task.completedDate = task.completed ? date : null;
}

function addTask(data: AppData, action: AppAction): void {
  if (!action.text.trim()) return;
  const task = new Task();
  task.id = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
  task.text = action.text.trim();
  task.createdAt = new Date().toISOString();
  task.scheduledDate = action.section === 'today' ? data.currentDate : (action.dueDate || null);
  task.group = action.group ? action.group.trim() : null;
  task.startDate = action.startDate || null;
  task.dueDate = action.dueDate || null;
  if (action.section === 'today') {
    if (data.currentDate > realDateOf(data)) {
      task.startDate = data.currentDate;
      task.dueDate = data.currentDate;
    }
    data.todayTasks.push(task);
  } else {
    if (task.dueDate) {
      if (!task.startDate) task.startDate = addDays(data.currentDate, 1);
      if (task.startDate > task.dueDate) task.startDate = task.dueDate;
      insertFuture(data, task);
    } else data.futureTasks.push(task);
  }
}

function editTask(data: AppData, action: AppAction): void {
  const today = data.todayTasks.find((task: Task): boolean => task.id === action.id);
  const task = today || data.futureTasks.find((item: Task): boolean => item.id === action.id);
  if (!task) return;
  // 关联打卡保留周期及内容快照，普通编辑入口只接受进度。
  if (task.checkInId) {
    if (!data.checkIns.some((item: CheckInItem): boolean => item.id === task.checkInId && item.deleted)) applyProgress(task, action.progress, realDateOf(data));
    return;
  }
  if (!action.text.trim()) return;
  task.text = action.text.trim();
  if (action.group !== undefined) task.group = action.group ? action.group.trim() : null;
  applyProgress(task, action.progress, realDateOf(data));
  if (today) return;
  if (action.startDate !== undefined) task.startDate = action.startDate || null;
  if (action.dueDate !== undefined) {
    task.dueDate = action.dueDate || null;
    task.scheduledDate = task.dueDate;
  }
  data.futureTasks = data.futureTasks.filter((item: Task): boolean => item.id !== task.id);
  if (data.settings.retainCompletedFutureUntilDue && task.completed && task.dueDate && task.dueDate >= realDateOf(data)) {
    insertFuture(data, task);
  } else if (task.dueDate && task.dueDate <= data.currentDate) data.todayTasks.push(task);
  else if (task.dueDate) insertFuture(data, task);
  else data.futureTasks.push(task);
}

function moveTask(data: AppData, action: AppAction): void {
  const task = data.todayTasks.concat(data.futureTasks).find((item: Task): boolean => item.id === action.id);
  if (!task) return;
  if (task.checkInId && action.to !== 'today') return;
  if (action.to === 'today' && !task.checkInId) task.scheduledDate = data.currentDate;
  if (action.to === 'future') {
    task.dueDate = action.dueDate || task.dueDate || null;
    task.scheduledDate = task.dueDate;
    if (action.startDate !== undefined) task.startDate = action.startDate || null;
    if (!task.startDate) task.startDate = addDays(data.currentDate, 1);
    if (task.dueDate && task.startDate > task.dueDate) task.startDate = task.dueDate;
  }
  if (action.group !== undefined) task.group = action.group ? action.group.trim() : null;
  data.todayTasks = data.todayTasks.filter((item: Task): boolean => item.id !== task.id);
  data.futureTasks = data.futureTasks.filter((item: Task): boolean => item.id !== task.id);
  const destination = action.to === 'today' ? data.todayTasks : data.futureTasks;
  destination.splice(Math.max(0, Math.min(action.toIndex, destination.length)), 0, task);
}

function deleteGroup(data: AppData, action: AppAction): void {
  if (!action.group) return;
  const source = action.section === 'today' ? data.todayTasks : data.futureTasks;
  const other = action.section === 'today' ? data.futureTasks : data.todayTasks;
  if (!other.some((task: Task): boolean => task.group === action.group)) {
    data.groups = data.groups.filter((group: string): boolean => group !== action.group);
    // 最后一个日程分区移除目录时，一并解除计划与未来周期的归属，防止次日生成复活标签。
    data.checkIns.forEach((item: CheckInItem): void => { if (item.group === action.group) item.group = ''; });
    data.checkInRecords.forEach((record: CheckInRecord): void => {
      if (record.group === action.group && record.key >= realDateOf(data)) record.group = '';
    });
  }
  const moved = source.filter((task: Task): boolean => task.group === action.group);
  const rest = source.filter((task: Task): boolean => task.group !== action.group);
  moved.forEach((task: Task): void => { task.group = null; });
  let lastNull: number = -1;
  rest.forEach((task: Task, index: number): void => { if (task.group === null) lastNull = index; });
  const insertion = lastNull < 0 ? rest.length : lastNull + 1;
  const result = rest.slice(0, insertion).concat(moved, rest.slice(insertion));
  if (action.section === 'today') data.todayTasks = result;
  else data.futureTasks = result;
}

function moveGroup(data: AppData, action: AppAction): void {
  const source = action.section === 'today' ? data.todayTasks : data.futureTasks;
  const first = source.findIndex((task: Task): boolean => task.group === action.group);
  if (first < 0) return;
  let last = first;
  while (last + 1 < source.length && source[last + 1].group === action.group) last++;
  if (action.toIndex > first && action.toIndex <= last) return;
  const group = source.splice(first, last - first + 1);
  const insertion = Math.max(0, Math.min(action.toIndex > first ? action.toIndex - group.length : action.toIndex, source.length));
  const result = source.slice(0, insertion).concat(group, source.slice(insertion));
  if (action.section === 'today') data.todayTasks = result;
  else data.futureTasks = result;
}

function restore(data: AppData, action: AppAction): void {
  const entry = data.history.find((item: HistoryEntry): boolean => item.date === action.entryDate);
  const task = entry?.tasks.find((item: Task): boolean => item.id === action.id);
  if (!task) return;
  if (task.checkInId) {
    const undo = new AppAction('CHECKIN_UNDO'); undo.id = task.checkInId; undo.key = task.checkInKey;
    applyCheckInAction(data, undo); return;
  }
  const planned = task.plannedDate;
  task.completed = false;
  task.completedAt = null;
  task.completedDate = null;
  task.plannedDate = null;
  task.archivedAt = null;
  removeHistory(data, action.entryDate, action.id);
  if (action.target === 'today') {
    task.scheduledDate = data.currentDate;
    task.dueDate = data.currentDate > realDateOf(data) ? data.currentDate : null;
    data.todayTasks.push(task);
  } else {
    task.dueDate = action.dueDate || planned || null;
    task.scheduledDate = task.dueDate;
    if (!task.startDate) task.startDate = addDays(data.currentDate, 1);
    if (task.dueDate) insertFuture(data, task);
    else data.futureTasks.push(task);
  }
}

export function reduce(state: AppData, action: AppAction): AppData {
  if (action.type === 'LOAD' && action.data) return normalizeData(action.data);
  if (action.type === 'DELETE_GROUP' && action.group === null) return state;
  const data = state.clone();
  if (!data.lastRolloverDate) data.lastRolloverDate = realDateOf(data);
  data.todayTasks.forEach((task: Task): void => {
    if (!task.scheduledDate) task.scheduledDate = task.dueDate && task.dueDate <= data.lastRolloverDate ? task.dueDate : data.lastRolloverDate;
  });
  if (action.type.startsWith('CHECKIN_')) {
    applyCheckInAction(data, action); syncCheckInCompletion(data); return settle(data);
  }
  switch (action.type) {
    case 'ADD_TASK': addTask(data, action); break;
    case 'EDIT_TASK': editTask(data, action); break;
    case 'DELETE_TASK':
      data.todayTasks.concat(data.futureTasks).filter((task: Task): boolean => task.id === action.id && !!task.checkInId)
        .forEach((task: Task): void => skipCheckInTask(data, task));
      data.todayTasks = data.todayTasks.filter((task: Task): boolean => task.id !== action.id);
      data.futureTasks = data.futureTasks.filter((task: Task): boolean => task.id !== action.id);
      break;
    case 'TOGGLE_TODAY': {
      const first = data.todayTasks.find((task: Task): boolean => !task.completed);
      const task = data.todayTasks.find((item: Task): boolean => item.id === action.id);
      if (task) {
        if (task.checkInId && data.checkIns.some((item: CheckInItem): boolean => item.id === task.checkInId && item.deleted)) break;
        const advance = !task.completed && first?.id === task.id && data.settings.autoScrollNextOnComplete;
        task.completed = !task.completed;
        task.completedAt = task.completed ? new Date().toISOString() : null;
        task.completedDate = task.completed ? realDateOf(data) : null;
        if (task.completed && task.scheduledDate && task.scheduledDate > realDateOf(data) && task.dueDate) {
          // 预览中提前完成一项未来安排，仍遵循未来完成的保留设置。
          data.todayTasks = data.todayTasks.filter((item: Task): boolean => item.id !== task.id);
          if (data.settings.retainCompletedFutureUntilDue) insertFuture(data, task);
          else archiveFuture(data, task, realDateOf(data), task.completedAt || new Date().toISOString());
        }
        if (advance) data.todayAnchorId = data.todayTasks.find((item: Task): boolean => !item.completed)?.id || null;
      }
      break;
    }
    case 'COMPLETE_FUTURE': {
      const task = data.futureTasks.find((item: Task): boolean => item.id === action.id);
      if (task) {
        const retain = data.settings.retainCompletedFutureUntilDue && !!task.dueDate && task.dueDate >= realDateOf(data);
        task.completed = retain ? !task.completed : true;
        const now = new Date().toISOString();
        task.completedAt = task.completed ? now : null;
        task.completedDate = task.completed ? realDateOf(data) : null;
        if (!retain) archiveFuture(data, task, realDateOf(data), now);
        else if (!task.completed && task.dueDate && task.dueDate <= data.currentDate) {
          // 截止日当天取消完成后恢复原到期规则，立即转入当日处理。
          data.futureTasks = data.futureTasks.filter((item: Task): boolean => item.id !== task.id);
          data.todayTasks.push(task);
        }
      }
      break;
    }
    case 'REORDER': {
      const list = action.section === 'today' ? data.todayTasks : data.futureTasks;
      if (action.from >= 0 && action.from < list.length) {
        const item = list.splice(action.from, 1)[0];
        list.splice(Math.max(0, Math.min(action.toIndex, list.length)), 0, item);
      }
      break;
    }
    case 'MOVE_TASK': moveTask(data, action); break;
    case 'MOVE_GROUP': moveGroup(data, action); break;
    case 'DELETE_GROUP': deleteGroup(data, action); break;
    case 'END_DAY': rollover(data, addDays(realDateOf(data), 1)); break;
    case 'ROLLOVER_TO': rollover(data, action.key); break;
    case 'ROLLBACK_TO': rollback(data, action.key); break;
    case 'SELECT_DATE': selectDate(data, action.key); break;
    case 'RESTORE': restore(data, action); break;
    case 'DELETE_HISTORY_TASK': removeHistory(data, action.entryDate, action.id); break;
    case 'CLEAR_HISTORY': data.history = []; break;
    case 'SET_SETTINGS': {
      const retainedBefore = data.settings.retainCompletedFutureUntilDue;
      if (action.settings) data.settings = Settings.copy(action.settings);
      if (retainedBefore && !data.settings.retainCompletedFutureUntilDue) {
        const now = new Date().toISOString();
        data.futureTasks.filter((task: Task): boolean => task.completed)
          .forEach((task: Task): void => archiveFuture(data, task, realDateOf(data), now));
      }
      if (!data.settings.autoScrollNextOnComplete) data.todayAnchorId = null;
      break;
    }
    case 'SET_TODAY_ANCHOR': data.todayAnchorId = action.id || null; break;
  }
  syncCheckInCompletion(data);
  if (action.type === 'ROLLOVER_TO' || action.type === 'END_DAY') syncCheckIns(data);
  return settle(data);
}


