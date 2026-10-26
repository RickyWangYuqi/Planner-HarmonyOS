import { AppData } from '../model/PlanerModel';
import { CheckInItem, CheckInFrequency, CheckInNamePattern } from '../model/CheckInModel';
import { validateCheckIn, parseCheckInName, formatCheckInName, nextCheckInName } from '../model/CheckInEngine';
import { todayKey } from '../model/PlanerEngine';
import { Palette } from '../theme/Theme';
import { Materials, Motion, PlanerControlModifier, ButtonFeedback } from '../theme/Appearance';
import { MaterialButtonScope } from './MaterialButtonScope';
import { MaterialSection, EditorMaterialRefresh } from './MaterialSection';
import { PlanerCalendar } from './CalendarPicker';
import { IconButton } from './IconButton';
import { PlanerIcon } from './PlanerIcon';
import { HistoryBackButton } from './HistoryBackButton';

@Component
export struct CheckInEditor {
  @Prop item: CheckInItem = new CheckInItem();
  @Prop data: AppData = new AppData();
  @Prop palette: Palette = new Palette();
  @Prop isSubpage: boolean = false;
  onBack: () => void = (): void => {};
  onSave: (item: CheckInItem) => string = (): string => '';
  onClose: () => void = (): void => {};
  scroller: Scroller = new Scroller();
  onInputFocus: (id: string) => void = (): void => {};
  onInputBlur: (id: string) => void = (): void => {};
  onViewportChange: () => void = (): void => {};
  @State private name: string = '';
  @State private selectedGroup: string = '';
  @State private groupTouched: boolean = false;
  @State private draftGroups: string[] = [];
  @State private creatingGroup: boolean = false;
  @State private groupName: string = '';
  @State private startDate: string = '';
  @State private frequency: CheckInFrequency = 'daily';
  @State private weekdays: number[] = [];
  @State private monthDays: number[] = [];
  @State private autoIncrement: boolean = false;
  @State private step: string = '1';
  @State private error: string = '';
  @State private calendarShown: boolean = false;
  @State private pressedButton: string = '';
  private readonly weekOrder: number[] = [1, 2, 3, 4, 5, 6, 0];
  private readonly monthRows: number[] = [0, 7, 14, 21, 28];
  private readonly columns: number[] = [1, 2, 3, 4, 5, 6, 7];

  aboutToAppear(): void {
    this.name = this.item.name;
    this.selectedGroup = this.item.group || '';
    this.groupTouched = false; this.draftGroups = []; this.creatingGroup = false; this.groupName = '';
    this.startDate = this.item.startDate || todayKey();
    this.frequency = this.item.frequency;
    this.weekdays = this.item.weekdays.slice(); this.monthDays = this.item.monthDays.slice();
    this.autoIncrement = this.item.id ? this.item.autoIncrement : false;
    const pattern = parseCheckInName(this.name);
    this.step = this.item.id ? this.item.step.toString() : (pattern.valid ? pattern.step.toString() : '1');
  }

  aboutToDisappear(): void { this.pressedButton = ''; this.onInputBlur('checkin-group-name'); }

  private pattern(): CheckInNamePattern { return parseCheckInName(this.name.trim()); }

