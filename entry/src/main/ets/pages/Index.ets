import { ResponsiveLayout } from '../theme/ResponsiveLayout';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { window, KeyboardAvoidMode, FrameCallback, SymbolGlyphModifier } from '@kit.ArkUI';
import { AppData, AppAction, Task } from '../model/PlanerModel';
import { freshData, reduce, todayKey, addDays, formatFull, formatRange, normalizeData, realDateOf } from '../model/PlanerEngine';
import { PlanerStorage } from '../services/PlanerStorage';
import { FormSync } from '../services/FormSync';
import { TutorialStorage } from '../services/TutorialStorage';
import { TutorialView } from '../components/TutorialView';
import { TutorialProgress, shouldAutoTutorial, closeTutorial } from '../tutorial/TutorialConfig';
import { Palette, paletteFor } from '../theme/Theme';
import { IconButton } from '../components/IconButton';
import { PlanerCalendar } from '../components/CalendarPicker';
import { TaskEditor } from '../components/TaskEditor';
import { SettingsView } from '../components/SettingsView';
import { HistoryView } from '../components/HistoryView';
import { CheckInView } from '../components/CheckInView';
import { validateCheckInAction } from '../model/CheckInEngine';
import { PlanerIcon } from '../components/PlanerIcon';
import { GroupDragVisual, GroupDragMember } from '../components/GroupDragVisual';
import { TaskCardView } from '../components/TaskCardView';
import { Motion, Materials, PlanerTabsModifier, PlanerControlModifier, ButtonFeedback } from '../theme/Appearance';
import { MaterialButtonScope } from '../components/MaterialButtonScope';
import { SheetMaterialSurface } from '../components/SheetMaterialSurface';
import { MaterialSection, EditorMaterialRefresh } from '../components/MaterialSection';

// 每次只保留一个系统帧回调；停止后的旧回调由代次校验失效。
class DragScrollFrame extends FrameCallback {
  private callback: (time: number) => void;
  constructor(callback: (time: number) => void) { super(); this.callback = callback; }
  onFrame(frameTimeInNano: number): void { this.callback(frameTimeInNano); }
}

// 教程首帧提交后启动条目动画，与原生面板的上升动画并行。
class TutorialEntranceFrame extends FrameCallback {
  private action: () => void;
  constructor(action: () => void) { super(); this.action = action; }
  onFrame(_time: number): void { this.action(); }
}

class DragBounds {
  left: number = 0;
  top: number = 0;
  width: number = 0;
  height: number = 0;
}

// 手势与落点算法共享窗口坐标，不再依赖系统拖拽预览的生命周期。
class PlanerDragPoint {
  private x: number;
  private y: number;
  result: DragResult = DragResult.DRAG_CANCELED;
  constructor(x: number, y: number) { this.x = x; this.y = y; }
  getWindowX(): number { return this.x; }
  getWindowY(): number { return this.y; }
  setResult(result: DragResult): void { this.result = result; }
}

@Entry
@Component
struct Index {
  @StorageProp('planerSafeTop') safeTop: number = 0;
  @StorageProp('planerSafeBottom') safeBottom: number = 0;
  @State data: AppData = freshData();
  @State palette: Palette = paletteFor('seasalt', false);
  @State ready: boolean = false;
  @State loadError: string = '';
  @State saveError: string = '';
  @State saving: boolean = false;
  @State private tutorialShown: boolean = false;
  @State private tutorialEntered: boolean = false;
  @State private tutorialProgress: TutorialProgress = new TutorialProgress();
  @State private tutorialError: string = '';
  private tutorialStore: TutorialStorage = new TutorialStorage();
  private tutorialLoading: boolean = true;
  private tutorialStoreReady: boolean = false;
  private tutorialDisposed: boolean = false;
  private tutorialRevision: number = 0;
  private tutorialEntranceRevision: number = 0;
  @State page: number = 0;
  @State checkInRequestedId: string = '';
  @State checkInRequestRevision: number = 0;
  private checkInSheetShown: boolean = false;
  private foregroundSyncPending: boolean = false;
  @State private historyCreated: boolean = false;
  @State modal: string = '';
  @State sheetShown: boolean = false;
  @State activeTab: number = 0;
  @State displayedTab: number = 0;
  @State editorSection: string = 'today';
  @State selectedTask: Task = new Task();
  @State selectedHistoryDate: string = '';
  @State selectedTarget: number = 0;
  @State selectedGroup: string | null | undefined = undefined;
  @State restoreTarget: string = 'today';
  @State restoreDate: string = '';
  @State private modalPressedButton: string = '';
  private modalScroller: Scroller = new Scroller();
  @State splitRatio: number = 0.45;
  @State dragId: string = '';
  @State dragSection: string = '';
  @State dragIsGroup: boolean = false;
  @State dragGroup: string | null = null;
  @State dropSection: string = '';
  @State dropIndex: number = -1;
  @State dragHeight: number = 58;
  @StorageProp('systemDark') @Watch('darkModeChanged') systemDark: boolean = false;
  @StorageProp('planerForeground') @Watch('foregroundChanged') foregroundTick: number = 0;
  @StorageProp('planerBackground') @Watch('backgroundChanged') backgroundTick: number = 0;
  private tabsController: TabsController = new TabsController();
  private paletteKey: string = '';
  private appliedColorMode: string = '';
  private storage: PlanerStorage = new PlanerStorage();
  private context: common.UIAbilityContext | null = null;
  private todayScroller: Scroller = new Scroller();
  private futureScroller: Scroller = new Scroller();
  private settingsScroller: Scroller = new Scroller();
  private historyScroller: Scroller = new Scroller();
  private timer: number = -1;
  private saveRevision: number = 0;
  private anchorRevision: number = 0;
  private anchorPending: boolean = false;
  // 最近一次与磁盘一致的数据快照，用于识别卡片进程写入的变更。
  private adoptedRaw: string = '';
  @State private paneHeight: number = 0;
  @State private viewportWidth: number = 0;
  @State private wideLayout: boolean = false;
  private splitStart: number = 0.45;
  private todayTop: number = 0;
  private todayHeight: number = 200;
  private futureTop: number = 0;
  private futureHeight: number = 300;
  @State private futureTailSpace: number = 44;
  @State private todayMoreBelow: boolean = false;
  @State private futureMoreBelow: boolean = false;
  @State private futureMoreInset: number = 0;
  private todayFirstVisible: number = -1;
  private todayLastVisible: number = -1;
  private futureFirstVisible: number = -1;
  private futureLastVisible: number = -1;
  private moreLayout: (() => void) | undefined = undefined;
  private dragPointerX: number = 0;
  private dragPointerY: number = 0;
  private dragHoverSection: string = '';
  private edgeFramePending: boolean = false;
  private edgeGeneration: number = 0;
  private edgeFrameTime: number = 0;
  private edgeLastOffset: number = 0;
  private edgeExpectedMove: boolean = false;
  private edgeStalledFrames: number = 0;
  @State private dropGroup: string | null | undefined = undefined;
  @State private floatingPhase: string = 'idle';
  @State private floatingTask: Task = new Task();
  @State private floatingTasks: Task[] = [];
  @State private floatingMembers: GroupDragMember[] = [];
  @State private floatingGroup: boolean = false;
  @State private floatingSection: string = 'today';
  @State private floatingOrder: number = 1;
  @State private floatingX: number = 0;
  @State private floatingY: number = 0;
  @State private floatingWidth: number = 1;
  @State private floatingHeight: number = 1;
  @State private floatingLift: number = 0;
  private floatingGeneration: number = 0;
  private floatingPointer: number = -1;
  private floatingOriginX: number = 0;
  private floatingOriginY: number = 0;
  private floatingTouchX: number = 0;
  private floatingTouchY: number = 0;
  private floatingRootX: number = 0;
  private floatingRootY: number = 0;
  private floatingMoved: boolean = false;
  private landingLayout: (() => void) | undefined = undefined;


  aboutToAppear(): void {
    this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 页面保持原尺寸；编辑器按实际键盘交叠局部避让，不挤压底层主页。
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    this.startMoreObservation();
    this.load();
    this.timer = setInterval(() => this.checkDate(), 30000);
  }

  aboutToDisappear(): void {
    this.tutorialDisposed = true;
    this.anchorRevision++;
    this.anchorPending = false;
    this.stopMoreObservation();
    if (this.timer >= 0) clearInterval(this.timer);
    this.resetDrag();
  }

  onPageHide(): void {
    this.resetDrag();
  }

  onPageShow(): void {
    this.checkDate();
  }

  onBackPress(): boolean {
    if (this.tutorialShown) {
      this.dismissTutorial();
      return true;
    }
    if (this.sheetShown) {
      this.closeModal();
      return true;
    }
    if (this.dragId || this.dragIsGroup) {
      this.resetDrag();
      return true;
    }
    // 打卡弹层交给系统返回手势关闭，并由回调同步状态。
    if (this.checkInSheetShown) return false;
    if (this.page === 3) {
      this.navigate(2);
      return true;
    }
    return false;
  }

  private async load(): Promise<void> {
    if (!this.context) return;
    this.ready = false;
    this.loadError = '';
    try {
      this.data = await this.storage.load(this.context);
      this.adoptedRaw = JSON.stringify(this.data);
      this.splitRatio = this.data.settings.todayPaneRatio;
      this.updatePalette();
      this.ready = true;
      this.updatePalette();
      this.checkDate();
      this.dispatch(new AppAction('CHECKIN_SYNC'));
      this.restoreAnchor();
      this.initializeTutorial();
      // 启动时先与桌面卡片对齐一次：卡片可能停在上次退出前的状态。
      this.syncForm();
    } catch (error) {
      this.loadError = '无法读取本地日程。请重试；原数据文件已保留。';
    }
  }

  private async initializeTutorial(): Promise<void> {
    if (!this.context) return;
    try {
      const progress = await this.tutorialStore.load(this.context);
      if (this.tutorialDisposed) return;
      this.tutorialStoreReady = true;
      this.tutorialProgress = progress;
    } catch (error) {
      if (this.tutorialDisposed) return;
      this.tutorialError = '教程进度暂不可用';
    }
    this.tutorialLoading = false;
    if (shouldAutoTutorial(this.tutorialProgress)) this.openTutorial();
  }

  private openTutorial(): void {
    if (this.tutorialLoading || this.tutorialShown) return;
    this.resetDrag();
    this.tutorialEntranceRevision++;
    this.tutorialEntered = false;
    this.tutorialShown = true;
  }

  private dismissTutorial(): void {
    this.tutorialEntranceRevision++;
    this.tutorialShown = false;
    this.completeTutorial();
  }

  private completeTutorial(): void {
    // 按钮、返回、遮罩与下滑关闭共用标记；不因 onDisappear 再次落盘。
    if (this.tutorialProgress.status === 'completed') return;
    this.tutorialProgress = closeTutorial(this.tutorialProgress);
    this.saveTutorial();
  }

  private tutorialContentReady(): void {
    const revision = this.tutorialEntranceRevision;
    this.getUIContext().postFrameCallback(new TutorialEntranceFrame((): void => {
      if (!this.tutorialDisposed && this.tutorialShown && revision === this.tutorialEntranceRevision) {
        this.tutorialEntered = true;
      }
    }));
  }

