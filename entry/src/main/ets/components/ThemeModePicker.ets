import { curves } from '@kit.ArkUI';
import { Palette } from '../theme/Theme';
import { Materials } from '../theme/Appearance';

// 只维护滑块几何与手势草稿；主题的实际状态和持久化由页面回调负责。
@Component
export struct ThemeModePicker {
  @Prop @Watch('selectionChanged') selectedMode: string = 'system';
  @Prop palette: Palette = new Palette();
  onSelect: (mode: string) => void = (_mode: string): void => {};
  @State private trackWidth: number = 1;
  @State private sliderX: number = 0;
  @State private dragging: boolean = false;
  @State private stretch: number = 0;
  private modes: string[] = ['light', 'dark', 'system'];
  private labels: string[] = ['浅色', '深色', '跟随系统'];
  private dragOriginX: number = 0;
  private lastOffset: number = 0;
  private lastMoveAt: number = 0;
  private relaxTimer: number = -1;
  private disposed: boolean = true;

  aboutToAppear(): void {
    this.disposed = false;
    this.sliderX = this.selectedIndex() * this.segmentWidth();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    clearTimeout(this.relaxTimer);
  }

  private selectedIndex(): number {
    const index = this.modes.indexOf(this.selectedMode);
    return index < 0 ? 2 : index;
  }

  private segmentWidth(): number { return this.trackWidth / 3; }
  private clampIndex(index: number): number { return Math.max(0, Math.min(2, Math.round(index))); }
  private pillWidth(): number { return this.segmentWidth() * (1 + this.stretch); }
  private pillHeight(): number { return 44 * (1 - this.stretch * 0.4); }
  private pillX(): number { return this.sliderX - (this.pillWidth() - this.segmentWidth()) / 2; }
  private pillY(): number { return (44 - this.pillHeight()) / 2; }

  private snap(index: number): void {
    clearTimeout(this.relaxTimer);
    this.getUIContext().animateTo({ curve: curves.springMotion(0.46, 0.64) }, () => {
      this.sliderX = this.clampIndex(index) * this.segmentWidth();
      this.stretch = 0;
    });
  }

  private selectionChanged(): void {
    if (!this.dragging) this.snap(this.selectedIndex());
  }

  private follow(event: GestureEvent): void {
    const now = Date.now();
    const speed = Math.abs(event.offsetX - this.lastOffset) / Math.max(8, now - this.lastMoveAt);
    const x = Math.max(0, Math.min(this.trackWidth - this.segmentWidth(), this.dragOriginX + event.offsetX));
    this.lastOffset = event.offsetX;
    this.lastMoveAt = now;
    this.getUIContext().animateTo({ curve: curves.springMotion(0.18, 0.78) }, () => {
      this.sliderX = x;
      this.stretch = Math.min(0.12, 0.025 + speed * 0.05);
    });
    clearTimeout(this.relaxTimer);
    this.relaxTimer = setTimeout(() => {
      if (!this.disposed && this.dragging) {
        this.getUIContext().animateTo({ curve: curves.springMotion(0.3, 0.7) }, () => { this.stretch = 0.02; });
      }
    }, 90);
  }

  private select(index: number): void {
    const selected = this.clampIndex(index);
    this.dragging = false;
    this.snap(selected);
    if (this.modes[selected] !== this.selectedMode) this.onSelect(this.modes[selected]);
  }

  private resize(size: SizeOptions): void {
    const width = Number(size.width);
    if (!Number.isFinite(width) || width <= 0 || Math.abs(width - this.trackWidth) < 0.1) return;
    const fraction = this.sliderX / this.segmentWidth();
    this.getUIContext().animateTo({ duration: 0 }, () => {
      this.trackWidth = width;
      this.sliderX = (this.dragging ? fraction : this.selectedIndex()) * this.segmentWidth();
    });
  }

  @Builder
  private label(index: number, selected: boolean) {
    Text(this.labels[index]).fontSize(13).fontWeight(selected ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(selected ? this.palette.accent : this.palette.textSoft)
      .width('100%').height(44).textAlign(TextAlign.Center).maxLines(1)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Row() {
          ForEach(this.modes, (mode: string, index: number) => {
            Button({ type: ButtonType.Normal, stateEffect: false }) {
              this.label(index, false)
            }.id('theme-' + mode).width('33.333333%').height(44).padding(0).borderRadius(12)
              .backgroundColor(Color.Transparent)
              .accessibilityText(this.labels[index] + (this.selectedMode === mode ? '，已选中' : ''))
              .onClick(() => this.select(index))
          }, (mode: string) => mode)
        }.width('100%').height(44)
        // 仅重复不可交互的文字前景；原始按钮、标签位置和无障碍节点保持固定。
        Stack({ alignContent: Alignment.TopStart }) {
          Row() {
            ForEach(this.modes, (_mode: string, index: number) => {
              Column() { this.label(index, true) }.width('33.333333%')
            }, (mode: string) => mode)
          }.width(this.trackWidth).height(44).position({ x: -this.pillX(), y: -this.pillY() })
            .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
        }.width(this.pillWidth()).height(this.pillHeight()).borderRadius(12)
          .backgroundColor(Materials.fallback(this.palette, true)).clip(true)
          .position({ x: this.pillX(), y: this.pillY() })
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
          .id('theme-selection-indicator')
      }.width('100%').height(44)
        .onSizeChange((_old: SizeOptions, size: SizeOptions) => this.resize(size))
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.dragOriginX = this.sliderX;
            this.lastOffset = 0;
            this.lastMoveAt = Date.now();
            clearTimeout(this.relaxTimer);
          }
        })
        .priorityGesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 6 })
          .onActionStart((event: GestureEvent) => {
            this.dragging = true;
            this.follow(event);
          })
          .onActionUpdate((event: GestureEvent) => { if (this.dragging) this.follow(event); })
          .onActionEnd(() => {
            if (this.dragging) this.select(this.sliderX / this.segmentWidth());
          })
          .onActionCancel(() => {
            this.dragging = false;
            this.snap(this.selectedIndex());
          }))
    }.width('100%').padding(3).borderRadius(14).backgroundColor(Materials.fallback(this.palette))
  }
}