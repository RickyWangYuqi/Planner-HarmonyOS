// 配色与桌面 themes.css 对齐；尺寸使用 vp，文字使用 sp。
export class Palette {
  bg: string = '#eef3fa';
  bgSoft: string = '#e2eaf6';
  panel: string = '#ffffff';
  panel2: string = '#f6f9fe';
  text: string = '#1e2b45';
  textSoft: string = '#5d6f90';
  textFaint: string = '#97a6c2';
  accent: string = '#2e7cf6';
  accentStrong: string = '#1e63d8';
  accentSoft: string = '#dce9ff';
  border: string = '#dde6f2';
  danger: string = '#e5484d';
  dangerSoft: string = '#fde8e9';
  success: string = '#1fa971';
  successSoft: string = '#def3ea';

  constructor(colors?: string[]) {
    if (!colors || colors.length !== 15) return;
    this.bg = colors[0];
    this.bgSoft = colors[1];
    this.panel = colors[2];
    this.panel2 = colors[3];
    this.text = colors[4];
    this.textSoft = colors[5];
    this.textFaint = colors[6];
    this.accent = colors[7];
    this.accentStrong = colors[8];
    this.accentSoft = colors[9];
    this.border = colors[10];
    this.danger = colors[11];
    this.dangerSoft = colors[12];
    this.success = colors[13];
    this.successSoft = colors[14];
  }
}

export function paletteFor(preset: string, dark: boolean): Palette {
  if (preset === 'forest') {
    return new Palette(dark ?
      ['#0e1712', '#132017', '#17281e', '#1c3124', '#e6f3ea', '#92ab9a', '#5d7466', '#46c07d', '#5fd495', '#1d3a2b', '#25392c', '#f2555a', '#3a2025', '#46c07d', '#1b3a2e'] :
      ['#f1f7f0', '#e4efe2', '#ffffff', '#f5faf4', '#20342a', '#58705f', '#8ba391', '#2f9e5f', '#1f8a4d', '#d9f0e0', '#dce9dd', '#e5484d', '#fde8e9', '#2f9e5f', '#d9f0e0']);
  }
  if (preset === 'sunset') {
    return new Palette(dark ?
      ['#1a1210', '#211612', '#2a1b15', '#33211a', '#fbeae2', '#c29a8a', '#8a6555', '#ff7a55', '#ff9677', '#452720', '#3d2820', '#f2555a', '#3a2025', '#34c97c', '#1b3a2e'] :
      ['#fdf4ee', '#f8e8dd', '#ffffff', '#fff8f3', '#3b2a23', '#7c6357', '#b09a8e', '#f05f3c', '#d94c2c', '#ffe4d7', '#f0ded3', '#e5484d', '#fde8e9', '#1fa971', '#def3ea']);
  }
  if (preset === 'ink') {
    return new Palette(dark ?
      ['#131318', '#181820', '#1e1e28', '#242432', '#ededf5', '#9a9ab0', '#63637c', '#8f83f5', '#a69cff', '#2a2745', '#2c2c3a', '#f2555a', '#3a2025', '#34c97c', '#1b3a2e'] :
      ['#f5f5f8', '#ececf1', '#ffffff', '#f8f8fb', '#26263a', '#66667f', '#9b9bb0', '#6d5df0', '#5a49e0', '#e5e1fc', '#e3e3ec', '#e5484d', '#fde8e9', '#1fa971', '#def3ea']);
  }
  return dark ? new Palette(['#0e1524', '#131c30', '#18233b', '#1d2a47', '#e7eefb', '#93a4c6', '#5f7093', '#4d94ff', '#6ba7ff', '#213252', '#26334f', '#f2555a', '#3a2025', '#34c97c', '#1b3a2e']) : new Palette();
}
