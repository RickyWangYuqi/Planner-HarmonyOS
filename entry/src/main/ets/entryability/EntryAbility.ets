import { AbilityConstant, ConfigurationConstant, systemConfiguration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { display, window } from '@kit.ArkUI';

const DOMAIN = 0x0000;
const TAG = 'Planer';

export default class EntryAbility extends UIAbility {
  private mainWindow: window.Window | undefined = undefined;
  private avoidAreaListener = (options: window.AvoidAreaOptions): void => {
    if (options.type === window.AvoidAreaType.TYPE_SYSTEM || options.type === window.AvoidAreaType.TYPE_CUTOUT ||
      options.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
      this.updateSafeArea();
    }
  };
  private systemConfigurationRegistered: boolean = false;
  private systemConfigurationListener: systemConfiguration.UpdatedCallback = {
    onColorModeUpdated: (colorMode: ConfigurationConstant.ColorMode): void => {
      this.updateSystemColorMode(colorMode);
    }
  };

  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    // 应用尚未覆盖颜色模式时初始化；之后只从真实系统环境回调更新。
    this.updateSystemColorMode(this.context.config.colorMode);
    try {
      this.context.getApplicationContext().onSystemConfigurationUpdated(this.systemConfigurationListener);
      this.systemConfigurationRegistered = true;
    } catch (error) {
      hilog.error(DOMAIN, TAG, '订阅系统颜色模式失败：%{public}s', String(error));
    }
    AppStorage.setOrCreate('planerForeground', Date.now());
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.prepareWindow(windowStage);
  }

  private async prepareWindow(windowStage: window.WindowStage): Promise<void> {
    try {
      this.mainWindow = windowStage.getMainWindowSync();
      // 内容铺到状态栏背后；可操作内容与固定标题各自避让，滚动内容不被顶部色块裁断。
      await this.mainWindow.setWindowLayoutFullScreen(true);
      this.mainWindow.on('avoidAreaChange', this.avoidAreaListener);
      this.updateSafeArea();
    } catch (error) {
      hilog.error(DOMAIN, TAG, '设置沉浸窗口失败：%{public}s', String(error));
    }
    windowStage.loadContent('pages/Index', (error): void => {
      if (error.code) {
        hilog.error(DOMAIN, TAG, '加载页面失败：%{public}s', JSON.stringify(error));
      }
    });
  }

  private updateSafeArea(): void {
    if (!this.mainWindow) return;
    try {
      const system = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const cutout = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const indicator = this.mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const density = display.getDefaultDisplaySync().densityPixels;
      AppStorage.setOrCreate('planerSafeTop', Math.max(system.topRect.height, cutout.topRect.height) / density);
      AppStorage.setOrCreate('planerSafeBottom', Math.max(system.bottomRect.height, indicator.bottomRect.height) / density);
    } catch (error) {
      hilog.error(DOMAIN, TAG, '读取系统安全区失败：%{public}s', String(error));
    }
  }

  onWindowStageDestroy(): void {
    try {
      this.mainWindow?.off('avoidAreaChange', this.avoidAreaListener);
    } catch (error) {
      hilog.error(DOMAIN, TAG, '注销安全区订阅失败：%{public}s', String(error));
    }
    this.mainWindow = undefined;
  }

  onForeground(): void {
    // 页面收到前台事件后按本地日期检查跨日，无需后台常驻或通知权限。
    AppStorage.setOrCreate('planerForeground', Date.now());
  }

  onDestroy(): void {
    if (!this.systemConfigurationRegistered) return;
    try {
      this.context.getApplicationContext().offSystemConfigurationUpdated(this.systemConfigurationListener);
      this.systemConfigurationRegistered = false;
    } catch (error) {
      hilog.error(DOMAIN, TAG, '注销系统颜色模式订阅失败：%{public}s', String(error));
    }
  }

  private updateSystemColorMode(colorMode: ConfigurationConstant.ColorMode | undefined): void {
    if (colorMode !== undefined && colorMode !== ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET) {
      AppStorage.setOrCreate('systemDark', colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } else if (!AppStorage.has('systemDark')) {
      AppStorage.setOrCreate('systemDark', false);
    }
  }
}