import { AppData } from '../model/PlanerModel';
import { CheckInItem, CheckInRecord } from '../model/CheckInModel';
import { isCheckInDate, previewCheckInRecord } from '../model/CheckInEngine';
import { realDateOf, fromKey, todayKey, formatFull } from '../model/PlanerEngine';
import { Palette } from '../theme/Theme';
import { Materials, Motion, PlanerControlModifier, ButtonFeedback } from '../theme/Appearance';
import { HistoryBackButton } from './HistoryBackButton';
import { IconButton } from './IconButton';
import { MaterialSection, EditorMaterialRefresh } from './MaterialSection';
import { MaterialButtonScope } from './MaterialButtonScope';

@Component
export struct CheckInBackfill {
  @Prop @Watch('dataChanged') data: AppData = new AppData();
  @Prop @Watch('identityChanged') itemId: string = '';
  @Prop @Watch('identityChanged') initialDate: string = '';
  @Prop palette: Palette = new Palette();
  scroller: Scroller = new Scroller();
  onBack: () => void = (): void => {};
  onComplete: (key: string, name: string) => string = (_key: string, _name: string): string => '';
  onAdvance: (key: string) => string = (_key: string): string => '';
  onInputFocus: (id: string) => void = (_id: string): void => {};
  onInputBlur: (id: string) => void = (_id: string): void => {};
  onViewportChange: () => void = (): void => {};
  @State private year: number = new Date().getFullYear();
  @State private month: number = new Date().getMonth();
  @State private selectedDate: string = '';
  @State private draftName: string = '';
  @State private error: string = '';
  @State private notice: string = '';
  @State private submitting: boolean = false;
  @State private pressedButton: string = '';
  @State private monthRecords: CheckInRecord[] = [];
  @State private selectedProjection: CheckInRecord | undefined = undefined;
  private readonly week: string[] = ['一', '二', '三', '四', '五', '六', '日'];
  private readonly rows: number[] = [0, 1, 2, 3, 4, 5];
  private readonly columns: number[] = [0, 1, 2, 3, 4, 5, 6];

  aboutToAppear(): void { this.identityChanged(); }
  aboutToDisappear(): void { this.pressedButton = ''; }

