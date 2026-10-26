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

const sectionMaterials: Map<string, uiMaterial.ImmersiveMaterial> = new Map();

export class Materials {
  static supported(): boolean {
    if (deviceInfo.apiAvailable('26.0.0')) {
      try {
        return uiMaterial.isImmersiveMaterialSupported() &&
          uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE;
      } catch (_) {
        return false;
      }
    }
    return false;
  }
  // 系统自动管理材质等级；低档不传赋色，避免透明值覆盖系统自带的可读背板。
  static adaptiveTint(tint: ResourceColor): ResourceColor | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      try {
        return uiMaterial.getGlobalMaterialLevel() === uiMaterial.MaterialLevel.SMOOTH ? undefined : tint;
      } catch (_) {
        return undefined;
      }
    }
    return undefined;
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
      if (Materials.supported()) {
        return new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          materialColor: Materials.adaptiveTint('#12' + palette.accent.substring(1)),
          interactive: true, lightEffect: {}, applyShadow: true
        });
      }
    }
    return undefined;
  }
  static dialog(palette: Palette): uiMaterial.ImmersiveMaterial | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (Materials.supported()) {
        return new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR,
          materialColor: Materials.adaptiveTint('#40' + palette.panel.substring(1)),
          interactive: false, lightEffect: {}, applyShadow: true
        });
      }
    }
    return undefined;
  }
  static button(palette: Palette): uiMaterial.ImmersiveMaterial | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (Materials.supported()) {
        return new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
          materialColor: Materials.adaptiveTint(Color.Transparent),
          interactive: true, lightEffect: {}, applyShadow: true
        });
      }
    }
    return undefined;
  }
  static input(palette: Palette): ResourceColor {
    // 输入区使用更实的内凹底色，与外层通透材质形成清晰对比。
    const color = Materials.mode(palette) === ThemeColorMode.DARK ? palette.bg : palette.bgSoft;
    return '#F2' + color.substring(1);
  }
  static section(palette: Palette, danger: boolean = false): uiMaterial.ImmersiveMaterial | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (Materials.supported()) {
        const color = danger ? palette.dangerSoft : palette.panel;
        const tint = Materials.adaptiveTint((danger ? '#24' : '#40') + color.substring(1));
        const key = tint === undefined ? 'system-default' : String(tint);
        let material = sectionMaterials.get(key);
        if (material === undefined) {
          material = new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.REGULAR, materialColor: tint,
            interactive: false, lightEffect: null, applyShadow: false
          });
          sectionMaterials.set(key, material);
        }
        return material;
      }
    }
    return undefined;
  }
  static sectionShadow(palette: Palette): ShadowOptions {
    const dark = Materials.mode(palette) === ThemeColorMode.DARK;
    // 阴影只属于正在变高的圆角节点，不让原生材质按旧标题范围保留投影。
    return { radius: dark ? 16 : 14, offsetX: 0, offsetY: dark ? 5 : 4,
      color: dark ? '#60000000' : '#18' + palette.text.substring(1), fill: false };
  }
  // 原生 SheetPage 会把中档额外降为低档；中低档改由内容中的通用材质背板承载。
  static sheetUsesContentSurface(): boolean {
    if (deviceInfo.apiAvailable('26.0.0') && Materials.supported()) {
      try {
        return uiMaterial.getGlobalMaterialLevel() !== uiMaterial.MaterialLevel.EXQUISITE;
      } catch (_) {
        return true;
      }
    }
    return false;
  }
  // 面板只跟随明暗使用中性底色，不叠加配色预设的主题色。
  static sheetColor(palette: Palette): string {
    return Materials.mode(palette) === ThemeColorMode.DARK ? '#202020' : '#ffffff';
  }
  // 高档保留半模态厚度；内容背板继续使用超薄样式，低档保留系统默认背板。
  // 设备等级只读，不强制提档，也不另叠毛玻璃。
  static sheetMaterial(palette: Palette): uiMaterial.ImmersiveMaterial | undefined {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (Materials.supported()) {
        let toolbarStyle = true;
        try {
          toolbarStyle = uiMaterial.getGlobalMaterialLevel() !== uiMaterial.MaterialLevel.EXQUISITE;
        } catch (_) {
          // 等级不可读时使用更轻的系统样式，赋色查询失败也交由系统提供默认值。
        }
        return new uiMaterial.ImmersiveMaterial({
          style: toolbarStyle ? uiMaterial.ImmersiveStyle.ULTRA_THIN : uiMaterial.ImmersiveStyle.REGULAR,
          materialColor: Materials.adaptiveTint('#90' + Materials.sheetColor(palette).substring(1)),
          interactive: false, lightEffect: {}, applyShadow: true
        });
      }
    }
    return undefined;
  }
  static sheet(palette: Palette, options: SheetOptions): SheetOptions {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (Materials.sheetUsesContentSurface()) {
        // 不传 Material.empty：原生 Sheet 更新主题时仍会将它视为材质并回填纯色。
        // 明确的透明色和无模糊关闭默认背板，真正材质位于 SheetMaterialSurface。
        options.systemMaterial = undefined;
        options.backgroundColor = Color.Transparent;
        options.blurStyle = BlurStyle.NONE;
        return options;
      }
      const material = Materials.sheetMaterial(palette);
      if (material !== undefined) {
        // 高档由原生背板独占材质，不混用背景色与模糊参数。
        options.backgroundColor = undefined;
        options.blurStyle = undefined;
        options.systemMaterial = material;
        return options;
      }
      // 应用关闭材质或设备不支持时，清除旧材质，防止沿用上次半透明配置。
      options.systemMaterial = uiMaterial.Material.empty;
    }
    options.backgroundColor = Materials.sheetColor(palette);
    options.blurStyle = BlurStyle.NONE;
    return options;
  }
  static confirmation(palette: Palette, options: promptAction.ShowDialogOptions): promptAction.ShowDialogOptions {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (Materials.supported()) {
        options.systemMaterial = Materials.dialog(palette);
      }
    }
    return options;
  }
}

