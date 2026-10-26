// 打卡条目与周期快照独立存储，编辑计划不回写已经生成的历史。
export type CheckInFrequency = 'daily' | 'weekly' | 'monthly';
export type CheckInStatus = 'pending' | 'ready' | 'completed' | 'skipped';
export type CheckInIncrementMode = 'segment' | 'shift';

// 数字模板只描述名称中唯一的一处整数或整数范围；前导零仅用于显示。
export class CheckInNamePattern {
  valid: boolean = false;
  error: string = '';
  mode: 'none' | 'single' | 'range' = 'none';
  prefix: string = '';
  suffix: string = '';
  separator: string = '-';
  start: number = 0;
  end: number = 0;
  startWidth: number = 0;
  endWidth: number = 0;
  step: number = 1;
}
export class CheckInPause {
  from: string = '';
  to: string = '';
  static copy(value: CheckInPause): CheckInPause {
    const result = new CheckInPause();
    result.from = value.from || ''; result.to = value.to || '';
    return result;
  }
}

export class CheckInSchedule {
  effectiveFrom: string = '';
  startDate: string = '';
  frequency: CheckInFrequency = 'daily';
  weekdays: number[] = [];
  monthDays: number[] = [];
  static copy(value: CheckInSchedule): CheckInSchedule {
    const result = new CheckInSchedule();
    result.effectiveFrom = value.effectiveFrom || ''; result.startDate = value.startDate || '';
    result.frequency = value.frequency === 'weekly' || value.frequency === 'monthly' ? value.frequency : 'daily';
    result.weekdays = Array.isArray(value.weekdays) ? value.weekdays.filter((day: number): boolean => Number.isInteger(day) && day >= 0 && day <= 6) : [];
    result.monthDays = Array.isArray(value.monthDays) ? value.monthDays.filter((day: number): boolean => Number.isInteger(day) && day >= 1 && day <= 31) : [];
    return result;
  }
}

export class CheckInItem {
  id: string = '';
  name: string = '';
  group: string = '';
  nameVersion: number = 1;
  goal: string = '';
  startDate: string = '';
  frequency: CheckInFrequency = 'daily';
  weekdays: number[] = [];
  monthDays: number[] = [];
  paused: boolean = false;
  deleted: boolean = false;
  autoIncrement: boolean = false;
  useRange: boolean = false;
  rangeStart: number = 1;
  rangeEnd: number = 10;
  incrementMode: CheckInIncrementMode = 'segment';
  step: number = 1;
  count: number = 10;
  // 保留旧字段读取兼容；开启自动递增即确认后续周期规则。
  confirmNext: boolean = false;
  notes: string = '';
  createdAt: string = '';
  deletedDate: string = '';
  rangeUpdatedFor: string = '';
  // 未生成首期或手动重设数字后，从此日期起的首个有效周期使用当前名称。
  nameAnchorDate: string = '';
  pauses: CheckInPause[] = [];
  schedules: CheckInSchedule[] = [];

  clone(): CheckInItem { return CheckInItem.copy(this); }
  static copy(value: CheckInItem): CheckInItem {
    const item = new CheckInItem();
    item.id = typeof value.id === 'string' ? value.id : '';
    item.name = typeof value.name === 'string' ? value.name : '';
    item.group = typeof value.group === 'string' ? value.group.trim() : '';
    item.nameVersion = typeof value.nameVersion === 'number' ? value.nameVersion : 0;
    item.goal = typeof value.goal === 'string' ? value.goal : '';
    item.startDate = typeof value.startDate === 'string' ? value.startDate : '';
    item.frequency = value.frequency === 'weekly' || value.frequency === 'monthly' ? value.frequency : 'daily';
    item.weekdays = Array.isArray(value.weekdays) ? value.weekdays.slice() : [];
    item.monthDays = Array.isArray(value.monthDays) ? value.monthDays.slice() : [];
    item.paused = value.paused === true; item.deleted = value.deleted === true;
    item.autoIncrement = value.autoIncrement === true; item.useRange = value.useRange === true;
    item.rangeStart = typeof value.rangeStart === 'number' ? value.rangeStart : 1;
    item.rangeEnd = typeof value.rangeEnd === 'number' ? value.rangeEnd : 10;
    item.incrementMode = value.incrementMode === 'shift' ? 'shift' : 'segment';
    item.step = typeof value.step === 'number' ? value.step : 1;
    item.count = typeof value.count === 'number' ? value.count : 10;
    item.confirmNext = false;
    item.notes = typeof value.notes === 'string' ? value.notes : '';
    item.createdAt = value.createdAt || ''; item.deletedDate = value.deletedDate || '';
    item.rangeUpdatedFor = value.rangeUpdatedFor || '';
    item.nameAnchorDate = value.nameAnchorDate || '';
    item.pauses = Array.isArray(value.pauses) ? value.pauses.filter((entry: CheckInPause): boolean => !!entry).map((entry: CheckInPause): CheckInPause => CheckInPause.copy(entry)) : [];
    item.schedules = Array.isArray(value.schedules) ? value.schedules.filter((entry: CheckInSchedule): boolean => !!entry).map((entry: CheckInSchedule): CheckInSchedule => CheckInSchedule.copy(entry)) : [];
    return item;
  }
}

export class CheckInRecord {
  itemId: string = '';
  key: string = '';
  status: CheckInStatus = 'pending';
  name: string = '';
  group: string = '';
  nameVersion: number = 1;
  goal: string = '';
  useRange: boolean = false;
  rangeStart: number = 0;
  rangeEnd: number = 0;
  notes: string = '';
  completedAt: string = '';
  backfilled: boolean = false;
  advanced: boolean = false;
  // 删除日程只解除显示，不再把周期标为跳过。
  taskDetached: boolean = false;
  taskId: string = '';
  generatedAt: string = '';
  clone(): CheckInRecord { return CheckInRecord.copy(this); }
  static copy(value: CheckInRecord): CheckInRecord {
    const record = new CheckInRecord();
    record.itemId = typeof value.itemId === 'string' ? value.itemId : '';
    record.key = typeof value.key === 'string' ? value.key : '';
    record.status = value.status === 'skipped' ? 'ready' : (['ready', 'completed'].includes(value.status) ? value.status : 'pending');
    record.name = typeof value.name === 'string' ? value.name : '';
    record.group = typeof value.group === 'string' ? value.group.trim() : '';
    record.nameVersion = typeof value.nameVersion === 'number' ? value.nameVersion : 0;
    record.goal = typeof value.goal === 'string' ? value.goal : '';
    record.useRange = value.useRange === true;
    record.rangeStart = Number.isFinite(value.rangeStart) ? value.rangeStart : 0;
    record.rangeEnd = Number.isFinite(value.rangeEnd) ? value.rangeEnd : 0;
    record.notes = typeof value.notes === 'string' ? value.notes : '';
    record.completedAt = value.status === 'skipped' ? '' : (value.completedAt || ''); record.backfilled = value.backfilled === true;
    record.advanced = value.advanced === true; record.taskDetached = value.taskDetached === true || value.status === 'skipped';
    record.taskId = value.taskId || ''; record.generatedAt = value.generatedAt || '';
    return record;
  }
}

export class CheckInRange {
  start: number = 0;
  end: number = 0;
  constructor(start: number = 0, end: number = 0) { this.start = start; this.end = end; }
}

export class CheckInStats {
  completed: number = 0;
  total: number = 0;
  rate: number = 0;
  currentStreak: number = 0;
  longestStreak: number = 0;
}
