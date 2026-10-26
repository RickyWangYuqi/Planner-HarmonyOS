import { window, FrameCallback } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode, HdsNavigationTitleBarStyle, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { AppAction, AppData } from '../model/PlanerModel';
import { CheckInItem, CheckInRecord, CheckInStats } from '../model/CheckInModel';
import { checkInStats, checkInTimeline, checkInFutureTimeline, previewCheckInRecord, isCheckInDate, validateCheckInAction } from '../model/CheckInEngine';
import { realDateOf, addDays } from '../model/PlanerEngine';
import { Palette } from '../theme/Theme';
import { Materials, Motion, PlanerControlModifier, ButtonFeedback } from '../theme/Appearance';
import { ResponsiveLayout } from '../theme/ResponsiveLayout';
import { SheetMaterialSurface } from './SheetMaterialSurface';
import { MaterialButtonScope } from './MaterialButtonScope';
import { MaterialSection, EditorMaterialRefresh } from './MaterialSection';
import { CheckInToggleButton } from './CheckInToggleButton';
import { CheckInEditor } from './CheckInEditor';
import { CheckInBackfill } from './CheckInBackfill';
import { CheckInHistoryRecord } from './CheckInHistoryRecord';
import { CheckInFilter } from './CheckInFilter';
import { HistoryBackButton } from './HistoryBackButton';
import { IconButton } from './IconButton';
import { PlanerIcon } from './PlanerIcon';

// 布局提交后只做一次焦点测量，避免反复请求帧造成无效渲染。
class CheckInFocusFrame extends FrameCallback {
  private callback: () => void;
  constructor(callback: () => void) { super(); this.callback = callback; }
  onIdle(_time: number): void { this.callback(); }
}

@Component
export struct CheckInView {
  @StorageProp('planerSafeTop') safeTop: number = 0;
  @Prop @Watch('dataChanged') data: AppData = new AppData();
  @Prop palette: Palette = new Palette();
  @Prop windowWidth: number = 0;
  @Prop safeBottom: number = 0;
  @Prop requestedItemId: string = '';
  @Prop @Watch('openRequestedItem') requestRevision: number = 0;
  @Prop saveError: string = '';
  onAction: (action: AppAction) => void = (): void => {};
  onRetrySave: () => void = (): void => {};
  onSheetChange: (shown: boolean) => void = (): void => {};
  @State @Watch('sheetChanged') private sheetShown: boolean = false;
  @State private modal: string = 'detail';
  @State @Watch('refreshSelectedDerived') private selectedId: string = '';
  @State private editorItem: CheckInItem = new CheckInItem();
  @State private recordKey: string = '';
  @State private draftName: string = '';
  @State private actionError: string = '';
  @State private showAll: boolean = false;
  @State private pressedButton: string = '';
  @State private listDirection: number = 1;
  @State @Watch('refreshSelectedDerived') private timelineLimit: number = 60;
  @State private keyboardInset: number = 0;
  @State private overallStats: CheckInStats = new CheckInStats();
  @State private selectedStats: CheckInStats = new CheckInStats();
  @State private selectedTimeline: CheckInRecord[] = [];
  @State private selectedFutureTimeline: CheckInRecord[] = [];
  @State @Watch('refreshSelectedDerived') private futureLimit: number = 30;
  @State private listViewportWidth: number = 0;
  private sheetActive: boolean = false;
  private sheetWindow: window.Window | undefined = undefined;
  private keyboardObserverVersion: number = 0;
  private keyboardHeightPx: number = 0;
  private sheetBottomVp: number = 0;
  private sheetAreaKnown: boolean = false;
  private detailScroller: Scroller = new Scroller();
  private timelineScroller: Scroller = new Scroller();
  private historyRecordScroller: Scroller = new Scroller();
  private editorScroller: Scroller = new Scroller();
  private backfillScroller: Scroller = new Scroller();
  private rangeScroller: Scroller = new Scroller();
  private overviewScroller: Scroller = new Scroller();
  private focusedInput: string = '';
  private focusScrollTimer: number = -1;
  private focusScrollVersion: number = 0;
  private focusFrameQueued: boolean = false;
  private keyboardListener: (height: number) => void = (height: number): void => {
    if (!this.sheetActive) return;
    this.keyboardHeightPx = Math.max(0, height);
    this.updateKeyboardInset();
  };

  aboutToAppear(): void { this.dataChanged(); if (this.requestedItemId) this.openRequestedItem(); }
  aboutToDisappear(): void { this.stopKeyboardObserver(); this.onSheetChange(false); }
  private sheetChanged(): void { this.pressedButton = ''; this.onSheetChange(this.sheetShown); }
  private today(): string { return realDateOf(this.data); }

  private dataChanged(): void {
    this.overallStats = checkInStats(this.data);
    this.refreshSelectedDerived();
  }

  private refreshSelectedDerived(): void {
    this.selectedStats = this.selectedId ? checkInStats(this.data, this.selectedId) : new CheckInStats();
    this.selectedTimeline = this.selectedId ? checkInTimeline(this.data, this.selectedId, this.timelineLimit) : [];
    this.selectedFutureTimeline = this.selectedId ? checkInFutureTimeline(this.data, this.selectedId, this.futureLimit) : [];
  }

  private stats(scope: string): CheckInStats { return scope === 'selected' ? this.selectedStats : this.overallStats; }

  private metricValue(scope: string, field: string): string {
    const stats = this.stats(scope);
    if (field === 'rate') return Math.round(stats.rate) + '%';
    if (field === 'currentStreak') return stats.currentStreak.toString();
    if (field === 'longestStreak') return stats.longestStreak.toString();
    return stats.completed.toString();
  }

  private itemById(id: string): CheckInItem {
    return this.data.checkIns.find((item: CheckInItem): boolean => item.id === id) || new CheckInItem();
  }

  private timelineRecord(key: string): CheckInRecord {
    return this.selectedTimeline.concat(this.selectedFutureTimeline).find((record: CheckInRecord): boolean => record.key === key) || new CheckInRecord();
  }

  private hasSnapshot(key: string): boolean { return !!this.recordFor(this.selectedId, key); }

  private snapshotContentText(key: string): string {
    if (key > this.today()) return this.timelineRecord(key).name || '数字超出范围，请先调整计划';
    if (!this.hasSnapshot(key)) return '未记录当期内容';
    return this.timelineRecord(key).name;
  }