  private today(): string { return realDateOf(this.data) || todayKey(); }
  private item(): CheckInItem | undefined {
    return this.data.checkIns.find((item: CheckInItem): boolean => item.id === this.itemId);
  }
  private validDate(key: string): boolean {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) return false;
    const date = fromKey(key);
    return Number.isFinite(date.getTime()) && date.getFullYear().toString().padStart(4, '0') + '-' +
      (date.getMonth() + 1).toString().padStart(2, '0') + '-' + date.getDate().toString().padStart(2, '0') === key;
  }
  private monthKey(): string { return this.year + '-' + (this.month + 1).toString().padStart(2, '0'); }
  private monthTitle(): string { return this.year + ' 年 ' + (this.month + 1) + ' 月'; }

  private identityChanged(): void {
    const key = this.validDate(this.initialDate) ? this.initialDate : this.today();
    const date = fromKey(key);
    this.year = date.getFullYear(); this.month = date.getMonth();
    this.selectedDate = ''; this.draftName = ''; this.error = ''; this.notice = '';
    this.dataChanged();
    if (this.initialDate && this.validDate(this.initialDate)) this.selectDate(this.initialDate);
  }

  private dataChanged(): void {
    const prefix = this.monthKey() + '-';
    this.monthRecords = this.data.checkInRecords.filter((record: CheckInRecord): boolean =>
      record.itemId === this.itemId && record.key.startsWith(prefix));
    this.refreshProjection();
  }

  private refreshProjection(): void {
    this.selectedProjection = this.selectedDate > this.today() ?
      previewCheckInRecord(this.data, this.itemId, this.selectedDate) : undefined;
  }

  private projectionFor(key: string): CheckInRecord | undefined {
    return key === this.selectedDate ? this.selectedProjection : previewCheckInRecord(this.data, this.itemId, key);
  }

  private recordFor(key: string): CheckInRecord | undefined {
    if (key.startsWith(this.monthKey() + '-')) {
      return this.monthRecords.find((record: CheckInRecord): boolean => record.key === key);
    }
    return this.data.checkInRecords.find((record: CheckInRecord): boolean => record.itemId === this.itemId && record.key === key);
  }

  private day(index: number, calendarMonth: string): number {
    const first = fromKey(calendarMonth + '-01');
    const offset = (first.getDay() + 6) % 7;
    const day = index - offset + 1;
    const count = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
    return day > 0 && day <= count ? day : 0;
  }
  private dateKey(index: number, calendarMonth: string): string {
    return calendarMonth + '-' + this.day(index, calendarMonth).toString().padStart(2, '0');
  }
  private visibleRows(calendarMonth: string): number[] {
    const first = fromKey(calendarMonth + '-01');
    const offset = (first.getDay() + 6) % 7;
    const count = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
    return this.rows.slice(0, Math.ceil((offset + count) / 7));
  }

  private dateState(key: string): string {
    const record = this.recordFor(key);
    if (record?.status === 'completed') return record.advanced ? 'advanced' : (record.backfilled ? 'backfilled' : 'completed');
    const item = this.item();
    if (!item || (!record && !isCheckInDate(item, key))) return 'off';
    if (key > this.today()) return 'future';
    if (key === this.today()) return 'today';
    return 'unfinished';
  }

  private statusText(key: string): string {
    const state = this.dateState(key);
    if (state === 'advanced') return '已提前打卡';
    if (state === 'completed') return '已完成';
    if (state === 'backfilled') return '已补卡';
    if (state === 'unfinished') return '未完成';
    if (state === 'today') return '待打卡';
    if (state === 'future') return '未到期';
    return '非周期';
  }

  private statusColor(key: string): string {
    const state = this.dateState(key);
    if (state === 'completed' || state === 'advanced') return this.palette.success;
    if (state === 'backfilled') return this.palette.accent;
    if (state === 'unfinished') return this.palette.danger;
    return this.palette.textFaint;
  }

  private selectionError(key: string): string {
    if (!this.validDate(key)) return '请选择一个有效日期';
    if (!this.item()) return '这个打卡计划已不存在';
    const record = this.recordFor(key);
    if (record?.status === 'completed') {
      if (record.advanced) return '这一天已提前打卡，无需重复打卡';
      return record.backfilled ? '这一天已补卡，无需重复补卡' : '这一天已完成，无需重复补卡';
    }
    if (!record && !isCheckInDate(this.item() as CheckInItem, key)) return '这一天不在打卡周期内，暂停期间也无需补卡';
    if (key > this.today()) {
      const projection = this.projectionFor(key);
      if (!projection || projection.status !== 'ready' || !projection.name.trim()) return '无法生成当日内容，请调整计划后再提前打卡';
      return '';
    }
    if (key === this.today()) return '今天请在打卡页完成';
    return '';
  }

  private animateLayout(change: () => void): void {
    const animation = Motion.quick();
    animation.onFinish = (): void => this.viewportChanged();
    this.getUIContext().animateTo(animation, change);
    EditorMaterialRefresh.request(this.getUIContext());
  }

  private viewportChanged(): void {
    this.onViewportChange();
    EditorMaterialRefresh.request(this.getUIContext());
  }

  private moveMonth(offset: number): void {
    const date = new Date(this.year, this.month + offset, 1, 12);
    if (date.getFullYear() < 100 || date.getFullYear() > 9999) return;
    this.animateLayout((): void => {
      this.year = date.getFullYear(); this.month = date.getMonth();
      this.dataChanged();
    });
  }

  private selectDate(key: string): void {
    this.animateLayout((): void => {
      this.selectedDate = key; this.refreshProjection();
      const message = this.selectionError(key);
      // 非周期日直接在内容区显示“当日无打卡项”，不在底栏重复长提示。
      this.error = this.hasSelectedItem() ? message : ''; this.notice = '';
      const record = this.recordFor(key);
      // 未来只读预测内容；过去缺少快照时须填写实际内容，不借用今天的数字。
      this.draftName = this.canEditSelected() && record ? record.name : '';
    });
    this.onInputBlur('checkin-backfill-name');
  }

  private hasSelectedItem(): boolean {
    if (!this.validDate(this.selectedDate)) return false;
    if (this.recordFor(this.selectedDate)) return true;
    const item = this.item();
    return !!item && isCheckInDate(item, this.selectedDate);
  }

  private selectedName(): string {
    if (!this.selectedDate) return '点选未完成日期补卡';
    // 已完成和已补卡周期也可查看，只读取自己的历史名称，不套用当前计划内容。
    const record = this.recordFor(this.selectedDate);
    if (record) return record.name || '未填写打卡内容';
    if (!this.hasSelectedItem()) return '当日无打卡项';
    if (this.selectedDate > this.today()) return this.selectedProjection?.name || '请调整计划后再提前打卡';
    return '尚未生成打卡项';
  }

  private canEditSelected(): boolean {
    return !!this.selectedDate && this.selectedDate < this.today() && !this.selectionError(this.selectedDate);
  }

  private submitLabel(): string {
    if (this.recordFor(this.selectedDate)?.advanced) return '已提前打卡';
    return this.selectedDate > this.today() ? '提前打卡' : '确认补卡';
  }

  private canSubmitSelected(): boolean {
    if (this.submitting || !this.selectedDate || this.selectionError(this.selectedDate)) return false;
    return this.selectedDate > this.today() || (this.canEditSelected() && this.draftName.trim().length > 0);
  }

  private submit(): void {
    if (this.submitting) return;
    this.error = this.selectionError(this.selectedDate);
    if (this.error) return;
    const advance = this.selectedDate > this.today();
    const name = this.draftName.trim();
    if (!advance && !name) { this.error = '请输入本期实际完成的名称'; return; }
    this.submitting = true;
    const key = this.selectedDate;
    try {
      const message = advance ? this.onAdvance(key) : this.onComplete(key, name);
      if (message) { this.error = message; return; }
      this.notice = formatFull(key) + (advance ? ' 已提前打卡。' : ' 已补卡，可继续选择其他日期。');
      if (!advance) this.selectedDate = '';
      this.draftName = ''; this.error = '';
      this.onInputBlur('checkin-backfill-name');
      this.dataChanged();
    } catch (_) {
      this.error = advance ? '提前打卡未完成，请重试' : '补卡未完成，请重试';
    } finally {
      this.submitting = false;
    }
  }

  @Builder private dateCell(index: number, calendarMonth: string) {
    if (this.day(index, calendarMonth) > 0) {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        Column({ space: 3 }) {
          Text(this.day(index, calendarMonth).toString()).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor(this.dateKey(index, calendarMonth) === this.selectedDate ? this.palette.accent : this.palette.text)
            .width('100%').textAlign(TextAlign.Center)
          Text(this.statusText(this.dateKey(index, calendarMonth))).fontSize(9).minFontSize(7).maxFontSize(9).maxLines(1)
            .fontColor(this.statusColor(this.dateKey(index, calendarMonth))).width('100%').textAlign(TextAlign.Center)
        }.width('100%').justifyContent(FlexAlign.Center)
      }.layoutWeight(1).height(56).padding(0).borderRadius(11)
        .backgroundColor(this.dateKey(index, calendarMonth) === this.selectedDate ? this.palette.accentSoft : Color.Transparent)
        .border({ width: this.dateKey(index, calendarMonth) === this.selectedDate ? 1 : 0, color: this.palette.accent, radius: 11 })
        .id('checkin-backfill-day-' + this.dateKey(index, calendarMonth))
        .accessibilityText(this.dateKey(index, calendarMonth) + '，' + this.statusText(this.dateKey(index, calendarMonth)))
        .scale({ x: ButtonFeedback.scale(this.pressedButton, this.dateKey(index, calendarMonth)), y: ButtonFeedback.scale(this.pressedButton, this.dateKey(index, calendarMonth)) }).animation(Motion.quick())
        .onTouch((event: TouchEvent) => { this.pressedButton = ButtonFeedback.next(this.pressedButton, this.dateKey(index, calendarMonth), event.type); })
        .onDisAppear(() => { this.pressedButton = ''; })
        .onClick(() => { this.pressedButton = ''; this.selectDate(this.dateKey(index, calendarMonth)); })
    } else {
      Blank().layoutWeight(1).height(56)
    }
  }

  @Builder private legend(text: string, color: string) {
    Row({ space: 5 }) {
      Row().width(6).height(6).borderRadius(3).backgroundColor(color)
      Text(text).fontSize(11).fontColor(this.palette.textSoft)
    }
  }

  @Builder private calendarSection() {
    Column({ space: 10 }) {
      Row() {
        IconButton({ icon: 'left', label: '上个月', palette: this.palette, onTap: () => this.moveMonth(-1) })
        Text(this.monthTitle()).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.palette.text)
          .layoutWeight(1).textAlign(TextAlign.Center).id('checkin-backfill-month')
        IconButton({ icon: 'right', label: '下个月', palette: this.palette, onTap: () => this.moveMonth(1) })
      }.width('100%')
      Row() {
        ForEach(this.week, (day: string) => {
          Text(day).layoutWeight(1).fontSize(12).fontColor(this.palette.textSoft).textAlign(TextAlign.Center)
        }, (day: string): string => day)
      }.width('100%')
      ForEach([this.monthKey()], (calendarMonth: string) => {
        Column({ space: 3 }) {
          ForEach(this.visibleRows(calendarMonth), (row: number) => {
            Row({ space: 3 }) {
              ForEach(this.columns, (column: number) => {
                this.dateCell(row * 7 + column, calendarMonth)
              }, (column: number): string => column.toString())
            }.width('100%')
          }, (row: number): string => row.toString())
        }.width('100%').transition(Motion.reveal())
      }, (calendarMonth: string): string => calendarMonth)
      Row({ space: 14 }) {
        this.legend('已完成', this.palette.success)
        this.legend('已补卡', this.palette.accent)
        this.legend('未完成', this.palette.danger)
      }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 4 })
    }.width('100%').padding(14).clip(false)
  }

  @Builder private nameSection() {
    Column({ space: 12 }) {
      Text(this.selectedDate ? formatFull(this.selectedDate) : '选择补卡日期').fontSize(16)
        .fontWeight(FontWeight.Medium).fontColor(this.palette.text).width('100%')
      if (this.canEditSelected()) {
        TextArea({ text: this.draftName, placeholder: '填写当日打卡内容' }).id('checkin-backfill-name')
          .width('100%').height(112).padding(12).maxLength(120).fontSize(16)
          .fontColor(this.palette.text).placeholderColor(this.palette.textSoft)
          .backgroundColor(Materials.input(this.palette)).borderRadius(12)
          .onFocus(() => this.onInputFocus('checkin-backfill-name')).onBlur(() => this.onInputBlur('checkin-backfill-name'))
          .onChange((value: string) => { this.draftName = value; this.error = ''; })
      } else {
        Text(this.selectedName()).fontSize(16).fontColor(this.palette.text).lineHeight(24).width('100%')
          .id('checkin-backfill-day-name')
      }
    }.width('100%').padding(14)
  }

  @Builder private bottomFade() {
    Column({ space: 0 }) {
      Blank().layoutWeight(1).backgroundColor(Color.White).hitTestBehavior(HitTestMode.None)
      Row().width('100%').height(32).hitTestBehavior(HitTestMode.None)
        .linearGradient({ direction: GradientDirection.Bottom, colors: [
          ['#FFFFFFFF', 0], ['#00FFFFFF', 1]
        ] })
    }.width('100%').height('100%')
      // 只以 alpha 淡出滚动内容，材质背板与固定底栏不参与混合。
      .blendMode(BlendMode.DST_IN, BlendApplyType.OFFSCREEN)
      .hitTestBehavior(HitTestMode.Transparent).accessibilityLevel('no-hide-descendants')
      .id('checkin-backfill-bottom-fade')
  }

  @Builder private confirmButton() {
    Button(this.submitLabel(), { type: ButtonType.Normal, stateEffect: false }).id('checkin-backfill-submit').width('100%').height(46).borderRadius(12)
      .fontSize(16).fontColor(this.palette.accent).attributeModifier(new PlanerControlModifier(this.palette, true))
      .enabled(this.canSubmitSelected())
      .scale({ x: ButtonFeedback.scale(this.pressedButton, 'submit'), y: ButtonFeedback.scale(this.pressedButton, 'submit') }).animation(Motion.quick())
      .onTouch((event: TouchEvent) => { this.pressedButton = ButtonFeedback.next(this.pressedButton, 'submit', event.type); })
      .onDisAppear(() => { this.pressedButton = ''; })
      .onClick(() => { this.pressedButton = ''; this.submit(); })
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        HistoryBackButton({ palette: this.palette, label: '返回打卡', buttonId: 'checkin-backfill-back', onBack: () => this.onBack() })
        Column({ space: 4 }) {
          Text('补卡').fontSize(21).fontWeight(FontWeight.Bold).fontColor(this.palette.text).width('100%')
          Text(this.item()?.name || '打卡计划').fontSize(12).fontColor(this.palette.textSoft).width('100%').maxLines(2)
        }.layoutWeight(1)
      }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      Divider().color(this.palette.border).opacity(0.6)
      Stack({ alignContent: Alignment.Bottom }) {
        Scroll(this.scroller) {
          Column({ space: 18 }) {
            MaterialSection({ palette: this.palette, viewportId: 'checkin-backfill-scroll', content: () => { this.calendarSection(); } }).width('100%')
            MaterialSection({ palette: this.palette, viewportId: 'checkin-backfill-scroll', content: () => { this.nameSection(); } }).width('100%')
          }.width('100%').padding({ left: 16, right: 16, top: 18, bottom: 40 }).constraintSize({ maxWidth: 680 }).clip(false)
        }.id('checkin-backfill-scroll').width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring)
          .onAreaChange(() => this.viewportChanged()).onDidScroll(() => EditorMaterialRefresh.request(this.getUIContext()))
        this.bottomFade()
      }.width('100%').layoutWeight(1).blendMode(BlendMode.SRC_OVER, BlendApplyType.OFFSCREEN)
      Column({ space: 8 }) {
        if (this.error) Text(this.error).id('checkin-backfill-error').fontSize(13).fontColor(this.palette.danger).width('100%')
        if (this.notice) Text(this.notice).id('checkin-backfill-success').fontSize(13).fontColor(this.palette.success).width('100%')
        MaterialButtonScope({ palette: this.palette, controlHeight: 46, content: () => { this.confirmButton(); } }).width('100%').height(46)
      }.id('checkin-backfill-footer').width('100%').padding({ left: 20, right: 20, top: 12, bottom: 18 }).constraintSize({ maxWidth: 680 })
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
  }
}

