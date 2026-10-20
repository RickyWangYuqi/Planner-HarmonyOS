import { Task } from '../model/PlanerModel';
import { Palette } from '../theme/Theme';
import { PlanerIcon } from './PlanerIcon';

// 拖拽预览离屏生成，使用明确尺寸与纯色卡片，不依赖窗口或异步材质。
@Component
export struct GroupDragPreview {
  @Prop groupName: string = '';
  @Prop tasks: Task[] = [];
  @Prop palette: Palette = new Palette();

  private visibleTasks(): Task[] {
    return this.tasks.slice(0, 2);
  }

  private cardHeight(): number {
    const count = Math.min(this.tasks.length, 2);
    return 52 + (count > 0 ? 10 + count * 18 + (count - 1) * 6 : 0) +
      (this.tasks.length > 2 ? 24 : 0);
  }

  @Builder
  private summary(task: Task) {
    Row({ space: 8 }) {
      Stack() {
        if (task.completed) {
          PlanerIcon({ icon: 'check', color: this.palette.success, iconSize: 12 })
        } else {
          Row().width(6).height(6).borderRadius(2).backgroundColor(this.palette.textFaint)
        }
      }.width(14).height(18)
      Text(task.text).fontSize(12).lineHeight(18).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        .fontColor(task.completed ? this.palette.textFaint : this.palette.textSoft)
        .decoration({ type: task.completed ? TextDecorationType.LineThrough : TextDecorationType.None,
          color: this.palette.textFaint })
    }.width('100%').height(18)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 轻微错位保留整组的层次感，避免旋转或模糊影响预览截图。
      Row().width(252).height(this.cardHeight() - 4)
        .backgroundColor(this.palette.accentSoft)
        .border({ width: 1, color: this.palette.border, radius: 16 })
        .position({ x: 12, y: 12 })
      Row().width(256).height(this.cardHeight() - 2)
        .backgroundColor(this.palette.panel2)
        .border({ width: 1, color: this.palette.border, radius: 16 })
        .position({ x: 6, y: 6 })
      Column() {
        Row({ space: 8 }) {
          Row().width(4).height(16).borderRadius(2).backgroundColor(this.palette.accent)
          Text(this.groupName || '未分组').fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor(this.palette.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(`${this.tasks.length} 项`).fontSize(11).fontWeight(FontWeight.Medium)
            .fontColor(this.palette.accent).height(22).textAlign(TextAlign.Center)
            .padding({ left: 8, right: 8 }).backgroundColor(this.palette.accentSoft).borderRadius(8)
        }.width('100%').height(24)
        if (this.tasks.length > 0) {
          Column({ space: 6 }) {
            ForEach(this.visibleTasks(), (task: Task) => {
              this.summary(task)
            }, (task: Task): string => task.id)
          }.width('100%').margin({ top: 10 })
        }
        if (this.tasks.length > 2) {
          Text(`另有 ${this.tasks.length - 2} 项`).fontSize(11).lineHeight(16).height(16)
            .fontColor(this.palette.textFaint).width('100%').padding({ left: 22 }).margin({ top: 8 })
        }
      }.width(260).height(this.cardHeight()).padding(14).alignItems(HorizontalAlign.Start)
        .backgroundColor(this.palette.panel)
        .border({ width: 1, color: this.palette.border, radius: 16 })
    }.width(272).height(this.cardHeight() + 10)
      .hitTestBehavior(HitTestMode.None).accessibilityLevel('no-hide-descendants')
  }
}