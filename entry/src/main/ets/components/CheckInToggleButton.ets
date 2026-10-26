import { Palette } from '../theme/Theme';
import { Motion, PlanerControlModifier } from '../theme/Appearance';
import { MaterialButtonScope } from './MaterialButtonScope';
import { PlanerIcon } from './PlanerIcon';

// 固定按钮尺寸，只让内部图标、文字转场，完成与撤销不会改变卡片布局。
@Component
export struct CheckInToggleButton {
  @Prop palette: Palette = new Palette();
  @Prop completed: boolean = false;
  @Prop pending: boolean = false;
  @Prop future: boolean = false;
  @Prop buttonId: string = '';
  @State private pressed: boolean = false;
  onToggle: () => void = (): void => {};

  private label(): string {
    if (this.completed) return '撤销';
    if (this.pending) return '调整本期内容';
    return this.future ? '提前打卡' : '完成打卡';
  }
  // 根据转场条目自身的文案取图标与颜色，退场中的旧内容不会提前变成新状态。
  private labelIcon(label: string): string {
    if (label === '撤销') return 'restore';
    return label === '调整本期内容' ? 'edit' : '';
  }
  private labelColor(label: string): ResourceColor {
    return label === '撤销' ? this.palette.textSoft : this.palette.accent;
  }
  private updatePressed(value: boolean): void {
    if (this.pressed === value) return;
    this.getUIContext().animateTo(Motion.quick(), (): void => { this.pressed = value; });
  }
  private contentTransition(): TransitionEffect {
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 8 })),
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: -8 }))).animation(Motion.quick());
  }

  @Builder private actionContent() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Stack() {
        ForEach([this.label()], (label: string) => {
          Row({ space: 6 }) {
            if (this.labelIcon(label)) {
              PlanerIcon({ icon: this.labelIcon(label), iconSize: 17, color: this.labelColor(label) })
            }
            Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.labelColor(label))
          }.width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
            .transition(this.contentTransition())
        }, (label: string): string => label)
      }.width('100%').height('100%').clip(true)
    }.id(this.buttonId).width('100%').height(44).padding(0).borderRadius(12)
      .attributeModifier(new PlanerControlModifier(this.palette, !this.completed))
      .accessibilityText(this.label()).scale({ x: this.pressed ? 0.97 : 1, y: this.pressed ? 0.97 : 1 })
      .onTouch((event: TouchEvent): void => {
        if (event.type === TouchType.Down) this.updatePressed(true);
        else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.updatePressed(false);
      })
      .onDisAppear((): void => { this.pressed = false; })
      .onClick((): void => { this.pressed = false; this.onToggle(); })
  }

  build() {
    MaterialButtonScope({ palette: this.palette, content: () => { this.actionContent(); } }).width(136).height(44)
  }
}