// 分区材质背板位于 MaterialSection 的标题作用域，真实正文独立自然布局。
// 原生背板的阴影独立绘制，避免旧标题范围在收起时拖尾；回退仍使用自身普通阴影。
export class EditorSectionModifier implements AttributeModifier<ColumnAttribute> {
  private palette: Palette;
  private danger: boolean;
  constructor(palette: Palette, danger: boolean = false) {
    this.palette = palette; this.danger = danger;
  }
  applyNormalAttribute(instance: ColumnAttribute): void {
    instance.borderRadius(18);
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (Materials.supported()) {
        instance.backgroundColor(Color.Transparent).border({ width: 0, radius: 18 });
        instance.systemMaterial(Materials.section(this.palette, this.danger))
          // 阴影由 MaterialSection 的独立圆角节点绘制，不留在原生标题裁切区中。
          .shadow({ radius: 0, color: Color.Transparent });
        return;
      }
      instance.systemMaterial(uiMaterial.Material.empty);
    }
    const dark = Materials.mode(this.palette) === ThemeColorMode.DARK;
    const color = this.danger ? this.palette.dangerSoft : this.palette.panel;
    const alpha = this.danger ? '#42' : (dark ? '#CC' : '#B8');
    instance.borderRadius(18)
      .backgroundColor(alpha + color.substring(1))
      .border({ width: 1, radius: 18, color: dark ? '#22FFFFFF' : '#B3' + color.substring(1) })
      .shadow(Materials.sectionShadow(this.palette));
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
// 按钮须在 MaterialButtonScope 的原生标题作用域内应用；先清除 Button 默认强调色。
// 按压反馈独立于 Button 默认着色层；业务跳转前清空状态，避免缺少释放事件时残留。
export class ButtonFeedback {
  static next(currentId: string, buttonId: string, type: TouchType): string {
    if (type === TouchType.Down) return buttonId;
    if ((type === TouchType.Up || type === TouchType.Cancel) && currentId === buttonId) return '';
    return currentId;
  }
  static scale(currentId: string, buttonId: string): number { return currentId === buttonId ? 0.97 : 1; }
}

const controlMaterials: Map<string, uiMaterial.ImmersiveMaterial> = new Map();
export class PlanerControlModifier implements AttributeModifier<ButtonAttribute> {
  private palette: Palette;
  private selected: boolean;
  private danger: boolean;
  private active: boolean;
  private outline: BorderStyle | undefined;
  constructor(palette: Palette, selected: boolean = false, danger: boolean = false, active: boolean = true,
    outline: BorderStyle | undefined = undefined) {
    this.palette = palette; this.selected = selected; this.danger = danger; this.active = active;
    this.outline = outline;
  }
  applyNormalAttribute(instance: ButtonAttribute): void {
    if (!this.active) {
      if (deviceInfo.apiAvailable('26.0.0')) instance.systemMaterial(uiMaterial.Material.empty);
      instance.backgroundColor(Color.Transparent);
      return;
    }
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (Materials.supported()) {
        const color = this.danger ? this.palette.danger : (this.selected ? this.palette.accent : this.palette.panel);
        // 普通按钮不再叠白色赋色，超薄原生材质直接采样后方内容；强调态仅轻染主题色。
        const alpha = this.outline === undefined ? '#18' : '#2A';
        const tint = Materials.adaptiveTint(this.selected || this.danger ? alpha + color.substring(1) : '#00000000');
        // 低档的 undefined 和高档的透明色使用不同缓存键，避免复用透明背板。
        const key = tint === undefined ? 'system-default' : String(tint);
        let material = controlMaterials.get(key);
        if (material === undefined) {
          material = new uiMaterial.ImmersiveMaterial({
            style: uiMaterial.ImmersiveStyle.ULTRA_THIN, materialColor: tint,
            interactive: true, lightEffect: {}, applyShadow: true
          });
          controlMaterials.set(key, material);
        }
        // 标签仅使用系统材质的一套高光轮廓，不在容器外再描边。
        if (this.outline !== undefined) instance.border({ width: 0, radius: 12 });
        instance.backgroundColor(Color.Transparent);
        instance.systemMaterial(material);
        return;
      }
    }
    if (deviceInfo.apiAvailable('26.0.0')) instance.systemMaterial(uiMaterial.Material.empty);
    instance.backgroundColor(Materials.inset(this.palette, this.selected, this.danger));
    // 不支持沉浸材质时，轮廓画在真实按钮上，与按钮尺寸和圆角完全一致。
    if (this.outline !== undefined) {
      instance.border({ width: 1, radius: 12, style: this.outline,
        color: this.danger ? this.palette.danger : (this.selected ? this.palette.accent : this.palette.border) });
    }
  }
}
