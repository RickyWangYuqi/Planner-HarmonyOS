import { deviceInfo } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';
import { Palette } from '../theme/Theme';
import { Materials, Motion, ButtonFeedback } from '../theme/Appearance';

class BackButtonModifier implements AttributeModifier<ButtonAttribute> {
  private palette: Palette;

  constructor(palette: Palette) { this.palette = palette; }

  applyNormalAttribute(button: ButtonAttribute): void {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (Materials.supported()) {
        button.backgroundColor(Color.Transparent);
        button.systemMaterial(Materials.button(this.palette));
      } else {
        button.systemMaterial(uiMaterial.Material.empty);
        button.backgroundColor(Materials.fallback(this.palette));
      }
    } else {
      button.backgroundColor(Materials.fallback(this.palette));
    }
  }
}

// 唯一返回按钮放在小尺寸 Navigation 的标题作用域；不是全屏交互覆盖层。
@Component
export struct HistoryBackButton {
  @Prop palette: Palette = new Palette();
  @Prop label: string = '返回设置';
  @Prop buttonId: string = 'history-back';
  @State private pressedButton: string = '';
  onBack: () => void = (): void => {};

  private buttonTouch(event: TouchEvent): void {
    const next = ButtonFeedback.next(this.pressedButton, this.buttonId, event.type);
    if (next === this.pressedButton) return;
    this.getUIContext().animateTo(Motion.quick(), (): void => { this.pressedButton = next; });
  }

  private titleOptions(): NavigationTitleOptions {
    const options: NavigationTitleOptions = {
      backgroundColor: Color.Transparent,
      backgroundBlurStyle: BlurStyle.NONE
    };
    if (deviceInfo.apiAvailable('26.0.0')) options.systemMaterial = uiMaterial.Material.empty;
    return options;
  }

  @Builder
  private backContent() {
    Button({ type: ButtonType.Normal, stateEffect: false }) {
      Image($r('app.media.chevron_left')).width(22).height(44).objectFit(ImageFit.Contain)
        .fillColor(this.palette.text).draggable(false).accessibilityLevel('no')
    }.width(44).height(44).padding(0).borderRadius(12)
      .attributeModifier(new BackButtonModifier(this.palette))
      .scale({ x: ButtonFeedback.scale(this.pressedButton, this.buttonId),
        y: ButtonFeedback.scale(this.pressedButton, this.buttonId) })
      .onTouch((event: TouchEvent): void => this.buttonTouch(event))
      .id(this.buttonId).accessibilityText(this.label)
      .onDisAppear((): void => { this.pressedButton = ''; })
      .onClick((): void => { this.pressedButton = ''; this.onBack(); })
  }

  build() {
    Navigation() {}
      .title({ builder: () => { this.backContent(); }, height: 44 }, this.titleOptions())
      .titleMode(NavigationTitleMode.Mini).hideBackButton(true).hideToolBar(true).mode(NavigationMode.Stack)
      .width(44).height(44).backgroundColor(Color.Transparent).borderRadius(12).clip(true)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .accessibilityLevel('no')
  }
}