  private sectionCount(section: string): number {
    if (section === 'today') return this.todayItems().length;
    if (section === 'waiting') return this.waiting().length;
    if (section === 'completed') return this.completed().length;
    if (section === 'other') return this.otherDays().length;
    if (section === 'paused') return this.paused().length;
    return this.active().length;
  }

  private modalTitle(): string {
    if (this.modal === 'range') return '确认本期内容';
    if (this.modal === 'backfill') return '补卡';
    if (this.modal === 'history') return '历史计划';
    return this.selected().name;
  }

  private modalSubtitle(): string {
    if (this.modal === 'range') return this.selected().name + ' · ' + this.recordKey;
    if (this.modal !== 'detail') return this.selected().name;
    return this.frequencyLabel(this.selected()) + ' · ' + this.itemStatus(this.selected());
  }

  private smallButtonText(title: string, id: string): string {
    if (id === 'checkin-pause-resume') return this.selected().paused ? '已暂停' : '暂停';
    if (id.startsWith('checkin-complete-')) {
      const itemId = id.substring('checkin-complete-'.length);
      return this.recordFor(itemId, this.today())?.status === 'pending' ? '确认内容' : '打卡';
    }
    return title;
  }

  private manageButtonIcon(icon: string, id: string): string {
    // 最内层 Builder 直接读取当前状态，避免材质回调保留旧的按值图标参数。
    return id === 'checkin-pause-resume' ? (this.selected().paused ? 'paused' : 'pause') : icon;
  }

  private startKeyboardObserver(): void {
    if (this.sheetActive) return;
    this.sheetActive = true;
    this.observeKeyboard();
  }

