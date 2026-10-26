import { FrameCallback, UIContext, uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Palette } from '../theme/Theme';
import { EditorSectionModifier, Materials, Motion } from '../theme/Appearance';

let sectionSequence: number = 0;

class SectionRefreshFrame extends FrameCallback {
  private refresh: () => void;
  constructor(refresh: () => void) { super(); this.refresh = refresh; }
  onFrame(): void { this.refresh(); }
}

class EditorMaterialTarget {
  context: UIContext;
  viewportId: string;
  constructor(context: UIContext, viewportId: string) {
    this.context = context;
    this.viewportId = viewportId;
  }
}

// 同一帧合并分区重绘，让滚动、键盘避让和半模态移动后的采样位置同步。
export class EditorMaterialRefresh {
  private static targets: Map<string, EditorMaterialTarget> = new Map();
  private static queued: boolean = false;
  static register(context: UIContext, id: string, viewportId: string = 'task-editor-scroll'): void {
    EditorMaterialRefresh.targets.set(id, new EditorMaterialTarget(context, viewportId));
    EditorMaterialRefresh.request(context);
  }
  static unregister(id: string): void { EditorMaterialRefresh.targets.delete(id); }
  static request(context: UIContext): void {
    if (EditorMaterialRefresh.queued || EditorMaterialRefresh.targets.size === 0) return;
    EditorMaterialRefresh.queued = true;
    context.postFrameCallback(new SectionRefreshFrame((): void => {
      EditorMaterialRefresh.queued = false;
      EditorMaterialRefresh.targets.forEach((entry: EditorMaterialTarget, id: string): void => {
        // 每个分区跟随所属表单，不能让打卡页依赖并不存在的日程编辑滚动节点。
        const target = entry.context;
        const viewport = target.getFrameNodeById(entry.viewportId);
        if (!viewport || !viewport.isAttached() || !viewport.isVisible()) return;
        const origin = viewport.getPositionToWindowWithTransform();
        const viewportHeight = target.px2vp(viewport.getMeasuredSize().height);
        const node = target.getFrameNodeById(id);
        if (!node || !node.isAttached() || !node.isVisible()) return;
        const top = node.getPositionToWindowWithTransform().y;
        const height = target.px2vp(node.getMeasuredSize().height);
        if (height > 0 && top < origin.y + viewportHeight && top + height > origin.y) node.invalidate();
      });
    }));
  }
}

// 正文决定高度，绝对定位的原生背板只单向跟随正文尺寸。
// 不使用自定义 background 子树：Navigation 标题在该离屏背景内不能可靠绘制材质。
@Component
export struct MaterialSection {
  @BuilderParam content: () => void;
  @Prop palette: Palette = new Palette();
  @Prop danger: boolean = false;
  @Prop viewportId: string = 'task-editor-scroll';
  @State private surfaceHeight: number = 1;
  @State private scopeHeight: number = 1;
  private surfaceReady: boolean = false;
  private surfaceRevision: number = 0;
  private surfaceActive: boolean = true;
  private surfaceId: string = 'editor-material-' + (++sectionSequence).toString();

  aboutToAppear(): void {
    if (Materials.supported()) EditorMaterialRefresh.register(this.getUIContext(), this.surfaceId, this.viewportId);
  }
  aboutToDisappear(): void {
    this.surfaceActive = false;
    this.surfaceRevision++;
    EditorMaterialRefresh.unregister(this.surfaceId);
  }

  private updateSurfaceHeight(height: number): void {
    if (!Number.isFinite(height) || height <= 0 || Math.abs(height - this.surfaceHeight) <= 0.1) return;
    if (!this.surfaceReady) {
      // 首次布局直接就位，不能把半模态入场再变成一次从 1vp 开始的展开。
      this.surfaceReady = true;
      this.scopeHeight = height;
      this.surfaceHeight = height;
    } else {
      const revision = ++this.surfaceRevision;
      // 标题高度自身不会连续插值。先保留足够的裁切范围，避免收起时提前截断材质。
      this.scopeHeight = Math.max(this.scopeHeight, height);
      const animation = Motion.spring();
      animation.onFinish = (): void => {
        if (!this.surfaceActive || revision !== this.surfaceRevision) return;
        this.scopeHeight = height;
        EditorMaterialRefresh.request(this.getUIContext());
      };
      // 尺寸回调已离开正文动画闭包；在这里接续同一弹簧，仅材质轮廓参与高度动画。
      this.getUIContext().animateTo(animation, (): void => { this.surfaceHeight = height; });
    }
    EditorMaterialRefresh.request(this.getUIContext());
  }

  private titleOptions(): NavigationTitleOptions {
    const options: NavigationTitleOptions = {
      backgroundColor: Color.Transparent, backgroundBlurStyle: BlurStyle.NONE
    };
    if (deviceInfo.apiAvailable('26.0.0')) options.systemMaterial = uiMaterial.Material.empty;
    return options;
  }

  @Builder
  private surfaceContent(palette: Palette, danger: boolean) {
    Column() {
      Column() {}
        .id(this.surfaceId).width('100%').height(this.surfaceHeight)
        .attributeModifier(new EditorSectionModifier(palette, danger))
    }.width('100%').height(this.scopeHeight).justifyContent(FlexAlign.Start)
  }

  @Builder
  private materialBackdrop(palette: Palette, danger: boolean) {
    WithTheme({ colorMode: Materials.mode(palette) }) {
      Navigation() {}
        .title({ builder: () => { this.surfaceContent(palette, danger); }, height: this.scopeHeight }, this.titleOptions())
        .titleMode(NavigationTitleMode.Mini).hideBackButton(true).hideToolBar(true)
        .mode(NavigationMode.Stack).width('100%').height(this.scopeHeight)
        .backgroundColor(Color.Transparent).borderRadius(18).clip(true)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
    }
  }

  build() {
    if (Materials.supported()) {
      Column() {
        // 阴影位于原生标题裁切区之外，只跟随实际背板高度，不跟随 scopeHeight。
        // fill:false 不染黑材质内部；父容器不裁切，展开与收起都有完整柔和投影。
        Column() {}
          .id(this.surfaceId + '-shadow').width('100%').height(this.surfaceHeight).borderRadius(18)
          .backgroundColor(Color.Transparent).shadow(Materials.sectionShadow(this.palette))
          .position({ x: 0, y: 0 }).zIndex(0)
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
        // Column 中 position 子节点不占位，因此旧背板高度不会阻止正文展开或收起。
        Column() {
          this.materialBackdrop(this.palette, this.danger)
        }.width('100%').height(this.scopeHeight).position({ x: 0, y: 0 })
          .zIndex(1).hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
        Column() {
          this.content()
        }.width('100%').zIndex(2)
          .onSizeChange((_old: SizeOptions, size: SizeOptions): void => {
            this.updateSurfaceHeight(Number(size.height));
          })
      }.width('100%').borderRadius(18).clip(false)
    } else {
      Column() {
        this.content()
      }.width('100%').attributeModifier(new EditorSectionModifier(this.palette, this.danger))
    }
  }
}
