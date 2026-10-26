import { Palette } from '../theme/Theme';
import { Motion, PlanerControlModifier } from '../theme/Appearance';
import { PlanerIcon } from './PlanerIcon';
import { MaterialButtonScope } from './MaterialButtonScope';

@Component
export struct IconButton {
  @Prop icon: string = 'plus';
  @Prop palette: Palette = new Palette();
  @Prop label: string = '';
  @Prop buttonSize: number = 44;
  @Prop iconSize: number = 21;
  @Prop cornerRadius: number = 12;
  @Prop tone: string = 'normal';
  @State private pressed: boolean = false;
  onTap: () => void = (): void => {};

  private iconColor(): ResourceColor {
    if (this.icon === 'trash') return this.palette.danger;
    return this.tone === 'accent' ? this.palette.accent : this.palette.textSoft;
  }

  private updatePressed(value: boolean): void {
    if (this.pressed === value) return;
    this.getUIContext().animateTo(Motion.quick(), (): void => {
      this.pressed = value;
    });
  }

  @Builder
  private buttonContent() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      PlanerIcon({ icon: this.icon, color: this.iconColor(), iconSize: this.iconSize })
    }
    .width(this.buttonSize).height(this.buttonSize).padding(0).borderRadius(this.cornerRadius)
    // 紧凑分组标题只缩小可见按钮，响应区继续至少保持44vp。
    .responseRegion({ x: Math.min(0, (this.buttonSize - 44) / 2), y: Math.min(0, (this.buttonSize - 44) / 2),
      width: Math.max(44, this.buttonSize), height: Math.max(44, this.buttonSize) })
    .attributeModifier(new PlanerControlModifier(this.palette, this.tone === 'accent', this.icon === 'trash',
      this.icon === 'plus' || this.icon === 'close' || this.icon === 'trash')).accessibilityText(this.label)
    .scale({ x: this.pressed ? 0.90 : 1, y: this.pressed ? 0.90 : 1 })
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) this.updatePressed(true);
      else if (event.type === TouchType.Up || event.type === TouchType.Cancel) this.updatePressed(false);
    })
    .id('icon-' + this.icon + '-' + this.label)
    .onDisAppear((): void => { this.pressed = false; })
    .onClick((): void => { this.pressed = false; this.onTap(); })
  }

  build() {
    if (this.icon === 'plus' || this.icon === 'close' || this.icon === 'trash') {
      MaterialButtonScope({ palette: this.palette, controlHeight: this.buttonSize, radius: this.cornerRadius, content: () => {
        this.buttonContent()
      } }).width(this.buttonSize).height(this.buttonSize)
    } else {
      this.buttonContent()
    }
  }
}
