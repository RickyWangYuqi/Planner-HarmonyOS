import { ResponsiveLayout } from '../theme/ResponsiveLayout';
import { window } from '@kit.ArkUI';
import { AppAction, AppData, Task } from '../model/PlanerModel';
import { addDays } from '../model/PlanerEngine';
import { Palette } from '../theme/Theme';
import { Materials, Motion, PlanerControlModifier, ButtonFeedback } from '../theme/Appearance';
import { PlanerCalendar } from './CalendarPicker';
import { IconButton } from './IconButton';
import { PlanerIcon } from './PlanerIcon';
import { MaterialButtonScope } from './MaterialButtonScope';
import { EditorMaterialRefresh, MaterialSection } from './MaterialSection';

@Component
export struct TaskEditor {
  @Prop data: AppData = new AppData();
  @Prop palette: Palette = new Palette();
  @Prop section: string = 'today';
  @Prop task: Task | null = null;
  @Prop mode: string = 'add';
  @Prop targetIndex: number = 0;
  @Prop targetGroup: string | null | undefined = undefined;
  onAction: (action: AppAction) => void = (_action: AppAction): void => {};
  onClose: () => void = (): void => {};
  onDelete: () => void = (): void => {};
  @State private content: string = '';
  @State private pressedButton: string = '';
  @State private startDate: string = '';
  @State private dueDate: string = '';
  @State private dueDateError: string = '';
  @State private dateField: string = 'due';
  @State private selectedGroup: string = '';
  @State private draftGroups: string[] = [];
  @State private deletedGroups: string[] = [];
  @State private creatingGroup: boolean = false;
  @State private groupName: string = '';
  @State @Watch('deleteModeChanged') private deleteMode: string = '';
  @State private deleteShakeAngle: number = 0;
  @State private createdGroup: string = '';
  @State private progressEnabled: boolean = false;
  @State private progressValue: number = 0;
  private deleteShakeTimer: number = -1;
  private deleteShakeDirection: number = 1;
  private editorActive: boolean = false;
  @State private editorWidth: number = 0;
  @State private keyboardInset: number = 0;
  private editorWindow: window.Window | undefined = undefined;
  private keyboardObserverVersion: number = 0;
  private keyboardHeightPx: number = 0;
  private keyboardLayoutSettling: boolean = false;
  private keyboardLayoutVersion: number = 0;
  private dueDateScrollPending: boolean = false;
  private dueDateScrollAnimating: boolean = false;
  private dueDateScrollTimer: number = -1;
  private contentController: TextAreaController | undefined = undefined;
  private groupController: TextInputController | undefined = undefined;
  private editorBottomVp: number = 0;
  private rootAreaKnown: boolean = false;
  @State private focusedInput: string = '';
  private keyboardListener: (height: number) => void = (height: number): void => {
    if (!this.editorActive) return;
    this.keyboardHeightPx = Math.max(0, height);
    this.updateKeyboardInset();
    this.scheduleDueDateScroll();
  };
  private progressDirty: boolean = false;
  private progressStops: number[] = [0, 25, 50, 75, 100];
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.editorActive = true;
    // 控制器为可选能力；不支持完整 ArkUI 的设备沿用输入组件默认行为。
    if (canIUse('SystemCapability.ArkUI.ArkUI.Full')) {
      this.contentController = new TextAreaController();
      this.groupController = new TextInputController();
    }
    this.observeKeyboard();
    const task = this.task;
    this.content = task ? task.text : '';
    this.selectedGroup = task && task.group ? task.group : '';
    if (this.mode === 'move') {
      this.startDate = task && task.startDate && task.startDate > this.data.currentDate ? task.startDate : '';
      this.dueDate = task && task.dueDate && task.dueDate > this.data.currentDate ? task.dueDate : this.minDate();
    } else if (this.section === 'future' && task) {
      this.startDate = task.startDate || '';
      this.dueDate = task.dueDate || '';
    }
    if (task) {
      this.progressEnabled = task.progress !== null || task.completed;
      this.progressValue = task.progress !== null ? task.progress : (task.completed ? 100 : 0);
    }
  }

  aboutToDisappear(): void {
    this.editorActive = false;
    this.pressedButton = '';
    this.cancelDueDateScroll();
    this.stopKeyboardObserver();
    this.stopDeleteShake();
  }

  private buttonTouch(id: string, event: TouchEvent): void {
    const next = ButtonFeedback.next(this.pressedButton, id, event.type);
    if (next === this.pressedButton) return;
    this.getUIContext().animateTo(Motion.quick(), (): void => { this.pressedButton = next; });
  }

  private releaseButtonPress(): void {
    // 在打开/关闭面板的业务回调前同步复位，不依赖原生按压层收到后续 Up。
    this.getUIContext().animateTo({ duration: 0 }, (): void => { this.pressedButton = ''; });
  }

  private buttonScale(id: string): number { return ButtonFeedback.scale(this.pressedButton, id); }

  private async observeKeyboard(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (!context) return;
    const version = ++this.keyboardObserverVersion;
    try {
      const editorWindow = await window.getLastWindow(context);
      // 弹层已关闭时，异步取得窗口也不能重新注册监听。
      if (!this.editorActive || version !== this.keyboardObserverVersion) return;
      this.editorWindow = editorWindow;
      editorWindow.on('keyboardHeightChange', this.keyboardListener);
      this.keyboardHeightPx = editorWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD).bottomRect.height;
      this.updateKeyboardInset();
    } catch {
      console.error('编辑器读取键盘区域失败');
    }
  }

  private stopKeyboardObserver(): void {
    this.keyboardObserverVersion++;
    if (this.editorWindow) {
      try {
        this.editorWindow.off('keyboardHeightChange', this.keyboardListener);
      } catch {
        console.error('编辑器移除键盘监听失败');
      }
    }
    this.editorWindow = undefined;
    this.keyboardHeightPx = 0;
    this.keyboardLayoutVersion++;
    this.keyboardLayoutSettling = false;
    this.keyboardInset = 0;
    this.rootAreaKnown = false;
    this.focusedInput = '';
  }

  private updateEditorArea(area: Area): void {
    const width = Number(area.width);
    if (Number.isFinite(width) && width > 0) this.editorWidth = width;
    const bottom = Number(area.globalPosition.y) + Number(area.height);
    if (!this.editorActive || !Number.isFinite(bottom)) return;
    this.editorBottomVp = bottom;
    this.rootAreaKnown = true;
    this.updateKeyboardInset();
  }

  private updateKeyboardInset(): void {
    if (!this.editorActive) return;
    const uiContext = this.getUIContext();
    const root = uiContext.getFrameNodeById('task-editor-root');
    if (root) {
      // 半模态包含平移，优先读取节点在窗口中的实际位置，避免只按内容区坐标计算。
      const height = uiContext.px2vp(root.getMeasuredSize().height);
      const bottom = root.getPositionToWindowWithTransform().y + height;
      if (height > 0 && Number.isFinite(bottom)) {
        this.editorBottomVp = bottom;
        this.rootAreaKnown = true;
      }
    }
    if (!this.editorWindow || !this.rootAreaKnown || this.keyboardHeightPx <= 0) {
      this.setKeyboardInset(0);
      return;
    }
    try {
      // 只缩小当前表单的滚动区，底部按钮随内边距抬起，不移动主页或整个窗口。
      const height = this.editorWindow.getWindowProperties().windowRect.height;
      const keyboardTop = this.getUIContext().px2vp(Math.max(0, height - this.keyboardHeightPx));
      this.setKeyboardInset(Math.max(0, this.editorBottomVp - keyboardTop));
    } catch {
      // 窗口短暂不可读时保留上次安全位置，等待下一次区域或键盘回调重算。
      console.error('编辑器读取窗口尺寸失败');
    }
  }

  private setKeyboardInset(value: number): void {
    if (this.keyboardInset === value) return;
    const version = ++this.keyboardLayoutVersion;
    this.keyboardLayoutSettling = true;
    const animation = Motion.quick();
    animation.onFinish = () => {
      if (!this.editorActive || version !== this.keyboardLayoutVersion) return;
      this.keyboardLayoutSettling = false;
      this.scheduleDueDateScroll();
    };
    this.getUIContext().animateTo(animation, () => { this.keyboardInset = value; });
  }

  private focusInput(id: string): void {
    this.focusedInput = id;
    this.ensureFocusedInputVisible();
  }

  private blurInput(id: string): void {
    if (this.focusedInput === id) this.focusedInput = '';
  }

  private ensureFocusedInputVisible(): void {
    if (!this.editorActive || !this.focusedInput) return;
    const uiContext = this.getUIContext();
    const input = uiContext.getFrameNodeById(this.focusedInput);
    const viewport = uiContext.getFrameNodeById('task-editor-scroll');
    if (!input || !viewport) return;
    // 窗口位置使用 vp，测量尺寸使用 px；统一单位后只滚动编辑器内部。
    const inputTop = input.getPositionToWindowWithTransform().y;
    const inputBottom = inputTop + uiContext.px2vp(input.getMeasuredSize().height);
    const visibleTop = viewport.getPositionToWindowWithTransform().y + 8;
    const visibleBottom = viewport.getPositionToWindowWithTransform().y + uiContext.px2vp(viewport.getMeasuredSize().height) - 8;
    if (inputBottom > visibleBottom) {
      this.scroller.scrollBy(0, inputBottom - visibleBottom);
    } else if (inputTop < visibleTop) {
      this.scroller.scrollBy(0, inputTop - visibleTop);
    }
  }

  private deleteModeChanged(): void {
    this.stopDeleteShake();
    if (!this.deleteMode || !this.editorActive) return;
    this.deleteShakeDirection = 1;
    this.stepDeleteShake();
    this.deleteShakeTimer = setInterval(() => this.stepDeleteShake(), 240);
  }

  private stepDeleteShake(): void {
    if (!this.editorActive || !this.deleteMode) {
      this.stopDeleteShake();
      return;
    }
    const angle = this.deleteShakeDirection * 1.3;
    this.deleteShakeDirection *= -1;
    this.getUIContext().animateTo(Motion.quick(), () => { this.deleteShakeAngle = angle; });
  }

  private stopDeleteShake(): void {
    if (this.deleteShakeTimer >= 0) clearInterval(this.deleteShakeTimer);
    this.deleteShakeTimer = -1;
    // 停止循环后立即复位，避免退出删除态仍保留倾斜或继续触发回调。
    this.getUIContext().animateTo({ duration: 0 }, () => { this.deleteShakeAngle = 0; });
  }

  private minDate(): string {
    return addDays(this.data.currentDate, 1);
  }

  private title(): string {
    if (this.mode === 'move') return '移动到未来日程';
    return `${this.mode === 'edit' ? '编辑' : '添加'}${this.section === 'today' ? '当日' : '未来'}日程`;
  }

  private hasDates(): boolean {
    return this.section === 'future' || this.mode === 'move';
  }

  private canAttemptSubmit(): boolean {
    return this.content.trim().length > 0;
  }

  private validDueDate(): boolean {
    return /^\d{4}-\d{2}-\d{2}$/.test(this.dueDate) && addDays(this.dueDate, 0) === this.dueDate &&
      this.dueDate >= this.minDate() && (!this.startDate || this.dueDate >= this.startDate);
  }

  private canSubmit(): boolean {
    return this.canAttemptSubmit() && (!this.hasDates() || this.validDueDate());
  }

  private showDueDateError(): void {
    // 日期区域共用一个日历；校验失败时先切回必选的截止日期。
    this.dateField = 'due';
    const earliest = this.startDate > this.minDate() ? this.startDate : this.minDate();
    this.dueDateError = this.dueDate ? `请选择有效的截止日期，不能早于 ${earliest}。` : '请选择截止日期后再提交。';
    if (this.dueDateScrollPending || this.dueDateScrollAnimating) return;
    this.dueDateScrollPending = true;
    // 先结束文本编辑，再等待系统键盘高度归零和表单避让动画结束。
    if (canIUse('SystemCapability.ArkUI.ArkUI.Full')) {
      if (this.focusedInput === 'task-content') {
        this.contentController?.stopEditing();
      } else if (this.focusedInput === 'group-name') {
        this.groupController?.stopEditing();
      } else if (this.keyboardHeightPx > 0) {
        this.contentController?.stopEditing();
        this.groupController?.stopEditing();
      }
    }
    this.focusedInput = '';
    this.getUIContext().getFocusController().clearFocus();
    this.scheduleDueDateScroll();
  }

  private cancelDueDateScroll(): void {
    if (this.dueDateScrollAnimating && this.editorActive) {
      const offset = this.scroller.offset();
      // 清除 JS 定时器不会终止原生滚动；以当前位置发出无动画滚动才能真正停下。
      if (offset) this.scroller.scrollTo({ xOffset: offset.xOffset, yOffset: offset.yOffset, animation: false });
    }
    if (this.dueDateScrollTimer >= 0) clearTimeout(this.dueDateScrollTimer);
    this.dueDateScrollTimer = -1;
    this.dueDateScrollPending = false;
    this.dueDateScrollAnimating = false;
  }

  private clearDueDateError(): void {
    this.dueDateError = '';
    this.cancelDueDateScroll();
  }

  private scheduleDueDateScroll(): void {
    if (!this.editorActive || !this.dueDateScrollPending || this.keyboardHeightPx > 0 || this.keyboardLayoutSettling) return;
    if (this.dueDateScrollTimer >= 0) clearTimeout(this.dueDateScrollTimer);
    // 错误提示、键盘避让和滚动区布局可能连续变化；只保留最后一次稳定布局后的定位。
    this.dueDateScrollTimer = setTimeout(() => {
      this.dueDateScrollTimer = -1;
      this.scrollToDueDate();
    }, 100);
  }

  private scrollToDueDate(): void {
    if (!this.editorActive || !this.dueDateScrollPending || this.keyboardHeightPx > 0 || this.keyboardLayoutSettling) return;
    const uiContext = this.getUIContext();
    const target = uiContext.getFrameNodeById('task-due-date');
    const viewport = uiContext.getFrameNodeById('task-editor-scroll');
    const offset = this.scroller.offset();
    if (!target || !viewport || !offset) {
      this.dueDateScrollPending = false;
      return;
    }
    const distance = target.getPositionToWindowWithTransform().y - viewport.getPositionToWindowWithTransform().y - 12;
    this.dueDateScrollPending = false;
    this.dueDateScrollAnimating = true;
    this.scroller.scrollTo({ xOffset: 0, yOffset: Math.max(0, offset.yOffset + distance),
      animation: { duration: 360, curve: Curve.EaseInOut } });
    // 定位期间重复点击不重启动画；到期只解除本次定位锁，不触发第二次滚动。
    this.dueDateScrollTimer = setTimeout(() => {
      this.dueDateScrollTimer = -1;
      this.dueDateScrollAnimating = false;
    }, 400);
  }

  private editorViewportChanged(): void {
    this.ensureFocusedInputVisible();
    this.scheduleDueDateScroll();
  }

  private groups(): string[] {
    const groups: string[] = this.data.groups.filter((group: string): boolean => !this.deletedGroups.includes(group));
    this.draftGroups.forEach((group: string): void => {
      if (!groups.includes(group)) groups.push(group);
    });
    if (this.selectedGroup && !groups.includes(this.selectedGroup)) groups.push(this.selectedGroup);
    return groups;
  }

  private pickGroup(group: string): void {
    if (group && this.deleteMode === group) {
      this.animateGroup(() => { this.deleteMode = ''; });
      return;
    }
    this.getUIContext().animateTo(Motion.quick(), () => {
      this.deleteMode = '';
      this.createdGroup = '';
      this.selectedGroup = this.selectedGroup === group ? '' : group;
    });
  }

  private animateGroup(change: () => void): void {
    this.getUIContext().animateTo(Motion.spring(), change);
  }

  private openGroupForm(): void {
    this.animateGroup(() => {
      this.creatingGroup = true;
      this.groupName = '';
      this.deleteMode = '';
    });
  }

  private createGroup(): void {
    const group = this.groupName.trim();
    if (!group) return;
    this.animateGroup(() => {
      if (!this.groups().includes(group)) {
        this.draftGroups = this.draftGroups.concat([group]);
        this.createdGroup = group;
      } else {
        this.createdGroup = '';
      }
      this.deletedGroups = this.deletedGroups.filter((deleted: string): boolean => deleted !== group);
      this.selectedGroup = group;
      this.groupName = '';
      this.creatingGroup = false;
      this.deleteMode = '';
    });
  }

  private removeGroup(group: string): void {
    // 已保存分组的删除立即生效；取消表单也不撤回。草稿只影响本次编辑。
    const saved = this.data.groups.includes(group);
    this.animateGroup(() => {
      this.draftGroups = this.draftGroups.filter((draft: string): boolean => draft !== group);
      this.deletedGroups = this.deletedGroups.concat([group]);
      if (this.selectedGroup === group) this.selectedGroup = '';
      if (this.createdGroup === group) this.createdGroup = '';
      this.deleteMode = '';
    });
    if (saved) {
      const today = new AppAction('DELETE_GROUP');
      today.group = group;
      today.section = 'today';
      this.onAction(today);
      const future = new AppAction('DELETE_GROUP');
      future.group = group;
      future.section = 'future';
      this.onAction(future);
    }
  }

  private pickStart(key: string): void {
    this.startDate = key;
    if (this.dueDate && key > this.dueDate) this.dueDate = key;
    if (this.validDueDate()) this.clearDueDateError();
  }

  private pickDue(key: string): void {
    this.dueDate = key;
    if (this.startDate && this.startDate > key) this.startDate = key;
    if (this.validDueDate()) this.clearDueDateError();
  }

  private dateFieldText(field: string): string {
    // Builder 内直接读当前状态，不把初始空日期按普通参数捕获为永久占位文案。
    const value = field === 'start' ? this.startDate : this.dueDate;
    return value || (field === 'start' ? '默认次日' : '请选择日期');
  }

  private selectDateField(field: string): void {
    if (field !== 'start' && field !== 'due') return;
    this.contentController?.stopEditing();
    this.groupController?.stopEditing();
    this.focusedInput = '';
    this.getUIContext().getFocusController().clearFocus();
    this.getUIContext().animateTo(Motion.quick(), () => { this.dateField = field; });
  }

  private calendarValue(): string {
    return this.dateField === 'start' ? this.startDate : this.dueDate;
  }

  private calendarMinimum(): string {
    return this.dateField === 'start' ? this.minDate() : (this.startDate || this.minDate());
  }

  private selectCalendarDate(key: string): void {
    if (this.dateField === 'start') this.pickStart(key);
    else this.pickDue(key);
  }

  private clearStartDate(): void {
    this.getUIContext().animateTo(Motion.quick(), () => {
      this.startDate = '';
      if (this.validDueDate()) this.clearDueDateError();
    });
  }

  private submit(): void {
    if (!this.canAttemptSubmit()) return;
    if (!this.canSubmit()) {
      this.showDueDateError();
      return;
    }
    this.clearDueDateError();
    this.deleteMode = '';
    // 主保存一并提交正在填写的分组，空白名称保留原有选择。
    if (this.data.settings.showGroups && this.mode !== 'move' && this.creatingGroup && this.groupName.trim()) {
      this.createGroup();
    }
    const action = new AppAction(this.mode === 'move' ? 'MOVE_TASK' : (this.mode === 'edit' ? 'EDIT_TASK' : 'ADD_TASK'));
    if (this.task) action.id = this.task.id;
    action.section = this.section;
    action.text = this.content.trim();
    if (this.mode === 'move') {
      action.to = 'future';
      action.toIndex = this.targetIndex;
      action.group = this.targetGroup;
    } else if (this.data.settings.showGroups) {
      action.group = this.selectedGroup || null;
    }
    if (this.hasDates()) {
      action.startDate = this.startDate || null;
      action.dueDate = this.dueDate;
    }
    if (this.mode === 'edit' && this.progressDirty) {
      action.progress = this.progressEnabled ? this.progressValue : null;
    }
    this.onAction(action);
    this.onClose();
  }

  @Builder
  private sectionHeading(title: string, hint: string = '') {
    Row({ space: 8 }) {
      Text(title).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette.text).layoutWeight(1)
      if (hint) {
        Text(hint).fontSize(11).fontColor(this.palette.textFaint)
      }
    }.width('100%')
  }

  private groupChipWidth(group: string): number {
    const measured = this.getUIContext().getMeasureUtils().measureTextSize({
      textContent: group || '未分组', fontSize: 13, fontWeight: FontWeight.Medium
    });
    return Math.max(60, Math.min(230, this.getUIContext().px2vp(Number(measured.width)) + 28));
  }

  @Builder
  private groupLabelButton(group: string) {
    Button(group || '未分组', { type: ButtonType.Normal, stateEffect: false })
      .width('100%').height(44).borderRadius(12).fontSize(13).padding({ left: 13, right: 13 })
      .fontColor(this.deleteMode === group && group ? this.palette.danger :
        (this.selectedGroup === group ? this.palette.accent : this.palette.textSoft))
      .attributeModifier(new PlanerControlModifier(this.palette, this.selectedGroup === group,
        this.deleteMode === group && group.length > 0, true, BorderStyle.Solid))
      .scale({ x: this.buttonScale('group:' + group), y: this.buttonScale('group:' + group) })
      .onTouch((event: TouchEvent): void => this.buttonTouch('group:' + group, event))
      .onClick(() => { this.releaseButtonPress(); this.pickGroup(group); })
      .gesture(LongPressGesture({ repeat: false, duration: 520 }).onAction(() => {
        if (group) this.animateGroup(() => { this.deleteMode = group; });
      }))
  }

  @Builder
  private groupDeleteButton(group: string) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      PlanerIcon({ icon: 'close', color: this.palette.danger, iconSize: 14 })
    }.width(24).height(24).padding(0).borderRadius(8)
      .attributeModifier(new PlanerControlModifier(this.palette, false, true))
      .responseRegion({ x: -10, y: -10, width: 44, height: 44 })
      .id('icon-close-删除分组' + group).accessibilityText('删除分组' + group)
      .scale({ x: this.buttonScale('delete-group:' + group), y: this.buttonScale('delete-group:' + group) })
      .onTouch((event: TouchEvent): void => this.buttonTouch('delete-group:' + group, event))
      .onClick(() => { this.releaseButtonPress(); this.removeGroup(group); })
  }

  @Builder
  private groupCreateButton() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 6 }) {
        PlanerIcon({ icon: 'plus', color: this.palette.accent, iconSize: 16 })
        Text('新建分组').fontSize(13).fontColor(this.palette.accent)
      }
    }.id('group-create').width('100%').height(44).borderRadius(12)
      .attributeModifier(new PlanerControlModifier(this.palette, this.creatingGroup, false, true, BorderStyle.Dashed))
      .padding({ left: 13, right: 13 }).scale({ x: this.buttonScale('group-create'), y: this.buttonScale('group-create') })
      .onTouch((event: TouchEvent): void => this.buttonTouch('group-create', event))
      .onClick(() => { this.releaseButtonPress(); this.openGroupForm(); })
  }

  @Builder
  private groupCancelButton() {
    Button('取消', { type: ButtonType.Normal, stateEffect: false }).height(44).width('100%').fontSize(13)
      .fontColor(this.palette.textSoft).attributeModifier(new PlanerControlModifier(this.palette)).borderRadius(12)
      .scale({ x: this.buttonScale('group-cancel'), y: this.buttonScale('group-cancel') })
      .onTouch((event: TouchEvent): void => this.buttonTouch('group-cancel', event))
      .onClick(() => { this.releaseButtonPress(); this.animateGroup(() => { this.creatingGroup = false; }); })
  }

  @Builder
  private groupConfirmButton() {
    Button(this.groups().includes(this.groupName.trim()) ? '选用分组' : '创建并选中', { type: ButtonType.Normal, stateEffect: false }).id('group-confirm')
      .height(44).width('100%').fontSize(13).fontColor(this.palette.accent)
      .attributeModifier(new PlanerControlModifier(this.palette, true)).borderRadius(12).enabled(this.groupName.trim().length > 0)
      .scale({ x: this.buttonScale('group-confirm'), y: this.buttonScale('group-confirm') })
      .onTouch((event: TouchEvent): void => this.buttonTouch('group-confirm', event))
      .onClick(() => { this.releaseButtonPress(); this.createGroup(); })
  }

  @Builder
  private taskCancelButton() {
    Button('取消', { type: ButtonType.Normal, stateEffect: false }).id('task-cancel').width('100%').height(46).fontSize(15).borderRadius(12)
      .fontColor(this.palette.textSoft).attributeModifier(new PlanerControlModifier(this.palette))
      .scale({ x: this.buttonScale('task-cancel'), y: this.buttonScale('task-cancel') })
      .onTouch((event: TouchEvent): void => this.buttonTouch('task-cancel', event))
      .onClick(() => { this.releaseButtonPress(); this.deleteMode = ''; this.cancelDueDateScroll(); this.onClose(); })
  }

  @Builder
  private taskSubmitButton() {
    Button(this.mode === 'move' ? '确认移动' : (this.mode === 'edit' ? '保存' : '添加'), { type: ButtonType.Normal, stateEffect: false }).id('task-submit')
      .width('100%').height(46).fontSize(15).fontWeight(FontWeight.Medium).borderRadius(12)
      .fontColor(this.palette.accent).attributeModifier(new PlanerControlModifier(this.palette, true))
      .enabled(this.canAttemptSubmit())
      .opacity(this.canAttemptSubmit() ? 1 : 0.45).scale({ x: this.buttonScale('task-submit'), y: this.buttonScale('task-submit') })
      .onTouch((event: TouchEvent): void => this.buttonTouch('task-submit', event))
      .onClick(() => { this.releaseButtonPress(); this.submit(); })
  }

  @Builder
  private taskDeleteButton() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Row({ space: 8 }) {
        PlanerIcon({ icon: 'trash', color: this.palette.danger, iconSize: 20 })
        Text('删除日程').fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette.danger)
      }.justifyContent(FlexAlign.Center)
    }.id('task-delete').width('100%').height(44).borderRadius(12)
      .attributeModifier(new PlanerControlModifier(this.palette, false, true)).accessibilityText('删除日程')
      .scale({ x: this.buttonScale('task-delete'), y: this.buttonScale('task-delete') })
      .onTouch((event: TouchEvent): void => this.buttonTouch('task-delete', event))
      .onClick(() => { this.releaseButtonPress(); this.deleteMode = ''; this.cancelDueDateScroll(); this.onDelete(); })
  }

  @Builder
  private groupChip(group: string) {
    Stack({ alignContent: Alignment.TopEnd }) {
      MaterialButtonScope({ palette: this.palette, content: () => { this.groupLabelButton(group); } }).width(this.groupChipWidth(group)).height(44)
        .rotate({ angle: this.deleteMode === group && group ? this.deleteShakeAngle : 0 })
        .margin({ top: 8, right: 8 })
      if (this.deleteMode === group && group) {
        MaterialButtonScope({ palette: this.palette, controlHeight: 24, radius: 8, content: () => { this.groupDeleteButton(group); } }).width(24).height(24)
          .position({ top: 0, right: 0 }).transition(Motion.reveal())
      }
    }.margin({ right: 6, bottom: 6 }).clip(false)
      .transition(Motion.reveal())
  }

  @Builder
  private groupPicker() {
    Column({ space: 8 }) {
      Flex({ wrap: FlexWrap.Wrap }) {
        this.groupChip('')
        ForEach(this.groups(), (group: string) => {
          this.groupChip(group)
        }, (group: string) => group)
        MaterialButtonScope({ palette: this.palette, content: () => { this.groupCreateButton(); } }).width(this.groupChipWidth('新建分组') + 22).height(44)
          .margin({ top: 8, right: 6, bottom: 6 })
      }.width('100%').padding({ top: 2, right: 2, bottom: 2, left: 2 }).clip(false)
      if (this.creatingGroup) {
        Column({ space: 8 }) {
          TextInput({ text: this.groupName, placeholder: '分组名称', controller: this.groupController }).id('group-name')
            .height(44).fontSize(15).fontColor(this.palette.text).backgroundColor(Materials.inset(this.palette))
            .borderRadius(12)
            .onFocus(() => this.focusInput('group-name'))
            .onBlur(() => this.blurInput('group-name'))
            .onChange((value: string) => this.groupName = value)
            .onSubmit(() => this.createGroup())
          Text('填写名称后，可创建并选中，也可随日程一起保存。')
            .width('100%').fontSize(12).lineHeight(18).fontColor(this.palette.textSoft)
          Row({ space: 8 }) {
            MaterialButtonScope({ palette: this.palette, content: () => { this.groupCancelButton(); } }).layoutWeight(1).height(44)
            MaterialButtonScope({ palette: this.palette, content: () => { this.groupConfirmButton(); } }).layoutWeight(2).height(44)
          }.width('100%')
        }.transition(Motion.reveal())
      }
      Text(this.deleteMode ? `点击叉号删除“${this.deleteMode}”，组内日程会移入未分组。再次点击标签取消删除。` :
        (this.selectedGroup ? `${this.createdGroup === this.selectedGroup ? '已创建并选中' : '已选分组'}：${this.selectedGroup} · 随日程保存` : '当前未分组，可选择已有分组或新建'))
        .width('100%').fontSize(12).lineHeight(18).fontColor(this.selectedGroup ? this.palette.accent : this.palette.textSoft)
    }.width('100%').alignItems(HorizontalAlign.Start).id('task-groups')
  }

  @Builder
  private progressStopButton(value: number) {
    Button(`${value}%`, { type: ButtonType.Normal, stateEffect: false }).id('progress-' + value.toString()).width('100%').height(44).padding(0).fontSize(12)
      .borderRadius(12).fontColor(this.progressValue === value ? this.palette.accent : this.palette.textSoft)
      .attributeModifier(new PlanerControlModifier(this.palette, this.progressValue === value))
      .scale({ x: this.buttonScale('progress:' + value.toString()), y: this.buttonScale('progress:' + value.toString()) })
      .onTouch((event: TouchEvent): void => this.buttonTouch('progress:' + value.toString(), event))
      .onClick(() => { this.releaseButtonPress();
        this.getUIContext().animateTo(Motion.quick(), () => {
          this.progressValue = value;
          this.progressDirty = true;
        });
      })
  }

  @Builder
  private progressEditor() {
    Column({ space: 8 }) {
      Row() {
        Text('完成进度').fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette.text)
        Text(this.progressEnabled ? `${this.progressValue}%` : '未设置').fontSize(13)
          .fontColor(this.progressEnabled ? this.palette.accent : this.palette.textFaint).margin({ left: 8 }).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.progressEnabled }).id('progress-enable').selectedColor(this.palette.accent)
          .accessibilityText('设置完成进度').onChange((enabled: boolean) => {
            if (this.progressEnabled === enabled) return;
            this.getUIContext().animateTo(Motion.spring(), () => {
              this.progressEnabled = enabled;
              this.progressDirty = true;
            });
          })
      }.width('100%')
      if (this.progressEnabled) {
        Column({ space: 8 }) {
          Slider({ value: this.progressValue, min: 0, max: 100, step: 5, style: SliderStyle.OutSet })
            .width('100%').selectedColor(this.palette.accent).id('progress-slider')
            .onChange((value: number) => {
              this.progressValue = Math.round(value);
              this.progressDirty = true;
            })
          Row({ space: 5 }) {
            ForEach(this.progressStops, (value: number) => {
              MaterialButtonScope({ palette: this.palette, content: () => { this.progressStopButton(value); } })
                .layoutWeight(1).height(44)
            }, (value: number) => value.toString())
          }.width('100%')
        }.width('100%').transition(Motion.reveal())
      }
    }.width('100%').id('task-progress')
  }

  @Builder
  private contentSection() {
    MaterialSection({ palette: this.palette, content: () => { this.contentSectionBody(); } }).width('100%')
  }

  @Builder
  private dateSection() {
    MaterialSection({ palette: this.palette, content: () => { this.dateSectionBody(); } }).width('100%')
  }

  @Builder
  private groupSection() {
    MaterialSection({ palette: this.palette, content: () => { this.groupSectionBody(); } }).width('100%')
  }

  @Builder
  private progressSection() {
    MaterialSection({ palette: this.palette, content: () => { this.progressSectionBody(); } }).width('100%')
  }

  @Builder
  private dangerSection() {
    MaterialSection({ palette: this.palette, danger: true, content: () => { this.dangerSectionBody(); } }).width('100%').margin({ top: 4 })
  }

  @Builder
  private contentSectionBody() {
    Column({ space: 10 }) {
      this.sectionHeading('日程内容', '必填')
      if (this.mode === 'move') {
        Text(this.content).width('100%').fontSize(16).lineHeight(24).fontColor(this.palette.text).padding(12)
          .borderRadius(12).backgroundColor(Materials.inset(this.palette))
        Text(this.task && this.task.dueDate ? '已填入保留的时间区间，可在下方调整。' : '设置时间区间，也可只填截止日期。')
          .width('100%').fontSize(12).lineHeight(18).fontColor(this.palette.textSoft)
      } else {
        TextArea({ text: this.content, placeholder: this.section === 'today' ? '今天要做点什么…' : '计划做点什么…', controller: this.contentController }).id('task-content')
          .width('100%').height(96).padding(12).fontSize(16).fontColor(this.palette.text)
          .backgroundColor(Materials.input(this.palette)).borderRadius(12).placeholderColor(this.palette.textSoft)
          .border({ width: 1, radius: 12, color: this.focusedInput === 'task-content' ? this.palette.accent : this.palette.border })
          .onFocus(() => this.focusInput('task-content'))
          .onBlur(() => this.blurInput('task-content'))
          .onChange((text: string) => this.content = text)
      }
    }.width('100%').padding(14)
  }

  @Builder
  private dateFieldButton(field: string, title: string) {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Column({ space: 6 }) {
        Text(title).fontSize(12).fontColor(this.palette.textSoft)
        Text(this.dateFieldText(field)).fontSize(14).fontWeight(FontWeight.Medium).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontColor(field === 'due' && this.dueDateError ? this.palette.danger :
            (this.dateField === field ? this.palette.accent : this.palette.text))
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.layoutWeight(1).height(76).padding(12).borderRadius(12)
      .backgroundColor(Materials.inset(this.palette, this.dateField === field))
      .border({ width: 1, radius: 12, color: field === 'due' && this.dueDateError ? this.palette.danger :
        (this.dateField === field ? this.palette.accent : this.palette.border) })
      .id('date-' + field + '-field').accessibilityText(title + '，' + this.dateFieldText(field))
      .scale({ x: this.buttonScale('date:' + field), y: this.buttonScale('date:' + field) })
      .onTouch((event: TouchEvent): void => this.buttonTouch('date:' + field, event))
      .onClick(() => { this.releaseButtonPress(); this.selectDateField(field); })
  }

  @Builder
  private dateSectionBody() {
    Column({ space: 10 }) {
      this.sectionHeading('时间安排', '起始可选 · 截止必选')
      Row({ space: 8 }) {
        this.dateFieldButton('start', '起始日期')
        this.dateFieldButton('due', '截止日期')
      }.width('100%')
      if (this.dueDateError) {
        Text(this.dueDateError).id('due-date-error').width('100%').fontSize(12).lineHeight(18)
          .fontColor(this.palette.danger).accessibilityText(this.dueDateError)
      }
      Row() {
        Text(this.dateField === 'start' ? '选择起始日期' : '选择截止日期')
          .fontSize(12).fontColor(this.palette.textSoft).layoutWeight(1)
        if (this.dateField === 'start' && this.startDate) {
          Button('清除起始日期', { type: ButtonType.Normal, stateEffect: false }).height(32).fontSize(12).borderRadius(10)
            .responseRegion({ x: 0, y: -6, width: '100%', height: 44 })
            .fontColor(this.palette.accent).backgroundColor(Color.Transparent)
            .scale({ x: this.buttonScale('clear-start'), y: this.buttonScale('clear-start') })
            .onTouch((event: TouchEvent): void => this.buttonTouch('clear-start', event))
            .onClick(() => { this.releaseButtonPress(); this.clearStartDate(); })
        }
      }.width('100%').height(32)
      PlanerCalendar({ compact: ResponsiveLayout.editorColumns(this.editorWidth), value: this.calendarValue(), minDate: this.calendarMinimum(), palette: this.palette,
        onSelect: (key: string) => this.selectCalendarDate(key) })
    }.id('task-due-date').width('100%').padding(14)
      .alignItems(HorizontalAlign.Start)
      .onAreaChange(() => this.scheduleDueDateScroll())
  }

  @Builder
  private groupSectionBody() {
    Column({ space: 4 }) {
      this.sectionHeading('分组', '可选')
      this.groupPicker()
    }.width('100%').padding(14)
  }

  @Builder
  private progressSectionBody() {
    Column({ space: 8 }) {
      this.progressEditor()
      if (this.section === 'today' && this.task && this.task.dueDate) {
        Text('该日程保留原时间区间，此处不修改日期。').width('100%').fontSize(12).lineHeight(18)
          .fontColor(this.palette.textFaint)
      }
    }.width('100%').padding(14)
  }

  @Builder
  private dangerSectionBody() {
    Column({ space: 10 }) {
      this.sectionHeading('日程管理', '删除后无法恢复')
      // 删除保留在编辑页末尾，确认和持久化仍由宿主处理。
      MaterialButtonScope({ palette: this.palette, content: () => { this.taskDeleteButton(); } }).width('100%').height(44)
    }.width('100%').padding(14)
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(this.title()).fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.palette.text)
          Text(this.mode === 'move' ? '保留日程内容，重新安排日期' :
            (this.hasDates() ? '起始日期可选，截止日期必选' : '记录今天要完成的事'))
            .fontSize(12).fontColor(this.palette.textSoft)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        IconButton({ icon: 'close', palette: this.palette, label: '取消编辑', onTap: () => { this.deleteMode = ''; this.cancelDueDateScroll(); this.onClose(); } })
      }.width('100%').padding({ left: 20, right: 12, top: 12, bottom: 12 })
      Divider().color(this.palette.border)
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          if (ResponsiveLayout.editorColumns(this.editorWidth)) {
            Row({ space: 20 }) {
              Column({ space: 16 }) {
                this.contentSection()
                if (this.data.settings.showGroups && this.mode !== 'move') { this.groupSection() }
                if (this.mode === 'edit' && this.hasDates()) {
                  this.progressSection()
                  this.dangerSection()
                }
              }.layoutWeight(1)
              if (this.hasDates()) {
                Column() { this.dateSection() }.layoutWeight(1)
              } else if (this.mode === 'edit') {
                Column({ space: 16 }) {
                  this.progressSection()
                  this.dangerSection()
                }.layoutWeight(1)
              }
            }.width('100%').alignItems(VerticalAlign.Top).id('wide-editor-columns')
          } else {
          this.contentSection()
          if (this.hasDates()) {
            this.dateSection()
          }
          if (this.data.settings.showGroups && this.mode !== 'move') {
            this.groupSection()
          }
          if (this.mode === 'edit') {
            this.progressSection()
            this.dangerSection()
          }
          }
        }.width('100%').padding({ left: 20, right: 20, top: 16, bottom: 24 })
          .alignItems(HorizontalAlign.Start)
      }.id('task-editor-scroll').layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Auto)
        .onAreaChange(() => this.editorViewportChanged())
        .onDidScroll(() => EditorMaterialRefresh.request(this.getUIContext()))
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      Divider().color(this.palette.border)
      Row({ space: 12 }) {
        MaterialButtonScope({ palette: this.palette, controlHeight: 46, content: () => { this.taskCancelButton(); } }).layoutWeight(1).height(46)
        MaterialButtonScope({ palette: this.palette, controlHeight: 46, content: () => { this.taskSubmitButton(); } }).layoutWeight(1).height(46)
      }.width('100%').constraintSize({ maxWidth: 520 }).padding({ left: 20, right: 20, top: 14, bottom: 18 })
    }.id('task-editor-root').width('100%').height('100%').padding({ bottom: this.keyboardInset })
      .onAreaChange((_oldArea: Area, area: Area) => {
        this.updateEditorArea(area);
        EditorMaterialRefresh.request(this.getUIContext());
      })
      .backgroundColor(Color.Transparent).borderRadius(24)
  }
}
