import { Task } from '../model/PlanerModel';
import { Palette } from '../theme/Theme';
import { GroupDragPreview } from './GroupDragPreview';
import { TaskCardView } from './TaskCardView';

// 位置描述可见裁片，完整卡片只裁切、不改宽度，避免收拢过程中重新换行。
export class GroupDragMember {
  task: Task = new Task();
  order: number = 1;
  depth: number = 0;
  x: number = 0;
  y: number = 0;
  width: number = 1;
  height: number = 1;
  clipTop: number = 0;
  visibleHeight: number = 1;
  visible: boolean = true;

  private boundedProgress(progress: number): number {
    return Number.isNaN(progress) ? 0 : Math.max(0, Math.min(1, progress));
  }

  private safeWidth(): number {
    return Number.isFinite(this.width) && this.width > 0 ? this.width : 1;
  }

  private stackDepth(): number {
    return Number.isFinite(this.depth) ? Math.max(0, Math.min(2, this.depth)) : 0;
  }

  scaleAt(progress: number): number {
    const visibleHeight = Number.isFinite(this.visibleHeight) && this.visibleHeight > 0 ? this.visibleHeight : 1;
    const folded = Math.min(1, 252 / this.safeWidth(), 60 / visibleHeight);
    const value = this.boundedProgress(progress);
    return (1 - value) + folded * value;
  }

  leftAt(progress: number): number {
    // 不再可见的成员停留在收拢位置消失，不向过期源坐标飞回。
    const value = this.visible ? this.boundedProgress(progress) : 1;
    const start = Number.isFinite(this.x) ? this.x : 0;
    const folded = (272 - this.safeWidth() * this.scaleAt(1)) / 2 + this.stackDepth() * 4;
    return start * (1 - value) + folded * value;
  }

  topAt(progress: number): number {
    const value = this.visible ? this.boundedProgress(progress) : 1;
    const start = Number.isFinite(this.y) ? this.y : 0;
    const folded = 10 + this.stackDepth() * 6;
    return start * (1 - value) + folded * value;
  }

  opacityAt(progress: number): number {
    return this.visible ? 1 - this.boundedProgress(progress) : 0;
  }
}

// 宿主控制唯一进度；组件只投影几何，不添加独立动画或整层淡入淡出。
@Component
export struct GroupDragVisual {
  @Prop groupName: string = '';
  @Prop tasks: Task[] = [];
  @Prop members: GroupDragMember[] = [];
  @Prop palette: Palette = new Palette();
  @Prop progress: number = 0;
  @Prop showNumber: boolean = false;
  @Prop showDefaultProgress: boolean = false;
  @Prop showDates: boolean = false;
  @Prop viewedDate: string = '';
  @Prop realDate: string = '';

  private currentMember(id: string): GroupDragMember {
    const member = this.members.find((item: GroupDragMember): boolean => item.task.id === id);
    if (member) return member;
    const missing = new GroupDragMember();
    missing.visible = false;
    return missing;
  }

  private summaryHeight(): number {
    const count = Math.min(this.tasks.length, 2);
    return 52 + (count > 0 ? 10 + count * 18 + (count - 1) * 6 : 0) +
      (this.tasks.length > 2 ? 24 : 0) + 10;
  }

  private summaryOpacity(): number {
    return Number.isNaN(this.progress) ? 0 : Math.max(0, Math.min(1, this.progress));
  }

  @Builder
  private memberCard(id: string) {
    Stack({ alignContent: Alignment.TopStart }) {
      TaskCardView({ task: this.currentMember(id).task, order: this.currentMember(id).order,
        showNumber: this.showNumber, showDefaultProgress: this.showDefaultProgress,
        showDates: this.showDates, viewedDate: this.viewedDate, realDate: this.realDate, palette: this.palette, preview: true })
        .width(this.currentMember(id).width).height(this.currentMember(id).height)
        .translate({ y: -this.currentMember(id).clipTop })
    }.width(this.currentMember(id).width).height(this.currentMember(id).visibleHeight).clip(true)
      .scale({ x: this.currentMember(id).scaleAt(this.progress), y: this.currentMember(id).scaleAt(this.progress),
        centerX: 0, centerY: 0 })
      .position({ x: this.currentMember(id).leftAt(this.progress), y: this.currentMember(id).topAt(this.progress) })
      .opacity(this.currentMember(id).opacityAt(this.progress))
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 只捕获稳定任务标识，后续状态计算始终查询最新成员，避免保留旧几何对象。
      ForEach(this.members, (member: GroupDragMember) => {
        this.memberCard(member.task.id)
      }, (member: GroupDragMember): string => member.task.id)
      GroupDragPreview({ groupName: this.groupName, tasks: this.tasks, palette: this.palette })
        .opacity(this.summaryOpacity())
    }.width(272).height(this.summaryHeight()).clip(false)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
  }
}