// 打卡业务只使用传入的真实业务日期；浏览未来日期不产生任何新周期。
import { AppAction, AppData, HistoryEntry, Task } from './PlanerModel';
import { CheckInItem, CheckInRecord, CheckInRange, CheckInStats, CheckInSchedule, CheckInPause, CheckInNamePattern } from './CheckInModel';

function actualDate(data: AppData): string { return data.lastRolloverDate || data.currentDate; }
function validDate(key: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) return false;
  const parts = key.split('-').map((part: string): number => Number(part));
  const date = new Date(parts[0], parts[1] - 1, parts[2], 12);
  return date.getFullYear() === parts[0] && date.getMonth() === parts[1] - 1 && date.getDate() === parts[2];
}
function dateValue(key: string): Date {
  const parts = key.split('-');
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12);
}
function nextDay(key: string): string {
  const date = dateValue(key); date.setDate(date.getDate() + 1);
  return `${String(date.getFullYear()).padStart(4, '0')}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}
function recordFor(data: AppData, id: string, key: string): CheckInRecord | undefined {
  return data.checkInRecords.find((record: CheckInRecord): boolean => record.itemId === id && record.key === key);
}
function scheduleOf(item: CheckInItem, key: string): CheckInSchedule {
  let schedule: CheckInSchedule;
  if (item.schedules.length > 0) {
    schedule = item.schedules[0];
    item.schedules.forEach((value: CheckInSchedule): void => { if (value.effectiveFrom < schedule.effectiveFrom) schedule = value; });
  } else {
    schedule = new CheckInSchedule(); schedule.startDate = item.startDate; schedule.frequency = item.frequency;
    schedule.weekdays = item.weekdays; schedule.monthDays = item.monthDays;
  }
  item.schedules.forEach((value: CheckInSchedule): void => {
    if (value.effectiveFrom <= key && (!schedule.effectiveFrom || value.effectiveFrom >= schedule.effectiveFrom)) schedule = value;
  });
  return schedule;
}

// 只识别唯一的整数或范围，多个分散数字、日期、小数和负数均不猜测。
export function parseCheckInName(name: string): CheckInNamePattern {
  const result = new CheckInNamePattern();
  const text = name.trim(); const numbers = text.match(/\d+/g) || [];
  if (numbers.length === 0) { result.error = '名称中没有可递增的数字'; return result; }
  if (numbers.length > 2) { result.error = '名称中有多组数字，若要开启自动递增/接续功能，请只保留一处数字或范围'; return result; }
  const firstNumber: string = numbers[0] || '';
  const first = text.indexOf(firstNumber); const firstEnd = first + firstNumber.length;
  result.prefix = text.substring(0, first);
  if (/[.．+＋\-−－﹣]\s*$/.test(result.prefix)) { result.error = '自动递增仅支持非负整数'; return result; }
  result.start = Number(firstNumber); result.end = result.start;
  result.startWidth = firstNumber.length > 1 && firstNumber.startsWith('0') ? firstNumber.length : 0;
  result.endWidth = result.startWidth;
  result.suffix = text.substring(firstEnd);
  if (numbers.length === 2) {
    const secondNumber: string = numbers[1] || '';
    const second = text.indexOf(secondNumber, firstEnd);
    result.separator = text.substring(firstEnd, second);
    if (!/^\s*[-–—~～至到]\s*$/.test(result.separator)) { result.error = '名称中有多组数字，若要开启自动递增/接续功能，请只保留一处数字或范围'; return result; }
    result.end = Number(secondNumber); result.suffix = text.substring(second + secondNumber.length);
    result.endWidth = secondNumber.length > 1 && secondNumber.startsWith('0') ? secondNumber.length : 0;
    result.mode = 'range';
  } else result.mode = 'single';
  if (!Number.isSafeInteger(result.start) || !Number.isSafeInteger(result.end)) { result.error = '名称中的数字超出安全整数范围'; return result; }
  if (result.start > result.end) { result.error = '名称中的范围起点不能大于终点'; return result; }
  result.step = result.mode === 'range' ? result.end - result.start + 1 : 1;
  if (!Number.isSafeInteger(result.step)) { result.error = '范围数量超出安全整数范围'; return result; }
  result.valid = true; return result;
}

export function validateCheckInName(name: string): string {
  if (!name.trim()) return '请输入打卡名称';
  return parseCheckInName(name).error;
}

export function formatCheckInName(pattern: CheckInNamePattern, start: number, end: number = start): string {
  if (!pattern.valid || !Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || end < start) return '';
  const first = start.toString().padStart(pattern.startWidth, '0');
  const last = end.toString().padStart(pattern.endWidth, '0');
  return pattern.prefix + first + (pattern.mode === 'range' ? pattern.separator + last : '') + pattern.suffix;
}

function nextNameRange(pattern: CheckInNamePattern, step: number): CheckInRange {
  return pattern.mode === 'range' ? new CheckInRange(pattern.end + 1, pattern.end + step) : new CheckInRange(pattern.start + step, pattern.start + step);
}

// 编辑器的预览始终是下一期，首期是否生成由真实周期状态单独决定。
export function nextCheckInName(item: CheckInItem): string {
  const pattern = parseCheckInName(item.name);
  if (!pattern.valid || !Number.isSafeInteger(item.step) || item.step < 1) return '';
  const next = nextNameRange(pattern, item.step);
  return formatCheckInName(pattern, next.start, next.end);
}

export function validateCheckInRange(start: number, end: number): string {
  if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || end < 0 || start > Number.MAX_SAFE_INTEGER || end > Number.MAX_SAFE_INTEGER) return '范围必须是有效的非负数';
  return start > end ? '范围起点不能大于终点' : '';
}

export function validateCheckIn(item: CheckInItem): string {
  if (!item || !item.name.trim()) return '请输入打卡名称';
  if (!validDate(item.startDate)) return '请选择有效的开始日期';
  if (!['daily', 'weekly', 'monthly'].includes(item.frequency)) return '请选择有效的重复频率';
  if (item.frequency === 'weekly' && (!Array.isArray(item.weekdays) || item.weekdays.length === 0 || item.weekdays.some((day: number): boolean => !Number.isInteger(day) || day < 0 || day > 6))) return '请至少选择一个有效星期';
  if (item.frequency === 'monthly' && (!Array.isArray(item.monthDays) || item.monthDays.length === 0 || item.monthDays.some((day: number): boolean => !Number.isInteger(day) || day < 1 || day > 31))) return '请选择有效的每月日期';
  if (item.autoIncrement) {
    const error = validateCheckInName(item.name); if (error) return error;
    if (!Number.isSafeInteger(item.step) || item.step < 1) return '递增步长或每期数量必须为正整数';
  }
  return '';
}

// 历史日期使用当时的节律与暂停区间；不存在的月日自然跳过，不挪到月底。
export function isCheckInDate(item: CheckInItem, key: string): boolean {
  if (!validDate(key) || (item.deletedDate && key >= item.deletedDate)) return false;
  const schedule = scheduleOf(item, key);
  if (!validDate(schedule.startDate) || key < schedule.startDate) return false;
  if (item.pauses.some((pause: CheckInPause): boolean => pause.from <= key && (!pause.to || key < pause.to))) return false;
  const date = dateValue(key);
  if (schedule.frequency === 'weekly') return schedule.weekdays.includes(date.getDay());
  if (schedule.frequency === 'monthly') return schedule.monthDays.includes(date.getDate());
  return true;
}

function previousDay(key: string): string {
  const date = dateValue(key); date.setDate(date.getDate() - 1);
  return String(date.getFullYear()).padStart(4, '0') + '-' + String(date.getMonth() + 1).padStart(2, '0') + '-' + String(date.getDate()).padStart(2, '0');
}
function calendarDayCount(from: string, to: string): number {
  const a = dateValue(from); const b = dateValue(to);
  return Math.floor((Date.UTC(b.getFullYear(), b.getMonth(), b.getDate()) - Date.UTC(a.getFullYear(), a.getMonth(), a.getDate())) / 86400000) + 1;
}
function countSchedule(schedule: CheckInSchedule, from: string, to: string): number {
  if (!validDate(schedule.startDate)) return 0;
  const start = from < schedule.startDate ? schedule.startDate : from;
  if (start > to) return 0;
  const days = calendarDayCount(start, to);
  if (schedule.frequency === 'daily') return days;
  const first = dateValue(start); const last = dateValue(to);
  if (schedule.frequency === 'weekly') {
    let count = 0; const seen: number[] = [];
    schedule.weekdays.forEach((weekday: number): void => {
      if (seen.includes(weekday) || weekday < 0 || weekday > 6) return;
      seen.push(weekday); const offset = (weekday - first.getDay() + 7) % 7;
      if (offset < days) count += Math.floor((days - 1 - offset) / 7) + 1;
    });
    return count;
  }
  const selected = schedule.monthDays.filter((day: number, index: number): boolean => day >= 1 && day <= 31 && schedule.monthDays.indexOf(day) === index);
  let count = 0;
  for (let month = first.getFullYear() * 12 + first.getMonth(); month <= last.getFullYear() * 12 + last.getMonth(); month++) {
    const year = Math.floor(month / 12); const monthIndex = month % 12;
    const end = new Date(year, monthIndex + 1, 0, 12).getDate();
    const lower = year === first.getFullYear() && monthIndex === first.getMonth() ? first.getDate() : 1;
    const upper = year === last.getFullYear() && monthIndex === last.getMonth() ? last.getDate() : end;
    selected.forEach((day: number): void => { if (day >= lower && day <= upper && day <= end) count++; });
  }
  return count;
}
// 按节律版本和暂停边界分段，避免多年日期投影逐日扫描。
function countPeriods(item: CheckInItem, from: string, to: string): number {
  if (!validDate(from) || !validDate(to) || from > to) return 0;
  const boundaries: string[] = [from];
  const add = (date: string): void => { if (validDate(date) && date > from && date <= to && !boundaries.includes(date)) boundaries.push(date); };
  item.schedules.forEach((schedule: CheckInSchedule): void => add(schedule.effectiveFrom));
  item.pauses.forEach((pause: CheckInPause): void => { add(pause.from); add(pause.to); }); add(item.deletedDate);
  boundaries.sort(); let count = 0;
  boundaries.forEach((start: string, index: number): void => {
    if (item.deletedDate && start >= item.deletedDate) return;
    if (item.pauses.some((pause: CheckInPause): boolean => pause.from <= start && (!pause.to || start < pause.to))) return;
    const end = index + 1 < boundaries.length ? previousDay(boundaries[index + 1]) : to;
    count += countSchedule(scheduleOf(item, start), start, end);
  });
  return count;
}

// 名称与真实日期绑定。漏开应用的有效周期仍占用编号，休息和暂停日不占用。
function projectedPeriods(item: CheckInItem, key: string): number {
  const generated = validDate(item.rangeUpdatedFor);
  const anchor = generated ? item.rangeUpdatedFor : (validDate(item.nameAnchorDate) ? item.nameAnchorDate : item.startDate);
  if (!validDate(anchor) || key < anchor) return 0;
  const count = countPeriods(item, generated ? nextDay(anchor) : anchor, key);
  return generated ? count : Math.max(0, count - 1);
}
function rangeAfterPeriods(item: CheckInItem, count: number): CheckInRange {
  const pattern = parseCheckInName(item.name);
  if (!pattern.valid) return new CheckInRange();
  if (!item.autoIncrement || count === 0) return new CheckInRange(pattern.start, pattern.end);
  if (pattern.mode === 'range') return new CheckInRange(pattern.end + 1 + (count - 1) * item.step, pattern.end + count * item.step);
  return new CheckInRange(pattern.start + count * item.step, pattern.start + count * item.step);
}
export function recommendedRange(item: CheckInItem, records: CheckInRecord[] = [], key: string = ''): CheckInRange {
  return rangeAfterPeriods(item, key ? projectedPeriods(item, key) : (item.rangeUpdatedFor ? 1 : 0));
}

export function checkInTaskText(record: CheckInRecord): string { return record.name; }

function candidateName(item: CheckInItem, record: CheckInRecord | undefined, records: CheckInRecord[], key: string, action: AppAction): string {
  return action.text.length > 0 ? action.text.trim() : (record ? record.name : (action.type === 'CHECKIN_BACKFILL' ? '' : createRecord(item, key, records).name));
}

export function validateCheckInAction(data: AppData, action: AppAction): string {
  if (action.type === 'CHECKIN_SYNC') return '';
  if (action.type === 'CHECKIN_SKIP') return '不再支持跳过，可保留未完成或暂停整个计划';
  if (action.type === 'CHECKIN_SAVE') {
    if (!action.checkIn) return '缺少打卡内容';
    return validateCheckIn(action.checkIn);
  }
  const item = data.checkIns.find((value: CheckInItem): boolean => value.id === action.id);
  if (!item) return '找不到此打卡';
  if (action.type === 'CHECKIN_PAUSE') return item.paused ? '该打卡已暂停' : '';
  if (action.type === 'CHECKIN_RESUME') return !item.paused ? '该打卡已在进行中' : '';
  if (action.type === 'CHECKIN_DELETE') return '';
  const key = action.key || actualDate(data); const today = actualDate(data);
  if (action.type === 'CHECKIN_ADVANCE') {
    if (!validDate(key) || key <= today) return '提前打卡只能选择未来的有效日期';
    const existing = recordFor(data, item.id, key);
    if (existing?.status === 'completed') return '该周期已完成，无需重复提前打卡';
    if (item.paused || !isCheckInDate(item, key)) return '这一天不是该打卡的有效周期';
    const preview = previewCheckInRecord(data, item.id, key);
    if (!preview?.name || preview.status === 'pending') return '未来内容无法生成，请先调整计划名称或递增规则';
    if (action.text.length > 0 || action.rangeStart !== undefined || action.rangeEnd !== undefined) return '提前打卡使用该日期的计划内容，请先编辑计划再确认';
    return '';
  }
  if (action.type === 'CHECKIN_UNDO' && validDate(key) && key > today) {
    const existing = recordFor(data, item.id, key);
    if (!existing || existing.status !== 'completed' || !existing.advanced) return '该未来周期尚未提前完成';
    if (action.text.length > 0 || action.rangeStart !== undefined || action.rangeEnd !== undefined) return '撤销只改变完成状态，不修改当期内容';
    return '';
  }
  if (!validDate(key) || key > today) return '只能操作今天或过去的有效日期';
  const record = recordFor(data, item.id, key);
  if (!record && !isCheckInDate(item, key)) return '这一天不是该打卡的有效周期';
  if (action.type === 'CHECKIN_BACKFILL' && key >= today) return '补卡只能选择过去的日期';
  if (action.rangeStart !== undefined || action.rangeEnd !== undefined) return '请直接修改打卡名称中的数字';
  switch (action.type) {
    case 'CHECKIN_GENERATE': {
      if (item.paused) return '请先恢复此打卡';
      if (record && record.status !== 'pending') return '该周期已生成';
      const name = candidateName(item, record, data.checkInRecords, key, action);
      if (!name) return '请填写有效的本期名称；数字溢出时请手动调整';
      return item.autoIncrement ? validateCheckInName(name) : '';
    }
    case 'CHECKIN_COMPLETE': return !record || record.status === 'pending' ? '请先确认本期内容并生成日程' : (record.status === 'completed' ? '该周期已完成' : '');
    case 'CHECKIN_UNDO': return !record || record.status !== 'completed' ? '该周期尚未完成' : '';
    case 'CHECKIN_BACKFILL': {
      if (record?.status === 'completed') return '该周期已完成，无需重复补卡';
      return candidateName(item, record, data.checkInRecords, key, action) ? '' : '请填写本期实际完成的打卡名称';
    }
    default: return '不支持的打卡操作';
  }
}

function nameSnapshot(record: CheckInRecord, name: string): void {
  record.name = name; record.nameVersion = 1;
  const pattern = parseCheckInName(name); record.useRange = pattern.valid;
  record.rangeStart = pattern.valid ? pattern.start : 0; record.rangeEnd = pattern.valid ? pattern.end : 0;
}

function createRecord(item: CheckInItem, key: string, records: CheckInRecord[], periods: number = -1): CheckInRecord {
  const record = new CheckInRecord(); const range = periods >= 0 ? rangeAfterPeriods(item, periods) : recommendedRange(item, records, key);
  const pattern = parseCheckInName(item.name);
  const name = item.autoIncrement && pattern.valid ? formatCheckInName(pattern, range.start, range.end) : item.name;
  record.itemId = item.id; record.key = key; record.group = item.group; nameSnapshot(record, name);
  // 溢出的建议保留为待手改状态，绝不回退到上一期名称后自动生成。
  if (!name && item.autoIncrement) { record.useRange = true; record.rangeStart = range.start; record.rangeEnd = range.end; }
  return record;
}

function allTasks(data: AppData): Task[] {
  let tasks = data.todayTasks.concat(data.futureTasks);
  data.history.forEach((entry: HistoryEntry): void => { tasks = tasks.concat(entry.tasks); });
  return tasks;
}
function removeLinkedTask(data: AppData, record: CheckInRecord): void {
  data.todayTasks = data.todayTasks.filter((task: Task): boolean => task.checkInId !== record.itemId || task.checkInKey !== record.key);
  data.futureTasks = data.futureTasks.filter((task: Task): boolean => task.checkInId !== record.itemId || task.checkInKey !== record.key);
  data.history.forEach((entry: HistoryEntry): void => { entry.tasks = entry.tasks.filter((task: Task): boolean => task.checkInId !== record.itemId || task.checkInKey !== record.key); });
  data.history = data.history.filter((entry: HistoryEntry): boolean => entry.tasks.length > 0);
}
function taskFor(data: AppData, record: CheckInRecord): Task {
  const task = new Task();
  task.id = record.taskId || 'checkin:' + record.itemId + ':' + record.key;
  record.taskId = task.id; task.checkInId = record.itemId; task.checkInKey = record.key;
  // 已删除的目录不因历史撤销而复活，原历史快照仍保留当时归属。
  task.group = record.group && data.groups.includes(record.group) ? record.group : null;
  task.text = checkInTaskText(record); task.createdAt = record.generatedAt || new Date().toISOString();
  task.scheduledDate = record.key; task.completed = record.status === 'completed';
  task.completedAt = record.completedAt || null;
  task.completedDate = record.completedAt ? (record.advanced ? record.key : actualCompletionDate(record.completedAt)) : null;
  return task;
}
function actualCompletionDate(timestamp: string): string {
  const date = new Date(timestamp);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}
function ensureRecordTask(data: AppData, record: CheckInRecord): void {
  if (record.status !== 'ready' || record.taskDetached || record.key > actualDate(data)) return;
  if (allTasks(data).some((task: Task): boolean => task.checkInId === record.itemId && task.checkInKey === record.key)) return;
  data.todayTasks.push(taskFor(data, record));
}
function advanceCurrentName(item: CheckInItem, record: CheckInRecord): void {
  item.name = record.name; item.nameVersion = 1;
  item.useRange = record.useRange; item.rangeStart = record.rangeStart; item.rangeEnd = record.rangeEnd;
  item.rangeUpdatedFor = record.key; item.nameAnchorDate = record.key;
}
function generate(data: AppData, item: CheckInItem, record: CheckInRecord, action: AppAction): void {
  if (action.text.length > 0) nameSnapshot(record, action.text.trim());
  record.status = 'ready'; record.generatedAt = new Date().toISOString(); record.taskDetached = false;
  if (record.key === actualDate(data) && (!item.rangeUpdatedFor || record.key >= item.rangeUpdatedFor)) advanceCurrentName(item, record);
  ensureRecordTask(data, record);
}

// 已确认的未来周期到期才接入日程；完成项错过到期日归档，撤销项保留为延期未完成。
function materializeConfirmed(data: AppData): void {
  const today = actualDate(data);
  data.checkInRecords.forEach((record: CheckInRecord): void => {
    if (record.key > today || record.taskId || record.taskDetached) return;
    const ready = record.status === 'ready';
    if (!ready && (!record.advanced || record.status !== 'completed')) return;
    const item = data.checkIns.find((value: CheckInItem): boolean => value.id === record.itemId);
    if (!item || (ready && (item.paused || !isCheckInDate(item, record.key)))) return;
    if (record.key === today && (!item.rangeUpdatedFor || item.rangeUpdatedFor < today) && !item.paused && isCheckInDate(item, today)) {
      // 已确认的未来快照不随编辑变化；当前进度仍按编辑后的规则推进，不倒退到旧内容。
      const current = createRecord(item, today, data.checkInRecords);
      if (current.name) advanceCurrentName(item, current);
    }
    if (ready) { ensureRecordTask(data, record); return; }
    const task = taskFor(data, record);
    if (record.key === today) data.todayTasks.push(task);
    else {
      let entry = data.history.find((value: HistoryEntry): boolean => value.date === record.key);
      if (!entry) { entry = new HistoryEntry(); entry.date = record.key; data.history.push(entry); }
      task.plannedDate = record.key; task.archivedAt = new Date().toISOString(); entry.tasks.push(task);
    }
  });
}

// 启动/回前台和真实日期推进共用，遗漏日期不伪造已生成记录，名称按实际有效周期对齐。
export function syncCheckIns(data: AppData, key: string = actualDate(data)): void {
  if (!validDate(key) || key !== actualDate(data)) return;
  materializeConfirmed(data);
  data.checkIns.forEach((item: CheckInItem): void => {
    if (item.paused || item.deleted || !isCheckInDate(item, key)) return;
    let record = recordFor(data, item.id, key);
    if (!record) { record = createRecord(item, key, data.checkInRecords); data.checkInRecords.push(record); }
    if (record.status !== 'pending') return;
    if (record.name && (!item.autoIncrement || !validateCheckInName(record.name))) generate(data, item, record, new AppAction('CHECKIN_GENERATE'));
  });
}

function scheduleSnapshot(item: CheckInItem, effectiveFrom: string): CheckInSchedule {
  const schedule = new CheckInSchedule(); schedule.effectiveFrom = effectiveFrom;
  schedule.startDate = item.startDate; schedule.frequency = item.frequency;
  schedule.weekdays = item.weekdays.slice(); schedule.monthDays = item.monthDays.slice();
  return schedule;
}
function saveItem(data: AppData, source: CheckInItem): void {
  const item = CheckInItem.copy(source); const today = actualDate(data);
  item.name = item.name.trim(); item.nameVersion = 1;
  item.group = item.group.trim();
  if (item.group && !data.groups.includes(item.group)) data.groups.push(item.group);
  const pattern = parseCheckInName(item.name); item.useRange = pattern.valid;
  item.rangeStart = pattern.valid ? pattern.start : 0; item.rangeEnd = pattern.valid ? pattern.end : 0;
  item.incrementMode = 'segment'; item.count = item.step;
  const old = data.checkIns.find((value: CheckInItem): boolean => value.id === item.id);
  if (!old) {
    item.id = item.id || `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
    item.createdAt = new Date().toISOString(); item.deleted = false; item.deletedDate = '';
    item.rangeUpdatedFor = ''; item.nameAnchorDate = item.startDate > today ? item.startDate : today;
    item.pauses = []; item.schedules = [scheduleSnapshot(item, item.startDate)];
    if (item.paused) { const pause = new CheckInPause(); pause.from = today; item.pauses.push(pause); }
    data.checkIns.push(item); return;
  }
  // 编辑不能经表单绕过暂停/删除动作，也不能重写历史停用区间。
  item.paused = old.paused; item.deleted = old.deleted; item.createdAt = old.createdAt; item.deletedDate = old.deletedDate;
  item.pauses = old.pauses.map((pause: CheckInPause): CheckInPause => CheckInPause.copy(pause));
  item.schedules = old.schedules.map((schedule: CheckInSchedule): CheckInSchedule => CheckInSchedule.copy(schedule));
  if (item.schedules.length === 0) item.schedules.push(scheduleSnapshot(old, old.startDate));
  if (old.startDate !== item.startDate || old.frequency !== item.frequency || old.weekdays.join(',') !== item.weekdays.join(',') || old.monthDays.join(',') !== item.monthDays.join(',')) item.schedules.push(scheduleSnapshot(item, today));
  item.rangeUpdatedFor = old.rangeUpdatedFor; item.nameAnchorDate = old.nameAnchorDate || today;
  const oldPattern = parseCheckInName(old.name);
  if (oldPattern.valid !== pattern.valid || oldPattern.mode !== pattern.mode || oldPattern.start !== pattern.start || oldPattern.end !== pattern.end) {
    const todayRecord = recordFor(data, item.id, today);
    const firstUnconfirmed = todayRecord && todayRecord.status !== 'pending' ? nextDay(today) : today;
    item.rangeUpdatedFor = ''; item.nameAnchorDate = item.startDate > firstUnconfirmed ? item.startDate : firstUnconfirmed;
  }
  data.checkIns = data.checkIns.map((value: CheckInItem): CheckInItem => value.id === item.id ? item : value);
  if (old.group !== item.group) {
    // 归属变更同步仍在日程中的周期和未来周期；已归档内容保持历史分组。
    const activeKeys: string[] = [];
    data.todayTasks.concat(data.futureTasks).forEach((task: Task): void => {
      if (task.checkInId !== item.id) return;
      task.group = item.group || null; activeKeys.push(task.checkInKey);
    });
    data.checkInRecords.forEach((record: CheckInRecord): void => {
      if (record.itemId === item.id && (record.key >= today || activeKeys.includes(record.key))) record.group = item.group;
    });
  }
  // 尚未确认的今日建议不是历史快照；编辑后重新按最新设置生成建议。
  data.checkInRecords = data.checkInRecords.filter((record: CheckInRecord): boolean => record.itemId !== item.id || record.key !== today || record.status !== 'pending');
}

