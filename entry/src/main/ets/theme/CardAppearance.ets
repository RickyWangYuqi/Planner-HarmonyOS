import { Palette } from './Theme';

export class CardGradient {
  start: string;
  middle: string;
  end: string;
  constructor(start: string, middle: string, end: string) {
    this.start = start; this.middle = middle; this.end = end;
  }
}

function blendChannel(base: string, tint: string, offset: number, weight: number): string {
  const first = parseInt(base.substring(offset, offset + 2), 16);
  const second = parseInt(tint.substring(offset, offset + 2), 16);
  return Math.round(first + (second - first) * weight).toString(16).padStart(2, '0');
}

function blend(base: string, tint: string, weight: number): string {
  // 不透明渐变可隔离壁纸明暗，保证同一主题在不同桌面背景下仍有一致对比度。
  return '#FF' + blendChannel(base, tint, 1, weight) + blendChannel(base, tint, 3, weight) +
    blendChannel(base, tint, 5, weight);
}

// 轻底色占据主要阅读区，主题柔色集中在右下方；深色只提升色相层次，避免发亮。
export function cardGradient(palette: Palette, dark: boolean): CardGradient {
  return new CardGradient(blend(palette.panel, palette.accentSoft, 0.02),
    blend(palette.panel, palette.accentSoft, dark ? 0.38 : 0.30),
    blend(palette.panel, palette.accentSoft, 1.0));
}

// 更明显的浅色渐变搭配略深的辅助文字，不改变全应用色板或深色正文。
export function cardSecondaryColor(palette: Palette, dark: boolean): string {
  return dark ? palette.textSoft : '#' + blend(palette.textSoft, palette.text, 0.12).substring(3);
}
