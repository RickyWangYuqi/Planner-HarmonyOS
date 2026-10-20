import { HdsNavigation, HdsNavigationTitleMode, HdsNavigationTitleBarStyle, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { Task, AppData, HistoryEntry } from '../model/PlanerModel';
import { formatFull } from '../model/PlanerEngine';
import { Palette } from '../theme/Theme';
import { IconButton } from './IconButton';
import { PlanerIcon } from './PlanerIcon';
import { HistoryBackButton } from './HistoryBackButton';
import { Motion, Materials } from '../theme/Appearance';

@Component
export struct HistoryView {
  @StorageProp('planerSafeTop') safeTop: number = 0;
  @Prop data: AppData = new AppData();
  @Prop palette: Palette = new Palette();
  @State private viewportHeight: number = 500;
  scroller: Scroller = new Scroller();
  onBack: () => void = () => {};
  onRestore: (task: Task, date: string) => void = () => {};
  onDelete: (task: Task, date: string) => void = () => {};
  onClear: () => void = () => {};

  private entries(): HistoryEntry[] {
    return this.data.history.slice().sort((a: HistoryEntry, b: HistoryEntry): number => a.date < b.date ? 1 : -1);
  }

  private tasksAt(date: string): Task[] {
    const entry = this.data.history.find((item: HistoryEntry): boolean => item.date === date);
    return entry ? entry.tasks : [];
  }

  private headerStyle(): HdsNavigationTitleBarStyle {
    return {
      backgroundStyle: { backgroundColor: Color.Transparent },
      contentStyle: { titleStyle: { mainTitleColor: this.palette.text } }
    };
  }

  @Builder
  private fixedHeader() {
    Row({ space: 10 }) {
      HistoryBackButton({ palette: this.palette, onBack: () => this.onBack() })
      Text('历史日程').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.palette.text).layoutWeight(1)
        .id('history-title')
      if (this.data.history.length > 0) {
        Button('清空历史', { type: ButtonType.Normal }).fontSize(13).height(44)
          .backgroundColor(Materials.fallback(this.palette, false, true)).fontColor(this.palette.danger).borderRadius(12)
          .onClick(() => this.onClear()).id('clear-history')
      }
    }.width('100%').height(56).padding({ left: 16, right: 16 })
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
        Column({ space: 20 }) {
          if (this.data.history.length === 0) {
            Column({ space: 12 }) {
              Text('暂无历史日程').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.palette.text)
              Text('当日已完成的日程在次日自动归档\n未来日程完成后立即归档').fontSize(13)
                .fontColor(this.palette.textSoft).textAlign(TextAlign.Center).lineHeight(22)
            }.constraintSize({ minHeight: Math.max(260, this.viewportHeight - this.safeTop - 112) })
              .justifyContent(FlexAlign.Center).width('100%')
          } else {
            ForEach(this.entries(), (entry: HistoryEntry) => {
              Column({ space: 8 }) {
                Row({ space: 8 }) {
                  Text(formatFull(entry.date)).fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.palette.textSoft)
                  Text(this.tasksAt(entry.date).length.toString()).fontSize(12).fontColor(this.palette.accent)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 }).backgroundColor(this.palette.accentSoft).borderRadius(8)
                }.width('100%')
                Column() {
                  ForEach(this.tasksAt(entry.date), (task: Task) => {
                    Row({ space: 10 }) {
                      PlanerIcon({ icon: 'check', color: this.palette.success, iconSize: 20 })
                      Column({ space: 5 }) {
                        Text(task.text).fontSize(15).fontColor(this.palette.text).width('100%')
                        if (task.plannedDate) {
                          Text('计划 ' + formatFull(task.plannedDate)).fontSize(12).fontColor(this.palette.textSoft).width('100%')
                        }
                      }.layoutWeight(1)
                      IconButton({ icon: 'restore', label: '恢复日程', palette: this.palette,
                        onTap: () => this.onRestore(task, entry.date) })
                      IconButton({ icon: 'trash', label: '永久删除历史日程', palette: this.palette,
                        onTap: () => this.onDelete(task, entry.date) })
                    }.width('100%').padding({ left: 12, right: 6, top: 12, bottom: 12 })
                  }, (task: Task) => task.id)
                }.width('100%').backgroundColor(Materials.fallback(this.palette)).borderRadius(16)
                  .backgroundBlurStyle(BlurStyle.COMPONENT_THIN, { colorMode: Materials.mode(this.palette) })
                  .transition(Motion.reveal())
              }.width('100%')
            }, (entry: HistoryEntry) => entry.date)
          }
        }.width('100%').padding({ left: 16, right: 16, top: this.safeTop + 72, bottom: 40 })
      }.width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Auto).clip(false)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .onAreaChange((_old: Area, area: Area) => { this.viewportHeight = Number(area.height); })
    }.width('100%').height('100%').backgroundColor(this.palette.bg)
      .mode(NavigationMode.Stack).hideBackButton(true).hideToolBar(true)
      .bindToScrollable([this.scroller])
      .titleBar({
        // 全屏内容穿过状态栏，固定标题由 HDS 主动避让系统安全区。
        avoidLayoutSafeArea: true,
        // 内容不避让标题，初始间距放在 Scroll 内，滚动时连同安全区一并滑出。
        enableComponentSafeArea: false,
        style: {
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          },
          scrollEffectOpts: {
            enableScrollEffect: true,
            // 使用系统默认的 0–8vp 阈值，兼容设备端对 LengthMetrics 的解析差异。
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR
          },
          originalStyle: this.headerStyle(),
          scrollEffectStyle: this.headerStyle()
        },
        content: { title: { mainTitle: '' }, stackBuilder: () => { this.fixedHeader(); } }
      }).withTheme({ enableThemeColorMode: true })
      // 紧凑标题为 56vp，历史内容在安全区下另留 16vp 间距。
      .titleMode(HdsNavigationTitleMode.MINI)
  }
}