  @Builder
  private tutorialContent() {
    TutorialView({ wideLayout: this.wideLayout, palette: this.palette, safeBottom: this.safeBottom, entered: this.tutorialEntered,
      saveError: this.tutorialError, onClose: (): void => this.dismissTutorial(),
      onRetry: (): void => { this.saveTutorial(true); } })
      .onAppear((): void => this.tutorialContentReady())
  }

  @Builder
  private tutorialSurfaceContent() {
    SheetMaterialSurface({ palette: this.palette, radius: 26, content: () => { this.tutorialContent(); } })
  }

  private async saveTutorial(retry: boolean = false): Promise<void> {
    const progress = this.tutorialProgress;
    const revision = ++this.tutorialRevision;
    try {
      if (retry && !this.tutorialStoreReady && this.context) {
        await this.tutorialStore.load(this.context);
        this.tutorialStoreReady = true;
      }
      await this.tutorialStore.save(progress);
      if (!this.tutorialDisposed && revision === this.tutorialRevision) this.tutorialError = '';
    } catch (error) {
      if (this.tutorialDisposed || revision !== this.tutorialRevision) return;
      this.tutorialError = '教程进度未保存';
      if (!this.tutorialShown) {
        try {
          this.getUIContext().getPromptAction().showToast({ message: '教程进度保存失败，下次可能再次显示。可从设置回看并重试。' });
        } catch (toastError) { console.warn('无法显示教程进度提示'); }
      }
    }
  }
  private updatePalette(): void {
    const mode = this.data.settings.themeMode;
    if (this.ready && this.context && this.appliedColorMode !== mode) {
      // 只切换本应用颜色模式；回到跟随系统时解除应用覆盖，由配置回调同步系统值。
      try {
        this.context.getApplicationContext().setColorMode(mode === 'dark' ?
        ConfigurationConstant.ColorMode.COLOR_MODE_DARK : (mode === 'light' ?
        ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET));
        this.appliedColorMode = mode;
      } catch (error) {
        console.error('更新应用颜色模式失败：' + String(error));
      }
    }
    const dark = mode === 'dark' || (mode === 'system' && this.systemDark);
    const key = this.data.settings.colorPreset + ':' + dark;
    if (key === this.paletteKey) return;
    this.paletteKey = key;
    this.getUIContext().animateTo(Motion.theme(), () => {
      this.palette = paletteFor(this.data.settings.colorPreset, dark);
    });
    this.updateSystemBars(dark);
  }
  private async updateSystemBars(dark: boolean): Promise<void> {
    if (!this.context) return;
    try {
      const currentWindow = await window.getLastWindow(this.context);
      await currentWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: dark ? '#E7EEFB' : '#1E2B45',
        navigationBarContentColor: dark ? '#E7EEFB' : '#1E2B45'
      });
    } catch (error) {
      console.error('更新系统栏颜色失败：' + String(error));
    }
  }

  // 退到后台时补推一次卡片：被 router 进入的那张卡片回到桌面时才重绘，届时数据已是最新。
  private backgroundChanged(): void {
    this.syncForm();
  }

  private async foregroundChanged(): Promise<void> {
    this.resetDrag();
    // 必须先把卡片进程写进磁盘的改动采纳进来：卡片上完成的未来日程只落在文件里，
    // 若先 checkDate / syncForm，会用内存中的旧状态把文件覆盖回去，卡片随即“复活”已完成项。
    if (this.saving) { this.foregroundSyncPending = true; return; }
    if (!await this.adoptExternalChange()) return;
    this.checkDate();
    if (this.ready) this.dispatch(new AppAction('CHECKIN_SYNC'));
    this.syncForm();
  }

  // 系统深色开关变化：应用内立即换色，跟随系统时同步把新配色推给桌面卡片。
  private darkModeChanged(): void {
    this.updatePalette();
    if (this.data.settings.themeMode === 'system') this.syncForm();
  }

  private async adoptExternalChange(): Promise<boolean> {
    if (!this.context || !this.ready) return false;
    if (this.saving || this.dragId || this.dragIsGroup) return false;
    try {
      const raw: string = await this.storage.readRaw(this.context);
      if (!raw) return false;
      if (raw === this.adoptedRaw) return true;
      const data: AppData = normalizeData(JSON.parse(raw) as AppData);
      this.adoptedRaw = raw;
      this.data = data;
      this.splitRatio = data.settings.todayPaneRatio;
      this.updatePalette();
      return true;
    } catch (error) {
      console.warn('外部日程变更无法解析，保留当前状态。');
      return false;
    }
  }

  private checkDate(): void {
    if (!this.ready || todayKey() <= realDateOf(this.data)) return;
    const action = new AppAction('ROLLOVER_TO');
    action.key = todayKey();
    this.dispatch(action);
  }

  private dispatch(action: AppAction): void {
    if (!this.ready) return;
    // 处理操作发生前的真实跨日；预览未来不能让日历时钟跳过午夜检查。
    if (action.type !== 'ROLLOVER_TO' && todayKey() > realDateOf(this.data)) {
      const elapsed = new AppAction('ROLLOVER_TO');
      elapsed.key = todayKey();
      this.data = reduce(this.data, elapsed);
    }
    if (action.type.startsWith('CHECKIN_')) {
      const message = validateCheckInAction(this.data, action);
      if (message) {
        this.checkInFeedback(message);
        return;
      }
    }
    const previousAnchor = this.data.todayAnchorId;
    const autoBefore = this.data.settings.autoScrollNextOnComplete;
    const first = this.data.todayTasks.find((task: Task): boolean => !task.completed);
    // 取消完成后再次勾选，下一项可能仍等于旧锚点，不能只靠锚点字符串变化触发。
    const advance = autoBefore && action.type === 'TOGGLE_TODAY' && first?.id === action.id;
    this.getUIContext().animateTo(action.type === 'SET_SETTINGS' ? Motion.theme() : Motion.spring(), () => {
      this.data = reduce(this.data, action);
    });
    this.updatePalette();
    this.persist();
    if (advance || previousAnchor !== this.data.todayAnchorId ||
      (!autoBefore && this.data.settings.autoScrollNextOnComplete)) {
      this.restoreAnchor();
    }
  }

  private async persist(): Promise<void> {
    if (!this.context || !this.ready) return;
    const revision = ++this.saveRevision;
    this.saving = true;
    try {
      await this.storage.save(this.context, this.data);
      if (revision === this.saveRevision) {
        this.saving = false;
        this.saveError = '';
        this.adoptedRaw = JSON.stringify(this.data);
        this.syncForm();
        if (this.foregroundSyncPending) {
          this.foregroundSyncPending = false;
          this.foregroundChanged();
        }
      }
    } catch (error) {
      if (revision === this.saveRevision) {
        this.saving = false;
        this.saveError = '自动保存失败，点此重试';
      }
    }
  }

  // 保存成功后把同一份视图数据推给桌面上已添加的卡片；未添加卡片时内部直接返回。
  private syncForm(): void {
    if (!this.context) return;
    const mode: string = this.data.settings.themeMode;
    const dark: boolean = mode === 'dark' || (mode === 'system' && this.systemDark);
    FormSync.sync(this.context, this.data, dark).catch((): void => {
      console.warn('桌面卡片同步未完成，日程数据不受影响。');
    });
  }

  private restoreAnchor(): void {
    const revision = ++this.anchorRevision;
    this.anchorPending = false;
    if (!this.ready || !this.data.settings.autoScrollNextOnComplete || this.page !== 0) return;
    const first = this.data.todayTasks.find((task: Task): boolean => !task.completed);
    const target = first ? first.id : null;
    if (this.data.todayAnchorId !== target) {
      const action = new AppAction('SET_TODAY_ANCHOR');
      action.id = target || '';
      this.data = reduce(this.data, action);
      this.persist();
    }
    this.anchorPending = true;
    setTimeout((): void => {
      if (revision === this.anchorRevision) this.applyPendingAnchor();
    }, 60);
  }

  private applyPendingAnchor(): void {
    if (!this.anchorPending) return;
    if (!this.ready || this.page !== 0 || !this.data.settings.autoScrollNextOnComplete ||
      this.dragId || this.dragIsGroup) {
      this.anchorPending = false;
      return;
    }
    // 首次加载 / 切页时定时器可能早于 List 挂载；由 didLayout 补做，不能静默丢掉定位。
    const node = this.getUIContext().getFrameNodeById('list-today');
    if (!node || node.getMeasuredSize().height <= 0) return;
    this.anchorPending = false;
    const index = this.data.todayTasks.findIndex((task: Task): boolean => !task.completed);
    if (index < 0 || this.nearTodayBottom()) return;
    this.todayScroller.scrollToIndex(index, true, ScrollAlign.START);
  }

  // 只按真实 List 视口判断末条日程是否完整露出；分区还包含标题，不能用分区高度。
  private nearTodayBottom(): boolean {
    const total = this.data.todayTasks.length;
    if (total === 0) return true;
    if (this.todayLastVisible >= 0 && this.todayLastVisible < total - 1) return false;
    try {
      const last = this.todayScroller.getItemRect(total - 1);
      if (!last || last.width <= 0 || last.height <= 0) return false;
      const viewport = this.todayViewportHeight();
      if (viewport <= 0) return false;
      return last.y + last.height <= viewport + 1;
    } catch (error) {
      // 非可视条目不保证能取到矩形；不能把无效矩形当成已经到底。
      return false;
    }
  }

  private todayViewportHeight(): number {
    const node = this.getUIContext().getFrameNodeById('list-today');
    if (node) {
      const height = this.getUIContext().px2vp(node.getMeasuredSize().height);
      if (height > 0) return height;
    }
    return this.todayHeight > 0 ? this.todayHeight : 0;
  }

  private navigate(page: number): void {
    this.resetDrag();
    if (page < 3) {
      this.tabsController.changeIndex(page);
    }
    this.getUIContext().animateTo(Motion.spring(), () => {
      // 历史页首次访问才建树，避免启动时默认位置到右侧隐藏位置产生退场动画。
      if (page === 3) this.historyCreated = true;
      this.page = page;
    });
    if (page === 0) this.restoreAnchor();
  }

  private openModal(kind: string): void {
    this.modalPressedButton = '';
    this.stopEdgeScroll();
    this.modal = kind;
    this.sheetShown = true;
  }

  private closeModal(): void {
    this.modalPressedButton = '';
    this.sheetShown = false;
  }

  // 非教程表单使用统一高度和内部滚动区，日历在小窗中也能完整访问。
  private sheetHeight(): SheetSize | Length {
    return ['add', 'edit', 'move', 'date', 'restore'].includes(this.modal) ?
      (this.viewportWidth >= 600 ? '90%' : '84%') : SheetSize.FIT_CONTENT;
  }
  private modalButtonTouch(id: string, event: TouchEvent): void {
    const next = ButtonFeedback.next(this.modalPressedButton, id, event.type);
    if (next === this.modalPressedButton) return;
    this.getUIContext().animateTo(Motion.quick(), (): void => { this.modalPressedButton = next; });
  }

  private modalTap(action: () => void): void { this.modalPressedButton = ''; action(); }

  private selectBrowsingDate(key: string): void {
    const action = new AppAction('SELECT_DATE');
    action.key = key;
    this.dispatch(action);
    this.closeModal();
  }

  private selectRestoreTarget(target: string): void {
    if (this.restoreTarget === target) return;
    const animation = Motion.spring();
    animation.onFinish = (): void => EditorMaterialRefresh.request(this.getUIContext());
    this.getUIContext().animateTo(animation, (): void => { this.restoreTarget = target; });
  }

  private tasks(section: string): Task[] {
    return section === 'today' ? this.data.todayTasks : this.data.futureTasks;
  }

  // 列表复用节点时按稳定 ID 读取新快照，避免捕获 reducer 替换前的任务对象。
  private currentTask(section: string, id: string): Task {
    return this.tasks(section).find((task: Task): boolean => task.id === id) || new Task();
  }

  private currentIndex(section: string, id: string): number {
    return this.tasks(section).findIndex((task: Task): boolean => task.id === id);
  }

  private doneCount(): number {
    return this.data.todayTasks.filter((task: Task): boolean => task.completed).length;
  }

  private markedDates(): string[] {
    const result: string[] = [];
    this.data.futureTasks.forEach((task: Task): void => {
      if (task.startDate) result.push(task.startDate);
      if (task.dueDate) result.push(task.dueDate);
    });
    return result;
  }

  private openEditor(section: string, task: Task | null = null): void {
    if (task && task.checkInId) {
      this.checkInRequestedId = task.checkInId;
      this.navigate(1);
      this.checkInRequestRevision++;
      return;
    }
    this.editorSection = section;
    this.selectedTask = task === null ? new Task() : task;
    this.selectedTarget = 0;
    this.selectedGroup = undefined;
    this.openModal(task === null ? 'add' : 'edit');
  }

  private async confirmDelete(task: Task, historyDate: string = ''): Promise<boolean> {
    let accepted = false;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog(Materials.confirmation(this.palette, {
      title: historyDate ? '删除历史日程' : '删除日程',
      message: '确定永久删除“' + task.text + '”吗？此操作不可恢复。' +
        (task.checkInId && historyDate ? '打卡页中的周期记录与统计仍会保留。' : ''),
      buttons: [{ text: '取消', color: this.palette.textSoft }, { text: '永久删除', color: this.palette.danger }]
    }));
      accepted = result.index === 1;
    } catch (error) {
      console.error('打开确认对话框失败：' + String(error));
    }
    if (!accepted) return false;
    const action = new AppAction(historyDate ? 'DELETE_HISTORY_TASK' : 'DELETE_TASK');
    action.id = task.id;
    action.entryDate = historyDate;
    this.dispatch(action);
    return true;
  }

  private async deleteEditingTask(): Promise<void> {
    // 取消确认仍留在编辑页，保留尚未保存的输入。
    if (await this.confirmDelete(this.selectedTask)) this.closeModal();
  }

  private async clearHistory(): Promise<void> {
    let accepted = false;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog(Materials.confirmation(this.palette, {
      title: '清空历史日程',
      message: '将永久删除历史日程列表，且不可恢复。打卡页中的周期记录与统计仍会保留。确定继续吗？',
      buttons: [{ text: '取消', color: this.palette.textSoft }, { text: '清空', color: this.palette.danger }]
    }));
      accepted = result.index === 1;
    } catch (error) {
      console.error('打开确认对话框失败：' + String(error));
    }
    if (accepted) this.dispatch(new AppAction('CLEAR_HISTORY'));
  }

  private restoreTask(task: Task, date: string): void {
    if (task.checkInId) {
      const undo = new AppAction('CHECKIN_UNDO');
      undo.id = task.checkInId;
      undo.key = task.checkInKey;
      this.dispatch(undo);
      return;
    }
    this.selectedTask = task;
    this.selectedHistoryDate = date;
    if (task.plannedDate && task.plannedDate >= this.data.currentDate) {
      const action = new AppAction('RESTORE');
      action.id = task.id;
      action.entryDate = date;
      action.target = task.plannedDate === this.data.currentDate ? 'today' : 'future';
      action.dueDate = task.plannedDate;
      this.dispatch(action);
    } else {
      this.getUIContext().animateTo(Motion.spring(), () => { this.restoreTarget = 'today'; });
      this.restoreDate = addDays(this.data.currentDate, 1);
      this.openModal('restore');
    }
  }

  private restoreSelected(): void {
    const action = new AppAction('RESTORE');
    action.id = this.selectedTask.id;
    action.entryDate = this.selectedHistoryDate;
    action.target = this.restoreTarget;
    action.dueDate = this.restoreTarget === 'future' ? this.restoreDate : null;
    this.dispatch(action);
    this.closeModal();
  }

  private toggle(task: Task, section: string): void {
    const action = new AppAction(section === 'today' ? 'TOGGLE_TODAY' : 'COMPLETE_FUTURE');
    action.id = task.id;
    this.dispatch(action);
  }

  private clearLandingLayout(): void {
    if (this.landingLayout) this.getUIContext().getUIObserver().off('didLayout', this.landingLayout);
    this.landingLayout = undefined;
  }

  private clearFloating(): void {
    this.clearLandingLayout();
    this.floatingGeneration++;
    this.floatingPhase = 'idle';
    this.floatingMembers = [];
    this.floatingPointer = -1;
    this.floatingMoved = false;
    this.floatingLift = 0;
  }

  private floatingSource(taskId: string): boolean {
    if (this.floatingPhase === 'idle') return false;
    return this.floatingGroup ? this.floatingTasks.some((task: Task): boolean => task.id === taskId) :
      this.floatingTask.id === taskId;
  }

  private floatingHeader(section: string, taskId: string): boolean {
    return this.floatingPhase !== 'idle' && this.floatingGroup && this.floatingSection === section &&
      this.floatingTask.id === taskId;
  }

  private groupMemberSource(taskId: string): boolean {
    return this.floatingPhase !== 'idle' && this.floatingGroup &&
      this.floatingMembers.some((member: GroupDragMember): boolean => member.task.id === taskId && member.visible);
  }

  private captureGroupMembers(section: string, anchorX: number, anchorY: number): GroupDragMember[] {
    const bounds = this.dragBounds(section);
    if (!bounds) return [];
    const ui = this.getUIContext();
    const members: GroupDragMember[] = [];
    this.floatingTasks.forEach((task: Task, depth: number) => {
      const order = this.currentIndex(section, task.id);
      const node = ui.getFrameNodeById('task-' + task.id);
      if (order < 0 || !node) return;
      const size = node.getMeasuredSize();
      const width = ui.px2vp(size.width);
      const height = ui.px2vp(size.height);
      if (width <= 0 || height <= 0) return;
      const position = node.getPositionToWindow();
      const top = Math.max(position.y, bounds.top);
      const bottom = Math.min(position.y + height, bounds.top + bounds.height);
      if (bottom <= top || position.x + width <= bounds.left || position.x >= bounds.left + bounds.width) return;
      const member = new GroupDragMember();
      member.task = this.currentTask(section, task.id).clone();
      member.order = order + 1;
      member.depth = depth;
      member.x = position.x - this.floatingRootX - anchorX;
      member.y = top - this.floatingRootY - anchorY;
      member.width = width;
      member.height = height;
      member.clipTop = top - position.y;
      member.visibleHeight = bottom - top;
      members.push(member);
    });
    return members;
  }

  private groupLandingMembers(targets: GroupDragMember[]): GroupDragMember[] {
    // 保持旧成员节点身份；新进入视口的成员先在收拢端建立，避免直接跳出最终卡片。
    const staged = this.floatingMembers.slice();
    targets.forEach((target: GroupDragMember) => {
      if (!staged.some((member: GroupDragMember): boolean => member.task.id === target.task.id)) staged.push(target);
    });
    this.floatingMembers = staged;
    return staged.map((member: GroupDragMember): GroupDragMember => {
      const target = targets.find((item: GroupDragMember): boolean => item.task.id === member.task.id);
      if (target) return target;
      // 已离屏或无有效目标的成员只在叠层中隐去，不飞回过期源坐标。
      const hidden = new GroupDragMember();
      hidden.task = member.task;
      hidden.order = member.order;
      hidden.depth = member.depth;
      hidden.width = member.width;
      hidden.height = member.height;
      hidden.clipTop = member.clipTop;
      hidden.visibleHeight = member.visibleHeight;
      hidden.visible = false;
      return hidden;
    });
  }

  private startFloating(event: GestureEvent, section: string, taskId: string, group: boolean = false): void {
    if (this.floatingPhase !== 'idle' || this.page !== 0 || this.sheetShown) return;
    const finger = (event.fingerInfos || []).find((item: FingerInfo): boolean => item.id >= 0);
    const task = this.tasks(section).find((item: Task): boolean => item.id === taskId);
    const ui = this.getUIContext();
    const node = ui.getFrameNodeById((group ? 'group-' + section + '-' : 'task-') + taskId);
    const root = ui.getFrameNodeById('planer-root');
    if (!finger || !task || !node || !root) return;
    const size = node.getMeasuredSize();
    if (size.width <= 0 || size.height <= 0) return;
    const origin = node.getPositionToWindow();
    const rootOrigin = root.getPositionToWindow();
    if (group) this.beginGroupDrag(task.group, section);
    else this.beginTaskDrag(task, section);
    this.floatingTask = task.clone();
    this.floatingTasks = group ? this.tasks(section).filter((item: Task): boolean => item.group === task.group)
      .map((item: Task): Task => item.clone()) : [];
    this.floatingGroup = group;
    this.floatingSection = section;
    this.floatingOrder = this.currentIndex(section, taskId) + 1;
    this.floatingRootX = rootOrigin.x;
    this.floatingRootY = rootOrigin.y;
    this.floatingWidth = group ? 272 : ui.px2vp(size.width);
    const count = Math.min(this.floatingTasks.length, 2);
    this.floatingHeight = group ? 62 + (count > 0 ? 10 + count * 18 + (count - 1) * 6 : 0) +
      (this.floatingTasks.length > 2 ? 24 : 0) : ui.px2vp(size.height);
    this.floatingOriginX = origin.x - rootOrigin.x + (group ? (ui.px2vp(size.width) - 272) / 2 : 0);
    this.floatingOriginY = origin.y - rootOrigin.y;
    this.floatingX = this.floatingOriginX;
    this.floatingY = this.floatingOriginY;
    this.floatingMembers = group ? this.captureGroupMembers(section, this.floatingOriginX, this.floatingOriginY) : [];
    this.floatingTouchX = finger.globalX;
    this.floatingTouchY = finger.globalY;
    this.floatingPointer = finger.id;
    this.floatingMoved = false;
    this.floatingLift = 0;
    this.floatingPhase = 'lifting';
    // 唯一浮层已存在：识别回调直接提交弹簧，不等待定时器、截图或系统800ms浮起阶段。
    ui.animateToImmediately(Motion.drag(), () => { this.floatingLift = 1; });
  }

  private updateFloating(event: GestureEvent): void {
    const finger = (event.fingerInfos || []).find((item: FingerInfo): boolean => item.id === this.floatingPointer);
    if (finger) this.moveFloating(finger.globalX, finger.globalY);
  }

  private moveFloating(x: number, y: number): void {
    if (this.floatingPhase !== 'lifting' && this.floatingPhase !== 'dragging') return;
    this.floatingMoved = true;
    this.floatingPhase = 'dragging';
    // 跟手坐标不做补间，避免手指移动快时卡片落后；只有高度与松手落位使用同一弹簧。
    this.floatingX = this.floatingOriginX + x - this.floatingTouchX;
    this.floatingY = this.floatingOriginY + y - this.floatingTouchY;
    this.dragPointerX = x;
    this.dragPointerY = y;
    const section = this.insideDragList('today', x, y) ? 'today' :
      (this.insideDragList('future', x, y) ? 'future' : '');
    if (!section) {
      this.stopEdgeScroll();
      this.clearDrop();
      return;
    }
    if (this.edgeScroll(new PlanerDragPoint(x, y), section)) this.refreshDragTarget(section, false);
  }

  private floatingTouch(event: TouchEvent): void {
    if (this.floatingPhase !== 'lifting' && this.floatingPhase !== 'dragging') return;
    const touch = event.changedTouches.find((item: TouchObject): boolean => item.id === this.floatingPointer);
    if (event.type === TouchType.Cancel) {
      this.finishFloating(false);
    } else if (event.type === TouchType.Up && touch) {
      // Sequence前项长按没有onActionEnd；原地松手也必须结束，和PanEnd共享幂等入口。
      if (this.floatingMoved) this.moveFloating(touch.windowX, touch.windowY);
      this.finishFloating(this.floatingMoved);
    }
  }

  private finishFloating(commit: boolean): void {
    if (this.floatingPhase !== 'lifting' && this.floatingPhase !== 'dragging') return;
    const point = new PlanerDragPoint(this.dragPointerX, this.dragPointerY);
    if (commit) this.refreshFinalDrop(point, this.dropSection);
    const section = this.dropSection;
    const valid = commit && this.floatingMoved && this.dropIndex >= 0 && this.validDragSection(section) &&
      this.insideDragList(section, this.dragPointerX, this.dragPointerY);
    this.floatingPhase = 'settling';
    const version = this.floatingGeneration;
    const needsDates = valid && !this.floatingGroup && this.floatingSection === 'today' && section === 'future';
    // 日期确认先回源位置，落位结束后才打开弹层，避免表单截断卡片动画。
    if (valid && !needsDates) this.finishDrop(point, section);
    else if (!needsDates) this.resetDrag(true);
    else this.stopEdgeScroll();
    const targetSection = valid && !needsDates ? section : this.floatingSection;
    const targetId = (this.floatingGroup ? 'group-' + targetSection + '-' : 'task-') + this.floatingTask.id;
    this.clearLandingLayout();
    this.landingLayout = () => {
      if (this.floatingPhase !== 'settling' || version !== this.floatingGeneration) return;
      this.clearLandingLayout();
      const node = this.getUIContext().getFrameNodeById(targetId);
      let x = this.floatingOriginX;
      let y = this.floatingOriginY;
      if (node && node.getMeasuredSize().height > 0) {
        const position = node.getPositionToWindow();
        x = position.x - this.floatingRootX + (this.floatingGroup ?
          (this.getUIContext().px2vp(node.getMeasuredSize().width) - this.floatingWidth) / 2 : 0);
        y = position.y - this.floatingRootY;
      }
      const members = this.floatingGroup ?
        this.groupLandingMembers(this.captureGroupMembers(targetSection, x, y)) : [];
      const animation = Motion.drag();
      animation.onFinish = () => {
        if (this.floatingPhase !== 'settling' || version !== this.floatingGeneration) return;
        this.clearFloating();
        if (needsDates) this.finishDrop(point, section);
      };
      // 先落实新增成员的收拢初值，再从当前呈现位置接续同一弹簧；快速松手也不等上一段结束。
      this.getUIContext().animateToImmediately(animation, () => {
        if (this.floatingGroup) this.floatingMembers = members;
        this.floatingX = x;
        this.floatingY = y;
        if (!this.floatingGroup && node && node.getMeasuredSize().width > 0 && node.getMeasuredSize().height > 0) {
          this.floatingSection = targetSection;
          this.floatingOrder = this.currentIndex(targetSection, this.floatingTask.id) + 1;
          this.floatingTask = this.currentTask(targetSection, this.floatingTask.id).clone();
          this.floatingWidth = this.getUIContext().px2vp(node.getMeasuredSize().width);
          this.floatingHeight = this.getUIContext().px2vp(node.getMeasuredSize().height);
        }
        this.floatingLift = 0;
      });
    };
    // 重排/跨区创建节点后再测量，onFrame只是帧开始，不能视作布局完成。
    this.getUIContext().getUIObserver().on('didLayout', this.landingLayout);
  }

  private resetDrag(preserveFloating: boolean = false): void {
    this.stopEdgeScroll();
    if (!preserveFloating) this.clearFloating();
    this.getUIContext().animateTo(Motion.drag(), () => {
      this.dragId = '';
      this.dragSection = '';
      this.dragIsGroup = false;
      this.dragGroup = null;
      this.dropSection = '';
      this.dropIndex = -1;
      this.dropGroup = undefined;
    });
  }

  private beginTaskDrag(task: Task, section: string): DragItemInfo {
    this.resetDrag();
    const node = this.getUIContext().getFrameNodeById('task-' + task.id);
    this.dragHeight = node ? Math.max(50, Math.min(180, this.getUIContext().px2vp(node.getMeasuredSize().height))) : 58;
    this.getUIContext().animateTo(Motion.quick(), () => {
      this.dragId = task.id;
      this.dragSection = section;
    });
    return { extraInfo: task.id };
  }

  private beginGroupDrag(group: string | null, section: string): DragItemInfo {
    this.resetDrag();
    this.dragHeight = Math.min(180, 44 + this.tasks(section).filter((task: Task): boolean => task.group === group).length * 58);
    this.getUIContext().animateTo(Motion.quick(), () => {
      this.dragIsGroup = true;
      this.dragSection = section;
      this.dragGroup = group;
    });
    return { extraInfo: 'group' };
  }

  private clearDrop(): void {
    if (this.dropIndex < 0) return;
    this.getUIContext().animateTo(Motion.drag(), () => {
      this.dropSection = '';
      this.dropIndex = -1;
      this.dropGroup = undefined;
    });
  }

  private previewDrop(section: string, index: number, group: string | null): void {
    if (!this.dragId && !this.dragIsGroup) return;
    if (this.dragIsGroup && section !== this.dragSection) {
      this.stopEdgeScroll();
      this.clearDrop();
      return;
    }
    const target = Math.max(0, Math.min(index, this.tasks(section).length));
    const targetGroup = this.data.settings.showGroups ? group : undefined;
    if (this.dropSection === section && this.dropIndex === target && this.dropGroup === targetGroup) return;
    this.getUIContext().animateTo(Motion.drag(), () => {
      this.dropSection = section;
      this.dropIndex = target;
      this.dropGroup = targetGroup;
    });
  }

  private sourceCard(section: string, taskId: string): boolean {
    return section === this.dragSection && (this.dragIsGroup ?
      this.currentTask(section, taskId).group === this.dragGroup : this.dragId === taskId);
  }

  private samePosition(): boolean {
    if (!this.dropSection || this.dropSection !== this.dragSection) return false;
    if (this.dragIsGroup) {
      const list = this.tasks(this.dragSection);
      const first = list.findIndex((task: Task): boolean => task.group === this.dragGroup);
      const count = list.filter((task: Task): boolean => task.group === this.dragGroup).length;
      return this.dropIndex >= first && this.dropIndex <= first + count;
    }
    const source = this.currentIndex(this.dragSection, this.dragId);
    const task = this.currentTask(this.dragSection, this.dragId);
    return (this.dropIndex === source || this.dropIndex === source + 1) &&
      (this.dropGroup === undefined || this.dropGroup === task.group);
  }

  private slotBeforeHeader(section: string, taskId: string): boolean {
    if (!taskId) return false;
    if (this.dragIsGroup) return true;
    // 组边界共有一个插入索引：归前组放在标题前，归后组放在标题后。
    return this.groupHead(section, this.currentIndex(section, taskId)) &&
      this.dropGroup !== this.currentTask(section, taskId).group;
  }

  private slotActive(section: string, taskId: string, forGroup: boolean): boolean {
    const index = taskId ? this.currentIndex(section, taskId) : this.tasks(section).length;
    return this.dropSection === section && this.dropIndex === index &&
      (this.slotBeforeHeader(section, taskId) === forGroup) && !this.samePosition();
  }

  private slotId(section: string, taskId: string, forGroup: boolean): string {
    return 'drop-' + section + '-' + (taskId || 'end') + (forGroup ? '-group' : '-task');
  }

  private pointerInSlot(event: PlanerDragPoint, section: string): boolean {
    return this.pointerAtSlot(event.getWindowY(), section);
  }

  private pointerAtSlot(y: number, section: string): boolean {
    if (this.dropSection !== section || this.dropIndex < 0 || this.samePosition()) return false;
    const list = this.tasks(section);
    const id = this.dropIndex < list.length ? list[this.dropIndex].id : '';
    const node = this.getUIContext().getFrameNodeById(this.slotId(section, id, this.slotBeforeHeader(section, id)));
    if (!node) return false;
    const top = node.getPositionToWindow().y;
    const height = this.getUIContext().px2vp(node.getMeasuredSize().height);
    // 静止布局保持槽内落点；实际滚动后按新几何命中，不锁死大分组占位。
    return height > 0 && y >= top - 3 && y <= top + height + 3;
  }

  private hoverTask(event: PlanerDragPoint, section: string, taskId: string): void {
    if (!this.edgeScroll(event, section) || this.pointerInSlot(event, section)) return;
    this.previewTaskAt(section, taskId, event.getWindowY());
  }

  private previewTaskAt(section: string, taskId: string, y: number, holdMiddle: boolean = true): void {
    const index = this.currentIndex(section, taskId);
    if (index < 0) return;
    const node = this.getUIContext().getFrameNodeById('task-' + taskId);
    if (!node) return;
    const middle = node.getPositionToWindow().y + this.getUIContext().px2vp(node.getMeasuredSize().height) / 2;
    if (holdMiddle && Math.abs(y - middle) < 4 && this.dropSection === section &&
      (this.dropIndex === index || this.dropIndex === index + 1)) return;
    const after = y >= middle;
    const group = this.currentTask(section, taskId).group;
    let boundary = index + (after ? 1 : 0);
    if (this.dragIsGroup) {
      const list = this.tasks(section);
      const first = list.findIndex((task: Task): boolean => task.group === group);
      const count = list.filter((task: Task): boolean => task.group === group).length;
      boundary = after ? first + count : first;
    }
    this.previewDrop(section, boundary, group);
  }

  private hoverGroup(event: PlanerDragPoint, section: string, taskId: string): void {
    if (!this.edgeScroll(event, section) || this.pointerInSlot(event, section)) return;
    this.previewDrop(section, this.currentIndex(section, taskId), this.currentTask(section, taskId).group);
  }

  private hoverList(event: PlanerDragPoint, section: string): void {
    if (this.edgeScroll(event, section)) this.refreshDragTarget(section, false);
  }

  private leaveDrag(event: PlanerDragPoint, section: string): void {
    if (this.dragHoverSection !== section) return;
    // 子卡片到同列表的标题、间隙或槽不是离开区域。
    if (this.insideDragList(section, event.getWindowX(), event.getWindowY())) {
      this.edgeScroll(event, section);
      return;
    }
    this.stopEdgeScroll();
    this.clearDrop();
  }

  private startMoreObservation(): void {
    this.stopMoreObservation();
    this.moreLayout = () => {
      this.updateMoreBelow();
      this.applyPendingAnchor();
    };
    this.getUIContext().getUIObserver().on('didLayout', this.moreLayout);
  }

  private stopMoreObservation(): void {
    if (this.moreLayout) this.getUIContext().getUIObserver().off('didLayout', this.moreLayout);
    this.moreLayout = undefined;
  }

  private recordVisibleItems(section: string, start: number, end: number): void {
    if (section === 'today') {
      this.todayFirstVisible = start;
      this.todayLastVisible = end;
    } else {
      this.futureFirstVisible = start;
      this.futureLastVisible = end;
    }
    this.updateMoreBelow();
  }

  private moreTasksBelow(section: string): boolean {
    const last = this.tasks(section).length - 1;
    if (last < 0) return false;
    const bounds = this.dragBounds(section);
    if (!bounds) return false;
    const scroller = section === 'today' ? this.todayScroller : this.futureScroller;
    try {
      // 只测最后一条真实日程，不把拖动提示行和末尾Blank算作未显示内容；矩形单位为vp。
      const rect = scroller.getItemRect(last);
      if (rect.width > 0 && rect.height > 0) {
        return bounds.top + rect.y + rect.height > bounds.top + bounds.height + 1;
      }
    } catch (error) {
      // 首次挂载或重新布局时控制器可能尚未绑定，随后didLayout会再次确认。
    }
    const first = section === 'today' ? this.todayFirstVisible : this.futureFirstVisible;
    const end = section === 'today' ? this.todayLastVisible : this.futureLastVisible;
    if (end >= 0 && end < last) return true;
    if (first > last) return false;
    // 零矩形不是已到底；未知状态保留上次结果，等待有效布局，避免提示闪烁。
    return section === 'today' ? this.todayMoreBelow : this.futureMoreBelow;
  }

  private updateMoreBelow(): void {
    const active = this.ready && this.page === 0;
    const today = active && this.moreTasksBelow('today');
    const future = active && this.moreTasksBelow('future');
    let inset = 0;
    const node = active ? this.getUIContext().getFrameNodeById('list-future') : null;
    if (node) {
      const height = this.getUIContext().px2vp(node.getMeasuredSize().height);
      const bottom = node.getPositionToWindow().y + height;
      inset = Math.max(0, Math.min(height, bottom - this.futureDragBottom(bottom)));
    }
    if (Math.abs(this.futureMoreInset - inset) > 0.5) this.futureMoreInset = inset;
    if (today === this.todayMoreBelow && future === this.futureMoreBelow) return;
    this.getUIContext().animateTo(Motion.quick(), () => {
      this.todayMoreBelow = today;
      this.futureMoreBelow = future;
    });
  }

  private moreHintVisible(section: string): boolean {
    // 渐隐属于列表视口，拖动浮层独立绘制；拾起、移动和落位均保留真实下溢提示。
    return section === 'today' ? this.todayMoreBelow : this.futureMoreBelow;
  }

  private tabsBottomPadding(): number {
    return deviceInfo.apiAvailable('26.0.0') ? 0 : this.safeBottom;
  }

  private futureExtension(): number {
    return 96 + Math.max(0, this.safeBottom - this.tabsBottomPadding());
  }

  private updateFutureTailSpace(): void {
    const bottom = this.futureTop + this.futureHeight;
    // 已有末尾间隔8、提示行40、底部padding12；仅补遮挡差额并保留8vp安全距离。
    const tail = Math.max(0, bottom - this.futureDragBottom(bottom) + 8 - 60);
    if (Math.abs(this.futureTailSpace - tail) > 0.5) this.futureTailSpace = tail;
  }

  private splitBaseHeight(): number {
    // 正常屏幕沿用原比例基准，新增可视高度仅归未来区；极小窗口至少留下半区供两区分配。
    return Math.max(1, this.paneHeight - Math.min(this.futureExtension(), this.paneHeight / 2));
  }

  private clampSplitRatio(value: number): number {
    const minimum = Math.min(0.4, 120 / this.splitBaseHeight());
    return Math.max(minimum, Math.min(1 - minimum, value));
  }

  private todayPaneHeight(): Length {
    if (this.paneHeight <= 0) return '40%';
    return this.splitBaseHeight() * this.clampSplitRatio(this.splitRatio);
  }

  private futureDragBottom(bottom: number): number {
    // 宽屏双栏已在底栏上方留空，两栏均使用真实可见高度。
    if (this.wideLayout) return bottom;
    // 使用原生 TabBar 外框，不把图标或文字内部矩形误作遮挡边界。
    let node = this.getUIContext().getFrameNodeById('tab-home');
    for (let depth = 0; node && depth < 8; depth++) {
      if (node.getNodeType() === 'TabBar') {
        const top = node.getPositionToWindow().y;
        const size = node.getMeasuredSize();
        if (size.width > 0 && size.height > 0 && top > 0 && top <= bottom) return top;
      }
      node = node.getParent();
    }
    return bottom - this.futureExtension();
  }

  private dragBounds(section: string): DragBounds | null {
    const node = this.getUIContext().getFrameNodeById('list-' + section);
    if (!node) return null;
    const position = node.getPositionToWindow();
    const size = node.getMeasuredSize();
    const bounds = new DragBounds();
    bounds.left = position.x;
    bounds.top = position.y;
    bounds.width = this.getUIContext().px2vp(size.width);
    bounds.height = this.getUIContext().px2vp(size.height);
    if (section === 'future') {
      bounds.height = Math.max(0, this.futureDragBottom(bounds.top + bounds.height) - bounds.top);
    }
    return bounds.width > 0 && bounds.height > 0 ? bounds : null;
  }

  private insideDragList(section: string, x: number, y: number): boolean {
    const bounds = this.dragBounds(section);
    return bounds !== null && x >= bounds.left && x <= bounds.left + bounds.width &&
      y >= bounds.top && y <= bounds.top + bounds.height;
  }

  private validDragSection(section: string): boolean {
    return (section === 'today' || section === 'future') && (this.dragId.length > 0 || this.dragIsGroup) &&
      this.page === 0 && !this.sheetShown && (!this.dragIsGroup || section === this.dragSection);
  }

  private edgeVelocity(section: string): number {
    const bounds = this.dragBounds(section);
    if (!bounds || !this.insideDragList(section, this.dragPointerX, this.dragPointerY)) return 0;
    const zone = Math.min(56, bounds.height / 3);
    const fromTop = this.dragPointerY - bounds.top;
    const fromBottom = bounds.top + bounds.height - this.dragPointerY;
    const direction = fromTop < zone ? -1 : (fromBottom < zone ? 1 : 0);
    if (direction === 0) return 0;
    const distance = direction < 0 ? fromTop : fromBottom;
    const depth = Math.max(0, Math.min(1, (zone - distance) / zone));
    return direction * 420 * depth * depth * (3 - 2 * depth);
  }

  private stopEdgeScroll(clearPointer: boolean = true): void {
    this.edgeGeneration++;
    this.edgeFrameTime = 0;
    this.edgeExpectedMove = false;
    this.edgeStalledFrames = 0;
    if (clearPointer) this.dragHoverSection = '';
    // 系统队列中的帧不可移除；保留 pending，排空旧回调后才安排新代次。
  }

  private queueEdgeFrame(): void {
    if (this.edgeFramePending || !this.validDragSection(this.dragHoverSection) ||
      this.edgeVelocity(this.dragHoverSection) === 0) return;
    const generation = this.edgeGeneration;
    this.edgeFramePending = true;
    this.getUIContext().postFrameCallback(new DragScrollFrame((time: number): void => {
      this.edgeFramePending = false;
      if (generation !== this.edgeGeneration) {
        this.queueEdgeFrame();
        return;
      }
      this.stepEdgeScroll(time);
    }));
  }

  private edgeScroll(event: PlanerDragPoint, section: string): boolean {
    if (!this.validDragSection(section) || !this.insideDragList(section, event.getWindowX(), event.getWindowY())) {
      this.stopEdgeScroll();
      this.clearDrop();
      return false;
    }
    if (this.dragHoverSection !== section) this.stopEdgeScroll();
    this.dragHoverSection = section;
    this.dragPointerX = event.getWindowX();
    this.dragPointerY = event.getWindowY();
    if (this.edgeVelocity(section) === 0) this.stopEdgeScroll(false);
    else this.queueEdgeFrame();
    return true;
  }

  private stepEdgeScroll(time: number): void {
    const section = this.dragHoverSection;
    if (!this.validDragSection(section) || !this.insideDragList(section, this.dragPointerX, this.dragPointerY)) {
      this.stopEdgeScroll();
      this.clearDrop();
      return;
    }
    const speed = this.edgeVelocity(section);
    if (speed === 0) { this.stopEdgeScroll(false); return; }
    const scroller = section === 'today' ? this.todayScroller : this.futureScroller;
    const offset = scroller.offset();
    if (!offset) { this.stopEdgeScroll(); return; }
    const moved = this.edgeExpectedMove && Math.abs(offset.yOffset - this.edgeLastOffset) > 0.05;
    if (this.edgeExpectedMove) this.edgeStalledFrames = moved ? 0 : this.edgeStalledFrames + 1;
    // 上一帧滚动完成布局后，用当前几何重新命中静止指针。
    this.refreshDragTarget(section, moved);
    if ((speed < 0 && offset.yOffset <= 0) || (speed > 0 && scroller.isAtEnd()) || this.edgeStalledFrames >= 3) {
      this.stopEdgeScroll(false);
      return;
    }
    const deltaSeconds = this.edgeFrameTime > 0 ? Math.max(0.001, Math.min(0.032, (time - this.edgeFrameTime) / 1000000000)) : 1 / 60;
    this.edgeFrameTime = time;
    this.edgeLastOffset = offset.yOffset;
    this.edgeExpectedMove = true;
    // 滚动直接跟随系统帧；仅落位槽用弹簧，不重复启动平滑滚动动画。
    scroller.scrollBy(0, speed * deltaSeconds);
    this.queueEdgeFrame();
  }

  private refreshDragTarget(section: string, scrolled: boolean): void {
    if (!this.validDragSection(section) || (!scrolled && this.pointerAtSlot(this.dragPointerY, section))) return;
    const bounds = this.dragBounds(section);
    if (!bounds) return;
    const list = this.tasks(section);
    const y = this.dragPointerY;
    let closest = '';
    let nearest = Number.MAX_VALUE;
    for (let index = 0; index < list.length; index++) {
      const task = list[index];
      if (this.groupHead(section, index)) {
        const header = this.getUIContext().getFrameNodeById('group-' + section + '-' + task.id);
        if (header) {
          const top = header.getPositionToWindow().y;
          const height = this.getUIContext().px2vp(header.getMeasuredSize().height);
          if (height > 0 && y >= top && y <= top + height) {
            this.previewDrop(section, index, task.group);
            return;
          }
        }
      }
      const node = this.getUIContext().getFrameNodeById('task-' + task.id);
      if (!node) continue;
      const top = node.getPositionToWindow().y;
      const height = this.getUIContext().px2vp(node.getMeasuredSize().height);
      if (height <= 0 || top + height < bounds.top || top > bounds.top + bounds.height) continue;
      const distance = Math.max(top - y, y - top - height, 0);
      if (distance < nearest) { closest = task.id; nearest = distance; }
    }
    const end = this.getUIContext().getFrameNodeById('list-end-' + section);
    const endTop = end ? end.getPositionToWindow().y : 0;
    const endHeight = end ? this.getUIContext().px2vp(end.getMeasuredSize().height) : 0;
    const inEnd = endHeight > 0 && endTop < bounds.top + bounds.height && endTop + endHeight > bounds.top &&
      y >= endTop && y <= endTop + endHeight;
    if (list.length === 0 || inEnd) {
      this.previewDrop(section, list.length, list.length > 0 ? list[list.length - 1].group : null);
    } else if (closest) {
      this.previewTaskAt(section, closest, y, !scrolled);
    }
  }

  private refreshFinalDrop(event: PlanerDragPoint, section: string): void {
    // 最后一帧滚动后可能立即松手，不等待下一帧才更新提交落点。
    if (this.dragHoverSection === section && this.validDragSection(section) && this.edgeExpectedMove &&
      this.insideDragList(section, event.getWindowX(), event.getWindowY())) {
      const scroller = section === 'today' ? this.todayScroller : this.futureScroller;
      const offset = scroller.offset();
      if (offset && Math.abs(offset.yOffset - this.edgeLastOffset) > 0.05) {
        this.dragPointerX = event.getWindowX();
        this.dragPointerY = event.getWindowY();
        this.refreshDragTarget(section, true);
      }
    }
  }

  private finishDrop(event: PlanerDragPoint, section: string): void {
    if (!this.dragId && !this.dragIsGroup) return;
    this.refreshFinalDrop(event, section);
    this.stopEdgeScroll();
    if (this.dropIndex < 0 || this.dropSection !== section ||
      (this.dragIsGroup && section !== this.dragSection)) {
      event.setResult(DragResult.DRAG_CANCELED);
      this.resetDrag(true);
      return;
    }
    if (this.dragIsGroup) {
      const action = new AppAction('MOVE_GROUP');
      action.section = this.dragSection;
      action.group = this.dragGroup;
      action.toIndex = this.dropIndex;
      this.dispatch(action);
      if (action.toIndex === 0) {
        // 置于首位时清除拖动边缘滚动的残余偏移，再由didLayout测量展开目标。
        // 滚动不另开动画，避免组员展开期间目标仍在移动，或标题因组名不同看似高低不一。
        const scroller = this.dragSection === 'today' ? this.todayScroller : this.futureScroller;
        scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
      }
    } else {
      const task = this.tasks(this.dragSection).find((item: Task): boolean => item.id === this.dragId);
      if (!task) {
        event.setResult(DragResult.DRAG_CANCELED);
        this.resetDrag(true);
        return;
      }
      let index = this.dropIndex;
      const sourceIndex = this.tasks(this.dragSection).findIndex((item: Task): boolean => item.id === task.id);
      if (this.dropSection === this.dragSection && sourceIndex < index) index--;
      if (task.checkInId && this.dropSection === 'future') {
        this.checkInFeedback('打卡按周期生成，不能移到未来日程；可在打卡页调整计划。');
        event.setResult(DragResult.DRAG_CANCELED);
        this.resetDrag(true);
        return;
      }
      if (this.dragSection === 'today' && this.dropSection === 'future') {
        this.selectedTask = task;
        this.editorSection = 'future';
        this.selectedTarget = index;
        this.selectedGroup = this.dropGroup;
        this.openModal('move');
      } else {
        const action = new AppAction('MOVE_TASK');
        action.id = task.id;
        action.to = this.dropSection;
        action.toIndex = index;
        action.group = this.dropGroup;
        this.dispatch(action);
      }
    }
    event.setResult(DragResult.DRAG_SUCCESSFUL);
    this.resetDrag(true);
  }

  private async deleteGroup(section: string, group: string | null): Promise<void> {
    if (group === null) return;
    let accepted = false;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog(Materials.confirmation(this.palette, {
      title: '删除分组',
      message: '将本区“' + group + '”中的日程移到未分组，日程不会被删除。',
      buttons: [{ text: '取消', color: this.palette.textSoft }, { text: '删除分组', color: this.palette.danger }]
    }));
      accepted = result.index === 1;
    } catch (error) {
      console.error('打开确认对话框失败：' + String(error));
    }
    if (accepted) {
      const action = new AppAction('DELETE_GROUP');
      action.section = section;
      action.group = group;
      this.dispatch(action);
    }
  }

  private groupHead(section: string, index: number): boolean {
    const tasks = this.tasks(section);
    if (index < 0 || index >= tasks.length) return false;
    if (!this.data.settings.showGroups) return false;
    if (tasks.every((task: Task): boolean => task.group === null)) return false;
    return index === 0 || tasks[index - 1].group !== tasks[index].group;
  }

  private commitRatio(): void {
    const action = new AppAction('SET_SETTINGS');
    const settings = this.data.settings.clone();
    settings.todayPaneRatio = this.splitRatio;
    action.settings = settings;
    this.dispatch(action);
  }

  @Builder
  private dropSlot(section: string, taskId: string = '', forGroup: boolean = false) {
    Column() {
      Row() {
        Text(this.dragIsGroup ? '将整组放到这里' : '放到这里').fontSize(12).fontColor(this.palette.accent)
      }.width('100%').height(this.dragHeight).justifyContent(FlexAlign.Center)
        .backgroundColor(this.palette.accentSoft).borderRadius(12)
        .border({ width: 1, color: this.palette.accent, style: BorderStyle.Dashed, radius: 12 })
    }.width('100%').height(this.slotActive(section, taskId, forGroup) ? this.dragHeight + 8 : 0)
      .opacity(this.slotActive(section, taskId, forGroup) ? 1 : 0).clip(true)
      .id(this.slotId(section, taskId, forGroup))
  }

  @Builder
  private taskCard(taskId: string, section: string) {
    Stack() {
      TaskCardView({ task: this.currentTask(section, taskId), order: this.currentIndex(section, taskId) + 1,
        showNumber: this.data.settings.autoNumber, showDefaultProgress: this.data.settings.progressDefaultZero,
        showDates: section === 'future', viewedDate: this.data.currentDate, realDate: todayKey(), palette: this.palette, dragged: this.floatingSource(taskId),
        onToggle: () => this.toggle(this.currentTask(section, taskId), section),
        onEdit: () => this.openEditor(section, this.currentTask(section, taskId)) })
    }.width('100%').id('task-' + taskId)
      .opacity(this.floatingSource(taskId) ?
        (this.floatingGroup ? (this.groupMemberSource(taskId) ? 0 : 1 - this.floatingLift) : 0.18) : 1)
      .draggable(false)
      .gesture(GestureGroup(GestureMode.Sequence,
        LongPressGesture({ duration: 500, repeat: false })
          .onAction((event: GestureEvent) => this.startFloating(event, section, taskId)),
        PanGesture({ direction: PanDirection.All, distance: 1 })
          .onActionStart((event: GestureEvent) => this.updateFloating(event))
          .onActionUpdate((event: GestureEvent) => this.updateFloating(event))
          .onActionEnd((event: GestureEvent) => { this.updateFloating(event); this.finishFloating(true); }))
        .onCancel(() => this.finishFloating(false)))
      .onTouch((event: TouchEvent) => this.floatingTouch(event))
  }

  @Builder
  private floatingPreview() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.floatingGroup) {
        GroupDragVisual({ groupName: this.floatingTask.group || '未分组', tasks: this.floatingTasks,
          members: this.floatingMembers, palette: this.palette, progress: this.floatingLift,
          showNumber: this.data.settings.autoNumber, showDefaultProgress: this.data.settings.progressDefaultZero,
          showDates: this.floatingSection === 'future', viewedDate: this.data.currentDate, realDate: todayKey() })
      } else {
        TaskCardView({ task: this.floatingTask, order: this.floatingOrder, showNumber: this.data.settings.autoNumber,
          showDefaultProgress: this.data.settings.progressDefaultZero, showDates: this.floatingSection === 'future',
          viewedDate: this.data.currentDate, realDate: todayKey(), palette: this.palette, preview: true })
      }
    }.width(this.floatingWidth).height(this.floatingHeight).borderRadius(16)
      .position({ x: this.floatingX, y: this.floatingY })
      .scale({ x: 1 + 0.025 * this.floatingLift, y: 1 + 0.025 * this.floatingLift })
      .translate({ y: -6 * this.floatingLift })
      .shadow({ radius: 8 * this.floatingLift, offsetX: 0, offsetY: 4 * this.floatingLift,
        color: Materials.mode(this.palette) === ThemeColorMode.DARK ? '#68000000' : '#28000000' })
      .visibility(this.floatingPhase === 'idle' ? Visibility.Hidden : Visibility.Visible)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
      .id('drag-floating-preview').zIndex(20)
  }

  @Builder
  private taskList(section: string) {
    List({ space: 8, scroller: section === 'today' ? this.todayScroller : this.futureScroller }) {
      ForEach(this.tasks(section), (task: Task) => {
        ListItem() {
          Column({ space: 0 }) {
            this.dropSlot(section, task.id, true)
            if (this.groupHead(section, this.currentIndex(section, task.id))) {
              Row({ space: 8 }) {
                Text(this.currentTask(section, task.id).group === null ? '未分组' : this.currentTask(section, task.id).group).fontSize(13).fontWeight(FontWeight.Medium)
                  .fontColor(this.palette.textSoft).layoutWeight(1)
                if (this.currentTask(section, task.id).group !== null) {
                  Row() {
                    IconButton({ icon: 'trash', label: '删除本区分组', palette: this.palette, buttonSize: 32, iconSize: 18, cornerRadius: 10,
                      onTap: () => this.deleteGroup(section, this.currentTask(section, task.id).group) })
                  }.width(44).justifyContent(FlexAlign.Center)
                }
              }.width('100%').constraintSize({ minHeight: 32 }).alignItems(VerticalAlign.Center).padding({ left: 6 })
                // 32vp 背板完整包住18vp图标；收紧行后间距，避免分组标题与卡片被拉远。
                .id('group-' + section + '-' + task.id).margin({ bottom: 6 })
                .backgroundColor(Color.Transparent).borderRadius(14)
                .opacity(this.floatingHeader(section, task.id) ? 1 - this.floatingLift : 1)
                .draggable(false)
                .gesture(GestureGroup(GestureMode.Sequence,
                  LongPressGesture({ duration: 500, repeat: false })
                    .onAction((event: GestureEvent) => this.startFloating(event, section, task.id, true)),
                  PanGesture({ direction: PanDirection.All, distance: 1 })
                    .onActionStart((event: GestureEvent) => this.updateFloating(event))
                    .onActionUpdate((event: GestureEvent) => this.updateFloating(event))
                    .onActionEnd((event: GestureEvent) => { this.updateFloating(event); this.finishFloating(true); }))
                  .onCancel(() => this.finishFloating(false)))
                .onTouch((event: TouchEvent) => this.floatingTouch(event))
            }
            this.dropSlot(section, task.id)
            this.taskCard(task.id, section)
          }.width('100%')
        }
      }, (task: Task): string => task.id)
      ListItem() {
        Column({ space: 0 }) {
          this.dropSlot(section)
          if (this.tasks(section).length === 0) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 8 }) {
                PlanerIcon({ icon: 'plus', color: this.palette.textSoft, iconSize: 18 })
                Text(section === 'today' ? '添加今日日程' : '添加未来日程')
                  .fontSize(14).fontColor(this.palette.textSoft)
              }.justifyContent(FlexAlign.Center)
            }
              .width('100%').height(74).backgroundColor(Materials.fallback(this.palette))
              .backgroundBlurStyle(BlurStyle.COMPONENT_THIN, { colorMode: Materials.mode(this.palette) })
              .borderRadius(12).border({ width: 1, color: this.palette.border, style: BorderStyle.Dashed, radius: 12 })
              .onClick(() => this.openEditor(section)).id('empty-' + section)
          } else {
            Row() {
              Text(this.dragId || this.dragIsGroup ? '移到列表末尾' : '长按日程拖动排序')
                .fontSize(11).fontColor(this.palette.textFaint)
            }.width('100%').height(40).justifyContent(FlexAlign.Center)
          }
          if (section === 'future') {
            // 可滚动尾部留白：内容能从浮栏背后经过，最后一项仍能上滑到可操作区。
            Blank().height(this.futureTailSpace).hitTestBehavior(HitTestMode.None)
          }
        }.width('100%')
          .id('list-end-' + section)
      }
    }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 12 })
      // 水平留白保持卡片宽度与横坐标；顶部收紧，浮起与阴影由根浮层绘制。
      .clipContent(ContentClipMode.BOUNDARY)
      .height('100%').scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .id('list-' + section)
      .onScrollIndex((start: number, end: number) => this.recordVisibleItems(section, start, end))
      .onDidScroll(() => {
        if (this.dragHoverSection === section) this.queueEdgeFrame();
        this.updateMoreBelow();
      })
      .onAreaChange((_oldArea: Area, area: Area) => {
        if (section === 'today') {
          this.todayTop = Number(area.globalPosition.y);
          this.todayHeight = Number(area.height);
        } else {
          this.futureTop = Number(area.globalPosition.y);
          this.futureHeight = Number(area.height);
          this.updateFutureTailSpace();
        }
      })
  }

  private moreFadeHeight(section: string): number {
    // 未来区从浮栏上方开始渐隐，一直连续延伸到屏幕底边，避免在胶囊顶部截出一条边。
    const height = section === 'today' ? this.todayHeight : this.futureHeight;
    const span = 30 + (section === 'future' ? this.futureMoreInset : 0);
    return Math.min(Math.max(0, height), span);
  }

  @Builder
  private moreBelowHint(section: string) {
    Column({ space: 0 }) {
      Blank().layoutWeight(1).backgroundColor(Color.White).hitTestBehavior(HitTestMode.None)
      Row().width('100%').height(this.moreFadeHeight(section)).hitTestBehavior(HitTestMode.None)
        .linearGradient({ direction: GradientDirection.Bottom, colors: [
          [Color.White, 0], [Color.White, 0.08],
          [this.moreHintVisible(section) ? Color.Transparent : Color.White, 1]
        ] })
    }.width('100%').height('100%')
      // 白色只提供 alpha，不参与最终颜色；真实圆角、主页渐变和底栏保持各自原有绘制。
      .blendMode(BlendMode.DST_IN, BlendApplyType.OFFSCREEN)
      .hitTestBehavior(HitTestMode.Transparent).accessibilityLevel('no-hide-descendants')
      .id('more-below-' + section)
  }

  @Builder
  private pane(section: string) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(section === 'today' ? '当日日程' : '未来日程').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.palette.text)
        if (this.tasks(section).length > 0) {
          Text(this.tasks(section).length.toString()).fontSize(12).fontColor(this.palette.accent)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 }).backgroundColor(this.palette.accentSoft).borderRadius(8)
        }
        Blank()
        IconButton({ icon: 'plus', label: section === 'today' ? '添加当日日程' : '添加未来日程',
          palette: this.palette, onTap: () => this.openEditor(section) })
      }.width('100%').height(44)
      Stack({ alignContent: Alignment.Bottom }) {
        this.taskList(section)
        this.moreBelowHint(section)
      }.width('calc(100% + 32vp)').layoutWeight(1)
        // 完整视口统一离屏混合；蒙版作为直接子节点显式穿透，不用会生成命中宿主的 overlay。
        .blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
    }.width('100%').height('100%')
  }

  @Builder
  private widePane(section: string) {
    Column() {
      this.pane(section)
    }.layoutWeight(1).height('100%').padding({ left: 20, right: 20, top: 14, bottom: 8 })
      .backgroundColor('#50' + this.palette.panel.substring(1)).borderRadius(24)
      .border({ width: 1, radius: 24, color: this.palette.border })
      .id('wide-pane-' + section)
  }

  @Builder
  private mainPage() {
    Column() {
      Row({ space: 8 }) {
        Row().width(9).height(9).borderRadius(3).backgroundColor(this.palette.accent)
        Text($r('app.string.brand_name')).fontSize(13).fontColor(this.palette.textSoft).fontWeight(FontWeight.Medium)
        Blank()
      }.width('100%').height(36)
      Row({ space: 8 }) {
        Column({ space: 6 }) {
          Text(formatFull(this.data.currentDate)).fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.palette.text)
            .maxLines(1).minFontSize(16).maxFontSize(22).heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
          Row({ space: 8 }) {
            Text(this.data.todayTasks.length > 0 ? '已完成 ' + this.doneCount() + ' / ' + this.data.todayTasks.length :
              '今天还没有日程，加一条吧').fontSize(12).fontColor(this.palette.textSoft)
            if (this.data.todayTasks.length > 0) {
              Progress({ value: this.doneCount(), total: this.data.todayTasks.length, type: ProgressType.Linear })
                .width(40).color(this.palette.accent).backgroundColor(this.palette.border).style({ strokeWidth: 4 })
            }
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        IconButton({ icon: 'calendar', label: '选择日期', palette: this.palette, onTap: () => { this.openModal('date'); } })
      }.width('100%').padding({ top: 8, bottom: 18 })
      if (this.data.currentDate > todayKey()) {
        Row({ space: 10 }) {
          Column({ space: 4 }) {
            Text('正在预览 ' + formatFull(this.data.currentDate)).fontSize(12).fontWeight(FontWeight.Medium)
              .fontColor(this.palette.accent).width('100%')
            Text('此前未完成的日程也会在此日展示；“预计延期”不代表真实日期已过去。')
              .fontSize(11).lineHeight(16).fontColor(this.palette.textSoft).width('100%')
          }.layoutWeight(1)
          MaterialButtonScope({ palette: this.palette, controlHeight: 40, content: () => { this.previewReturnButton(); } }).width(88).height(40)
        }.width('100%').padding(12).borderRadius(16).backgroundColor(this.palette.panel2)
          .margin({ bottom: 10 }).id('date-preview-notice')
      }
      if (this.saveError) {
        Text(this.saveError).fontColor(this.palette.danger).fontSize(12).width('100%').height(36)
          .onClick(() => this.persist())
      }
      if (this.wideLayout) {
        Row({ space: 24 }) {
          this.widePane('today')
          this.widePane('future')
        }.width('100%').layoutWeight(1).alignItems(VerticalAlign.Top)
          .padding({ top: 8, bottom: 100 + this.safeBottom }).id('wide-schedule-panes')
      } else {
        Column() {
          Column() {
            this.pane('today')
          }.width('100%').height(this.todayPaneHeight())
          Row() {
            Row().width(42).height(4).backgroundColor(this.palette.border).borderRadius(2)
          }.width('100%').height(24).justifyContent(FlexAlign.Center).id('pane-divider')
            .accessibilityText('拖动调整当日与未来区域大小')
            .gesture(PanGesture({ direction: PanDirection.Vertical, distance: 2 })
              .onActionStart(() => { this.splitStart = this.clampSplitRatio(this.splitRatio); })
              .onActionUpdate((event: GestureEvent) => {
                this.splitRatio = this.clampSplitRatio(this.splitStart + event.offsetY / this.splitBaseHeight());
              })
              .onActionEnd(() => this.commitRatio())
              .onActionCancel(() => { this.splitRatio = this.data.settings.todayPaneRatio; }))
          Column() {
            this.pane('future')
          }.width('100%').layoutWeight(1)
        }.width('100%').layoutWeight(1).onAreaChange((_oldArea: Area, area: Area) => {
          this.paneHeight = Math.max(1, Number(area.height) - 24);
        })
      }
    }.height('100%').width('100%').constraintSize({ maxWidth: ResponsiveLayout.contentWidth(this.viewportWidth) })
      .padding({ left: ResponsiveLayout.gutter(this.viewportWidth), right: ResponsiveLayout.gutter(this.viewportWidth), top: this.safeTop }).backgroundColor(Color.Transparent)
  }

  @Builder
  private modalTitle(title: string) {
    Row() {
      Text(title).fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.palette.text).layoutWeight(1)
      IconButton({ icon: 'close', label: '关闭', palette: this.palette, onTap: () => { this.closeModal(); } })
    }.width('100%').padding({ bottom: 12 })
  }

  @Builder
  private previewReturnButton() {
    Button('回到今天', { type: ButtonType.Normal }).width('100%').fontSize(12).height(40).borderRadius(12)
      .fontColor(this.palette.accent).attributeModifier(new PlanerControlModifier(this.palette, true))
      .onClick(() => {
        const action = new AppAction('SELECT_DATE');
        action.key = todayKey();
        this.dispatch(action);
      }).id('preview-return-today')
  }

  @Builder
  private modalActionContent(title: string, icon: string, id: string, action: () => void) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 8 }) {
        PlanerIcon({ icon: icon, color: this.palette.accent, iconSize: 18 })
        Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette.accent)
      }.width('100%').justifyContent(FlexAlign.Center)
    }.height(46).width('100%').padding(0).borderRadius(12).id(id)
      .attributeModifier(new PlanerControlModifier(this.palette, true))
      .scale({ x: ButtonFeedback.scale(this.modalPressedButton, id), y: ButtonFeedback.scale(this.modalPressedButton, id) })
      .onTouch((event: TouchEvent): void => this.modalButtonTouch(id, event))
      .onClick(() => this.modalTap(action))
      .onDisAppear(() => { if (this.modalPressedButton === id) this.modalPressedButton = ''; })
  }

  @Builder
  private actionButton(title: string, icon: string, id: string, action: () => void) {
    MaterialButtonScope({ palette: this.palette, controlHeight: 46, radius: 12,
      content: () => { this.modalActionContent(title, icon, id, action); } }).width('100%').height(46)
  }

  @Builder
  private dateSelectionBody() {
    Column({ space: 12 }) {
      Text('浏览日期').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette.text).width('100%')
      Text('浏览未来不会提前归档今天的完成项；未完成项会一起顺延展示')
        .fontSize(13).lineHeight(20).fontColor(this.palette.textSoft).width('100%')
      PlanerCalendar({ value: this.data.currentDate, minDate: todayKey(), marks: this.markedDates(), palette: this.palette,
        onSelect: (key: string) => this.selectBrowsingDate(key) })
    }.width('100%').padding(14)
  }

  @Builder
  private restoreTaskBody() {
    Column({ space: 10 }) {
      Text('日程内容').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette.text).width('100%')
      Text(this.selectedTask.text).fontSize(15).lineHeight(22).fontColor(this.palette.textSoft).width('100%')
    }.width('100%').padding(14)
  }

  @Builder
  private restoreTargetButton(target: string, title: string, icon: string) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 6 }) {
        PlanerIcon({ icon: icon, color: this.restoreTarget === target ? this.palette.accent : this.palette.textSoft, iconSize: 18 })
        Text(title).fontSize(13).fontColor(this.restoreTarget === target ? this.palette.accent : this.palette.text)
      }.width('100%').justifyContent(FlexAlign.Center)
    }.id('restore-target-' + target).width('100%').height(44).padding(0).borderRadius(12)
      .attributeModifier(new PlanerControlModifier(this.palette, this.restoreTarget === target))
      .accessibilityText(title + (this.restoreTarget === target ? '，已选中' : ''))
      .scale({ x: ButtonFeedback.scale(this.modalPressedButton, 'restore-' + target),
        y: ButtonFeedback.scale(this.modalPressedButton, 'restore-' + target) })
      .onTouch((event: TouchEvent): void => this.modalButtonTouch('restore-' + target, event))
      .onClick(() => this.modalTap(() => this.selectRestoreTarget(target)))
  }

  @Builder
  private restoreTargetBody() {
    Column({ space: 12 }) {
      Text('恢复位置').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette.text).width('100%')
      Text('原计划日期已过，请选择恢复方式。').fontSize(13).lineHeight(20).fontColor(this.palette.textSoft).width('100%')
      Row({ space: 10 }) {
        MaterialButtonScope({ palette: this.palette, controlHeight: 44,
          content: () => { this.restoreTargetButton('today', '恢复到当日', 'home'); } }).layoutWeight(1).height(44)
        MaterialButtonScope({ palette: this.palette, controlHeight: 44,
          content: () => { this.restoreTargetButton('future', '恢复到未来', 'calendar'); } }).layoutWeight(1).height(44)
      }.width('100%')
    }.width('100%').padding(14)
  }

  @Builder
  private restoreDateBody() {
    Column({ space: 10 }) {
      Text('恢复日期').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette.text).width('100%')
      PlanerCalendar({ value: this.restoreDate, minDate: this.data.currentDate, palette: this.palette,
        onSelect: (key: string) => { this.restoreDate = key; } })
    }.width('100%').padding(14)
  }

  @Builder
  private dateAndRestoreContent() {
    Column() {
      Column() { this.modalTitle(this.modal === 'date' ? '选择日期' : '恢复日程') }
        .width('100%').padding({ left: 20, right: 12, top: 12 })
      Divider().color(this.palette.border)
      Scroll(this.modalScroller) {
        Column({ space: 16 }) {
          if (this.modal === 'date') {
            MaterialSection({ palette: this.palette, viewportId: 'index-modal-scroll',
              content: () => { this.dateSelectionBody(); } }).width('100%')
          } else {
            MaterialSection({ palette: this.palette, viewportId: 'index-modal-scroll',
              content: () => { this.restoreTaskBody(); } }).width('100%')
            MaterialSection({ palette: this.palette, viewportId: 'index-modal-scroll',
              content: () => { this.restoreTargetBody(); } }).width('100%')
            if (this.restoreTarget === 'future') {
              MaterialSection({ palette: this.palette, viewportId: 'index-modal-scroll',
                content: () => { this.restoreDateBody(); } }).width('100%').transition(Motion.reveal())
            }
          }
        }.width('100%').padding({ left: 20, right: 20, top: 16, bottom: 24 })
          .alignItems(HorizontalAlign.Start)
      }.id('index-modal-scroll').width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .onAreaChange(() => EditorMaterialRefresh.request(this.getUIContext()))
        .onDidScroll(() => EditorMaterialRefresh.request(this.getUIContext()))
      Divider().color(this.palette.border)
      Column() {
        if (this.modal === 'date') {
          this.actionButton('回到今天', 'calendar', 'date-return-today', () => this.selectBrowsingDate(todayKey()))
        } else {
          this.actionButton('确认恢复', 'restore', 'restore-confirm', () => this.restoreSelected())
        }
      }.width('100%').constraintSize({ maxWidth: 520 }).padding({ left: 20, right: 20, top: 14, bottom: 18 })
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
      .onAreaChange(() => EditorMaterialRefresh.request(this.getUIContext()))
  }

  @Builder
  private modalContent() {
    if (this.modal === 'add' || this.modal === 'edit' || this.modal === 'move') {
      TaskEditor({
        data: this.data, palette: this.palette, section: this.modal === 'move' ? 'future' : this.editorSection,
        task: this.modal === 'add' ? null : this.selectedTask, mode: this.modal,
        targetIndex: this.selectedTarget, targetGroup: this.selectedGroup,
        onAction: (action: AppAction) => this.dispatch(action), onClose: () => { this.closeModal(); },
        onDelete: () => this.deleteEditingTask()
      })
    } else if (this.modal === 'date' || this.modal === 'restore') {
      this.dateAndRestoreContent()
    }
  }

  @Builder
  private modalSurfaceContent() {
    SheetMaterialSurface({ palette: this.palette, content: () => { this.modalContent(); } })
  }

  private checkInFeedback(message: string): void {
    try { this.getUIContext().getPromptAction().showToast({ message: message }); }
    catch (_) { console.warn('打卡操作反馈暂不可用'); }
  }

  private checkInTabSymbol(): TabBarSymbol {
    return {
      normal: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle')).fontColor([this.palette.textSoft]),
      selected: new SymbolGlyphModifier($r('sys.symbol.checkmark_circle_fill')).fontColor([this.palette.accent])
    };
  }

  build() {
    WithTheme({ colorMode: Materials.mode(this.palette) }) {
      Stack({ alignContent: Alignment.Bottom }) {
        if (!this.ready) {
          Column({ space: 16 }) {
            if (this.loadError) {
              Text(this.loadError).fontSize(15).fontColor(this.palette.danger).textAlign(TextAlign.Center)
              Button('重试读取', { type: ButtonType.Normal }).borderRadius(12)
                .onClick(() => this.load()).backgroundColor(this.palette.accent)
            } else {
              LoadingProgress().width(36).height(36).color(this.palette.accent)
              Text('正在加载日程…').fontSize(14).fontColor(this.palette.textSoft)
            }
          }.width('100%').height('100%').padding(24).justifyContent(FlexAlign.Center)
        } else {
          Stack() {
            Tabs({ barPosition: BarPosition.End, index: $$this.activeTab, controller: this.tabsController }) {
              TabContent() {
                this.mainPage()
              }.tabBar(BottomTabBarStyle.of(this.displayedTab === 0 ? $r('app.media.house_fill_tab') : $r('app.media.house_tab'), '主页')
                .id('tab-home').iconStyle({ selectedColor: this.palette.accent, unselectedColor: this.palette.textSoft })
                .labelStyle({ selectedColor: this.palette.accent, unselectedColor: this.palette.textSoft }))
              TabContent() {
                CheckInView({ data: this.data, palette: this.palette, windowWidth: this.viewportWidth,
                  safeBottom: Math.max(0, this.safeBottom - this.tabsBottomPadding()),
                  requestedItemId: this.checkInRequestedId, requestRevision: this.checkInRequestRevision,
                  saveError: this.saveError, onRetrySave: () => this.persist(),
                  onSheetChange: (shown: boolean) => { this.checkInSheetShown = shown; },
                  onAction: (action: AppAction) => this.dispatch(action) })
              }.tabBar(BottomTabBarStyle.of(this.checkInTabSymbol(), '打卡')
                .id('tab-checkin').labelStyle({ selectedColor: this.palette.accent, unselectedColor: this.palette.textSoft }))
              TabContent() {
                SettingsView({ data: this.data, palette: this.palette, windowWidth: this.viewportWidth, scroller: this.settingsScroller,
                  onAction: (action: AppAction) => this.dispatch(action), onHistory: () => this.navigate(3),
                  onTutorial: () => this.openTutorial() })
                  .padding({ bottom: this.safeBottom - this.tabsBottomPadding() })
              }.tabBar(BottomTabBarStyle.of(this.displayedTab === 2 ? $r('app.media.gearshape_fill_tab') : $r('app.media.gearshape_tab'), '设置')
                .id('tab-settings').iconStyle({ selectedColor: this.palette.accent, unselectedColor: this.palette.textSoft })
                .labelStyle({ selectedColor: this.palette.accent, unselectedColor: this.palette.textSoft }))
            }
            .width('100%').height('100%').vertical(false).barOverlap(true).barMode(BarMode.Fixed)
            .attributeModifier(new PlanerTabsModifier(this.palette, this.safeBottom))
            .scrollable(false).animationDuration(320).animationCurve(Motion.springCurve())
            .onAnimationStart((_index: number, targetIndex: number) => { this.displayedTab = targetIndex; })
            .onChange((index: number) => {
              this.displayedTab = index;
              this.page = index;
              this.resetDrag();
              if (index === 0) { this.restoreAnchor(); this.updateFutureTailSpace(); }
            })
            // 首次创建使用插入转场，访问后保留实例与滚动位置；以后仍按原位移动画进出。
            if (this.historyCreated) {
              HistoryView({ data: this.data, palette: this.palette, windowWidth: this.viewportWidth, scroller: this.historyScroller,
                onBack: () => this.navigate(2), onRestore: (task: Task, date: string) => this.restoreTask(task, date),
                onDelete: (task: Task, date: string) => this.confirmDelete(task, date), onClear: () => this.clearHistory() })
                .padding({ bottom: this.safeBottom - this.tabsBottomPadding() })
                .translate({ x: this.page === 3 ? '0%' : '100%' })
                .backgroundColor(this.palette.bg)
                .transition(TransitionEffect.translate({ x: '100%' }).animation(Motion.spring()))
                .id('history-page')
            }
          }.width('100%').height('100%').padding({ bottom: this.tabsBottomPadding() })
            .accessibilityLevel(this.tutorialShown ? 'no-hide-descendants' : 'auto')

        }
        this.floatingPreview()
        // 独立稳定宿主，避免与日程表单共用同一个 bindSheet 覆盖彼此。
        Row().width(1).height(1).position({ x: 0, y: 0 }).hitTestBehavior(HitTestMode.None)
          .bindSheet($$this.tutorialShown, this.tutorialSurfaceContent(), Materials.sheet(this.palette, {
            height: '94%', width: ResponsiveLayout.sheetWidth(this.viewportWidth, false), preferType: SheetType.BOTTOM, dragBar: true, showClose: false,
            radius: { topLeft: 26, topRight: 26, bottomLeft: 26, bottomRight: 26 },
            onDisappear: (): void => {
              this.tutorialEntered = false;
              if (!this.tutorialShown) this.completeTutorial();
            }
          }))
      }.id('planer-root').width('100%').height('100%')
        .onAreaChange((_old: Area, area: Area) => {
          const width = Number(area.width);
          if (width <= 0 || Math.abs(width - this.viewportWidth) < 1) return;
          const wide = ResponsiveLayout.wide(width);
          if (wide !== this.wideLayout) this.resetDrag();
          this.viewportWidth = width;
          this.wideLayout = wide;
        })
        .backgroundColor(this.palette.bg)
        .linearGradient({ direction: GradientDirection.Bottom, colors: [
          [this.palette.bg, 0.0], [this.palette.bgSoft, 0.65], [this.palette.accentSoft, 1.0]
        ] })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .bindSheet($$this.sheetShown, this.modalSurfaceContent(), Materials.sheet(this.palette, {
          height: this.sheetHeight(), width: ResponsiveLayout.sheetWidth(this.viewportWidth, this.modal === 'edit' || this.modal === 'move' ||
            (this.modal === 'add' && this.editorSection === 'future')),
          preferType: this.viewportWidth >= 600 ? SheetType.CENTER : SheetType.BOTTOM,
          dragBar: false, showClose: false,
          radius: { topLeft: 24, topRight: 24, bottomLeft: 24, bottomRight: 24 },
          keyboardAvoidMode: SheetKeyboardAvoidMode.NONE,
          onDisappear: () => {
            if (!this.sheetShown) {
              this.modal = '';
            }
          }
        }))
    }
  }
}
