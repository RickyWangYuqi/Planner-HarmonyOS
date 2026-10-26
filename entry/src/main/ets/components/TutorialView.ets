import { TutorialFeature, tutorialFeatures, TUTORIAL_TITLE, TUTORIAL_SUBTITLE, TUTORIAL_FOOTNOTE } from '../tutorial/TutorialConfig';
import { Palette } from '../theme/Theme';
import { Motion } from '../theme/Appearance';
import { PlanerIcon } from './PlanerIcon';

// 原生近全屏半模态内的一页说明；入场从配置顺序派生，不维护写死的条目动画。
@Component
export struct TutorialView {
  @Prop wideLayout: boolean = false;
  @Prop palette: Palette = new Palette();
  @Prop safeBottom: number = 0;
  @Prop entered: boolean = false;
  @Prop saveError: string = '';
  private features: TutorialFeature[] = tutorialFeatures();
  onClose: () => void = (): void => {};
  onRetry: () => void = (): void => {};

  build() {
    Column({ space: 0 }) {
      Row() {
        Text($r('app.string.welcome_title')).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.palette.accent).layoutWeight(1)
        Button('稍后', { type: ButtonType.Normal }).height(40).padding({ left: 12, right: 12 })
          .fontSize(12).fontColor(this.palette.textSoft).backgroundColor(Color.Transparent).borderRadius(12)
          .onClick((): void => this.onClose()).id('tutorial-skip')
      }.width('100%')
      Text(TUTORIAL_TITLE).fontSize(25).fontWeight(FontWeight.Bold).fontColor(this.palette.text).width('100%').margin({ top: 4 })
      Text(TUTORIAL_SUBTITLE).fontSize(13).fontColor(this.palette.textSoft).width('100%').margin({ top: 8, bottom: 20 })
      Scroll() {
        Column({ space: 18 }) {
          ForEach(this.features, (feature: TutorialFeature, index: number) => {
            Row({ space: 12 }) {
              Stack() { PlanerIcon({ icon: feature.icon, color: this.palette.accent, iconSize: 21 }) }
                .width(40).height(40).borderRadius(13).backgroundColor(this.palette.accentSoft)
              Column({ space: 5 }) {
                Text(feature.title).fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.palette.text).width('100%')
                Text(this.wideLayout && feature.wideDescription ? feature.wideDescription : feature.description).fontSize(12).lineHeight(18).fontColor(this.palette.textSoft).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%').alignItems(VerticalAlign.Top).id('tutorial-feature-' + feature.id)
              .opacity(this.entered ? 1 : 0)
              .translate({ y: this.entered ? 0 : 28 })
              .scale({ x: this.entered ? 1 : 0.985, y: this.entered ? 1 : 0.985 })
              // 正文首次挂载即开始，与面板上升并行；每条仅间隔 55ms。
              .animation({ curve: Motion.springCurve(), delay: index * 55 })
          }, (feature: TutorialFeature): string => feature.id)
        }.width('100%').padding({ top: 4, bottom: 10 })
      }.width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .id('tutorial-summary')
      Text(TUTORIAL_FOOTNOTE).fontSize(11).lineHeight(18).fontColor(this.palette.textFaint)
        .textAlign(TextAlign.Center).width('100%').margin({ top: 16, bottom: 12 })
      if (this.saveError) {
        Button(this.saveError + ' · 重试', { type: ButtonType.Normal }).height(36).width('100%').borderRadius(12)
          .fontSize(12).fontColor(this.palette.danger).backgroundColor(this.palette.dangerSoft)
          .onClick((): void => this.onRetry()).id('tutorial-retry').margin({ bottom: 8 })
      }
      Button('开始使用', { type: ButtonType.Normal }).width('100%').height(48).borderRadius(14)
        .fontSize(15).fontWeight(FontWeight.Medium).fontColor(Color.White).backgroundColor(this.palette.accent)
        .onClick((): void => this.onClose()).id('tutorial-start')
    }.width('100%').height('100%').constraintSize({ maxWidth: 520 })
      .padding({ left: 22, right: 22, top: 8, bottom: Math.max(20, this.safeBottom) })
      .alignItems(HorizontalAlign.Start).id('tutorial-card')
  }
}
