// 按当前窗口 vp 宽度适配，分屏和旋转与设备类型采用同一规则。
export class ResponsiveLayout {
  static wide(width: number): boolean { return width >= 840; }
  static gutter(width: number): number { return width >= 600 ? 24 : 16; }
  static contentWidth(width: number): number { return ResponsiveLayout.wide(width) ? 1280 : 720; }
  static sheetWidth(width: number, editor: boolean): Dimension {
    if (width < 600) return '100%';
    return Math.min(width - 64, editor && ResponsiveLayout.wide(width) ? 920 : 600);
  }
  static editorColumns(width: number): boolean { return width >= 760; }
}