  private candidate(): CheckInItem {
    const result = this.item.clone();
    result.name = this.name.trim(); result.goal = ''; result.notes = '';
    // 关闭分组显示时保留原归属；未操作选择时跟随外部删组或修改，避免保存旧草稿复活分组。
    result.group = this.data.settings.showGroups ? this.currentGroup() : this.latestGroup();
    result.startDate = this.startDate.trim(); result.frequency = this.frequency;
    result.weekdays = this.weekdays.slice(); result.monthDays = this.monthDays.slice();
    result.autoIncrement = this.autoIncrement; result.step = this.numberValue(this.step);
    result.count = result.step; result.incrementMode = 'segment'; result.confirmNext = false;
    // 未手改的数字随后台新进度前进；改前后缀不应把跨日更新后的数字退回旧值。
    const latest = this.data.checkIns.find((item: CheckInItem): boolean => item.id === this.item.id);
    if (latest) {
      const original = parseCheckInName(this.item.name);
      const draft = parseCheckInName(result.name);
      const current = parseCheckInName(latest.name);
      if (result.name === this.item.name.trim()) result.name = latest.name;
      else if (original.valid && draft.valid && current.valid && original.mode === draft.mode && current.mode === draft.mode &&
        original.start === draft.start && original.end === draft.end) {
        result.name = formatCheckInName(draft, current.start, current.end);
      }
    }
    const pattern = parseCheckInName(result.name);
    result.useRange = pattern.valid && pattern.mode === 'range';
    if (pattern.valid) { result.rangeStart = pattern.start; result.rangeEnd = pattern.end; }
    return result;
  }

  private numberValue(value: string): number { return value.trim().length === 0 ? Number.NaN : Number(value); }

  private changeName(value: string): void {
    const previous = this.pattern();
    this.name = value; this.error = '';
    const pattern = this.pattern();
    // 数字或模式变化时重新识别步长；只改前后缀保留用户调整过的数量。
    if (pattern.valid && (!previous.valid || pattern.mode !== previous.mode || pattern.start !== previous.start || pattern.end !== previous.end)) {
      this.step = pattern.step.toString();
    }
  }

  private animateLayout(change: () => void): void {
    const animation = Motion.spring();
    animation.onFinish = (): void => this.viewportChanged();
    this.getUIContext().animateTo(animation, change);
    EditorMaterialRefresh.request(this.getUIContext());
  }

  private viewportChanged(): void {
    this.onViewportChange();
    EditorMaterialRefresh.request(this.getUIContext());
  }

  private save(): void {
    if (this.data.settings.showGroups && this.creatingGroup && this.groupName.trim()) this.createGroup();
    const candidate = this.candidate();
    this.error = validateCheckIn(candidate);
    if (this.error) return;
    if (!candidate.id) candidate.id = 'checkin-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 8);
    this.error = this.onSave(candidate);
  }

  private toggleWeek(day: number): void {
    this.weekdays = this.weekdays.includes(day) ? this.weekdays.filter((value: number): boolean => value !== day) : this.weekdays.concat(day);
  }
  private toggleMonth(day: number): void {
    this.monthDays = this.monthDays.includes(day) ? this.monthDays.filter((value: number): boolean => value !== day) : this.monthDays.concat(day);
  }
  private weekLabel(day: number): string { return ['日', '一', '二', '三', '四', '五', '六'][day]; }

  private recognitionHint(): string {
    const pattern = this.pattern();
    if (!this.name.trim()) return '编号或区间可以分别按周期自动递增、接续（一次只能开启一项）';
    if (!pattern.valid) return pattern.error;
    const description = pattern.mode === 'range' ? '区间可以按周期自动接续' : '编号可以按周期自动递增';
    return description + '，' + (this.autoIncrement ? '已开启自动递增/接续' : '点击开启自动递增/接续');
  }

  private toast(message: string): void {
    try { this.getUIContext().getPromptAction().showToast({ message: message, duration: 2600 }); } catch (_) {}
  }

  private enableAutoIncrement(): void {
    const pattern = this.pattern();
    const step = this.numberValue(this.step);
    let error = pattern.error;
    if (!error && (!Number.isSafeInteger(step) || step < 1)) error = '请输入大于零的整数步长';
    const candidate = this.candidate(); candidate.autoIncrement = true;
    const nextName = !error ? nextCheckInName(candidate) : '';
    if (!error && !nextName) error = '下一期数字超出有效范围，请调整名称或步长';
    if (error) {
      this.autoIncrement = false; this.error = error; this.toast(error); return;
    }
    this.error = '';
    this.animateLayout(() => { this.autoIncrement = true; });
    this.toast('自动递增已打开，下一期将显示' + nextName);
  }