export function applyCheckInAction(data: AppData, action: AppAction): void {
  if (validateCheckInAction(data, action)) return;
  if (action.type === 'CHECKIN_SYNC') { syncCheckIns(data); return; }
  if (action.type === 'CHECKIN_SAVE' && action.checkIn) { saveItem(data, action.checkIn); syncCheckIns(data); return; }
  const item = data.checkIns.find((value: CheckInItem): boolean => value.id === action.id);
  if (!item) return;
  const today = actualDate(data); const key = action.key || today;
  if (action.type === 'CHECKIN_PAUSE') {
    item.paused = true; const pause = new CheckInPause(); pause.from = today; item.pauses.push(pause); return;
  }
  if (action.type === 'CHECKIN_RESUME') {
    item.paused = false; item.pauses.forEach((pause: CheckInPause): void => { if (!pause.to) pause.to = today; }); syncCheckIns(data); return;
  }
  if (action.type === 'CHECKIN_DELETE') { purgeCheckIn(data, item.id); return; }
  let record = recordFor(data, item.id, key);
  if (action.type === 'CHECKIN_ADVANCE') {
    const preview = previewCheckInRecord(data, item.id, key); if (!preview) return;
    if (!record) { record = preview; data.checkInRecords.push(record); }
    record.status = 'completed'; record.advanced = true; record.backfilled = false;
    record.completedAt = new Date().toISOString(); record.generatedAt = record.completedAt; record.taskId = ''; return;
  }
  if (!record) { record = createRecord(item, key, data.checkInRecords); data.checkInRecords.push(record); }
  if (action.type === 'CHECKIN_GENERATE') { generate(data, item, record, action); return; }
  if (action.type === 'CHECKIN_UNDO') {
    record.status = 'ready'; record.completedAt = ''; record.advanced = false; record.taskDetached = false;
    removeLinkedTask(data, record);
    if (key > today) { record.taskId = ''; record.backfilled = false; return; }
    ensureRecordTask(data, record); return;
  }
  if (action.type === 'CHECKIN_BACKFILL' || action.type === 'CHECKIN_COMPLETE') {
    if (action.type === 'CHECKIN_BACKFILL') {
      record.backfilled = true;
      if (action.text.length > 0) nameSnapshot(record, action.text.trim());
    }
    record.status = 'completed'; record.completedAt = new Date().toISOString(); record.advanced = false;
    if (action.notes !== undefined) record.notes = action.notes.trim();
    const task = allTasks(data).find((value: Task): boolean => value.checkInId === item.id && value.checkInKey === key);
    if (task) { task.text = checkInTaskText(record); task.completed = true; task.completedAt = record.completedAt; task.completedDate = today; if (task.progress !== null) task.progress = 100; }
    // 补卡只落独立历史快照；从未生成的过去周期不会因此产生当日日程。
  }
}

