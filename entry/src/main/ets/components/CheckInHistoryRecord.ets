import { AppAction, AppData } from '../model/PlanerModel';
import { CheckInItem, CheckInRecord } from '../model/CheckInModel';
import { isCheckInDate, validateCheckInAction } from '../model/CheckInEngine';
import { realDateOf, todayKey, fromKey, formatFull } from '../model/PlanerEngine';
import { Palette } from '../theme/Theme';
import { Materials, Motion, PlanerControlModifier, ButtonFeedback } from '../theme/Appearance';
import { HistoryBackButton } from './HistoryBackButton';
import { IconButton } from './IconButton';
import { PlanerIcon } from './PlanerIcon';
import { MaterialSection, EditorMaterialRefresh } from './MaterialSection';
import { MaterialButtonScope } from './MaterialButtonScope';

@Component
export struct CheckInHistoryRecord {
  @Prop @Watch('dataChanged') data: AppData = new AppData();
  @Prop @Watch('identityChanged') itemId: string = '';
  @Prop @Watch('identityChanged') keyDate: string = '';
  @Prop palette: Palette = new Palette();
  scroller: Scroller = new Scroller();
  onBack: () => void = (): void => {};
  onClose: () => void = (): void => {};
  onUndo: () => string = (): string => '';
  onBackfill: (name: string) => string = (_name: string): string => '';
  onInputFocus: (id: string) => void = (_id: string): void => {};
  onInputBlur: (id: string) => void = (_id: string): void => {};
  onViewportChange: () => void = (): void => {};
  @State private snapshot: CheckInRecord | undefined = undefined;
  @State private draftName: string = '';
  @State private error: string = '';
  @State private submitting: boolean = false;
  @State private awaitingRefresh: boolean = false;
  @State private pressedButton: string = '';
  private snapshotSignature: string = '';
  private waitingSignature: string = '';

