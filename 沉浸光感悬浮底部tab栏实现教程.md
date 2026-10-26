# HarmonyOS7 Navigation 底部工具栏变悬浮胶囊？沉浸光感三件套：隐藏 + 浮层 + systemMaterial 原创 精华

## 前言

这篇要解决的是社区里的一个真实问题：Navigation 组件导航底部的工具栏，怎么从传统的贴底色块变成悬浮胶囊形态，同时加上沉浸光感效果（毛玻璃模糊、按压流光），还不会影响用户操作。帖子地址：https://developer.huawei.com/consumer/cn/forum/topic/0208223292271602805?fid=0109140870620153026。

这个问题看着简单——不就是给 toolbar 加个圆角和模糊吗？实际做下来会发现三个坑：

1. Navigation 自带的 `toolbarConfiguration` 工具栏是贴底全宽的，没有悬浮形态，没有圆角胶囊选项，你没法通过属性把它变成"悬浮的"
2. 沉浸光感需要 `systemMaterial` 这个 API（SDK 26 新增），如果背景内容全是白色或纯色，毛玻璃和折射效果几乎看不出来
3. 自定义悬浮工具栏如果布局不当，会遮挡底部内容，影响用户滚动和点击

我排查下来，核心思路是三步走：**隐藏原生工具栏 → 用 Stack 叠层放自定义悬浮胶囊 → 给胶囊加 systemMaterial 沉浸光感**。下面一步步拆开讲。

### 先说结论

最终运行效果截图如下：

