import { ColorMetrics } from '@kit.ArkUI';
import { common2D, drawing } from '@kit.ArkGraphics2D';

// 优先使用用户提供的 HarmonyOS 官方 SVG；其余符号来自 API 26 系统资源目录。
@Component
export struct PlanerIcon {
  @Prop icon: string = 'plus';
  @Prop color: ResourceColor = '#5d6f90';
  @Prop iconSize: number = 21;
  @Prop filled: boolean = false;

  private usesSymbol(): boolean {
    switch (this.icon) {
      case 'close':
      case 'back':
      case 'left':
      case 'right':
      case 'move':
      case 'restore':
      case 'check':
      case 'up':
      case 'down':
      case 'history':
        return true;
      default:
        return false;
    }
  }

  private mediaSource(): Resource {
    switch (this.icon) {
      case 'home': return this.filled ? $r('app.media.house_fill') : $r('app.media.house');
      case 'settings': return this.filled ? $r('app.media.gearshape_fill') : $r('app.media.gearshape');
      case 'calendar': return this.filled ? $r('app.media.calendar_fill') : $r('app.media.calendar');
      case 'edit': return this.filled ? $r('app.media.square_and_pencil_fill') : $r('app.media.square_and_pencil');
      case 'trash': return this.filled ? $r('app.media.trash_fill') : $r('app.media.trash');
      default: return $r('app.media.plus');
    }
  }

  private symbolSource(): Resource {
    switch (this.icon) {
      case 'close': return $r('sys.symbol.xmark');
      case 'back':
      case 'left': return $r('sys.symbol.chevron_left');
      case 'right': return $r('sys.symbol.chevron_right');
      case 'move': return $r('sys.symbol.arrow_left_arrow_right');
      case 'restore': return $r('sys.symbol.arrow_counterclockwise');
      case 'check': return $r('sys.symbol.checkmark');
      case 'up': return $r('sys.symbol.chevron_up');
      case 'down': return $r('sys.symbol.chevron_down');
      case 'history': return $r('sys.symbol.arrow_counterclockwise_clock');
      default: return $r('sys.symbol.plus');
    }
  }

  private imageTint(): drawing.ColorFilter | undefined {
    let tint = ColorMetrics.numeric(0xFF5D6F90);
    try {
      tint = ColorMetrics.resourceColor(this.color);
    } catch (error) {
      console.error('解析图标颜色失败：' + String(error));
    }
    // 官方 ResourceColor 重载同样使用 SRC_ATOP；显式 Drawing 滤镜兼容最低版本。
    // common2D.Color 各通道均为 0–255，避免把颜色通道误用作归一化矩阵偏移。
    const color: common2D.Color = {
      alpha: tint.alpha, red: tint.red, green: tint.green, blue: tint.blue
    };
    try {
      return drawing.ColorFilter.createBlendModeColorFilter(color, drawing.BlendMode.SRC_ATOP);
    } catch (error) {
      console.error('创建图标颜色滤镜失败：' + String(error));
      return undefined;
    }
  }

  build() {
    if (this.usesSymbol()) {
      SymbolGlyph(this.symbolSource())
        .fontSize(this.iconSize).fontColor([this.color])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .width(this.iconSize).height(this.iconSize)
        .accessibilityLevel('no')
    } else {
      // 在 SVG 解码后统一着色，保留官方素材 mask 的黑白镂空关系。
      Image(this.mediaSource())
        .width(this.iconSize).height(this.iconSize).objectFit(ImageFit.Contain)
        .supportSvg2(true).colorFilter(this.imageTint())
        .draggable(false).accessibilityLevel('no')
    }
  }
}
