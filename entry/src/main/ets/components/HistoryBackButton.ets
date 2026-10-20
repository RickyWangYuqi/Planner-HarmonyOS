import { deviceInfo } from '@kit.BasicServicesKit';
import { uiMaterial } from '@kit.ArkUI';
import { Palette } from '../theme/Theme';
import { Materials } from '../theme/Appearance';

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
  onBack: () => void = (): void => {};

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
    Button({ type: ButtonType.Normal }) {
      Image($r('app.media.chevron_left')).width(22).height(44).objectFit(ImageFit.Contain)
        .fillColor(this.palette.text).draggable(false).accessibilityLevel('no')
    }.width(44).height(44).padding(0).borderRadius(12)
      .attributeModifier(new BackButtonModifier(this.palette))
      .id('icon-back-返回设置').accessibilityText('返回设置').onClick(() => this.onBack())
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