  private async observeKeyboard(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const version = ++this.keyboardObserverVersion;
    try {
      const sheetWindow = await window.getLastWindow(context);
      // 异步取窗期间已关闭的弹层不能重新注册监听。
      if (!this.sheetActive || version !== this.keyboardObserverVersion) return;
      this.sheetWindow = sheetWindow;
      sheetWindow.on('keyboardHeightChange', this.keyboardListener);
      this.keyboardHeightPx = sheetWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD).bottomRect.height;
      this.updateKeyboardInset();
    } catch {
      console.error('打卡弹层读取键盘区域失败');
    }
  }

  private stopKeyboardObserver(): void {
    this.sheetActive = false;
    this.focusedInput = '';
    this.cancelFocusedInputScroll();
    this.keyboardObserverVersion++;
    if (this.sheetWindow) {
      try { this.sheetWindow.off('keyboardHeightChange', this.keyboardListener); }
      catch { console.error('打卡弹层移除键盘监听失败'); }
    }
    this.sheetWindow = undefined;
    this.keyboardHeightPx = 0;
    this.sheetAreaKnown = false;
    this.keyboardInset = 0;
  }

  private updateSheetArea(area: Area): void {
    const bottom = Number(area.globalPosition.y) + Number(area.height);
    if (!this.sheetActive || !Number.isFinite(bottom)) return;
    this.sheetBottomVp = bottom;
    this.sheetAreaKnown = true;
    this.updateKeyboardInset();
  }

  private updateKeyboardInset(): void {
    if (!this.sheetActive) return;
    const uiContext = this.getUIContext();
    const root = uiContext.getFrameNodeById('checkin-sheet-root');
    if (root) {
      // 节点位置是 vp、测量高度是 px；使用带变换的实际位置覆盖半模态平移。
      const height = uiContext.px2vp(root.getMeasuredSize().height);
      const bottom = root.getPositionToWindowWithTransform().y + height;
      if (height > 0 && Number.isFinite(bottom)) {
        this.sheetBottomVp = bottom;
        this.sheetAreaKnown = true;
      }
    }
    if (!this.sheetWindow || !this.sheetAreaKnown || this.keyboardHeightPx <= 0) {
      this.setKeyboardInset(0);
      return;
    }
    try {
      const height = this.sheetWindow.getWindowProperties().windowRect.height;
      const keyboardTop = uiContext.px2vp(Math.max(0, height - this.keyboardHeightPx));
      this.setKeyboardInset(Math.max(0, this.sheetBottomVp - keyboardTop));
    } catch {
      console.error('打卡弹层读取窗口尺寸失败');
    }
  }

  private setKeyboardInset(value: number): void {
    if (Math.abs(this.keyboardInset - value) < 0.5) return;
    // 仅压缩弹层内部滚动内容，固定操作区随局部内边距抬起。
    const animation = Motion.quick();
    animation.onFinish = (): void => this.scheduleFocusedInputScroll();
    this.getUIContext().animateTo(animation, () => { this.keyboardInset = value; });
    this.scheduleFocusedInputScroll();
  }

  private focusInput(id: string): void {
    this.focusedInput = id;
    this.scheduleFocusedInputScroll();
  }

  private blurInput(id: string): void {
    if (this.focusedInput !== id) return;
    this.focusedInput = '';
    this.cancelFocusedInputScroll();
  }

  private cancelFocusedInputScroll(): void {
    this.focusScrollVersion++;
    this.focusFrameQueued = false;
    if (this.focusScrollTimer >= 0) clearTimeout(this.focusScrollTimer);
    this.focusScrollTimer = -1;
  }

  private scheduleFocusedInputScroll(): void {
    if (!this.sheetActive || !this.focusedInput) return;
    const version = this.focusScrollVersion;
    if (!this.focusFrameQueued) {
      this.focusFrameQueued = true;
      this.getUIContext().postFrameCallback(new CheckInFocusFrame((): void => {
        if (!this.sheetActive || version !== this.focusScrollVersion) return;
        this.focusFrameQueued = false;
        this.ensureFocusedInputVisible();
      }));
    }
    if (this.focusScrollTimer >= 0) clearTimeout(this.focusScrollTimer);
    // 键盘和局部避让都有动画，再补一次稳定布局测量；关闭/失焦会取消。
    this.focusScrollTimer = setTimeout((): void => {
      this.focusScrollTimer = -1;
      if (this.sheetActive && version === this.focusScrollVersion) this.ensureFocusedInputVisible();
    }, 320);
  }

  private ensureFocusedInputVisible(): void {
    if (!this.sheetActive || !this.focusedInput) return;
    const uiContext = this.getUIContext();
    const input = uiContext.getFrameNodeById(this.focusedInput);
    const viewportId = this.modal === 'editor' ? 'checkin-editor-scroll' :
      (this.modal === 'backfill' ? 'checkin-backfill-scroll' : (this.modal === 'history' ? 'checkin-history-scroll' : 'checkin-range-scroll'));
    const viewport = uiContext.getFrameNodeById(viewportId);
    if (!input || !viewport || !input.isAttached() || !viewport.isAttached()) return;
    const inputTop = input.getPositionToWindowWithTransform().y;
    const inputHeight = uiContext.px2vp(input.getMeasuredSize().height);
    const viewportHeight = uiContext.px2vp(viewport.getMeasuredSize().height);
    if (inputHeight <= 0 || viewportHeight <= 16) return;
    const visibleTop = viewport.getPositionToWindowWithTransform().y + 8;
    const visibleBottom = visibleTop + viewportHeight - 16;
    let distance = 0;
    if (inputHeight > visibleBottom - visibleTop) distance = inputTop - visibleTop;
    else if (inputTop + inputHeight > visibleBottom) distance = inputTop + inputHeight - visibleBottom;
    else if (inputTop < visibleTop) distance = inputTop - visibleTop;
    if (Math.abs(distance) > 0.5) this.activeScroller().scrollBy(0, distance);
  }

  private activeScroller(): Scroller {
    if (this.modal === 'editor') return this.editorScroller;
    if (this.modal === 'backfill') return this.backfillScroller;
    if (this.modal === 'history') return this.historyRecordScroller;
    return this.modal === 'range' ? this.rangeScroller : this.detailScroller;
  }

  private buttonTouch(id: string, event: TouchEvent): void {
    const next = ButtonFeedback.next(this.pressedButton, id, event.type);
    if (next !== this.pressedButton) this.getUIContext().animateTo(Motion.quick(), () => { this.pressedButton = next; });
  }

  private tapButton(tap: () => void): void { this.pressedButton = ''; tap(); }

  private switchList(all: boolean): void {
    if (all === this.showAll) return;
    this.pressedButton = '';
    this.listDirection = all ? 1 : -1;
    this.getUIContext().animateTo(Motion.spring(), () => { this.showAll = all; });
  }

  private listTravel(): number {
    // 使用完整窗口距离；百分比位移只覆盖内容宽度，会在左右留白处残留旧卡片。
    return Math.max(this.windowWidth, this.listViewportWidth, 360) + 32;
  }

  private listTransition(): TransitionEffect {
    const travel = this.listTravel();
    return TransitionEffect.asymmetric(
      TransitionEffect.translate({ x: this.listDirection > 0 ? travel : -travel }),
      TransitionEffect.translate({ x: this.listDirection > 0 ? -travel : travel })).animation(Motion.spring());
  }

  private showModal(next: string): void {
    this.focusedInput = ''; this.cancelFocusedInputScroll(); this.pressedButton = ''; this.actionError = '';
    this.getUIContext().animateTo(Motion.spring(), () => { this.modal = next; });
  }

  private openRequestedItem(): void {
    const item = this.data.checkIns.find((value: CheckInItem): boolean => value.id === this.requestedItemId);
    if (item) this.openDetail(item);
  }

  private selected(): CheckInItem {
    return this.data.checkIns.find((item: CheckInItem): boolean => item.id === this.selectedId) || new CheckInItem();
  }

  private recordFor(id: string, key: string): CheckInRecord | undefined {
    return this.data.checkInRecords.find((record: CheckInRecord): boolean => record.itemId === id && record.key === key);
  }

  private active(): CheckInItem[] { return this.data.checkIns.filter((item: CheckInItem): boolean => !item.deleted && !item.paused); }
  private paused(): CheckInItem[] { return this.data.checkIns.filter((item: CheckInItem): boolean => !item.deleted && item.paused); }
  private dueToday(item: CheckInItem): boolean { return !!this.recordFor(item.id, this.today()) || isCheckInDate(item, this.today()); }
  private completedToday(item: CheckInItem): boolean { return this.recordFor(item.id, this.today())?.status === 'completed'; }
  // 完成只改变按钮状态，稳定的计划顺序避免卡片跳到另一分区。
  private todayItems(): CheckInItem[] { return this.active().filter((item: CheckInItem): boolean => this.dueToday(item)); }
  private waiting(): CheckInItem[] { return this.active().filter((item: CheckInItem): boolean => this.dueToday(item) && !this.completedToday(item)); }
  private completed(): CheckInItem[] { return this.active().filter((item: CheckInItem): boolean => this.completedToday(item)); }
  private otherDays(): CheckInItem[] { return this.active().filter((item: CheckInItem): boolean => !this.dueToday(item)); }

  private frequencyLabel(item: CheckInItem): string {
    if (item.frequency === 'daily') return '每天';
    if (item.frequency === 'weekly') return '每周' + item.weekdays.slice().sort((a: number, b: number): number => (a || 7) - (b || 7))
      .map((day: number): string => ['日', '一', '二', '三', '四', '五', '六'][day]).join('、');
    return '每月 ' + item.monthDays.slice().sort((a: number, b: number): number => a - b).join('、') + ' 日';
  }

  private recordLabel(record: CheckInRecord): string {
    if (record.status === 'completed') return record.advanced ? '已提前打卡' : (record.backfilled ? '已补卡' : '已完成');
    if (record.key > this.today()) return record.name ? '未来计划' : '需调整内容';
    if (record.status === 'pending') return record.key < this.today() ? '未完成 · 未确认内容' : '待确认内容';
    return record.key < this.today() ? '未完成' : '待打卡';
  }

  private itemStatus(item: CheckInItem): string {
    if (item.paused) return '已暂停';
    if (item.startDate > this.today()) return '将于 ' + item.startDate + ' 开始';
    const record = this.recordFor(item.id, this.today());
    return record ? this.recordLabel(record) : (this.dueToday(item) ? '待打卡' : '今天无需打卡');
  }

  private openDetail(item: CheckInItem): void {
    this.selectedId = item.id; this.modal = 'detail'; this.actionError = ''; this.timelineLimit = 60; this.futureLimit = 30; this.sheetShown = true;
  }
  private openNew(): void {
    this.editorItem = new CheckInItem(); this.selectedId = ''; this.modal = 'editor'; this.actionError = ''; this.sheetShown = true;
  }
  private editSelected(): void { this.editorItem = this.selected().clone(); this.showModal('editor'); }
  private closeSheet(): void { this.pressedButton = ''; this.sheetShown = false; }
  private backToDetail(): void { this.showModal('detail'); }

  private dismissSheet(action: DismissSheetAction): void {
    if (action.reason === DismissReason.PRESS_BACK && this.selectedId && this.modal !== 'detail') {
      this.backToDetail();
    } else action.dismiss();
  }

  private toast(message: string): void {
    try { this.getUIContext().getPromptAction().showToast({ message: message, duration: 2200 }); } catch (_) {}
  }

  private dispatch(action: AppAction, message: string): string {
    const error = validateCheckInAction(this.data, action);
    this.actionError = error;
    if (error) { this.toast(error); return error; }
    this.onAction(action); this.toast(message); return '';
  }

  private saveItem(item: CheckInItem): string {
    const action = new AppAction('CHECKIN_SAVE'); action.checkIn = item;
    const error = this.dispatch(action, this.editorItem.id ? '已更新打卡计划' : '已创建打卡计划');
    if (!error) { if (this.editorItem.id) this.backToDetail(); else this.closeSheet(); }
    return error;
  }

  private async confirmAction(type: string, title: string, message: string, success: string, key: string = ''): Promise<void> {
    const targetId = this.selectedId;
    try {
      const result = await this.getUIContext().getPromptAction().showDialog(Materials.confirmation(this.palette, {
        title: title, message: message, buttons: [
          { text: '取消', color: this.palette.textSoft }, { text: '确认', color: this.palette.danger }
        ]
      }));
      if (result.index !== 1) return;
      const action = new AppAction(type); action.id = targetId; action.key = key;
      if (!this.dispatch(action, success) && this.selectedId === targetId) {
        if (type === 'CHECKIN_DELETE') {
          this.closeSheet(); this.selectedId = ''; this.draftName = ''; this.recordKey = '';
        } else this.backToDetail();
      }
    } catch (_) {}
  }

  private openComplete(item: CheckInItem, key: string): void {
    if (key < this.today()) {
      this.selectedId = item.id; this.recordKey = key; this.draftName = ''; this.actionError = '';
      if (this.sheetShown) this.showModal('backfill'); else this.modal = 'backfill';
      this.sheetShown = true;
      return;
    }
    const record = this.recordFor(item.id, key);
    if (record?.status === 'pending') { this.openRange(record); return; }
    const action = new AppAction('CHECKIN_COMPLETE'); action.id = item.id; action.key = key;
    this.dispatch(action, '已完成本次打卡');
  }

  private toggleToday(id: string): void {
    this.pressedButton = '';
    if (this.recordFor(id, this.today())?.status === 'completed') this.undo(id, this.today());
    else this.openComplete(this.itemById(id), this.today());
  }

  private undo(id: string, key: string): void {
    const action = new AppAction('CHECKIN_UNDO'); action.id = id; action.key = key;
    this.dispatch(action, '已撤销本次打卡');
  }

  private pauseSelected(): void {
    const item = this.selected();
    const action = new AppAction(item.paused ? 'CHECKIN_RESUME' : 'CHECKIN_PAUSE'); action.id = item.id;
    this.dispatch(action, item.paused ? '已恢复计划' : '已暂停计划');
  }

  private advance(key: string): string {
    const action = new AppAction('CHECKIN_ADVANCE'); action.id = this.selectedId; action.key = key;
    return this.dispatch(action, '已提前完成 ' + key + ' 的打卡');
  }

  private toggleFuture(key: string): void {
    this.pressedButton = '';
    if (this.timelineRecord(key).status === 'completed') this.undo(this.selectedId, key);
    else this.advance(key);
  }

  private openHistory(key: string): void {
    if (key >= this.today() || !previewCheckInRecord(this.data, this.selectedId, key)) return;
    this.recordKey = key; this.showModal('history');
  }

  private undoHistory(): string {
    const action = new AppAction('CHECKIN_UNDO'); action.id = this.selectedId; action.key = this.recordKey;
    return this.dispatch(action, '已撤销本次打卡');
  }

  private orderedTimeline(): CheckInRecord[] {
    return this.selectedTimeline.slice().reverse().concat(this.selectedFutureTimeline);
  }

  private timelineAnchorIndex(): number {
    const records = this.orderedTimeline();
    const index = records.findIndex((record: CheckInRecord): boolean => record.key >= this.today());
    // 首行是“更早记录”入口，首次定位今天；历史在上，未来在下。
    return 1 + (index >= 0 ? index : Math.max(0, records.length - 1));
  }

  private moreTimelineHistory(): void {
    const targetId = this.selectedId;
    const anchor = this.selectedTimeline[this.selectedTimeline.length - 1]?.key || '';
    this.timelineLimit += 60;
    this.getUIContext().postFrameCallback(new CheckInFocusFrame((): void => {
      if (!this.sheetShown || this.modal !== 'detail' || this.selectedId !== targetId) return;
      const index = this.orderedTimeline().findIndex((record: CheckInRecord): boolean => record.key === anchor);
      if (index >= 0) this.timelineScroller.scrollToIndex(index + 1, false, ScrollAlign.START);
    }));
  }

  private openBackfill(): void {
    const latest = this.records().find((record: CheckInRecord): boolean => record.key < this.today() && record.status !== 'completed');
    this.recordKey = latest ? latest.key : addDays(this.today(), -1); this.draftName = ''; this.actionError = '';
    this.showModal('backfill');
  }

  private openRange(record: CheckInRecord): void {
    this.selectedId = record.itemId; this.recordKey = record.key; this.draftName = record.name;
    this.actionError = '';
    if (this.sheetShown) this.showModal('range'); else this.modal = 'range';
    this.sheetShown = true;
  }

  private backfill(key: string, name: string): string {
    const action = new AppAction('CHECKIN_BACKFILL');
    action.id = this.selectedId; action.key = key; action.text = name;
    return this.dispatch(action, '已补卡');
  }

  private generate(): void {
    if (!this.draftName.trim()) { this.actionError = '请输入本期名称'; return; }
    const action = new AppAction('CHECKIN_GENERATE'); action.id = this.selectedId; action.key = this.recordKey;
    action.text = this.draftName.trim();
    if (!this.dispatch(action, '已确认内容并生成本期日程')) this.backToDetail();
  }

  private previousName(): string {
    const previous = this.data.checkInRecords.filter((record: CheckInRecord): boolean =>
      record.itemId === this.selectedId && record.key < this.recordKey && !!record.generatedAt && !record.backfilled)
      .sort((a: CheckInRecord, b: CheckInRecord): number => a.key < b.key ? 1 : -1)[0];
    return previous ? previous.name + '（' + previous.key + '）' : this.selected().name;
  }

  private records(): CheckInRecord[] {
    return this.selectedTimeline;
  }

  private completedTime(record: CheckInRecord): string {
    if (!record.completedAt) return '';
    const time = new Date(record.completedAt);
    if (!Number.isFinite(time.getTime())) return record.completedAt;
    return time.getFullYear() + '-' + (time.getMonth() + 1).toString().padStart(2, '0') + '-' + time.getDate().toString().padStart(2, '0') +
      ' ' + time.getHours().toString().padStart(2, '0') + ':' + time.getMinutes().toString().padStart(2, '0');
  }

  @Builder private smallButton(title: string, id: string, tap: () => void, danger: boolean = false) {
    Button(this.smallButtonText(title, id), { type: ButtonType.Normal, stateEffect: false }).id(id).height(42).fontSize(13).borderRadius(12)
      .padding({ left: 14, right: 14 }).fontColor(danger ? this.palette.danger : this.palette.accent)
      .attributeModifier(new PlanerControlModifier(this.palette, false, danger, false))
      .scale({ x: ButtonFeedback.scale(this.pressedButton, id), y: ButtonFeedback.scale(this.pressedButton, id) })
      .onTouch((event: TouchEvent) => this.buttonTouch(id, event)).onClick(() => this.tapButton(tap))
      .onDisAppear(() => { if (this.pressedButton === id) this.pressedButton = ''; })
  }

  @Builder private sectionTitle(title: string, section: string) {
    Row({ space: 8 }) {
      Text(title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.palette.text)
      Text(this.sectionCount(section).toString()).fontSize(12).fontColor(this.palette.textSoft)
    }.width('100%').margin({ top: 4, bottom: 2 })
  }

  @Builder private metric(scope: string, field: string, label: string) {
    Column({ space: 6 }) {
      Text(this.metricValue(scope, field)).fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.palette.text).maxLines(1)
      Text(label).fontSize(11).fontColor(this.palette.textSoft).maxLines(1)
    }.layoutWeight(1)
  }

  @Builder private statsContent(scope: string) {
    Column({ space: 12 }) {
      Row() {
        Blank().layoutWeight(1)
        Text('共 ' + this.stats(scope).total + ' 期').fontSize(11).fontColor(this.palette.textFaint)
      }.width('100%')
      Row() {
        this.metric(scope, 'completed', '累计完成')
        this.metric(scope, 'rate', '完成率')
        this.metric(scope, 'currentStreak', '当前连续')
        this.metric(scope, 'longestStreak', '最长连续')
      }.width('100%')
    }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 18 })
  }

  @Builder private statsPanel(scope: string) {
    if (scope === 'selected') {
      MaterialSection({ palette: this.palette, viewportId: 'checkin-detail-scroll', content: () => { this.statsContent(scope); } })
    } else {
      Column() { this.statsContent(scope) }.width('100%').borderRadius(18).backgroundColor(Materials.fallback(this.palette))
    }
  }

  @Builder private itemCard(id: string, todayAction: boolean = false) {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Column({ space: 7 }) {
          Text(this.itemById(id).name).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.palette.text).width('100%').maxLines(2)
          Text(this.frequencyLabel(this.itemById(id)) + ' · ' + this.itemStatus(this.itemById(id))).fontSize(12).fontColor(this.palette.textSoft).width('100%')
        }.layoutWeight(1)
        Row() {
          IconButton({ icon: 'edit', label: '查看打卡详情', palette: this.palette, onTap: () => this.openDetail(this.itemById(id)) })
        }.id('checkin-detail-' + id).width(44).height(44).justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      }.width('100%').alignItems(VerticalAlign.Center)
      if (todayAction && !this.itemById(id).paused) {
        Row() {
          Blank().layoutWeight(1)
          CheckInToggleButton({ palette: this.palette, completed: this.completedToday(this.itemById(id)),
            pending: this.recordFor(id, this.today())?.status === 'pending', buttonId: 'checkin-complete-' + id,
            onToggle: () => this.toggleToday(id) })
        }.width('100%')
      }
    }.id('checkin-card-' + this.itemById(id).id).width('100%').padding(16).borderRadius(18)
      .backgroundColor(Materials.fallback(this.palette))
  }

  @Builder private errorBanner() {
    if (this.saveError) {
      Column({ space: 8 }) {
        Text(this.saveError).fontSize(13).fontColor(this.palette.danger).lineHeight(20).width('100%')
        this.smallButton('重试保存', 'checkin-retry-save', () => this.onRetrySave())
      }.id('checkin-save-error').width('100%').padding(14).backgroundColor(this.palette.dangerSoft).borderRadius(14)
    }
  }

  @Builder private pausedList() {
    if (this.paused().length > 0) {
      this.sectionTitle('已暂停', 'paused')
      ForEach(this.paused(), (item: CheckInItem) => { this.itemCard(item.id) }, (item: CheckInItem): string => item.id)
    }
  }

  @Builder private emptyList() {
    Column({ space: 18 }) {
      Text('从一件小事开始').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.palette.text)
      this.smallButton('新建打卡', 'checkin-empty-create', () => this.openNew())
    }.width('100%').padding({ top: 38, bottom: 38, left: 12, right: 12 })
  }

  @Builder private allPlans() {
    Column({ space: 14 }) {
      if (this.active().length === 0 && this.paused().length === 0) { this.emptyList() }
      else {
        if (this.active().length > 0) {
          this.sectionTitle('进行中', 'active')
          ForEach(this.active(), (item: CheckInItem) => { this.itemCard(item.id, this.dueToday(item)) }, (item: CheckInItem): string => item.id)
        }
        this.pausedList()
      }
    }.width('100%')
  }

  @Builder private todayPlans() {
    Column({ space: 14 }) {
      if (this.active().length === 0 && this.paused().length === 0) { this.emptyList() }
      else {
        this.sectionTitle('今日打卡', 'today')
        if (this.todayItems().length === 0) {
          Text('今天暂无打卡项').fontSize(14).fontColor(this.palette.textSoft)
            .width('100%').padding({ top: 12, bottom: 16 })
        }
        ForEach(this.todayItems(), (item: CheckInItem) => { this.itemCard(item.id, true) }, (item: CheckInItem): string => item.id)
        if (this.otherDays().length > 0) {
          this.sectionTitle('其他计划', 'other')
          ForEach(this.otherDays(), (item: CheckInItem) => { this.itemCard(item.id) }, (item: CheckInItem): string => item.id)
        }
        this.pausedList()
      }
    }.width('100%')
  }

  @Builder private overview() {
    Column({ space: 16 }) {
      this.errorBanner()
      this.statsPanel('overall')
      CheckInFilter({ selectedMode: this.showAll ? 'all' : 'today', palette: this.palette,
        onSelect: (mode: string): void => this.switchList(mode === 'all') })
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.showAll) {
          Column() { this.allPlans() }.width('100%').transition(this.listTransition())
        } else {
          Column() { this.todayPlans() }.width('100%').transition(this.listTransition())
        }
      }.width('100%').clip(true).id('checkin-plan-lists')
        .onSizeChange((_old: SizeOptions, size: SizeOptions): void => { this.listViewportWidth = Number(size.width); })
    }.width('100%').constraintSize({ maxWidth: 760 })
      .padding({ left: ResponsiveLayout.gutter(this.windowWidth), right: ResponsiveLayout.gutter(this.windowWidth), top: this.safeTop + 72, bottom: 110 + this.safeBottom })
  }

  @Builder private detailHeader() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(this.selected().name).fontSize(21).fontWeight(FontWeight.Bold).fontColor(this.palette.text).width('100%').maxLines(2)
        Text(this.frequencyLabel(this.selected()) + ' · ' + this.itemStatus(this.selected())).fontSize(12).fontColor(this.palette.textSoft).width('100%').maxLines(2)
      }.layoutWeight(1)
      IconButton({ icon: 'close', label: '关闭打卡详情', palette: this.palette, onTap: () => this.closeSheet() }).id('checkin-detail-close')
    }.width('100%').padding({ left: 20, right: 16, top: 20, bottom: 14 })
    Divider().color(this.palette.border).opacity(0.6)
  }

  @Builder private modalHeader() {
    Row({ space: 12 }) {
      if (this.modal !== 'detail') {
        HistoryBackButton({ palette: this.palette, label: '返回打卡详情', buttonId: 'checkin-modal-back', onBack: () => this.backToDetail() })
      }
      Column({ space: 4 }) {
        Text(this.modalTitle()).fontSize(21).fontWeight(FontWeight.Bold).fontColor(this.palette.text).width('100%').maxLines(2)
        Text(this.modalSubtitle()).fontSize(12).fontColor(this.palette.textSoft).width('100%').maxLines(2)
      }.layoutWeight(1)
      IconButton({ icon: 'close', label: '关闭打卡详情', palette: this.palette, onTap: () => this.closeSheet() }).id('checkin-modal-close')
    }.width('100%').padding({ left: 20, right: 16, top: 20, bottom: 14 })
    Divider().color(this.palette.border).opacity(0.6)
  }

  @Builder private recordRow(key: string) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.timelineRecord(key).key).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette.text).layoutWeight(1)
        Text(this.recordLabel(this.timelineRecord(key))).fontSize(12).fontColor(this.timelineRecord(key).status === 'completed' ? this.palette.success : this.palette.textSoft)
        if (key < this.today()) PlanerIcon({ icon: 'right', iconSize: 15, color: this.palette.textSoft })
      }.width('100%')
      Text(this.snapshotContentText(key)).fontSize(16).fontColor(this.palette.text).width('100%').lineHeight(23)
      if (this.timelineRecord(key).completedAt) Text('完成于 ' + this.completedTime(this.timelineRecord(key))).fontSize(12).fontColor(this.palette.textSoft).width('100%')
      if (key >= this.today()) {
        Row() {
          Blank().layoutWeight(1)
          if (key > this.today()) {
            if (this.timelineRecord(key).name) {
              CheckInToggleButton({ palette: this.palette, future: true, completed: this.timelineRecord(key).status === 'completed',
                buttonId: 'checkin-advance-' + key, onToggle: () => { this.toggleFuture(key); } })
            }
          } else if (this.timelineRecord(key).status === 'pending') {
            this.smallButton('调整本期内容', 'checkin-range-' + key, () => this.openRange(this.timelineRecord(key)))
          } else {
            CheckInToggleButton({ palette: this.palette, completed: this.timelineRecord(key).status === 'completed',
              buttonId: 'checkin-record-toggle-' + key, onToggle: () => this.toggleToday(this.selectedId) })
          }
        }.width('100%')
      }
    }.id('checkin-record-' + key).width('100%').padding(16)
      .onClick(() => { if (key < this.today()) this.openHistory(key); })
      .accessibilityText(key < this.today() ? key + '，' + this.snapshotContentText(key) + '，查看历史计划' : key)
  }

  @Builder private timelineList() {
    List({ space: 12, scroller: this.timelineScroller, initialIndex: this.timelineAnchorIndex() }) {
      ListItem() {
        Row() {
          if (this.selectedTimeline.length >= this.timelineLimit) {
            this.smallButton('查看更早记录', 'checkin-more-history', () => this.moreTimelineHistory())
          } else {
            Text('历史记录').fontSize(12).fontColor(this.palette.textFaint)
          }
        }.width('100%').height(44).justifyContent(FlexAlign.Center)
      }
      ForEach(this.orderedTimeline(), (record: CheckInRecord) => {
        ListItem() {
          MaterialSection({ palette: this.palette, viewportId: 'checkin-timeline-list', content: () => { this.recordRow(record.key); } })
        }
      }, (record: CheckInRecord): string => record.itemId + ':' + record.key)
      ListItem() {
        Row() {
          if (this.selectedFutureTimeline.length >= this.futureLimit) {
            this.smallButton('查看更多未来计划', 'checkin-more-future', () => { this.futureLimit += 30; })
          } else {
            Text(this.selected().paused ? '已暂停，恢复后继续生成未来计划' : '暂无更多计划').fontSize(12).fontColor(this.palette.textFaint)
          }
        }.width('100%').height(44).justifyContent(FlexAlign.Center)
      }
    }.id('checkin-timeline-list').width('100%').height(440).scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring).nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
      .onDidScroll(() => EditorMaterialRefresh.request(this.getUIContext()))
      .onAreaChange(() => EditorMaterialRefresh.request(this.getUIContext()))
  }

  @Builder private manageButtonContent(title: string, icon: string, id: string, tap: () => void, danger: boolean = false) {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        Row({ space: 8 }) {
          PlanerIcon({ icon: this.manageButtonIcon(icon, id), iconSize: 18, color: danger ? this.palette.danger : this.palette.textSoft })
          Text(this.smallButtonText(title, id)).fontSize(14).fontColor(danger ? this.palette.danger : this.palette.text)
        }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      }.id(id).width('100%').height(44).padding(0).borderRadius(12)
        .attributeModifier(new PlanerControlModifier(this.palette, false, danger))
        .scale({ x: ButtonFeedback.scale(this.pressedButton, id), y: ButtonFeedback.scale(this.pressedButton, id) })
        .onTouch((event: TouchEvent) => this.buttonTouch(id, event)).onClick(() => this.tapButton(tap))
        .onDisAppear(() => { if (this.pressedButton === id) this.pressedButton = ''; })
  }

  @Builder private manageButton(title: string, icon: string, id: string, tap: () => void, danger: boolean = false) {
    MaterialButtonScope({ palette: this.palette, content: () => { this.manageButtonContent(title, icon, id, tap, danger); } }).height(44).layoutWeight(1)
  }

  @Builder private managementSection() {
    Column({ space: 14 }) {
      Text('计划管理').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.palette.text).width('100%')
      Text('开始于 ' + this.selected().startDate + (this.selected().autoIncrement ? ' · 自动递增/接续' : ''))
        .fontSize(13).fontColor(this.palette.textSoft).width('100%')
      Row({ space: 10 }) {
        this.manageButton('编辑计划', 'edit', 'checkin-edit', () => this.editSelected())
        this.manageButton('补卡', 'calendar', 'checkin-backfill', () => this.openBackfill())
      }.width('100%')
      Row({ space: 10 }) {
        this.manageButton(this.selected().paused ? '已暂停' : '暂停', this.selected().paused ? 'paused' : 'pause', 'checkin-pause-resume', () => this.pauseSelected())
        this.manageButton('删除', 'trash', 'checkin-delete', () => {
          this.confirmAction('CHECKIN_DELETE', '永久删除这个打卡计划？', '将永久删除这个计划、全部打卡记录及关联日程，无法恢复。', '已永久删除打卡计划');
        }, true)
      }.width('100%')
    }.width('100%').padding(16)
  }

  @Builder private emptyHistory() {
    Text('暂无记录').fontSize(14).fontColor(this.palette.textSoft).width('100%').padding(16)
  }

  @Builder private detailBody() {
    Column() {
      this.detailHeader()
      Scroll(this.detailScroller) {
        Column({ space: 16 }) {
          this.errorBanner()
          this.statsPanel('selected')
          if (!this.selected().deleted) {
            MaterialSection({ palette: this.palette, viewportId: 'checkin-detail-scroll', content: () => { this.managementSection(); } })
          }
          Text('打卡时间线').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.palette.text).width('100%')
          if (this.records().length === 0) {
            MaterialSection({ palette: this.palette, viewportId: 'checkin-detail-scroll', content: () => { this.emptyHistory(); } })
          }
          this.timelineList()
          if (this.actionError) Text(this.actionError).fontSize(13).fontColor(this.palette.danger).width('100%')
        }.width('100%').padding({ left: 20, right: 20, top: 16, bottom: 24 }).constraintSize({ maxWidth: 680 })
      }.id('checkin-detail-scroll').width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring)
        .onDidScroll(() => EditorMaterialRefresh.request(this.getUIContext()))
        .onAreaChange(() => EditorMaterialRefresh.request(this.getUIContext()))
    }.width('100%').height('100%')
  }

  @Builder private primaryButton(title: string, id: string, tap: () => void) {
    Button(title, { type: ButtonType.Normal, stateEffect: false }).id(id).width('100%').height(46).borderRadius(12).fontSize(16)
      .fontColor(this.palette.accent).attributeModifier(new PlanerControlModifier(this.palette, true))
      .scale({ x: ButtonFeedback.scale(this.pressedButton, id), y: ButtonFeedback.scale(this.pressedButton, id) })
      .onTouch((event: TouchEvent) => this.buttonTouch(id, event)).onClick(() => this.tapButton(tap))
  }

  @Builder private rangeSection() {
    Column({ space: 18 }) {
      Text('上一期内容').fontSize(13).fontColor(this.palette.textSoft).width('100%')
      Text(this.previousName()).fontSize(18).fontColor(this.palette.text).lineHeight(26).width('100%')
      Divider().color(this.palette.border)
      Text('本期名称，可直接修改').fontSize(14).fontColor(this.palette.text).width('100%')
      TextArea({ text: this.draftName, placeholder: '填写本期打卡名称' }).id('checkin-confirm-name').height(110).padding(12).maxLength(120)
        .onFocus(() => this.focusInput('checkin-confirm-name')).onBlur(() => this.blurInput('checkin-confirm-name'))
        .fontSize(16).fontColor(this.palette.text).backgroundColor(Materials.input(this.palette)).borderRadius(12)
        .onChange((value: string) => { this.draftName = value; this.actionError = ''; })
      Text('调整数字后继续生成本期。').fontSize(13).fontColor(this.palette.textSoft).lineHeight(22).width('100%')
    }.width('100%').padding(16)
  }

  @Builder private rangeBody() {
    Column() {
      this.modalHeader()
      Scroll(this.rangeScroller) {
        Column() {
          MaterialSection({ palette: this.palette, viewportId: 'checkin-range-scroll', content: () => {
            this.rangeSection()
          } })
        }.width('100%').padding(20).constraintSize({ maxWidth: 680 })
      }.id('checkin-range-scroll').width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Auto)
        .onDidScroll(() => EditorMaterialRefresh.request(this.getUIContext()))
        .onAreaChange(() => { this.scheduleFocusedInputScroll(); EditorMaterialRefresh.request(this.getUIContext()); })
      Column({ space: 10 }) {
        if (this.actionError) Text(this.actionError).id('checkin-range-error').fontSize(13).fontColor(this.palette.danger).width('100%')
        MaterialButtonScope({ palette: this.palette, controlHeight: 46,
          content: () => { this.primaryButton('确认并生成', 'checkin-confirm-range', () => this.generate()); } }).width('100%').height(46)
        Button('暂不', { type: ButtonType.Normal, stateEffect: false }).id('checkin-range-later').width('100%').height(44).fontSize(14)
          .fontColor(this.palette.textSoft).backgroundColor(Color.Transparent).onClick(() => this.backToDetail())
      }.width('100%').padding({ left: 20, right: 20, top: 12, bottom: 18 }).constraintSize({ maxWidth: 680 })
    }.width('100%').height('100%')
  }

  @Builder private modalBody() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.selectedId) {
        Column() { this.detailBody() }.width('100%').height('100%')
          .translate({ x: this.modal === 'detail' ? '0%' : '-20%' }).opacity(this.modal === 'detail' ? 1 : 0)
          .hitTestBehavior(this.modal === 'detail' ? HitTestMode.Default : HitTestMode.None)
          .accessibilityLevel(this.modal === 'detail' ? 'auto' : 'no-hide-descendants')
      }
      if (this.modal === 'editor') {
        Column() {
          CheckInEditor({ item: this.editorItem, data: this.data, palette: this.palette, scroller: this.editorScroller,
            isSubpage: !!this.selectedId, onBack: () => this.backToDetail(),
            onInputFocus: (id: string): void => this.focusInput(id), onInputBlur: (id: string): void => this.blurInput(id),
            onViewportChange: (): void => this.scheduleFocusedInputScroll(),
            onSave: (item: CheckInItem): string => this.saveItem(item), onClose: () => this.closeSheet() })
        }.width('100%').height('100%').transition(this.selectedId ? TransitionEffect.translate({ x: '100%' }).animation(Motion.spring()) : TransitionEffect.IDENTITY)
      } else if (this.modal === 'backfill') {
        Column() {
          CheckInBackfill({ data: this.data, itemId: this.selectedId, palette: this.palette, initialDate: this.recordKey,
            scroller: this.backfillScroller, onBack: () => this.backToDetail(),
            onComplete: (key: string, name: string): string => this.backfill(key, name),
            onAdvance: (key: string): string => this.advance(key),
            onInputFocus: (id: string): void => this.focusInput(id), onInputBlur: (id: string): void => this.blurInput(id),
            onViewportChange: (): void => this.scheduleFocusedInputScroll() })
        }.width('100%').height('100%').transition(TransitionEffect.translate({ x: '100%' }).animation(Motion.spring()))
      } else if (this.modal === 'history') {
        Column() {
          CheckInHistoryRecord({ data: this.data, itemId: this.selectedId, keyDate: this.recordKey, palette: this.palette,
            scroller: this.historyRecordScroller, onBack: () => this.backToDetail(), onClose: () => this.closeSheet(),
            onUndo: (): string => this.undoHistory(), onBackfill: (name: string): string => this.backfill(this.recordKey, name),
            onInputFocus: (id: string): void => this.focusInput(id), onInputBlur: (id: string): void => this.blurInput(id),
            onViewportChange: (): void => this.scheduleFocusedInputScroll() })
        }.width('100%').height('100%').transition(TransitionEffect.translate({ x: '100%' }).animation(Motion.spring()))
      } else if (this.modal === 'range') {
        Column() { this.rangeBody() }.width('100%').height('100%')
          .transition(TransitionEffect.translate({ x: '100%' }).animation(Motion.spring()))

      }
    }.width('100%').height('100%').clip(true)
  }

  @Builder private sheetContent() {
    Column() {
      Column() { this.modalBody() }.width('100%').layoutWeight(1)
    }.id('checkin-sheet-root').width('100%').height('100%').padding({ bottom: this.keyboardInset })
      .onAppear(() => this.startKeyboardObserver())
      .onDisAppear(() => this.stopKeyboardObserver())
      .onAreaChange((_old: Area, area: Area): void => this.updateSheetArea(area))
  }

  @Builder private materialSheet() {
    SheetMaterialSurface({ palette: this.palette, content: () => { this.sheetContent(); } })
  }

  private headerStyle(): HdsNavigationTitleBarStyle {
    return { backgroundStyle: { backgroundColor: Color.Transparent },
      contentStyle: { titleStyle: { mainTitleColor: this.palette.text } } };
  }

  @Builder private fixedHeader() {
    Row({ space: 12 }) {
      Text('打卡').id('checkin-title').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.palette.text).layoutWeight(1)
      IconButton({ icon: 'plus', label: '新增打卡', tone: 'accent', palette: this.palette, onTap: () => this.openNew() }).id('checkin-create')
    }.width('100%').height(56).padding({ left: ResponsiveLayout.gutter(this.windowWidth), right: ResponsiveLayout.gutter(this.windowWidth) })
  }

  build() {
    HdsNavigation() {
      Scroll(this.overviewScroller) { this.overview() }.id('checkin-overview-scroll').width('100%').height('100%')
        .align(Alignment.Top).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).clip(false)
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
      .mode(NavigationMode.Stack).hideBackButton(true).hideToolBar(true).bindToScrollable([this.overviewScroller])
      .titleBar({ avoidLayoutSafeArea: true, enableComponentSafeArea: false,
        style: { systemMaterialEffect: { materialType: hdsMaterial.MaterialType.ADAPTIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE },
          scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
          originalStyle: this.headerStyle(), scrollEffectStyle: this.headerStyle() },
        content: { title: { mainTitle: '' }, stackBuilder: () => { this.fixedHeader(); } }
      }).withTheme({ enableThemeColorMode: true }).titleMode(HdsNavigationTitleMode.MINI)
      .bindSheet($$this.sheetShown, this.materialSheet(), Materials.sheet(this.palette, {
        height: '90%', width: ResponsiveLayout.sheetWidth(this.windowWidth, false),
        preferType: this.windowWidth >= 600 ? SheetType.CENTER : SheetType.BOTTOM,
        showClose: false, dragBar: false, keyboardAvoidMode: SheetKeyboardAvoidMode.NONE,
        radius: { topLeft: 24, topRight: 24, bottomLeft: this.windowWidth >= 600 ? 24 : 0, bottomRight: this.windowWidth >= 600 ? 24 : 0 },
        onWillDismiss: (action: DismissSheetAction): void => this.dismissSheet(action),
        onDisappear: (): void => { this.sheetShown = false; }
      }))
  }
}