  private changeAutoIncrement(value: boolean): void {
    if (value) this.enableAutoIncrement();
    else this.animateLayout(() => { this.autoIncrement = false; this.error = ''; });
  }
  private preview(): string {
    const candidate = this.candidate();
    const error = validateCheckIn(candidate);
    if (error) return error;
    const name = nextCheckInName(candidate);
    return name ? '下一期：' + name : '下一期数字超出有效范围，请调整名称或步长。';
  }


  private latestGroup(): string {
    const latest = this.data.checkIns.find((item: CheckInItem): boolean => item.id === this.item.id);
    return latest ? latest.group : (this.item.group || '');
  }

  private currentGroup(): string { return this.groupTouched ? this.selectedGroup : this.latestGroup(); }

  private groups(): string[] {
    const groups = this.data.groups.slice();
    this.draftGroups.forEach((group: string): void => { if (!groups.includes(group)) groups.push(group); });
    const selected = this.currentGroup();
    if (selected && !groups.includes(selected)) groups.push(selected);
    return groups;
  }

  private pickGroup(group: string): void {
    this.animateLayout(() => {
      this.selectedGroup = this.currentGroup() === group ? '' : group;
      this.groupTouched = true; this.error = '';
    });
  }

  private openGroupForm(): void {
    this.animateLayout(() => { this.creatingGroup = true; this.groupName = ''; });
  }

  private cancelGroupForm(): void {
    this.animateLayout(() => { this.creatingGroup = false; this.groupName = ''; });
    this.onInputBlur('checkin-group-name');
  }

  private createGroup(): void {
    const group = this.groupName.trim();
    if (!group) return;
    this.animateLayout(() => {
      // 草稿只在保存计划时写入目录；关闭表单或校验失败都不会创建全局分组。
      if (!this.groups().includes(group)) this.draftGroups = this.draftGroups.concat(group);
      this.selectedGroup = group; this.groupTouched = true; this.error = '';
      this.groupName = ''; this.creatingGroup = false;
    });
    this.onInputBlur('checkin-group-name');
  }

  private groupChipWidth(group: string): number {
    const measured = this.getUIContext().getMeasureUtils().measureTextSize({
      textContent: group || '未分组', fontSize: 13, fontWeight: FontWeight.Medium
    });
    return Math.max(60, Math.min(230, this.getUIContext().px2vp(Number(measured.width)) + 28));
  }

  private groupTouch(id: string, event: TouchEvent): void {
    const next = ButtonFeedback.next(this.pressedButton, id, event.type);
    if (next !== this.pressedButton) this.getUIContext().animateTo(Motion.quick(), () => { this.pressedButton = next; });
  }

