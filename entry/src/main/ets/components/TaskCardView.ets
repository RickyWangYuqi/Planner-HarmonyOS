import { Task } from '../model/PlanerModel';
import { formatRange, taskDelayText, todayKey } from '../model/PlanerEngine';
import { Palette } from '../theme/Theme';
import { Materials, Motion } from '../theme/Appearance';
import { IconButton } from './IconButton';
import { PlanerIcon } from './PlanerIcon';

// 列表与跟手浮层共用同一张卡片，拖动手势、定位及透明度交由宿主统一处理。
@Component
export struct TaskCardView {
  @Prop task: Task = new Task();
  @Prop order: number = 1;
  @Prop showNumber: boolean = false;
  @Prop showDefaultProgress: boolean = false;
  @Prop showDates: boolean = false;
  @Prop viewedDate: string = '';
  @Prop realDate: string = todayKey();
  @Prop palette: Palette = new Palette();
  @Prop dragged: boolean = false;
  @Prop preview: boolean = false;
  onToggle: () => void = (): void => {};
  onEdit: () => void = (): void => {};

  build() {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        if (this.task.completed) {
          PlanerIcon({ icon: 'check', color: Color.White, iconSize: 17 })
            .transition(Motion.reveal())
        }
      }
        .width(28).height(28).borderRadius(8)
        .backgroundColor(this.task.completed ? this.palette.accent : this.palette.panel)
        .border({ width: 1.5, color: this.task.completed ? this.palette.accent : this.palette.textFaint, radius: 8 })
        .margin({ left: 4, right: 8 }).padding(0)
        .responseRegion({ x: -8, y: -8, width: 44, height: 44 })
        .accessibilityText(this.task.completed ? '标记为未完成' : '标记为完成')
        .id((this.preview ? 'preview-check-' : 'check-') + this.task.id).onClick(() => this.onToggle())
      if (this.showNumber) {
        Text(this.order.toString()).fontSize(12).fontColor(this.palette.textSoft)
          .textAlign(TextAlign.Center).width(22).height(22).backgroundColor(this.palette.panel2).borderRadius(6)
      }
      Column({ space: 7 }) {
        Text(this.task.text).fontSize(15).lineHeight(22)
          .fontColor(this.task.completed ? this.palette.textFaint : this.palette.text)
          .decoration({ type: this.task.completed ? TextDecorationType.LineThrough : TextDecorationType.None })
          .width('100%').draggable(false)
        // 当日日程可能保留隐藏时间区间，是否显示日期须由所属分区明确传入。
        if (this.showDates && this.task.dueDate) {
          Text(formatRange(this.task.startDate, this.task.dueDate)).fontSize(11).fontColor(this.palette.accent)
            .padding({ left: 7, right: 7, top: 3, bottom: 3 }).backgroundColor(this.palette.accentSoft).borderRadius(6)
        }
        if (taskDelayText(this.task, this.viewedDate || this.realDate, this.realDate)) {
          Text(taskDelayText(this.task, this.viewedDate || this.realDate, this.realDate))
            .fontSize(11).fontWeight(FontWeight.Medium)
            .fontColor(taskDelayText(this.task, this.viewedDate || this.realDate, this.realDate).startsWith('预计') ? this.palette.accent : this.palette.danger)
            .padding({ left: 7, right: 7, top: 3, bottom: 3 }).borderRadius(7)
            .backgroundColor(taskDelayText(this.task, this.viewedDate || this.realDate, this.realDate).startsWith('预计') ? this.palette.accentSoft : this.palette.dangerSoft).id('task-delay-' + this.task.id)
        }
        if (!this.task.completed && (this.task.progress !== null || this.showDefaultProgress)) {
          Row({ space: 6 }) {
            Progress({ value: this.task.progress === null ? 0 : this.task.progress, total: 100, type: ProgressType.Linear })
              .width(65).color(this.palette.accent).backgroundColor(this.palette.border).style({ strokeWidth: 4 })
            Text((this.task.progress || 0).toString() + '%').fontSize(11).fontColor(this.palette.textSoft)
          }
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start).padding({ left: 3 })
      Row() {
        IconButton({ icon: 'edit', label: '编辑日程', palette: this.palette, onTap: () => this.onEdit() })
      }.id((this.preview ? 'preview-edit-' : 'edit-') + this.task.id)
    }.width('100%').padding({ left: 8, right: 2, top: 3, bottom: 3 })
      .backgroundColor(Materials.fallback(this.palette)).borderRadius(16)
      .backgroundBlurStyle(BlurStyle.COMPONENT_THIN, { colorMode: Materials.mode(this.palette) })
      .border({ width: this.dragged ? 1 : 0, color: this.palette.accent, style: BorderStyle.Dashed, radius: 16 })
  }
}