// 普通日程及桌面卡片的完成入口仍共享 reducer，完成时间和备注不会被反向丢失。
export function syncCheckInCompletion(data: AppData): void {
  allTasks(data).forEach((task: Task): void => {
    if (!task.checkInId || !task.checkInKey || task.checkInKey > actualDate(data)) return;
    const record = recordFor(data, task.checkInId, task.checkInKey);
    if (!record || record.status === 'pending') return;
    record.group = task.group || '';
    if (task.completed && record.status !== 'completed') { record.status = 'completed'; record.completedAt = task.completedAt || new Date().toISOString(); }
    else if (!task.completed && record.status === 'completed') { record.status = 'ready'; record.completedAt = ''; record.advanced = false; }
  });
}

export function skipCheckInTask(data: AppData, task: Task): void {
  if (data.checkIns.some((item: CheckInItem): boolean => item.id === task.checkInId && item.deleted)) return;
  const record = recordFor(data, task.checkInId, task.checkInKey);
  if (record) { record.status = 'ready'; record.completedAt = ''; record.advanced = false; record.taskDetached = true; }
}

// 永久删除仅按关联标识清理，同名的普通日程和其他计划不受影响。
function purgeCheckIn(data: AppData, id: string): void {
  const removedAnchor = data.todayTasks.some((task: Task): boolean => task.checkInId === id && task.id === data.todayAnchorId);
  data.checkIns = data.checkIns.filter((item: CheckInItem): boolean => item.id !== id);
  data.checkInRecords = data.checkInRecords.filter((record: CheckInRecord): boolean => record.itemId !== id);
  data.todayTasks = data.todayTasks.filter((task: Task): boolean => task.checkInId !== id);
  data.futureTasks = data.futureTasks.filter((task: Task): boolean => task.checkInId !== id);
  data.history.forEach((entry: HistoryEntry): void => { entry.tasks = entry.tasks.filter((task: Task): boolean => task.checkInId !== id); });
  data.history = data.history.filter((entry: HistoryEntry): boolean => entry.tasks.length > 0);
  if (removedAnchor) data.todayAnchorId = null;
}