  @Builder private heading(title: string) {
    Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette.text).width('100%')
  }

  @Builder private nameSectionBody() {
    Column({ space: 10 }) {
      this.heading('名称')
      TextArea({ text: this.name, placeholder: '想坚持做什么？' }).id('checkin-name').width('100%').height(92).padding(12).fontSize(16)
        .fontColor(this.palette.text).placeholderColor(this.palette.textSoft).backgroundColor(Materials.input(this.palette)).borderRadius(12).maxLength(120)
        .onFocus(() => this.onInputFocus('checkin-name')).onBlur(() => this.onInputBlur('checkin-name'))
        .onChange((value: string) => this.changeName(value))
      Text(this.recognitionHint()).id('checkin-name-recognition').fontSize(12).fontColor(this.pattern().valid ? this.palette.accent : this.palette.textSoft)
        .lineHeight(19).width('100%').constraintSize({ minHeight: 36 })
        .onClick(() => { if (!this.autoIncrement) this.enableAutoIncrement(); })
    }.width('100%').padding(14)
  }

  @Builder private dateSectionBody() {
    Column({ space: 10 }) {
      this.heading('开始日期')
      Row({ space: 8 }) {
        TextInput({ text: this.startDate, placeholder: 'YYYY-MM-DD' }).id('checkin-start-date').height(46).layoutWeight(1)
          .fontColor(this.palette.text).backgroundColor(Materials.input(this.palette)).borderRadius(12).maxLength(10)
          .onFocus(() => this.onInputFocus('checkin-start-date')).onBlur(() => this.onInputBlur('checkin-start-date'))
          .onChange((value: string) => { this.startDate = value; this.error = ''; })
        Button(this.calendarShown ? '收起' : '日历', { type: ButtonType.Normal, stateEffect: false }).id('checkin-date-picker').height(46).padding({ left: 14, right: 14 })
          .fontSize(14).fontColor(this.palette.accent).backgroundColor(this.palette.accentSoft).borderRadius(12)
          .scale({ x: ButtonFeedback.scale(this.pressedButton, 'date-picker'), y: ButtonFeedback.scale(this.pressedButton, 'date-picker') }).animation(Motion.quick())
          .onTouch((event: TouchEvent) => { this.pressedButton = ButtonFeedback.next(this.pressedButton, 'date-picker', event.type); })
          .onClick(() => { this.pressedButton = ''; this.animateLayout(() => { this.calendarShown = !this.calendarShown; }); })
      }.width('100%')
      if (this.calendarShown) {
        Column() {
          PlanerCalendar({ value: this.startDate, compact: true, palette: this.palette,
            onSelect: (key: string): void => this.animateLayout(() => { this.startDate = key; this.calendarShown = false; }) })
        }.width('100%').transition(Motion.reveal())
      }
    }.width('100%').padding(14).clip(false)
  }

  @Builder private frequencyButton(title: string, value: CheckInFrequency) {
    Button(title, { type: ButtonType.Normal, stateEffect: false }).id('checkin-frequency-' + value).height(44).layoutWeight(1).padding(0)
      .fontSize(14).fontColor(this.frequency === value ? this.palette.accent : this.palette.textSoft)
      .backgroundColor(this.frequency === value ? this.palette.accentSoft : Materials.input(this.palette)).borderRadius(12)
      .scale({ x: ButtonFeedback.scale(this.pressedButton, 'frequency-' + value), y: ButtonFeedback.scale(this.pressedButton, 'frequency-' + value) }).animation(Motion.quick())
      .onTouch((event: TouchEvent) => { this.pressedButton = ButtonFeedback.next(this.pressedButton, 'frequency-' + value, event.type); })
      .onClick(() => { this.pressedButton = ''; this.animateLayout(() => { this.frequency = value; }); })
  }

  @Builder private monthDay(day: number) {
    if (day <= 31) {
      Button({ type: ButtonType.Normal, stateEffect: false }) {
        Text(day.toString()).fontSize(15).fontColor(this.monthDays.includes(day) ? this.palette.accent : this.palette.textSoft)
          .maxLines(1).textAlign(TextAlign.Center).width('100%')
      }.id('checkin-monthday-' + day).layoutWeight(1).height(44).padding(0).borderRadius(10)
        .backgroundColor(this.monthDays.includes(day) ? this.palette.accentSoft : Materials.input(this.palette))
        .scale({ x: ButtonFeedback.scale(this.pressedButton, 'monthday-' + day), y: ButtonFeedback.scale(this.pressedButton, 'monthday-' + day) }).animation(Motion.quick())
        .onTouch((event: TouchEvent) => { this.pressedButton = ButtonFeedback.next(this.pressedButton, 'monthday-' + day, event.type); })
        .onClick(() => { this.pressedButton = ''; this.toggleMonth(day); })
    } else { Blank().layoutWeight(1).height(44) }
  }

  @Builder private frequencySectionBody() {
    Column({ space: 12 }) {
      this.heading('重复频率')
      Row({ space: 8 }) {
        this.frequencyButton('每天', 'daily')
        this.frequencyButton('每周', 'weekly')
        this.frequencyButton('每月', 'monthly')
      }.width('100%')
      if (this.frequency === 'weekly') {
        Row({ space: 4 }) {
          ForEach(this.weekOrder, (day: number) => {
            Button(this.weekLabel(day), { type: ButtonType.Normal, stateEffect: false }).id('checkin-weekday-' + day).height(44).layoutWeight(1).padding(0)
              .fontSize(14).fontColor(this.weekdays.includes(day) ? this.palette.accent : this.palette.textSoft)
              .backgroundColor(this.weekdays.includes(day) ? this.palette.accentSoft : Materials.input(this.palette)).borderRadius(10)
              .scale({ x: ButtonFeedback.scale(this.pressedButton, 'weekday-' + day), y: ButtonFeedback.scale(this.pressedButton, 'weekday-' + day) }).animation(Motion.quick())
              .onTouch((event: TouchEvent) => { this.pressedButton = ButtonFeedback.next(this.pressedButton, 'weekday-' + day, event.type); })
              .onClick(() => { this.pressedButton = ''; this.toggleWeek(day); })
          }, (day: number): string => day.toString())
        }.width('100%').transition(Motion.reveal())
      }
      if (this.frequency === 'monthly') {
        Column({ space: 6 }) {
          ForEach(this.monthRows, (offset: number) => {
            Row({ space: 4 }) {
              ForEach(this.columns, (column: number) => { this.monthDay(offset + column) }, (column: number): string => column.toString())
            }.width('100%')
          }, (offset: number): string => offset.toString())
          Text('没有所选日期的月份将跳过').fontSize(12).fontColor(this.palette.textSoft).lineHeight(18).width('100%').margin({ top: 4 })
        }.width('100%').transition(Motion.reveal())
      }
    }.width('100%').padding(14).clip(false)
  }

  @Builder private groupLabelButton(group: string) {
    Button(group || '未分组', { type: ButtonType.Normal, stateEffect: false }).id('checkin-group-' + group)
      .width('100%').height(44).borderRadius(12).fontSize(13).padding({ left: 13, right: 13 })
      .fontColor(this.currentGroup() === group ? this.palette.accent : this.palette.textSoft)
      .attributeModifier(new PlanerControlModifier(this.palette, this.currentGroup() === group, false, true, BorderStyle.Solid))
      .scale({ x: ButtonFeedback.scale(this.pressedButton, 'group:' + group), y: ButtonFeedback.scale(this.pressedButton, 'group:' + group) })
      .onTouch((event: TouchEvent) => this.groupTouch('group:' + group, event))
      .onClick(() => { this.pressedButton = ''; this.pickGroup(group); })
      .onDisAppear(() => { if (this.pressedButton === 'group:' + group) this.pressedButton = ''; })
  }

  @Builder private groupCreateButton() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 6 }) {
        PlanerIcon({ icon: 'plus', color: this.palette.accent, iconSize: 16 })
        Text('新建分组').fontSize(13).fontColor(this.palette.accent)
      }
    }.id('checkin-group-create').width('100%').height(44).borderRadius(12)
      .attributeModifier(new PlanerControlModifier(this.palette, this.creatingGroup, false, true, BorderStyle.Dashed))
      .padding({ left: 13, right: 13 })
      .scale({ x: ButtonFeedback.scale(this.pressedButton, 'group-create'), y: ButtonFeedback.scale(this.pressedButton, 'group-create') })
      .onTouch((event: TouchEvent) => this.groupTouch('group-create', event))
      .onClick(() => { this.pressedButton = ''; this.openGroupForm(); })
  }

  @Builder private groupCancelButton() {
    Button('取消', { type: ButtonType.Normal, stateEffect: false }).id('checkin-group-cancel').width('100%').height(44).fontSize(13)
      .fontColor(this.palette.textSoft).attributeModifier(new PlanerControlModifier(this.palette)).borderRadius(12)
      .scale({ x: ButtonFeedback.scale(this.pressedButton, 'group-cancel'), y: ButtonFeedback.scale(this.pressedButton, 'group-cancel') })
      .onTouch((event: TouchEvent) => this.groupTouch('group-cancel', event))
      .onClick(() => { this.pressedButton = ''; this.cancelGroupForm(); })
  }

  @Builder private groupConfirmButton() {
    Button(this.groups().includes(this.groupName.trim()) ? '选用分组' : '创建并选中', { type: ButtonType.Normal, stateEffect: false })
      .id('checkin-group-confirm').width('100%').height(44).fontSize(13).fontColor(this.palette.accent)
      .attributeModifier(new PlanerControlModifier(this.palette, true)).borderRadius(12).enabled(this.groupName.trim().length > 0)
      .scale({ x: ButtonFeedback.scale(this.pressedButton, 'group-confirm'), y: ButtonFeedback.scale(this.pressedButton, 'group-confirm') })
      .onTouch((event: TouchEvent) => this.groupTouch('group-confirm', event))
      .onClick(() => { this.pressedButton = ''; this.createGroup(); })
  }

  @Builder private groupChip(group: string) {
    MaterialButtonScope({ palette: this.palette, content: () => { this.groupLabelButton(group); } })
      .width(this.groupChipWidth(group)).height(44).margin({ right: 8, bottom: 8 }).transition(Motion.reveal())
  }

  @Builder private groupSectionBody() {
    Column({ space: 10 }) {
      this.heading('分组')
      Flex({ wrap: FlexWrap.Wrap }) {
        this.groupChip('')
        ForEach(this.groups(), (group: string) => { this.groupChip(group) }, (group: string): string => group)
        MaterialButtonScope({ palette: this.palette, content: () => { this.groupCreateButton(); } })
          .width(this.groupChipWidth('新建分组') + 22).height(44).margin({ right: 8, bottom: 8 })
      }.width('100%').clip(false)
      if (this.creatingGroup) {
        Column({ space: 8 }) {
          TextInput({ text: this.groupName, placeholder: '分组名称' }).id('checkin-group-name')
            .height(44).fontSize(15).fontColor(this.palette.text).backgroundColor(Materials.inset(this.palette)).borderRadius(12)
            .onFocus(() => this.onInputFocus('checkin-group-name')).onBlur(() => this.onInputBlur('checkin-group-name'))
            .onChange((value: string) => { this.groupName = value; this.error = ''; }).onSubmit(() => this.createGroup())
          Row({ space: 8 }) {
            MaterialButtonScope({ palette: this.palette, content: () => { this.groupCancelButton(); } }).layoutWeight(1).height(44)
            MaterialButtonScope({ palette: this.palette, content: () => { this.groupConfirmButton(); } }).layoutWeight(2).height(44)
          }.width('100%')
        }.width('100%').transition(Motion.reveal())
      }
      Text(this.currentGroup() ? '已选分组：' + this.currentGroup() + ' · 随计划保存' : '未分组，可选择或新建')
        .fontSize(12).lineHeight(18).fontColor(this.currentGroup() ? this.palette.accent : this.palette.textSoft).width('100%')
    }.id('checkin-groups').width('100%').padding(14).alignItems(HorizontalAlign.Start).clip(false)
  }

  @Builder private incrementSectionBody() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text('自动递增/接续').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette.text).width('100%')
          Text('后续周期自动接续名称中的数字').fontSize(12).fontColor(this.palette.textSoft).lineHeight(18).width('100%')
        }.layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: $$this.autoIncrement }).id('checkin-auto-increment').selectedColor(this.palette.accent)
          .onChange((value: boolean) => this.changeAutoIncrement(value))
      }.width('100%')
      if (this.autoIncrement) {
        Column({ space: 12 }) {
          Text(this.pattern().mode === 'range' ? '步长（每期数量）' : '步长（每次增加）').fontSize(14).fontColor(this.palette.text).width('100%')
          TextInput({ text: this.step, placeholder: '1' }).id('checkin-step').type(InputType.Number).height(46)
            .fontColor(this.palette.text).backgroundColor(Materials.input(this.palette)).borderRadius(12)
            .onFocus(() => this.onInputFocus('checkin-step')).onBlur(() => this.onInputBlur('checkin-step'))
            .onChange((value: string) => { this.step = value; this.error = ''; })
          Text(this.preview()).id('checkin-next-preview').fontSize(13).fontColor(this.palette.accent).lineHeight(20).width('100%')

        }.width('100%').transition(Motion.reveal())
      }
    }.width('100%').padding(14).clip(false)
  }

  @Builder private saveButton() {
    Button('保存', { type: ButtonType.Normal, stateEffect: false }).id('checkin-save').width('100%').height(46).borderRadius(12)
      .fontSize(16).fontColor(this.palette.accent).attributeModifier(new PlanerControlModifier(this.palette, true))
      .scale({ x: ButtonFeedback.scale(this.pressedButton, 'save'), y: ButtonFeedback.scale(this.pressedButton, 'save') }).animation(Motion.quick())
      .onTouch((event: TouchEvent) => { this.pressedButton = ButtonFeedback.next(this.pressedButton, 'save', event.type); })
      .onClick(() => { this.pressedButton = ''; this.save(); })
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        if (this.isSubpage) {
          HistoryBackButton({ palette: this.palette, label: '返回打卡', buttonId: 'checkin-editor-back', onBack: () => this.onBack() })
        }
        Column({ space: 5 }) {
          Text(this.item.id ? '编辑打卡' : '新建打卡').fontSize(21).fontWeight(FontWeight.Bold).fontColor(this.palette.text).width('100%')
        }.layoutWeight(1)
        IconButton({ icon: 'close', palette: this.palette, label: '取消编辑', onTap: () => this.onClose() })
      }.width('100%').padding({ left: this.isSubpage ? 12 : 20, right: 12, top: 12, bottom: 12 })
      Divider().color(this.palette.border).opacity(0.6)
      Scroll(this.scroller) {
        Column({ space: 18 }) {
          MaterialSection({ palette: this.palette, viewportId: 'checkin-editor-scroll', content: () => { this.nameSectionBody(); } }).width('100%')
          MaterialSection({ palette: this.palette, viewportId: 'checkin-editor-scroll', content: () => { this.dateSectionBody(); } }).width('100%')
          MaterialSection({ palette: this.palette, viewportId: 'checkin-editor-scroll', content: () => { this.frequencySectionBody(); } }).width('100%')
          if (this.data.settings.showGroups) {
            MaterialSection({ palette: this.palette, viewportId: 'checkin-editor-scroll', content: () => { this.groupSectionBody(); } }).width('100%')
          }
          MaterialSection({ palette: this.palette, viewportId: 'checkin-editor-scroll', content: () => { this.incrementSectionBody(); } }).width('100%')
        }.width('100%').padding({ left: 16, right: 16, top: 18, bottom: 24 }).constraintSize({ maxWidth: 680 }).clip(false)
      }.id('checkin-editor-scroll').width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring)
        .onAreaChange(() => this.viewportChanged()).onDidScroll(() => EditorMaterialRefresh.request(this.getUIContext()))
      Divider().color(this.palette.border).opacity(0.6)
      Column({ space: 8 }) {
        if (this.error) Text(this.error).id('checkin-editor-error').fontSize(13).fontColor(this.palette.danger).width('100%')
        MaterialButtonScope({ palette: this.palette, controlHeight: 46, content: () => { this.saveButton(); } }).width('100%').height(46)
      }.width('100%').padding({ left: 20, right: 20, top: 12, bottom: 18 }).constraintSize({ maxWidth: 680 })
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
  }
}

