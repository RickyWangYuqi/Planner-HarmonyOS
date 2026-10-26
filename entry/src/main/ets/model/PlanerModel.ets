import { CheckInItem, CheckInRecord } from './CheckInModel';
// 与桌面版一致的数据结构；保留桌面窗口字段，以便数据版本兼容。
export class Task {
  id: string = '';
  text: string = '';
  createdAt: string = '';
  scheduledDate: string | null = null;
  completedDate: string | null = null;
  group: string | null = null;
  startDate: string | null = null;
  dueDate: string | null = null;
  completed: boolean = false;
  completedAt: string | null = null;
  progress: number | null = null;
  plannedDate: string | null = null;
  archivedAt: string | null = null;
  checkInId: string = '';
  checkInKey: string = '';

  clone(): Task {
    return Task.copy(this);
  }

  static copy(source: Task): Task {
    const task = new Task();
    task.id = typeof source.id === 'string' ? source.id : '';
    task.text = typeof source.text === 'string' ? source.text : '';
    task.createdAt = source.createdAt || new Date().toISOString();
    task.group = typeof source.group === 'string' && source.group.trim() ? source.group.trim() : null;
    task.startDate = source.startDate || null;
    task.dueDate = source.dueDate || null;
    task.scheduledDate = typeof source.scheduledDate === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(source.scheduledDate) ? source.scheduledDate : null;
    task.completedDate = typeof source.completedDate === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(source.completedDate) ? source.completedDate : null;
    task.completed = source.completed === true;
    task.completedAt = source.completedAt || null;
    task.progress = typeof source.progress === 'number' && Number.isFinite(source.progress)
      ? Math.max(0, Math.min(100, Math.round(source.progress))) : null;
    task.plannedDate = source.plannedDate || null;
    task.archivedAt = source.archivedAt || null;
    task.checkInId = typeof source.checkInId === 'string' ? source.checkInId : '';
    task.checkInKey = typeof source.checkInKey === 'string' ? source.checkInKey : '';
    return task;
  }
}

export class HistoryEntry {
  date: string = '';
  tasks: Task[] = [];

  clone(): HistoryEntry {
    const entry = new HistoryEntry();
    entry.date = this.date;
    entry.tasks = this.tasks.map((task: Task): Task => Task.copy(task));
    return entry;
  }
}

export class Settings {
  alwaysOnTop: boolean = false;
  autoHideFullscreen: boolean = false;
  autoNumber: boolean = true;
  shrinkOnBlur: boolean = false;
  themeMode: string = 'system';
  colorPreset: string = 'seasalt';
  closeAction: string = 'exit';
  launchAtStartup: boolean = false;
  progressDefaultZero: boolean = false;
  autoScrollNextOnComplete: boolean = false;
  todayPaneRatio: number = 0.45;
  showGroups: boolean = false;
  retainCompletedFutureUntilDue: boolean = false;

  clone(): Settings {
    return Settings.copy(this);
  }

  static copy(source: Settings): Settings {
    const settings = new Settings();
    if (!source) return settings;
    settings.alwaysOnTop = source.alwaysOnTop === true;
    settings.autoHideFullscreen = source.autoHideFullscreen === true;
    settings.autoNumber = source.autoNumber !== false;
    settings.shrinkOnBlur = source.shrinkOnBlur === true;
    settings.themeMode = ['light', 'dark', 'system'].includes(source.themeMode) ? source.themeMode : 'system';
    settings.colorPreset = ['seasalt', 'forest', 'sunset', 'ink'].includes(source.colorPreset) ? source.colorPreset : 'seasalt';
    settings.closeAction = source.closeAction === 'tray' ? 'tray' : 'exit';
    settings.launchAtStartup = source.launchAtStartup === true;
    settings.progressDefaultZero = source.progressDefaultZero === true;
    settings.autoScrollNextOnComplete = source.autoScrollNextOnComplete === true;
    settings.showGroups = source.showGroups === true;
    settings.retainCompletedFutureUntilDue = source.retainCompletedFutureUntilDue === true;
    settings.todayPaneRatio = typeof source.todayPaneRatio === 'number' && Number.isFinite(source.todayPaneRatio)
      ? Math.max(0.03, Math.min(0.97, source.todayPaneRatio)) : 0.45;
    return settings;
  }
}

export class AppData {
  version: number = 1;
  currentDate: string = '';
  // 与浏览日期分离，只有真实日期推进才更新该字段。
  lastRolloverDate: string = '';
  todayTasks: Task[] = [];
  futureTasks: Task[] = [];
  groups: string[] = [];
  history: HistoryEntry[] = [];
  checkIns: CheckInItem[] = [];
  checkInRecords: CheckInRecord[] = [];
  settings: Settings = new Settings();
  todayAnchorId: string | null = null;

  clone(): AppData {
    const data = new AppData();
    data.version = this.version;
    data.currentDate = this.currentDate;
    data.lastRolloverDate = this.lastRolloverDate;
    data.todayTasks = this.todayTasks.map((task: Task): Task => Task.copy(task));
    data.futureTasks = this.futureTasks.map((task: Task): Task => Task.copy(task));
    data.groups = this.groups.slice();
    data.history = this.history.map((entry: HistoryEntry): HistoryEntry => {
      const copy = new HistoryEntry();
      copy.date = entry.date;
      copy.tasks = entry.tasks.map((task: Task): Task => Task.copy(task));
      return copy;
    });
    data.checkIns = (this.checkIns || []).map((item: CheckInItem): CheckInItem => CheckInItem.copy(item));
    data.checkInRecords = (this.checkInRecords || []).map((record: CheckInRecord): CheckInRecord => CheckInRecord.copy(record));
    data.settings = Settings.copy(this.settings);
    data.todayAnchorId = this.todayAnchorId;
    return data;
  }
}

// 可选字段保留“未修改”和“清除”的区别，避免覆盖隐藏分组及日期。
export class AppAction {
  type: string;
  id: string = '';
  section: string = 'today';
  to: string = 'today';
  text: string = '';
  key: string = '';
  group?: string | null;
  startDate?: string | null;
  dueDate?: string | null;
  progress?: number | null;
  from: number = 0;
  toIndex: number = 0;
  entryDate: string = '';
  target: string = 'today';
  settings?: Settings;
  data?: AppData;
  checkIn?: CheckInItem;
  rangeStart?: number;
  rangeEnd?: number;
  notes?: string;

  constructor(type: string) {
    this.type = type;
  }
}
