import { curves, uiMaterial, promptAction } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Palette } from './Theme';

// 位移使用弹簧；颜色渐变不使用过冲，避免文字对比度突然变化。
export class Motion {
  static springCurve(): ICurve { return curves.springMotion(0.38, 0.84, 0.12); }
  static spring(): AnimateParam { return { curve: Motion.springCurve() }; }
  static quick(): AnimateParam { return { curve: curves.springMotion(0.24, 0.88, 0.08) }; }
  static drag(): AnimateParam { return { curve: curves.springMotion(0.22, 0.9, 0.08) }; }
  static theme(): AnimateParam {
    return { duration: 360, curve: curves.cubicBezierCurve(0.22, 0.0, 0.15, 1.0) };
  }
  static reveal(): TransitionEffect {
    return TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 10 }))
      .combine(TransitionEffect.scale({ x: 0.97, y: 0.97 })).animation(Motion.spring());
  }
}

export class Materials {
  static supported(): boolean {
    if (deviceInfo.apiAvailable('26.0.0')) {
      return uiMaterial.isImmersiveMaterialSupported();
    }
    return false;
  }
  static mode(palette: Palette): ThemeColorMode {
    return parseInt(palette.bg.substring(1, 3), 16) < 100 ? ThemeColorMode.DARK : ThemeColorMode.LIGHT;
  }
  static fallback(palette: Palette, selected: boolean = false, danger: boolean = false): ResourceColor {
    const color = danger ? palette.dangerSoft : (selected ? palette.accentSoft : palette.panel);
    return '#B8' + color.substring(1);
  }
  // 原生弹层内部只叠轻色，不再叠加毛玻璃采样。
  static inset(palette: Palette, selected: boolean = false, danger: boolean = false): ResourceColor {
    const color = danger ? palette.dangerSoft : (selected ? palette.accentSoft : palette.panel);
    return (selected || danger ? '#80' : '#65') + color.substring(1);
  }
  static toolbar(palette: Palette): uiMaterial.ImmersiveMaterial | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (uiMaterial.isImmersiveMaterialSupported()) {
        return new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          materialColor: '#12' + palette.accent.substring(1),
          interactive: true, lightEffect: {}, applyShadow: true
        });
      }
    }
    return undefined;
  }
  static dialog(palette: Palette): uiMaterial.ImmersiveMaterial | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (uiMaterial.isImmersiveMaterialSupported()) {
        return new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR,
          materialColor: '#40' + palette.panel.substring(1),
          interactive: false, lightEffect: {}, applyShadow: true
        });
      }
    }
    return undefined;
  }
  static button(palette: Palette): uiMaterial.ImmersiveMaterial | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (uiMaterial.isImmersiveMaterialSupported()) {
        return new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THIN,
          materialColor: '#10' + palette.panel.substring(1),
          interactive: true, lightEffect: {}, applyShadow: true
        });
      }
    }
    return undefined;
  }
  static sheet(palette: Palette, options: SheetOptions): SheetOptions {
    // 旧系统使用纯色可读回退，不调用或叠加新材质和毛玻璃。
    options.backgroundColor = palette.panel;
    options.blurStyle = BlurStyle.NONE;
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (uiMaterial.isImmersiveMaterialSupported()) {
        options.backgroundColor = Color.Transparent;
        options.systemMaterial = Materials.dialog(palette);
      }
    }
    return options;
  }
  static confirmation(palette: Palette, options: promptAction.ShowDialogOptions): promptAction.ShowDialogOptions {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (uiMaterial.isImmersiveMaterialSupported()) {
        options.systemMaterial = Materials.dialog(palette);
      }
    }
    return options;
  }
}

// 新版原生悬浮底栏；旧版系统保持可用的普通底栏。
export class PlanerTabsModifier implements AttributeModifier<TabsAttribute> {
  private palette: Palette;
  private safeBottom: number = 0;
  constructor(palette: Palette, safeBottom: number = 0) { this.palette = palette; this.safeBottom = Math.max(0, safeBottom); }
  applyNormalAttribute(instance: TabsAttribute): void {
    if (deviceInfo.apiAvailable('26.0.0')) {
      instance.barFloatingStyle({
        barSideMargin: 24, barBottomMargin: 12 + this.safeBottom,
        barWidth: { smallBarWidth: 232, mediumBarWidth: 280, largeBarWidth: 320 },
        maskHeight: 0, systemMaterial: Materials.toolbar(this.palette)
      });
    } else {
      instance.barBackgroundColor(this.palette.panel).barHeight(64).barBackgroundBlurStyle(BlurStyle.NONE);
    }
  }
}