// 旧版独立范围并入名称一次。已有可识别数字时保留原名，避免重复范围。
function migrateLegacyName(name: string, useRange: boolean, start: number, end: number): string {
  if (!useRange || parseCheckInName(name).valid || validateCheckInRange(start, end)) return name;
  return name.trim() + ' ' + start.toString() + '-' + end.toString();
}

export function normalizeCheckIns(data: AppData, raw: AppData): void {
  const ids: string[] = []; const keys: string[] = []; const deletedIds: string[] = [];
  data.checkIns = [];
  if (Array.isArray(raw.checkIns)) raw.checkIns.forEach((value: CheckInItem): void => {
    if (!value) return;
    if (value.deleted === true && typeof value.id === 'string') { deletedIds.push(value.id); return; }
    const item = CheckInItem.copy(value);
    if (item.nameVersion < 1) {
      item.name = migrateLegacyName(item.name, item.useRange, item.rangeStart, item.rangeEnd);
      const pattern = parseCheckInName(item.name);
      item.step = pattern.mode === 'range' ? (Number.isSafeInteger(item.count) && item.count > 0 ? item.count : pattern.step) : item.step;
      item.nameVersion = 1; item.incrementMode = 'segment';
      item.useRange = pattern.valid;
      if (pattern.valid) { item.rangeStart = pattern.start; item.rangeEnd = pattern.end; }
      // 无法唯一识别的旧计划保留手动运行，不擅自选其中一个数字递增。
      if (!pattern.valid || !Number.isSafeInteger(item.step) || item.step < 1) item.autoIncrement = false;
    }
    if (!validDate(item.nameAnchorDate)) item.nameAnchorDate = validDate(item.rangeUpdatedFor) ? item.rangeUpdatedFor : (item.startDate > actualDate(data) ? item.startDate : actualDate(data));
    if (!item.id || ids.includes(item.id) || validateCheckIn(item)) return;
    ids.push(item.id); data.checkIns.push(item);
  });
  data.checkInRecords = [];
  if (Array.isArray(raw.checkInRecords)) raw.checkInRecords.forEach((value: CheckInRecord): void => {
    if (!value) return;
    const record = CheckInRecord.copy(value); const key = record.itemId + '\u0000' + record.key;
    if (!record.itemId || !validDate(record.key) || keys.includes(key)) return;
    if (record.nameVersion < 1) {
      record.name = migrateLegacyName(record.name, record.useRange, record.rangeStart, record.rangeEnd);
      record.nameVersion = 1;
    }
    keys.push(key); data.checkInRecords.push(record);
  });
  deletedIds.forEach((id: string): void => purgeCheckIn(data, id));
  // 关联日程按其自己的记录快照迁移文字，绝不套用已编辑的计划名称。
  const snapshots = new Map<string, CheckInRecord>();
  data.checkInRecords.forEach((record: CheckInRecord): void => { snapshots.set(record.itemId + '\u0000' + record.key, record); });
  const taskKeys: string[] = [];
  const unique = (task: Task): boolean => {
    if (!task.checkInId || !task.checkInKey) return true;
    if (task.checkInKey > actualDate(data)) return false;
    const key = task.checkInId + '\u0000' + task.checkInKey;
    if (taskKeys.includes(key)) return false;
    taskKeys.push(key); task.dueDate = null; task.startDate = null; task.scheduledDate = task.checkInKey;
    const record = snapshots.get(key); if (record) task.text = record.name;
    return true;
  };
  data.todayTasks = data.todayTasks.filter(unique);
  data.history.forEach((entry: HistoryEntry): void => { entry.tasks = entry.tasks.filter(unique); });
  data.history = data.history.filter((entry: HistoryEntry): boolean => entry.tasks.length > 0);
  const misplaced = data.futureTasks.filter((task: Task): boolean => !!task.checkInId && !!task.checkInKey).filter(unique);
  data.futureTasks = data.futureTasks.filter((task: Task): boolean => !task.checkInId || !task.checkInKey);
  data.todayTasks = data.todayTasks.concat(misplaced);
  syncCheckInCompletion(data);
}
// 时间线补齐未打开应用时错过的有效周期，合成项只读且不产生日程。
export function checkInTimeline(data: AppData, itemId: string, limit: number = 180): CheckInRecord[] {
  const item = data.checkIns.find((value: CheckInItem): boolean => value.id === itemId);
  const records = data.checkInRecords.filter((record: CheckInRecord): boolean => record.itemId === itemId && record.key <= actualDate(data));
  if (!item) return records.map((record: CheckInRecord): CheckInRecord => CheckInRecord.copy(record)).sort((left: CheckInRecord, right: CheckInRecord): number => right.key.localeCompare(left.key)).slice(0, limit);
  const dates: string[] = [item.startDate].concat(records.map((record: CheckInRecord): string => record.key));
  item.schedules.forEach((schedule: CheckInSchedule): void => { dates.push(schedule.startDate); });
  const earliest = dates.filter((key: string): boolean => validDate(key)).sort()[0];
  const byDate = new Map<string, CheckInRecord>(); records.forEach((record: CheckInRecord): void => { byDate.set(record.key, record); });
  const result: CheckInRecord[] = [];
  let key = actualDate(data);
  while (earliest && key >= earliest && result.length < Math.max(0, limit)) {
    const existing = byDate.get(key);
    if (existing) result.push(CheckInRecord.copy(existing));
    else if (isCheckInDate(item, key)) {
      const record = new CheckInRecord(); record.itemId = item.id; record.key = key; record.status = 'ready'; result.push(record);
    }
    const date = dateValue(key); date.setDate(date.getDate() - 1);
    key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }
  return result;
}

