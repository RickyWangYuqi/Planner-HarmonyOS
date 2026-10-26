import { ResponsiveLayout } from '../theme/ResponsiveLayout';
import { HdsNavigation, HdsNavigationTitleMode, HdsNavigationTitleBarStyle, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { AppAction, AppData, HistoryEntry, Settings } from '../model/PlanerModel';
import { Palette, paletteFor } from '../theme/Theme';
import { Materials } from '../theme/Appearance';
import { PlanerIcon } from './PlanerIcon';
import { ThemeModePicker } from './ThemeModePicker';

@Component
export struct SettingsView {
  @StorageProp('planerSafeTop') safeTop: number = 0;
  @Prop windowWidth: number = 0;
  @Prop data: AppData = new AppData();
  @Prop palette: Palette = new Palette();
  scroller: Scroller = new Scroller();
  onAction: (action: AppAction) => void = (_action: AppAction): void => {};
  onHistory: () => void = (): void => {};
  onTutorial: () => void = (): void => {};
  private presets: string[] = ['seasalt', 'forest', 'sunset', 'ink'];
  private rows: number[] = [0, 1];

  private headerStyle(): HdsNavigationTitleBarStyle {
    return {
      backgroundStyle: { backgroundColor: Color.Transparent },
      contentStyle: { titleStyle: { mainTitleColor: this.palette.text } }
    };
  }
  private toggleValue(key: string): boolean {
    if (key === 'retainCompletedFutureUntilDue') return this.data.settings.retainCompletedFutureUntilDue;
    if (key === 'autoNumber') return this.data.settings.autoNumber;
    if (key === 'progressDefaultZero') return this.data.settings.progressDefaultZero;
    if (key === 'autoScrollNextOnComplete') return this.data.settings.autoScrollNextOnComplete;
    return this.data.settings.showGroups;
  }

  private updateToggle(key: string, value: boolean): void {
    if (this.toggleValue(key) === value) return;
    const settings = Settings.copy(this.data.settings);
    if (key === 'autoNumber') settings.autoNumber = value;
    if (key === 'progressDefaultZero') settings.progressDefaultZero = value;
    if (key === 'autoScrollNextOnComplete') settings.autoScrollNextOnComplete = value;
    if (key === 'showGroups') settings.showGroups = value;
    if (key === 'retainCompletedFutureUntilDue') settings.retainCompletedFutureUntilDue = value;
    this.save(settings);
  }

  private save(settings: Settings): void {
    const action = new AppAction('SET_SETTINGS');
    action.settings = settings;
    this.onAction(action);
  }

  private theme(mode: string): void {
    const settings = Settings.copy(this.data.settings);
    settings.themeMode = mode;
    this.save(settings);
  }

  private preset(id: string): void {
    const settings = Settings.copy(this.data.settings);
    settings.colorPreset = id;
    this.save(settings);
  }

  private presetName(id: string): string {
    if (id === 'forest') return '森林';
    if (id === 'sunset') return '日落';
    if (id === 'ink') return '墨影';
    return '海盐';
  }

  private presetDescription(id: string): string {
    if (id === 'forest') return '自然绿意';
    if (id === 'sunset') return '温暖橘橙';
    if (id === 'ink') return '石墨紫调';
    return '清爽蓝调';
  }

  private historyCount(): number {
    return this.data.history.reduce((count: number, entry: HistoryEntry): number => count + entry.tasks.length, 0);
  }

  @Builder
  private heading(text: string) {
    Text(text).fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.palette.textFaint)
      .width('100%').padding({ left: 4, top: 6 })
  }

  @Builder
  private toggleRow(key: string, title: string, description: string) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette.text).width('100%')
        Text(description).fontSize(12).fontColor(this.palette.textSoft).width('100%').lineHeight(18)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      // 在构建回调内读取当前设置，避免按值传入 Builder 后捕获旧开关状态。
      Toggle({ type: ToggleType.Switch, isOn: this.toggleValue(key) }).id('setting-' + key).selectedColor(this.palette.accent)
        .accessibilityText(title).onChange((checked: boolean) => this.updateToggle(key, checked))
    }.width('100%').padding({ top: 8, bottom: 8 })
  }

  @Builder
  private presetCard(id: string) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 9 }) {
        Row({ space: 6 }) {
          Row().width(34).height(24).borderRadius(8).backgroundColor(paletteFor(id, false).accentSoft)
          Row().width(34).height(24).borderRadius(8).backgroundColor(paletteFor(id, true).accent)
          Blank()
          if (this.data.settings.colorPreset === id) {
            PlanerIcon({ icon: 'check', color: this.palette.accent, iconSize: 18 })
          }
        }.width('100%')
        Text(this.presetName(id)).fontSize(15).fontWeight(FontWeight.Bold).fontColor(this.palette.text)
        Text(this.presetDescription(id)).fontSize(12).fontColor(this.palette.textSoft)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.layoutWeight(1).padding(14).borderRadius(14)
      .backgroundColor(Materials.fallback(this.palette, this.data.settings.colorPreset === id))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THIN, { colorMode: Materials.mode(this.palette) })
      .accessibilityText(`配色${this.presetName(id)}`).id('preset-' + id).onClick(() => this.preset(id))
  }

  @Builder
  private displaySettings() {
    Column({ space: 14 }) {
        this.heading('日程显示设置')
        Column({ space: 6 }) {
          this.toggleRow('autoNumber', '自动编号', '当日与未来日程各自从 1 开始编号')
          Divider().color(this.palette.border)
          this.toggleRow('progressDefaultZero', '未设进度默认显示 0%', '未设置完成百分比的日程也显示 0% 进度条')
          Divider().color(this.palette.border)
          this.toggleRow('autoScrollNextOnComplete', '完成后自动定位下一项', '完成第一个未完成日程后，定位并记住下一项')
          Divider().color(this.palette.border)
          this.toggleRow('showGroups', '按分组显示日程', '关闭仅隐藏分组，保留已设置的分组信息')
          Divider().color(this.palette.border)
          this.toggleRow('retainCompletedFutureUntilDue', '未来日程完成后保留至截止日', '开启后，已完成项保留至截止日结束，可取消完成；关闭会立即归档已完成项。桌面卡片同步生效。')
        }.padding(16).width('100%').borderRadius(16)
          .backgroundColor(Materials.fallback(this.palette)).backgroundBlurStyle(BlurStyle.COMPONENT_THIN, { colorMode: Materials.mode(this.palette) })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private appearanceSettings() {
    Column({ space: 14 }) {
        this.heading('外观主题')
        Column({ space: 14 }) {
          Text('主题模式').fontSize(13).fontColor(this.palette.textSoft).width('100%')
          ThemeModePicker({ selectedMode: this.data.settings.themeMode, palette: this.palette,
            onSelect: (mode: string) => this.theme(mode) }).id('theme-modes')
          Divider().color(this.palette.border)
          Text('配色预设').fontSize(13).fontColor(this.palette.textSoft).width('100%')
          ForEach(this.rows, (row: number) => {
            Row({ space: 8 }) {
              this.presetCard(this.presets[row * 2])
              this.presetCard(this.presets[row * 2 + 1])
            }.width('100%')
          }, (row: number) => row.toString())
        }.padding(16).width('100%').borderRadius(16).id('theme-presets')
          .backgroundColor(Materials.fallback(this.palette)).backgroundBlurStyle(BlurStyle.COMPONENT_THIN, { colorMode: Materials.mode(this.palette) })
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private historySettings() {
    Column({ space: 14 }) {
        this.heading('数据与历史')
        Button({ type: ButtonType.Normal }) {
          Row({ space: 12 }) {
            PlanerIcon({ icon: 'history', color: this.palette.accent, iconSize: 25 })
            Column({ space: 4 }) {
              Text('历史日程').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette.text)
              Text(this.historyCount() > 0 ? `共 ${this.historyCount()} 条记录，支持恢复或删除` : '暂无历史记录')
                .fontSize(12).fontColor(this.palette.textSoft)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            PlanerIcon({ icon: 'right', color: this.palette.textFaint, iconSize: 18 })
          }.width('100%')
        }.padding(16).width('100%').borderRadius(16)
          .backgroundColor(Materials.fallback(this.palette)).backgroundBlurStyle(BlurStyle.COMPONENT_THIN, { colorMode: Materials.mode(this.palette) })
          .onClick(() => this.onHistory()).id('settings-history')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private helpSettings() {
    Column({ space: 14 }) {
        this.heading('帮助与使用')
        Button({ type: ButtonType.Normal }) {
          Row({ space: 12 }) {
            PlanerIcon({ icon: 'history', color: this.palette.accent, iconSize: 25 })
            Column({ space: 4 }) {
              Text('新手教程').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette.text)
              Text('一页了解核心功能，随时回看').fontSize(12).fontColor(this.palette.textSoft)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            PlanerIcon({ icon: 'right', color: this.palette.textFaint, iconSize: 18 })
          }.width('100%')
        }.padding(16).width('100%').borderRadius(16)
          .backgroundColor(Materials.fallback(this.palette)).backgroundBlurStyle(BlurStyle.COMPONENT_THIN, { colorMode: Materials.mode(this.palette) })
          .onClick(() => this.onTutorial()).id('settings-tutorial')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavigation() {
      Scroll(this.scroller) {
      Column({ space: 14 }) {

        if (ResponsiveLayout.wide(this.windowWidth)) {
          Row({ space: 24 }) {
            Column({ space: 22 }) {
              this.displaySettings()
              this.historySettings()
            }.layoutWeight(1)
            Column({ space: 22 }) {
              this.appearanceSettings()
              this.helpSettings()
            }.layoutWeight(1)
          }.width('100%').alignItems(VerticalAlign.Top).id('wide-settings-columns')
        } else {
          this.displaySettings()
          this.appearanceSettings()
          this.historySettings()
          this.helpSettings()
        }
        Text($r('app.string.local_save_brand')).fontSize(12).fontColor(this.palette.textFaint)
          .textAlign(TextAlign.Center).width('100%').margin({ top: 10 })
      }.padding({ left: ResponsiveLayout.gutter(this.windowWidth), right: ResponsiveLayout.gutter(this.windowWidth), top: this.safeTop + 56, bottom: 100 }).width('100%')
        .constraintSize({ maxWidth: 1184 })
    }.id('settings-scroll').width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true }).backgroundColor(Color.Transparent).clip(false)
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
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
        content: { title: { mainTitle: '设置', mainTitleId: 'settings-title' } }
      }).withTheme({ enableThemeColorMode: true })
      // 紧凑标题为 56vp；首节不再叠加额外 16vp 空白。
      .titleMode(HdsNavigationTitleMode.MINI)
  }
}