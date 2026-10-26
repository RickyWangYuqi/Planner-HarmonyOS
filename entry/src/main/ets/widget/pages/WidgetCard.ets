// 桌面日程卡片：三种规格共用一套数据，按尺寸递减信息量。
// 小卡（2*2）、中卡（2*4）、大卡（4*4）的日程列表都可滚动，条数不截断；大卡额外列出未来日程（可勾选完成）。
// 点按条目即勾选完成，条目保持用户原有排序，不会因完成而跳到末尾。
// 勾选与取消都走属性动画：√ 缩放淡入淡出、删除线渐显渐隐、文字颜色过渡；未来日程完成后淡出消失。
// 背板使用同主题三段柔和渐变，保证深浅色对比度；不叠加系统模糊或装饰光效。
let storage = new LocalStorage();
// 卡片不可见时主题动画可能被冻结，返回源卡片后才续播。主题属性直接采用最终色，
// 保留勾选、删除线和未来条目淡出的操作反馈，不让返回桌面重放换色。

@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('size') cardSize: string = 'small';
  @LocalStorageProp('dateText') dateText: string = '';
  @LocalStorageProp('headline') headline: string = '';
  @LocalStorageProp('doneText') doneText: string = '0 / 0';
  @LocalStorageProp('progress') progress: number = 0;
  @LocalStorageProp('ids') ids: string[] = [];
  @LocalStorageProp('texts') texts: string[] = [];
  @LocalStorageProp('delays') delays: string[] = [];
  @LocalStorageProp('metas') metas: string[] = [];
  @LocalStorageProp('marks') marks: string[] = [];
  @LocalStorageProp('futureCount') futureCount: number = 0;
  @LocalStorageProp('futureIds') @Watch('futureChanged') futureIds: string[] = [];
  @LocalStorageProp('futureMarks') futureMarks: string[] = [];
  @LocalStorageProp('retainCompletedFutureUntilDue') retainCompletedFutureUntilDue: boolean = false;
  @LocalStorageProp('futureTexts') futureTexts: string[] = [];
  // 点击后先把该条淡出，再等卡片数据刷新把它移除：卡片内不依赖框架的移除转场也能看到消失过程。
  @State private removingFutureId: string = '';
  @LocalStorageProp('futureRanges') futureRanges: string[] = [];
  @LocalStorageProp('futureText') futureText: string = '';
  @LocalStorageProp('isDark') isDark: boolean = false;
  // 跟随系统主题时为 true：颜色改从 dark 资源目录解析，系统切换深浅色时由卡片渲染进程自动换色，
  // 不需要卡片提供方进程存活（onConfigurationUpdate 只在扩展存活时回调，进程退出后收不到）。
  @LocalStorageProp('followSystem') followSystem: boolean = false;
  @LocalStorageProp('preset') preset: string = 'seasalt';
  @LocalStorageProp('cPanel') cPanel: string = '#F2FFFFFF';
  // 空初值兼容升级前的卡片缓存：收到新渐变数据前保持原主题单色，不闪成默认配色。
  @LocalStorageProp('cGradientStart') cGradientStart: string = '';
  @LocalStorageProp('cGradientMiddle') cGradientMiddle: string = '';
  @LocalStorageProp('cGradientEnd') cGradientEnd: string = '';
  @LocalStorageProp('cText') cText: string = '#1e2b45';
  @LocalStorageProp('cSoft') cSoft: string = '#5d6f90';
  @LocalStorageProp('cFaint') cFaint: string = '#97a6c2';
  @LocalStorageProp('cAccent') cAccent: string = '#2e7cf6';
  @LocalStorageProp('cAccentSoft') cAccentSoft: string = '#dce9ff';
  @LocalStorageProp('cSuccess') cSuccess: string = '#1fa971';
  @LocalStorageProp('cBorder') cBorder: string = '#dde6f2';

  // 跟随系统时按色板名取 dark 资源目录中的同名色；手动模式沿用推送的静态色值。
  // $r 需要编译期字面量，这里按色板与色位逐一分支。
  private sysColor(slot: string): ResourceColor {
    if (this.preset === 'forest') {
      switch (slot) {
        case 'panel': return $r('app.color.card_forest_panel');
        case 'gradient_start': return $r('app.color.card_forest_gradient_start');
        case 'gradient_middle': return $r('app.color.card_forest_gradient_middle');
        case 'gradient_end': return $r('app.color.card_forest_gradient_end');
        case 'text': return $r('app.color.card_forest_text');
        case 'soft': return $r('app.color.card_forest_soft');
        case 'faint': return $r('app.color.card_forest_faint');
        case 'accent': return $r('app.color.card_forest_accent');
        case 'success': return $r('app.color.card_forest_success');
        case 'border': return $r('app.color.card_forest_border');
        default: return $r('app.color.card_forest_accent_soft');
      }
    }
    if (this.preset === 'sunset') {
      switch (slot) {
        case 'panel': return $r('app.color.card_sunset_panel');
        case 'gradient_start': return $r('app.color.card_sunset_gradient_start');
        case 'gradient_middle': return $r('app.color.card_sunset_gradient_middle');
        case 'gradient_end': return $r('app.color.card_sunset_gradient_end');
        case 'text': return $r('app.color.card_sunset_text');
        case 'soft': return $r('app.color.card_sunset_soft');
        case 'faint': return $r('app.color.card_sunset_faint');
        case 'accent': return $r('app.color.card_sunset_accent');
        case 'success': return $r('app.color.card_sunset_success');
        case 'border': return $r('app.color.card_sunset_border');
        default: return $r('app.color.card_sunset_accent_soft');
      }
    }
    if (this.preset === 'ink') {
      switch (slot) {
        case 'panel': return $r('app.color.card_ink_panel');
        case 'gradient_start': return $r('app.color.card_ink_gradient_start');
        case 'gradient_middle': return $r('app.color.card_ink_gradient_middle');
        case 'gradient_end': return $r('app.color.card_ink_gradient_end');
        case 'text': return $r('app.color.card_ink_text');
        case 'soft': return $r('app.color.card_ink_soft');
        case 'faint': return $r('app.color.card_ink_faint');
        case 'accent': return $r('app.color.card_ink_accent');
        case 'success': return $r('app.color.card_ink_success');
        case 'border': return $r('app.color.card_ink_border');
        default: return $r('app.color.card_ink_accent_soft');
      }
    }
    switch (slot) {
      case 'panel': return $r('app.color.card_seasalt_panel');
      case 'gradient_start': return $r('app.color.card_seasalt_gradient_start');
      case 'gradient_middle': return $r('app.color.card_seasalt_gradient_middle');
      case 'gradient_end': return $r('app.color.card_seasalt_gradient_end');
      case 'text': return $r('app.color.card_seasalt_text');
      case 'soft': return $r('app.color.card_seasalt_soft');
      case 'faint': return $r('app.color.card_seasalt_faint');
      case 'accent': return $r('app.color.card_seasalt_accent');
      case 'success': return $r('app.color.card_seasalt_success');
      case 'border': return $r('app.color.card_seasalt_border');
      default: return $r('app.color.card_seasalt_accent_soft');
    }
  }

  private panel(): ResourceColor { return this.followSystem ? this.sysColor('panel') : this.cPanel; }
  private gradientStart(): ResourceColor {
    return this.followSystem ? this.sysColor('gradient_start') : (this.cGradientStart || this.cPanel);
  }
  private gradientMiddle(): ResourceColor {
    return this.followSystem ? this.sysColor('gradient_middle') : (this.cGradientMiddle || this.cPanel);
  }
  private gradientEnd(): ResourceColor {
    return this.followSystem ? this.sysColor('gradient_end') : (this.cGradientEnd || this.cPanel);
  }
  private text(): ResourceColor { return this.followSystem ? this.sysColor('text') : this.cText; }
  private soft(): ResourceColor { return this.followSystem ? this.sysColor('soft') : this.cSoft; }
  private faint(): ResourceColor { return this.followSystem ? this.sysColor('faint') : this.cFaint; }
  private accent(): ResourceColor { return this.followSystem ? this.sysColor('accent') : this.cAccent; }
  private success(): ResourceColor { return this.followSystem ? this.sysColor('success') : this.cSuccess; }
  private lineColor(): ResourceColor { return this.followSystem ? this.sysColor('border') : this.cBorder; }

  private futureChanged(): void {
    this.removingFutureId = '';
  }

  private cardPadding(): number {
    return this.cardSize === 'small' ? 12 : 15;
  }

  private rowHeight(): number {
    return this.cardSize === 'large' ? 22 : 21;
  }

  // 卡片根容器高度按内容自适应，layoutWeight 拿不到"剩余空间"，可滚动列表必须给定高度。
  // 取值按各规格可视行数估算：内容少时贴合内容（不留大片空白），内容多时封顶并滚动。
  private listHeight(): number {
    if (this.cardSize === 'large') return 215;
    if (this.cardSize === 'medium') return 112;
    return 88;
  }

  private listArea(): number {
    const rows: number = this.texts.length;
    let content: number = rows === 0 ? 22 : rows * this.rowHeight() + (rows - 1);
    if (this.cardSize === 'large' && this.futureCount > 0) {
      content += 22 + this.futureTexts.length * this.futureRowHeight();
    }
    return content < this.listHeight() ? content : this.listHeight();
  }

  // 中卡左列与右列（标题 + 列表）等高：日期与标题顶对齐、未来项与列表底部对齐。
  private mediumLeftHeight(): number {
    const height: number = 19 + this.listArea();
    return height < 100 ? 100 : height;
  }

  private futureRowHeight(): number {
    return 20;
  }

  private checkSize(): number {
    return this.cardSize === 'small' ? 16 : 17;
  }

  // 勾选热区宽度：盖住方框并留出余量，又不至于压缩日程文字。
  private cellWidth(): number {
    return this.cardSize === 'small' ? 26 : 28;
  }

  private titleSize(): number {
    return this.cardSize === 'small' ? 12 : 13;
  }

  @Builder
  private header() {
    Row() {
      Text(this.dateText).fontSize(this.cardSize === 'small' ? 11 : 12).fontColor(this.soft()).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).animation(undefined)
      Text(this.doneText).fontSize(this.cardSize === 'small' ? 11 : 12).fontWeight(FontWeight.Medium)
        .fontColor(this.accent()).animation(undefined)
    }.width('100%')
  }

  @Builder
  private bar() {
    Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
      .width('100%').height(3).color(this.accent()).backgroundColor(this.lineColor())
      .style({ strokeWidth: 3 })
  }

  // 勾选框与应用内同款：系统 checkmark 符号 + 成功色圆角方块。
  // 勾选/取消通过 √ 缩放淡入淡出反馈；底色与描边直接取最终色，避免返回时补播主题。
  // 这里只负责绘制，点击热区交给整行：16vp 的小方框在桌面手势环境下很难点中。
  @Builder
  private checkBox(index: number) {
    Stack() {
      SymbolGlyph($r('sys.symbol.checkmark'))
        .fontSize(this.checkSize() - 5)
        .fontColor([Color.White])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .opacity(this.marks[index] === '1' ? 1 : 0)
        .scale({
          x: this.marks[index] === '1' ? 1 : 0.3,
          y: this.marks[index] === '1' ? 1 : 0.3
        })
        .animation({ duration: 170, curve: Curve.EaseOut })
    }
    .width(this.checkSize()).height(this.checkSize()).borderRadius(5)
    .backgroundColor(this.marks[index] === '1' ? this.accent() : '#00000000')
    .border({
      width: this.marks[index] === '1' ? 0 : 1.5,
      color: this.marks[index] === '1' ? this.accent() : this.faint(),
      radius: 5
    })
    .animation(undefined)
  }

  // 勾选格只负责占位与绘制，点击热区由整行承担（方框本身只有 16vp，桌面手感太差）。
  @Builder
  private checkCell(index: number) {
    Stack({ alignContent: Alignment.Start }) {
      this.checkBox(index)
    }
    .width(this.cellWidth())
    .height(this.rowHeight())
  }

  @Builder
  private taskRow(index: number) {
    Row({ space: 4 }) {
      this.checkCell(index)
      // 两层同文案叠放：未完成层正常色、完成层带删除线且为浅灰，靠透明度交叉淡入淡出。
      // 这样删除线只在已完成行出现，同时获得“线条渐显/渐隐”的过渡（decoration 类型本身不可动画）。
      Stack({ alignContent: Alignment.Start }) {
        Text(this.texts[index]).fontSize(this.titleSize()).lineHeight(this.rowHeight() - 2)
          .fontColor(this.text())
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          .animation(undefined)
          .opacity(this.marks[index] === '1' ? 0 : 1)
          .animation({ duration: 200, curve: Curve.EaseOut })
        Text(this.texts[index]).fontSize(this.titleSize()).lineHeight(this.rowHeight() - 2)
          .fontColor(this.faint())
          .decoration({ type: TextDecorationType.LineThrough, color: this.faint() })
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          .animation(undefined)
          .opacity(this.marks[index] === '1' ? 1 : 0)
          .animation({ duration: 200, curve: Curve.EaseOut })
      }
      .layoutWeight(1).height(this.rowHeight())
      if ((this.cardSize !== 'small' && this.metas[index]) || this.delays[index]) {
        Text(this.cardSize === 'small' ? this.delays[index] : this.metas[index]).fontSize(10).fontColor(this.soft()).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 78 })
      }
    }.width('100%').height(this.rowHeight()).alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (index < 0 || index >= this.ids.length) return;
      const id: string = this.ids[index];
      if (!id) return;
      postCardAction(this, {
        action: 'message',
        params: { action: 'toggle', id: id }
      });
    })
  }

  @Builder
  private emptyHint() {
    Text('点按卡片打开序笺添加日程').fontSize(11).fontColor(this.faint())
      .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  // 当日日程做成可滚动列表：条数不再按卡片尺寸截断，超出可视区的部分滑动查看。
  @Builder
  private todayList() {
    List({ space: 1 }) {
      ForEach(this.texts, (text: string, index: number) => {
        ListItem() {
          this.taskRow(index)
        }
      }, (text: string, index: number) => index.toString() + text)
    }
    .width('100%')
    .height(this.listArea())
    .scrollBar(BarState.Off)
  }

  // 大卡未来日程显示共享完成标记；保留模式下原位回显，立即归档模式才淡出。
  @Builder
  private futureRow(index: number) {
    Row({ space: 6 }) {
      Stack() {
        SymbolGlyph($r('sys.symbol.checkmark')).fontSize(this.checkSize() - 5).fontColor([Color.White])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          .opacity(this.futureMarks[index] === '1' ? 1 : 0)
          .scale({ x: this.futureMarks[index] === '1' ? 1 : 0.3, y: this.futureMarks[index] === '1' ? 1 : 0.3 })
          .animation({ duration: 170, curve: Curve.EaseOut })
      }
      .width(this.checkSize()).height(this.checkSize()).borderRadius(5)
      .backgroundColor(this.futureMarks[index] === '1' ? this.accent() : '#00000000')
      .border({ width: this.futureMarks[index] === '1' ? 0 : 1.5, color: this.faint(), radius: 5 })
      .animation(undefined)
      Stack({ alignContent: Alignment.Start }) {
        Text(this.futureTexts[index]).fontSize(11).fontColor(this.soft()).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').animation(undefined)
          .opacity(this.futureMarks[index] === '1' ? 0 : 1).animation({ duration: 200, curve: Curve.EaseOut })
        Text(this.futureTexts[index]).fontSize(11).fontColor(this.faint()).maxLines(1)
          .decoration({ type: TextDecorationType.LineThrough, color: this.faint() })
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').animation(undefined)
          .opacity(this.futureMarks[index] === '1' ? 1 : 0).animation({ duration: 200, curve: Curve.EaseOut })
      }.layoutWeight(1)
      Text(this.futureRanges[index]).fontSize(10).fontColor(this.faint()).maxLines(1)
        .constraintSize({ maxWidth: 120 })
    }
    .width('100%').height(this.futureRowHeight()).alignItems(VerticalAlign.Center)
    .opacity(this.removingFutureId === this.futureIds[index] ? 0 : 1)
    .translate({ x: this.removingFutureId === this.futureIds[index] ? -16 : 0 })
    .animation({ duration: 180, curve: Curve.EaseIn })
    .onClick(() => {
      if (index < 0 || index >= this.futureIds.length) return;
      const id: string = this.futureIds[index];
      if (!id) return;
      if (!this.retainCompletedFutureUntilDue) this.removingFutureId = id;
      postCardAction(this, {
        action: 'message',
        params: { action: 'completeFuture', id: id }
      });
    })
  }

  @Builder
  private smallLayout() {
    Column({ space: 3 }) {
      this.header()
      Text(this.headline).fontSize(13).fontWeight(FontWeight.Bold).fontColor(this.text())
        .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).animation(undefined)
      if (this.texts.length > 0) {
        this.bar()
        this.todayList()
      } else {
        Blank()
        this.emptyHint()
        Blank()
      }
    }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private mediumLayout() {
    Row({ space: 12 }) {
      // 左侧用环形进度替代横条：圆环内的数字本身就是完成比，同样宽度能塞下更多信息。
      Column() {
        Text(this.dateText).fontSize(11).fontColor(this.soft()).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Stack() {
          Progress({ value: this.progress, total: 100, type: ProgressType.Ring })
            .width(70).height(70)
            .color(this.accent())
            .backgroundColor(this.lineColor())
            .style({ strokeWidth: 6 })
          Text(this.doneText).fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.text())
            .maxLines(1)
        }
        .width(70).height(70)
        Text(this.futureText).fontSize(10).fontColor(this.faint()).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width(84)
      .height(this.mediumLeftHeight())
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(HorizontalAlign.Center)
      // 右列不再写死 height('100%')：卡片根容器按内容定高，百分比高度会退化成 0 并把列表裁掉。
      Column({ space: 1 }) {
        Text(this.headline).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.soft())
          .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ bottom: 1 }).animation(undefined)
        if (this.texts.length > 0) {
          this.todayList()
        } else {
          Blank()
          this.emptyHint()
          Blank()
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%')
  }

  @Builder
  private largeLayout() {
    Column({ space: 5 }) {
      Row() {
        Column({ space: 3 }) {
          Text(this.dateText).fontSize(11).fontColor(this.soft()).maxLines(1).animation(undefined)
          Text(this.headline).fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.text())
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).animation(undefined)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Text(this.doneText).fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.accent())
          .animation(undefined)
      }.width('100%')
      this.bar()
      // 当日与未来日程同处一个滚动区：今日条目在上，未来条目紧随其后。
      List({ space: 1 }) {
        if (this.texts.length > 0) {
          ForEach(this.texts, (text: string, index: number) => {
            ListItem() {
              this.taskRow(index)
            }
          }, (text: string, index: number) => index.toString() + text)
        } else {
          ListItem() {
            this.emptyHint()
          }
        }
        if (this.futureCount > 0) {
          ListItem() {
            Row() {
              Text('未来日程').fontSize(10).fontColor(this.faint())
              Blank()
              Text(this.futureCount.toString() + ' 项').fontSize(10).fontColor(this.faint())
            }.width('100%').height(22).alignItems(VerticalAlign.Center).padding({ top: 6 })
          }
        }
        ForEach(this.futureTexts, (text: string, index: number) => {
          ListItem() {
            this.futureRow(index)
          }
        }, (text: string, index: number) => 'future-' + index.toString() + text)
      }
      .width('100%')
      .height(this.listArea())
      .scrollBar(BarState.Off)
    }.width('100%').height('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      if (this.cardSize === 'small') {
        this.smallLayout()
      } else if (this.cardSize === 'medium') {
        this.mediumLayout()
      } else {
        this.largeLayout()
      }
    }
    .width('100%').height('100%')
    .padding(this.cardPadding())
    // 圆角与裁剪交给系统卡片容器，不再自绘边框与圆角，避免两套半径错位。
    .backgroundColor(this.panel())
    .linearGradient({ angle: 135, colors: [
      [this.gradientStart(), 0], [this.gradientMiddle(), 0.48], [this.gradientEnd(), 1]
    ] })
    .animation(undefined)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { from: 'widget' }
      });
    })
  }
}