![ HarmonyOS7 Navigation 底部工具栏变悬浮胶囊？沉浸光感三件套：隐藏 + 浮层 + systemMaterial-鸿蒙开发者社区](https://dl-harmonyos.51cto.com/oss/202608/28/52a78f364a427b3c3eb3268dcafacd72b02f64.png?x-oss-process=image/watermark,size_14,text_QDUxQ1RPIOm4v-iSmeW8gOWPkeiAheekvuWMug,color_FFFFFF,t_30,g_se,x_10,y_10,shadow_20,type_ZmFuZ3poZW5naGVpdGk=,x-oss-process=image/resize,m_fixed,w_1184/format,webp,image/resize,w_820,h_2555)

如果你也想让 Navigation 底部工具栏变成悬浮胶囊 + 沉浸光感，记住三个关键点：

- 隐藏原生工具栏，用 `Stack` 叠层放自定义胶囊，才能控制圆角、间距和悬浮形态
- `systemMaterial` 的 `ULTRA_THIN` 样式是官方推荐给浮动工具栏的，背景必须有丰富的色彩内容才能看出效果
- `interactive`、`lightEffect`、`colorInvert` 三件套一个不能少，分别负责按压弹性、触点流光、智能反色

## 问题还原：为什么原生 toolbar 做不了悬浮？

### 原生工具栏的局限

Navigation 自带的 `toolbarConfiguration` 提供了两种方式设置工具栏：`Array<ToolbarItem>` 和 `CustomBuilder`。前者是系统预设布局，所有选项均分底部宽度，没有圆角、没有悬浮、没有毛玻璃。后者虽然可以自定义内容，但工具栏的容器仍然是贴底全宽的矩形区域——你没法给它加 `borderRadius` 让它变成胶囊，也没法加 `margin` 让它脱离底部边缘。

```typescript
// 原生 toolbarConfiguration 写法——贴底全宽，没有悬浮形态
Navigation(this.pathStack) {
  // 内容
}
.toolbarConfiguration([
  { value: '首页', action: () => {} },
  { value: '发现', action: () => {} },
  { value: '消息', action: () => {} },
  { value: '我的', action: () => {} },
])
1.2.3.4.5.6.7.8.9.10.
```

不管怎么调，工具栏始终是贴底的。想让它悬浮起来，必须另辟蹊径。

### 沉浸光感为什么看不出来？

`systemMaterial` 是 SDK 26 新增的 API，通过 `ImmersiveMaterial` 给组件设置沉浸式系统材质。它的工作原理是对组件背后的内容做实时采样——模糊、折射、高光、阴影，全靠背后的内容来"供给"视觉效果。

如果你的页面背景是纯白色，工具栏背后没有任何色彩和纹理，那模糊和折射就没有素材可操作，效果自然出不来。这是很多人加了 `systemMaterial` 却觉得"没效果"的根本原因——不是 API 不工作，是背景太单调了。

### 方案总览

完整的实现方案分三步：

| 步骤 | 做什么                          | 关键 API                                      |
| ---- | ------------------------------- | --------------------------------------------- |
| 1    | 隐藏原生工具栏 + 自定义悬浮胶囊 | `hideToolBar(true)` + `Stack` 叠层            |
| 2    | 给胶囊加沉浸光感材质            | `systemMaterial` + `ImmersiveMaterial`        |
| 3    | 补齐交互和可读性                | `interactive` + `lightEffect` + `colorInvert` |

## 完整解决方案

### 第一步：定义数据模型

悬浮工具栏的每一项需要 id 和名称，内容区的彩色卡片需要 id、颜色和高度：

```typescript
class TabItem {
  id: number = 0
  name: string = ''

  constructor(id: number, name: string) {
    this.id = id
    this.name = name
  }
}

class CardItem {
  id: number = 0
  color: string = ''
  height: number = 120

  constructor(id: number, color: string, height: number) {
    this.id = id
    this.color = color
    this.height = height
  }
}
1.2.3.4.5.6.7.8.9.10.11.12.13.14.15.16.17.18.19.20.21.
```

- `TabItem`：底部导航项数据，`id` 用于 ForEach 的 key 和选中状态判断
- `CardItem`：内容区卡片数据，`color` 提供丰富背景色让沉浸光感有素材可用，`height` 做不等高网格增加层次

### 第二步：组件状态和初始化

```typescript
import { uiMaterial } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'

@Entry
@Component
struct Qa14 {
  private pathStack: NavPathStack = new NavPathStack()
  @State currentIndex: number = 0
  private supportImmersive: boolean = deviceInfo.apiAvailable('26.0.0')
  private scroller: Scroller = new Scroller()

  private tabItems: TabItem[] = [
    new TabItem(0, '首页'),
    new TabItem(1, '发现'),
    new TabItem(2, '消息'),
    new TabItem(3, '我的'),
  ]

  private cardColors: string[] = [
    '#FF6B6B', '#4ECDC4', '#FFD93D', '#6C5CE7',
    '#45B7D1', '#FF9F43', '#A29BFE', '#FD79A8',
    '#00B894', '#E17055', '#0984E3', '#636E72',
  ]

  private cards: CardItem[] = []

  aboutToAppear(): void {
    for (let i = 0; i < 12; i++) {
      this.cards.push(new CardItem(i, this.cardColors[i], 100 + (i % 4) * 30))
    }
  }
1.2.3.4.5.6.7.8.9.10.11.12.13.14.15.16.17.18.19.20.21.22.23.24.25.26.27.28.29.30.31.
```

逐行解读核心代码：

**`supportImmersive`**：`deviceInfo.apiAvailable('26.0.0')` 检测当前设备 SDK 是否支持沉浸光感。`systemMaterial` 从 SDK 26 才有，低版本设备运行时需要降级处理——不支持时回退到半透明白色背景 `'#E6FFFFFF'`，保证工具栏依然可用。

**`cardColors`**：12 种高饱和度颜色。这些颜色不是用来装饰的，是用来**喂给沉浸光感的**。毛玻璃模糊和折射效果需要背后有丰富的色彩内容才能产生通透感。白底纯文字的页面上，沉浸光感几乎不可见。

**`aboutToAppear`**：初始化 12 张不等高卡片，`100 + (i % 4) * 30` 产生 100/130/160/190 四种高度，让 Grid 内容有参差感，滚动时工具栏背后的色彩不断变化，光感效果更明显。

### 第三步：构建悬浮工具栏

这是整个方案的核心：

```typescript
  @Builder
  FloatingToolbar() {
    Row() {
      ForEach(this.tabItems, (item: TabItem) => {
        Column({ space: 2 }) {
          Text(item.name)
            .fontSize(12)
            .fontWeight(this.currentIndex === item.id ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentIndex === item.id ? '#007DFF' : '#182431')
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .borderRadius(24)
        .onClick(() => {
          this.currentIndex = item.id
        })
      }, (item: TabItem) => item.id.toString())
    }
    .width('88%')
    .height(56)
    .borderRadius(28)
    .justifyContent(FlexAlign.SpaceAround)
    .padding({ left: 8, right: 8 })
    .margin({ bottom: 40 })
    .systemMaterial(this.supportImmersive ? new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      interactive: true,
      lightEffect: { color: undefined },
      colorInvert: true,
      applyShadow: true,
    }) : undefined)
    .backgroundColor(this.supportImmersive ? Color.Transparent : '#E6FFFFFF')
  }
1.2.3.4.5.6.7.8.9.10.11.12.13.14.15.16.17.18.19.20.21.22.23.24.25.26.27.28.29.30.31.32.33.34.
```

逐行拆解关键属性：

**悬浮胶囊的形态**：

- `.width('88%')`：不是全宽，留出左右间距，让工具栏看起来是"浮"在内容上方的胶囊
- `.height(56)`：和原生工具栏等高
- `.borderRadius(28)`：高度 56 的一半，形成完全圆角的胶囊形态
- `.margin({ bottom: 40 })`：脱离屏幕底部边缘 40vp，悬浮感的关键——工具栏和底部之间有可见的内容"流过"

**沉浸光感材质**：

- `style: uiMaterial.ImmersiveStyle.ULTRA_THIN`：官方文档明确推荐 `ULTRA_THIN` 用于浮动工具栏场景，材质层具有很强的透明效果，内容能穿透工具栏隐约可见
- `interactive: true`：开启按压弹性形变，用户按压工具栏时产生弹性缩放动画，松手恢复，增强触感反馈
- `lightEffect: { color: undefined }`：开启光感交互反馈（流光效果），手指触摸时在触点位置产生光晕扩散。`color: undefined` 表示使用默认白色流光
- `colorInvert: true`：智能反色。当工具栏背后的内容颜色和文字颜色接近时，自动调整文字颜色保证可读性。ULTRA_THIN 材质透明度高，文字可能在某些背景上看不清，这个属性自动解决
- `applyShadow: true`：材质自带阴影效果，让悬浮胶囊有浮起的立体感

**降级处理**：

- `.systemMaterial(this.supportImmersive ? ... : undefined)`：SDK 26+ 设备启用沉浸光感，低版本设备不设置
- `.backgroundColor(this.supportImmersive ? Color.Transparent : '#E6FFFFFF')`：有沉浸光感时背景透明（材质自己处理背景），没有时回退到半透明白色

### 第四步：Stack 叠层组装页面

```typescript
  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Navigation(this.pathStack) {
        Scroll(this.scroller) {
          Column() {
            Column() {
              Text('沉浸光感')
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
              Text('悬浮工具栏')
                .fontSize(14)
                .fontColor('#DDFFFFFF')
                .margin({ top: 4 })
            }
            .width('100%')
            .height(180)
            .padding({ left: 24, top: 48 })
            .linearGradient({
              direction: GradientDirection.RightBottom,
              colors: [['#667EEA', 0.0], ['#764BA2', 1.0]]
            })

            Grid() {
              ForEach(this.cards, (item: CardItem) => {
                GridItem() {
                  Column() {
                    Text(`卡片 ${item.id + 1}`)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Color.White)
                  }
                  .width('100%')
                  .height(item.height)
                  .borderRadius(12)
                  .backgroundColor(item.color)
                  .justifyContent(FlexAlign.Center)
                  .padding(12)
                }
              }, (item: CardItem) => item.id.toString())
            }
            .columnsTemplate('1fr 1fr')
            .rowsGap(10)
            .columnsGap(10)
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 100 })
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
      }
      .hideToolBar(true)
      .hideTitleBar(true)

      this.FloatingToolbar()
    }
    .width('100%')
    .height('100%')
  }
1.2.3.4.5.6.7.8.9.10.11.12.13.14.15.16.17.18.19.20.21.22.23.24.25.26.27.28.29.30.31.32.33.34.35.36.37.38.39.40.41.42.43.44.45.46.47.48.49.50.51.52.53.54.55.56.57.58.59.60.
```

这段代码有三个关键设计决策，逐个说明：

**为什么用 `Stack` 不用 `Column`？**

`Stack` 是层叠布局，子组件按顺序从底到顶堆叠。Navigation 在底层占满全屏，悬浮工具栏浮在最上层。如果用 `Column`，工具栏会占据独立的布局空间，和 Navigation 上下排列，无法实现"工具栏浮在内容上方"的效果。`Stack` + `Alignment.Bottom` 让工具栏定位在底部，同时不影响 Navigation 的全屏布局。

**为什么要隐藏原生工具栏？**

`.hideToolBar(true)` 把 Navigation 自带的贴底工具栏隐藏掉，否则页面上会同时出现原生工具栏和自定义悬浮工具栏，互相重叠。`.hideTitleBar(true)` 顺带隐藏标题栏，给内容区更多空间。

**为什么内容区要有渐变色 header + 彩色卡片？**

顶部 `.linearGradient({ direction: GradientDirection.RightBottom, colors: [['#667EEA', 0.0], ['#764BA2', 1.0]] })` 是紫蓝渐变，确保页面一进来工具栏背后就有色彩。

下方的 12 张彩色卡片用 Grid 双列布局，滚动时色彩不断变化。Grid 底部 `padding({ bottom: 100 })` 留出 100vp 的空间，确保最后几张卡片不会被悬浮工具栏遮挡——用户滚动到底部时，内容不会被工具栏挡住。

### 完整源码

```ets
import { uiMaterial } from '@kit.ArkUI'
import { deviceInfo } from '@kit.BasicServicesKit'

class TabItem {
  id: number = 0
  name: string = ''

  constructor(id: number, name: string) {
    this.id = id
    this.name = name
  }
}

class CardItem {
  id: number = 0
  color: string = ''
  height: number = 120

  constructor(id: number, color: string, height: number) {
    this.id = id
    this.color = color
    this.height = height
  }
}

@Entry
@Component
struct Qa14 {
  private pathStack: NavPathStack = new NavPathStack()
  @State currentIndex: number = 0
  private supportImmersive: boolean = deviceInfo.apiAvailable('26.0.0')
  private scroller: Scroller = new Scroller()

  private tabItems: TabItem[] = [
    new TabItem(0, '首页'),
    new TabItem(1, '发现'),
    new TabItem(2, '消息'),
    new TabItem(3, '我的'),
  ]

  private cardColors: string[] = [
    '#FF6B6B', '#4ECDC4', '#FFD93D', '#6C5CE7',
    '#45B7D1', '#FF9F43', '#A29BFE', '#FD79A8',
    '#00B894', '#E17055', '#0984E3', '#636E72',
  ]

  private cards: CardItem[] = []

  aboutToAppear(): void {
    for (let i = 0; i < 12; i++) {
      this.cards.push(new CardItem(i, this.cardColors[i], 100 + (i % 4) * 30))
    }
  }

  @Builder
  FloatingToolbar() {
    Row() {
      ForEach(this.tabItems, (item: TabItem) => {
        Column({ space: 2 }) {
          Text(item.name)
            .fontSize(12)
            .fontWeight(this.currentIndex === item.id ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentIndex === item.id ? '#007DFF' : '#182431')
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .borderRadius(24)
        .onClick(() => {
          this.currentIndex = item.id
        })
      }, (item: TabItem) => item.id.toString())
    }
    .width('88%')
    .height(56)
    .borderRadius(28)
    .justifyContent(FlexAlign.SpaceAround)
    .padding({ left: 8, right: 8 })
    .margin({ bottom: 40 })
    .systemMaterial(this.supportImmersive ? new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      interactive: true,
      lightEffect: { color: undefined },
      colorInvert: true,
      applyShadow: true,
    }) : undefined)
    .backgroundColor(this.supportImmersive ? Color.Transparent : '#E6FFFFFF')
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Navigation(this.pathStack) {
        Scroll(this.scroller) {
          Column() {
            Column() {
              Text('沉浸光感')
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
              Text('悬浮工具栏')
                .fontSize(14)
                .fontColor('#DDFFFFFF')
                .margin({ top: 4 })
            }
            .width('100%')
            .height(180)
            .padding({ left: 24, top: 48 })
            .linearGradient({
              direction: GradientDirection.RightBottom,
              colors: [['#667EEA', 0.0], ['#764BA2', 1.0]]
            })

            Grid() {
              ForEach(this.cards, (item: CardItem) => {
                GridItem() {
                  Column() {
                    Text(`卡片 ${item.id + 1}`)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Color.White)
                  }
                  .width('100%')
                  .height(item.height)
                  .borderRadius(12)
                  .backgroundColor(item.color)
                  .justifyContent(FlexAlign.Center)
                  .padding(12)
                }
              }, (item: CardItem) => item.id.toString())
            }
            .columnsTemplate('1fr 1fr')
            .rowsGap(10)
            .columnsGap(10)
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 100 })
          }
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
      }
      .hideToolBar(true)
      .hideTitleBar(true)

      this.FloatingToolbar()
    }
    .width('100%')
    .height('100%')
  }
}
1.2.3.4.5.6.7.8.9.10.11.12.13.14.15.16.17.18.19.20.21.22.23.24.25.26.27.28.29.30.31.32.33.34.35.36.37.38.39.40.41.42.43.44.45.46.47.48.49.50.51.52.53.54.55.56.57.58.59.60.61.62.63.64.65.66.67.68.69.70.71.72.73.74.75.76.77.78.79.80.81.82.83.84.85.86.87.88.89.90.91.92.93.94.95.96.97.98.99.100.101.102.103.104.105.106.107.108.109.110.111.112.113.114.115.116.117.118.119.120.121.122.123.124.125.126.127.128.129.130.131.132.133.134.135.136.137.138.139.140.141.142.143.144.145.146.147.148.149.150.
```

## 三个容易踩的坑

### 坑一：白底页面加 systemMaterial 看不出效果

这是最常见的反馈：“我加了 systemMaterial，效果不明显。”

原因很简单：沉浸光感的毛玻璃模糊和折射效果是对组件背后内容做实时采样计算出来的。如果你的页面背景是白色，工具栏背后没有任何色彩和纹理，模糊算法"采"到的全是白色，结果还是白色，自然看不出区别。

修复方法：确保工具栏背后有丰富的色彩内容。顶部用渐变色 header，下方用彩色卡片网格。滚动时色彩不断变化，光感效果才会明显。

### 坑二：低版本设备兼容性

`systemMaterial` 和 `ImmersiveMaterial` 从 SDK 26 才可用。如果你的项目 `compatibleSdkVersion` 低于 26（比如 24），编译时会出 WARN，运行时在低版本设备上会崩溃。

修复方法：用 `deviceInfo.apiAvailable('26.0.0')` 做运行时检测，不支持时回退到半透明纯色背景：

```typescript
private supportImmersive: boolean = deviceInfo.apiAvailable('26.0.0')

.systemMaterial(this.supportImmersive ? new uiMaterial.ImmersiveMaterial({
  style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
  // ...
}) : undefined)
.backgroundColor(this.supportImmersive ? Color.Transparent : '#E6FFFFFF')
1.2.3.4.5.6.7.
```

不支持沉浸光感时，工具栏用 `'#E6FFFFFF'`（90% 透明度的白色）做背景，视觉上仍然有半透明悬浮感，只是没有毛玻璃和折射。

### 坑三：悬浮工具栏遮挡底部内容

自定义悬浮工具栏浮在内容上方，如果不做处理，页面底部的内容会被工具栏遮挡，用户无法看到也无法点击。

修复方法：给可滚动区域的底部加 `padding({ bottom: 100 })`，确保最后的内容项下方有足够的留白空间。100vp 大于工具栏的高度（56vp）加上底部间距（40vp），滚动到底时内容不会被遮挡。

## ImmersiveStyle 五种样式怎么选？

官方提供了五种材质样式，从薄到厚：

| 样式        | 透明度 | 适用场景               |
| ----------- | ------ | ---------------------- |
| ULTRA_THIN  | 极高   | 浮动工具栏、底部导航栏 |
| THIN        | 较高   | 搜索框、标签栏         |
| REGULAR     | 常规   | 通用卡片               |
| THICK       | 较低   | 菜单、下拉框           |
| ULTRA_THICK | 极低   | 弹窗、对话框           |

底部悬浮工具栏官方明确推荐 `ULTRA_THIN`。透明度高，内容能穿透工具栏隐约可见，配合 `colorInvert` 智能反色，文字可读性和通透感兼得。

如果你发现工具栏文字在某些背景上仍然看不清，可以尝试换成 `THIN`——透明度稍低，模糊更强，文字更清晰，但通透感会减弱。

## 总结

Navigation 底部工具栏变成悬浮胶囊 + 沉浸光感，核心思路就三步：

1. **隐藏原生工具栏**：`hideToolBar(true)` + `Stack` 叠层放自定义胶囊，才能控制圆角、间距和悬浮形态
2. **加沉浸光感材质**：`systemMaterial(new uiMaterial.ImmersiveMaterial({ style: ULTRA_THIN }))` 让胶囊呈现毛玻璃和折射效果，但前提是背后有丰富的色彩内容
3. **补齐交互和可读性**：`interactive` 按压弹性形变、`lightEffect` 触点流光、`colorInvert` 智能反色，三个属性保证光感效果不只是"好看"，更是"好用"

最容易忽略的一点：**沉浸光感不是给组件加个属性就完事的，它需要背后有内容来"喂"效果**。白底页面加 systemMaterial 等于白加。记住：丰富的背景色彩 + ULTRA_THIN 材质 + colorInvert 反色，三样齐了效果才出得来。