// 所有日期预览都是副本；不存在的过去快照不套用今天名称。
export function previewCheckInRecord(data: AppData, itemId: string, key: string): CheckInRecord | undefined {
  if (!validDate(key)) return undefined;
  const existing = recordFor(data, itemId, key);
  if (existing) return CheckInRecord.copy(existing);
  const item = data.checkIns.find((value: CheckInItem): boolean => value.id === itemId);
  if (!item || item.deleted || !isCheckInDate(item, key)) return undefined;
  if (key < actualDate(data)) {
    const record = new CheckInRecord(); record.itemId = itemId; record.key = key; record.status = 'ready'; return record;
  }
  if (item.paused) return undefined;
  const record = createRecord(item, key, data.checkInRecords);
  record.status = record.name ? 'ready' : 'pending'; return record;
}

function scheduledOnOrAfter(schedule: CheckInSchedule, key: string): string {
  if (schedule.frequency === 'daily') return key;
  const date = dateValue(key);
  if (schedule.frequency === 'weekly') {
    const offsets = schedule.weekdays.filter((day: number): boolean => day >= 0 && day <= 6)
      .map((day: number): number => (day - date.getDay() + 7) % 7).sort((a: number, b: number): number => a - b);
    if (offsets.length === 0) return '';
    date.setDate(date.getDate() + offsets[0]);
    return String(date.getFullYear()).padStart(4, '0') + '-' + String(date.getMonth() + 1).padStart(2, '0') + '-' + String(date.getDate()).padStart(2, '0');
  }
  const days = schedule.monthDays.filter((day: number): boolean => day >= 1 && day <= 31).slice().sort((a: number, b: number): number => a - b);
  if (days.length === 0) return '';
  let month = date.getFullYear() * 12 + date.getMonth(); let lower = date.getDate();
  while (month < 10000 * 12) {
    const year = Math.floor(month / 12); const index = month % 12;
    const last = new Date(year, index + 1, 0, 12).getDate();
    const day = days.find((value: number): boolean => value >= lower && value <= last);
    if (day !== undefined) return String(year).padStart(4, '0') + '-' + String(index + 1).padStart(2, '0') + '-' + String(day).padStart(2, '0');
    month++; lower = 1;
  }
  return '';
}

