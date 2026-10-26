import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Palette } from '../theme/Theme';
import { Materials } from '../theme/Appearance';

// 参照 DeepSeekUsage 的 NativeMaterialButton：真实按钮在原生标题作用域内绘制。
// Navigation 只占按钮自身尺寸，不创建页面路由，也不重复业务按钮或叠加毛玻璃。
@Component
export struct MaterialButtonScope {
  @BuilderParam content: () => void;
  @Prop palette: Palette = new Palette();
  @Prop controlHeight: number = 44;
  @Prop radius: number = 12;

  private titleOptions(): NavigationTitleOptions {
    const options: NavigationTitleOptions = {
      backgroundColor: Color.Transparent, backgroundBlurStyle: BlurStyle.NONE
    };
    if (deviceInfo.apiAvailable('26.0.0')) options.systemMaterial = uiMaterial.Material.empty;
    return options;
  }

  build() {
    if (Materials.supported()) {
      WithTheme({ colorMode: Materials.mode(this.palette) }) {
        Navigation() {}
          .title({ builder: this.content, height: this.controlHeight }, this.titleOptions())
          .titleMode(NavigationTitleMode.Mini).hideBackButton(true).hideToolBar(true)
          .mode(NavigationMode.Stack).width('100%').height(this.controlHeight)
          // 承载层与真实按钮保持相同圆角，避免露出原生方形背板。
          .backgroundColor(Color.Transparent).borderRadius(this.radius).clip(true)
          // 不继承键盘安全区，否则表单上抬时按钮可能留在键盘后面。
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .accessibilityLevel('no')
      }
    } else {
      this.content()
    }
  }
}
