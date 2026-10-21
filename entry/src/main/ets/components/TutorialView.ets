import { TutorialFeature, tutorialFeatures, TUTORIAL_TITLE, TUTORIAL_SUBTITLE, TUTORIAL_FOOTNOTE } from '../tutorial/TutorialConfig';
import { Palette } from '../theme/Theme';
import { Motion } from '../theme/Appearance';
import { PlanerIcon } from './PlanerIcon';

// 单页简要说明；小屏或大字体时正文可滚动，开始按钮始终可见。
@Component
export struct TutorialView {
  @Prop palette: Palette = new Palette();
  @Prop safeTop: number = 0;
  @Prop safeBottom: number = 0;
  @Prop saveError: string = '';
  private features: TutorialFeature[] = tutorialFeatures();
  onClose: () => void = (): void => {};
  onRetry: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
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
            ForEach(this.features, (feature: TutorialFeature) => {
              Row({ space: 12 }) {
                Stack() { PlanerIcon({ icon: feature.icon, color: this.palette.accent, iconSize: 21 }) }
                  .width(40).height(40).borderRadius(13).backgroundColor(this.palette.accentSoft)
                Column({ space: 5 }) {
                  Text(feature.title).fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.palette.text).width('100%')
                  Text(feature.description).fontSize(12).lineHeight(18).fontColor(this.palette.textSoft).width('100%')
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }.width('100%').alignItems(VerticalAlign.Top).id('tutorial-feature-' + feature.id)
            }, (feature: TutorialFeature): string => feature.id)
          }.width('100%').padding({ bottom: 6 })
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
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
      }.width('100%').height(620).constraintSize({ maxWidth: 420, maxHeight: '100%' })
        .padding({ left: 22, right: 22, top: 14, bottom: 22 }).borderRadius(26).backgroundColor(this.palette.panel)
        .shadow({ radius: 26, color: '#2510182A', offsetY: 10 }).transition(Motion.reveal()).id('tutorial-card')
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: this.safeTop + 16, bottom: this.safeBottom + 16 })
      .backgroundColor('#6610182A').hitTestBehavior(HitTestMode.Default).id('tutorial-root')
      .transition(TransitionEffect.OPACITY.animation(Motion.quick()))
  }
}