// limit 表示需要展示的周期数；扩大 limit 可继续读取，休息日不占行。
export function checkInFutureTimeline(data: AppData, itemId: string, limit: number = 30): CheckInRecord[] {
  const count = Number.isFinite(limit) ? Math.max(0, Math.floor(limit)) : 30;
  if (count === 0) return [];
  const today = actualDate(data); const byDate = new Map<string, CheckInRecord>();
  data.checkInRecords.filter((record: CheckInRecord): boolean => record.itemId === itemId && record.key > today)
    .forEach((record: CheckInRecord): void => { byDate.set(record.key, CheckInRecord.copy(record)); });
  const item = data.checkIns.find((value: CheckInItem): boolean => value.id === itemId);
  if (item && !item.paused && !item.deleted && !validateCheckIn(item)) {
    let generated = 0; let periods = -1; let key = nextDay(today);
    while (validDate(key) && generated < count) {
      if (item.deletedDate && key >= item.deletedDate) break;
      const pause = item.pauses.find((value: CheckInPause): boolean => value.from <= key && (!value.to || key < value.to));
      if (pause) { if (!pause.to || !validDate(pause.to)) break; key = pause.to; continue; }
      const schedule = scheduleOf(item, key);
      if (!validDate(schedule.startDate)) break;
      if (schedule.startDate > key) {
        // 若节律在开始日期之前有新的版本，先跳到版本边界再重新判断。
        const changes = item.schedules.filter((value: CheckInSchedule): boolean => value.effectiveFrom > key && value.effectiveFrom < schedule.startDate)
          .map((value: CheckInSchedule): string => value.effectiveFrom).sort();
        key = changes[0] || schedule.startDate; continue;
      }
      const due = scheduledOnOrAfter(schedule, key);
      if (!validDate(due)) break;
      if (due > key) {
        const boundaries = item.schedules.map((value: CheckInSchedule): string => value.effectiveFrom)
          .concat(item.pauses.map((value: CheckInPause): string => value.from))
          .filter((date: string): boolean => date > key && date < due).sort();
        key = boundaries[0] || due; continue;
      }
      if (isCheckInDate(item, key)) {
        periods = periods < 0 ? projectedPeriods(item, key) : periods + 1;
        const existing = recordFor(data, itemId, key);
        const record = existing ? CheckInRecord.copy(existing) : createRecord(item, key, data.checkInRecords, periods);
        if (!existing) record.status = record.name ? 'ready' : 'pending';
        byDate.set(key, record); generated++;
      }
      key = nextDay(key);
    }
  }
  return Array.from(byDate.values()).sort((left: CheckInRecord, right: CheckInRecord): number => left.key.localeCompare(right.key)).slice(0, count);
}

