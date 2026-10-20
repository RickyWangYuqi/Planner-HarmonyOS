import { AppAction, AppData, HistoryEntry, Task } from '../model/PlanerModel';
import { freshData, reduce } from '../model/PlanerEngine';
import { Palette, paletteFor } from '../theme/Theme';
import { HistoryView } from '../components/HistoryView';
import { SettingsView } from '../components/SettingsView';
import { TaskEditor } from '../components/TaskEditor';

function previewData(): AppData {
  const data = freshData();
  data.currentDate = '2026-10-15';
  data.groups = ['工作', '生活'];
  data.settings.showGroups = true;
  const task = new Task();
  task.id = 'preview-done';
  task.text = '整理本周的会议记录';
  task.group = '工作';
  task.completed = true;
  task.progress = 100;
  task.plannedDate = '2026-10-14';
  task.createdAt = '2026-10-14T01:00:00.000Z';
  task.completedAt = '2026-10-14T08:00:00.000Z';
  const history = new HistoryEntry();
  history.date = '2026-10-14';
  history.tasks = [task];
  data.history = [history];
  return data;
}

// 复用正式组件的无设备预览入口；样例仅驻留内存，不调用应用存储。
@Preview({ title: 'Planer 手机组件', width: 390, height: 844, locale: 'zh_CN', deviceType: 'phone' })
@Component
struct PlanerPreview {
  @State private data: AppData = previewData();
  @State private view: string = 'settings';

  private colors(): Palette {
    return paletteFor(this.data.settings.colorPreset, this.data.settings.themeMode === 'dark');
  }

  private apply(action: AppAction): void {
    this.data = reduce(this.data, action);
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button('设置', { type: ButtonType.Normal }).height(44).borderRadius(12).onClick((): void => { this.view = 'settings'; })
        Button('历史', { type: ButtonType.Normal }).height(44).borderRadius(12).onClick((): void => { this.view = 'history'; })
        Button('新建', { type: ButtonType.Normal }).height(44).borderRadius(12).onClick((): void => { this.view = 'editor'; })
      }.width('100%').justifyContent(FlexAlign.Center).padding(8)
      Column() {
        if (this.view === 'settings') {
          SettingsView({
            data: this.data,
            palette: this.colors(),
            onAction: (action: AppAction): void => this.apply(action),
            onHistory: (): void => { this.view = 'history'; }
          })
        } else if (this.view === 'history') {
          HistoryView({
            data: this.data,
            palette: this.colors(),
            onBack: (): void => { this.view = 'settings'; },
            onRestore: (task: Task, date: string): void => {
              const action = new AppAction('RESTORE');
              action.id = task.id;
              action.entryDate = date;
              this.apply(action);
            },
            onDelete: (task: Task, date: string): void => {
              const action = new AppAction('DELETE_HISTORY_TASK');
              action.id = task.id;
              action.entryDate = date;
              this.apply(action);
            },
            onClear: (): void => this.apply(new AppAction('CLEAR_HISTORY'))
          })
        } else {
          TaskEditor({
            data: this.data,
            palette: this.colors(),
            section: 'future',
            onAction: (action: AppAction): void => this.apply(action),
            onClose: (): void => { this.view = 'settings'; }
          })
        }
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%').backgroundColor(this.colors().bg)
  }
}
