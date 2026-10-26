import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Materials } from '../theme/Appearance';
import { Palette } from '../theme/Theme';

// 原生 SheetPage 在中算力上会额外降档；标题区域中的通用背板遵循与 Tabs 相同的设备档位。
// 半模态继续管理尺寸、遮罩和手势，背板不参与触摸与无障碍，也不额外叠加模糊。
@Component
export struct SheetMaterialSurface {
  @BuilderParam content: () => void;
  @Prop palette: Palette = new Palette();
  @Prop radius: number = 24;
  @State private surfaceHeight: number = 1;

  private titleOptions(): NavigationTitleOptions {
    const options: NavigationTitleOptions = {
      backgroundColor: Color.Transparent, backgroundBlurStyle: BlurStyle.NONE
    };
    if (deviceInfo.apiAvailable('26.0.0')) options.systemMaterial = uiMaterial.Material.empty;
    return options;
  }

  @Builder
  private surface() {
    if (deviceInfo.apiAvailable('26.0.0')) {
      Column() {}
        .width('100%').height(this.surfaceHeight).borderRadius(this.radius)
        .backgroundColor(Color.Transparent)
        .systemMaterial(Materials.sheetMaterial(this.palette))
    }
  }

  build() {
    if (Materials.sheetUsesContentSurface()) {
      Stack({ alignContent: Alignment.Top }) {
        Column() {
          WithTheme({ colorMode: Materials.mode(this.palette) }) {
            Navigation() {}
              .title({ builder: () => { this.surface(); }, height: this.surfaceHeight }, this.titleOptions())
              .titleMode(NavigationTitleMode.Mini).hideBackButton(true).hideToolBar(true)
              .mode(NavigationMode.Stack).width('100%').height(this.surfaceHeight)
              .backgroundColor(Color.Transparent).borderRadius(this.radius).clip(true)
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
              .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
          }
        }.width('100%').height(this.surfaceHeight).position({ x: 0, y: 0 })
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
        this.content()
      }.width('100%').height('100%')
        .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
          const height = Number(size.height);
          if (height > 0 && Math.abs(height - this.surfaceHeight) > 0.1) this.surfaceHeight = height;
        })
    } else {
      this.content()
    }
  }
}