// 连续值按应打卡日计算，休息日与暂停日不打断；整体某日所有应打项目完成才计为完成日。
export function checkInStats(data: AppData, itemId: string = '', through: string = actualDate(data)): CheckInStats {
  const stats = new CheckInStats(); const end = through > actualDate(data) ? actualDate(data) : through;
  const items = data.checkIns.filter((item: CheckInItem): boolean => !itemId || item.id === itemId);
  const records = data.checkInRecords.filter((record: CheckInRecord): boolean => (!itemId || record.itemId === itemId) && record.key <= end);
  const dates: string[] = items.map((item: CheckInItem): string => item.startDate).concat(records.map((record: CheckInRecord): string => record.key)).filter((key: string): boolean => validDate(key));
  items.forEach((item: CheckInItem): void => item.schedules.forEach((schedule: CheckInSchedule): void => { if (validDate(schedule.startDate)) dates.push(schedule.startDate); }));
  if (!validDate(end) || dates.length === 0) return stats;
  // 先索引周期，避免多年历史的每一天都扫描全部记录。
  const byPeriod = new Map<string, CheckInRecord>(); const orphanByDate = new Map<string, CheckInRecord[]>();
  const itemIds: string[] = items.map((item: CheckInItem): string => item.id);
  records.forEach((record: CheckInRecord): void => {
    byPeriod.set(record.itemId + '\u0000' + record.key, record);
    if (!itemIds.includes(record.itemId)) {
      const list = orphanByDate.get(record.key) || []; list.push(record); orphanByDate.set(record.key, list);
    }
  });
  dates.sort(); let streak = 0; let lastComplete = 0;
  for (let key = dates[0]; key <= end; key = nextDay(key)) {
    let expected = 0; let completed = 0;
    items.forEach((item: CheckInItem): void => {
      const record = byPeriod.get(item.id + '\u0000' + key);
      if (record || isCheckInDate(item, key)) { expected++; if (record?.status === 'completed') completed++; }
    });
    (orphanByDate.get(key) || []).forEach((record: CheckInRecord): void => { expected++; if (record.status === 'completed') completed++; });
    stats.total += expected; stats.completed += completed;
    if (expected === 0) continue;
    if (completed === expected) { streak++; lastComplete = streak; stats.longestStreak = Math.max(stats.longestStreak, streak); }
    else if (key !== actualDate(data)) { streak = 0; lastComplete = 0; }
  }
  stats.currentStreak = lastComplete;
  stats.rate = stats.total > 0 ? Math.round(stats.completed * 1000 / stats.total) / 10 : 0;
  return stats;
}