  aboutToAppear(): void { this.identityChanged(); }
  aboutToDisappear(): void { this.pressedButton = ''; this.onInputBlur('checkin-history-name'); }
  private today(): string { return realDateOf(this.data) || todayKey(); }
  private item(): CheckInItem | undefined {
    return this.data.checkIns.find((item: CheckInItem): boolean => item.id === this.itemId);
  }
  private recordFor(): CheckInRecord | undefined {
    return this.data.checkInRecords.find((record: CheckInRecord): boolean => record.itemId === this.itemId && record.key === this.keyDate);
  }
  private validDate(): boolean {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(this.keyDate)) return false;
    const date = fromKey(this.keyDate);
    return Number.isFinite(date.getTime()) && date.getFullYear().toString().padStart(4, '0') + '-' +
      (date.getMonth() + 1).toString().padStart(2, '0') + '-' + date.getDate().toString().padStart(2, '0') === this.keyDate;
  }
  private selectionError(): string {
    if (!this.validDate()) return '无法识别这个历史日期';
    if (this.keyDate >= this.today()) return '这里只能操作过去的打卡周期';
    const item = this.item();
    if (!item || item.deleted) return '这个打卡计划已不存在';
    if (!this.recordFor() && !isCheckInDate(item, this.keyDate)) return '这一天不在打卡周期内';
    return '';
  }
  private identityChanged(): void {
    this.draftName = ''; this.error = ''; this.pressedButton = ''; this.awaitingRefresh = false;
    this.snapshotSignature = ''; this.waitingSignature = '';
    this.onInputBlur('checkin-history-name');
    this.dataChanged();
  }
  private dataChanged(): void {
    const record = this.recordFor();
    const signature = this.selectionError() + ':' + JSON.stringify(record || null);
    if (signature !== this.snapshotSignature) this.error = '';
    this.snapshot = record;
    this.snapshotSignature = signature;
    if (this.awaitingRefresh && signature !== this.waitingSignature) this.awaitingRefresh = false;
    // 外部写入了历史快照时改为只读；不再用尚未提交的草稿覆盖已保存的当期内容。
    if (this.snapshot?.name.trim()) {
      this.draftName = '';
      this.onInputBlur('checkin-history-name');
    }
    this.viewportChanged();
  }
  private viewportChanged(): void {
    this.onViewportChange();
    EditorMaterialRefresh.request(this.getUIContext());
  }
  private completed(): boolean { return this.snapshot?.status === 'completed'; }
  private needsName(): boolean { return !this.selectionError() && !this.completed() && !this.snapshot?.name.trim(); }
  private historicalName(): string { return this.snapshot?.name || '当期未保存打卡内容'; }
  private statusText(): string {
    if (this.completed()) return this.snapshot?.advanced ? '已提前打卡' : (this.snapshot?.backfilled ? '已补卡' : '已完成');
    return this.snapshot?.status === 'pending' ? '未完成 · 当期内容未确认' : '未完成';
  }
  private completionTime(): string {
    const value = this.snapshot?.completedAt || '';
    if (!value) return '';
    const date = new Date(value);
    if (!Number.isFinite(date.getTime())) return value;
    return date.getFullYear() + '-' + (date.getMonth() + 1).toString().padStart(2, '0') + '-' +
      date.getDate().toString().padStart(2, '0') + ' ' + date.getHours().toString().padStart(2, '0') + ':' +
      date.getMinutes().toString().padStart(2, '0');
  }
  private submitLabel(): string {
    if (this.selectionError()) return '暂不可操作';
    return this.completed() ? '撤销这次打卡' : '确认补卡';
  }
  private canSubmit(): boolean {
    if (this.submitting || this.awaitingRefresh || this.selectionError()) return false;
    return this.completed() || !!(this.snapshot?.name.trim() || this.draftName.trim());
  }
  private submit(): void {
    if (this.submitting || this.awaitingRefresh) return;
    this.error = this.selectionError();
    if (this.error) return;
    // 提交时再次读取真实快照，外部卡片/其他页面的完成更新不能被旧界面状态覆盖。
    const record = this.recordFor();
    const undo = record?.status === 'completed';
    const name = record?.name.trim() || this.draftName.trim();
    if (!undo && !name) { this.error = '请填写当日实际完成的打卡内容'; return; }
    const action = new AppAction(undo ? 'CHECKIN_UNDO' : 'CHECKIN_BACKFILL');
    action.id = this.itemId; action.key = this.keyDate;
    if (!undo) action.text = name;
    this.error = validateCheckInAction(this.data, action);
    if (this.error) return;
    const identity = this.itemId + ':' + this.keyDate;
    const before = this.snapshotSignature;
    this.submitting = true;
    try {
      const message = undo ? this.onUndo() : this.onBackfill(name);
      if (identity !== this.itemId + ':' + this.keyDate) return;
      if (message) { this.error = message; return; }
      this.error = '';
      // 等父页面回传新快照期间避免连续点击重复派发；同步回传则直接采用更新后的状态。
      this.waitingSignature = before;
      this.awaitingRefresh = this.snapshotSignature === before;
      this.onInputBlur('checkin-history-name');
      this.viewportChanged();
    } catch (_) {
      if (identity === this.itemId + ':' + this.keyDate) this.error = '操作未完成，请重试';
    } finally {
      this.submitting = false;
    }
  }

  @Builder private contentSection() {
    Column({ space: 12 }) {
      Text('当期内容').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.palette.text).width('100%')
      if (this.needsName()) {
        TextArea({ text: this.draftName, placeholder: '填写当日打卡内容' }).id('checkin-history-name')
          .width('100%').height(112).padding(12).maxLength(120).fontSize(16)
          .fontColor(this.palette.text).placeholderColor(this.palette.textSoft)
          .backgroundColor(Materials.input(this.palette)).borderRadius(12)
          .onFocus(() => this.onInputFocus('checkin-history-name')).onBlur(() => this.onInputBlur('checkin-history-name'))
          .onChange((value: string) => { this.draftName = value; this.error = ''; })
      } else {
        Text(this.historicalName()).id('checkin-history-snapshot').fontSize(17).lineHeight(26)
          .fontColor(this.palette.text).width('100%')
      }
    }.width('100%').padding(16)
  }

  @Builder private statusSection() {
    Column({ space: 10 }) {
      Text('打卡记录').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.palette.text).width('100%')
      Text(this.statusText()).id('checkin-history-status').fontSize(14)
        .fontColor(this.completed() ? this.palette.success : this.palette.textSoft).width('100%')
      if (this.completed() && this.completionTime()) {
        Text('完成于 ' + this.completionTime()).id('checkin-history-time').fontSize(13)
          .fontColor(this.palette.textSoft).lineHeight(20).width('100%')
      }
    }.width('100%').padding(16)
  }

  @Builder private actionButton() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 8 }) {
        if (this.completed()) PlanerIcon({ icon: 'restore', color: this.palette.textSoft, iconSize: 18 })
        Text(this.submitLabel()).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(this.completed() ? this.palette.textSoft : this.palette.accent)
      }.width('100%').height('100%').justifyContent(FlexAlign.Center)
    }.id('checkin-history-submit').width('100%').height(46).padding(0).borderRadius(12)
      .attributeModifier(new PlanerControlModifier(this.palette, !this.completed())).enabled(this.canSubmit())
      .scale({ x: ButtonFeedback.scale(this.pressedButton, 'submit'), y: ButtonFeedback.scale(this.pressedButton, 'submit') })
      .animation(Motion.quick()).accessibilityText(this.submitLabel())
      .onTouch((event: TouchEvent) => { this.pressedButton = ButtonFeedback.next(this.pressedButton, 'submit', event.type); })
      .onDisAppear(() => { this.pressedButton = ''; })
      .onClick(() => { this.pressedButton = ''; this.submit(); })
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        HistoryBackButton({ palette: this.palette, label: '返回打卡详情', buttonId: 'checkin-history-back', onBack: () => this.onBack() })
        Column({ space: 4 }) {
          Text('历史打卡').fontSize(21).fontWeight(FontWeight.Bold).fontColor(this.palette.text).width('100%')
          Text(this.validDate() ? formatFull(this.keyDate) : this.keyDate).id('checkin-history-date')
            .fontSize(13).fontColor(this.palette.textSoft).width('100%')
        }.layoutWeight(1)
        IconButton({ icon: 'close', label: '关闭历史打卡', palette: this.palette, onTap: () => this.onClose() })
      }.width('100%').padding({ left: 16, right: 12, top: 14, bottom: 14 })
      Divider().color(this.palette.border).opacity(0.6)
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          MaterialSection({ palette: this.palette, viewportId: 'checkin-history-scroll', content: () => { this.contentSection(); } }).width('100%')
          MaterialSection({ palette: this.palette, viewportId: 'checkin-history-scroll', content: () => { this.statusSection(); } }).width('100%')
        }.width('100%').padding({ left: 20, right: 20, top: 18, bottom: 24 }).constraintSize({ maxWidth: 680 })
      }.id('checkin-history-scroll').width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring).onAreaChange(() => this.viewportChanged())
        .onDidScroll(() => EditorMaterialRefresh.request(this.getUIContext()))
      Divider().color(this.palette.border).opacity(0.6)
      Column({ space: 8 }) {
        if (this.error || this.selectionError()) {
          Text(this.error || this.selectionError()).id('checkin-history-error').fontSize(13)
            .fontColor(this.palette.danger).lineHeight(20).width('100%')
        }
        MaterialButtonScope({ palette: this.palette, controlHeight: 46, content: () => { this.actionButton(); } }).width('100%').height(46)
      }.width('100%').padding({ left: 20, right: 20, top: 14, bottom: 18 }).constraintSize({ maxWidth: 680 })
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
  }
}
