# 桌面主题渐变与验收

日期：2026-10-22；V1.1.0；编译 / 目标 SDK 26.0.0，最低兼容 6.1.1(24)。仅修改 PlanerHarmony。

## 设计与行为

- 三段 135° 斜向渐变：左上保持接近主面板的轻底色，右下逐渐融入主题柔色。浅色采用淡蓝 / 浅绿 / 暖杏 / 浅紫，深色保留低亮度同色系层次。
- 渐变全部不透明，隔离壁纸的明暗和图案，优先保证信息可读性；保留系统圆角和原有排版，不新增装饰边框或额外光斑。
- 小、中、大三种规格共用相同规则，不影响日程勾选、滚动、数量及未来日程设置。
- 沿用现有主题模式和配色选项；跟随系统时由卡片进程直接解析 base / dark 资源，手动模式使用主应用下发的三个渐变色点。
- 沿用直接采用最终主题颜色的策略，避免不可见卡片冻结主题动画后在返回桌面时重播。原有来源卡片返回时短暂旧画面问题不在此轮声明解决。
- 旧缓存没有渐变字段时，回退其已有 cPanel，避免闪成默认配色；收到新数据后自然采用当前主题渐变。

## 关键文件与维护

- `theme/CardAppearance.ets`：纯色板衍生规则；当前浅色混合权重 0.02 / 0.30 / 1.00，深色 0.02 / 0.38 / 1.00。浅色卡片辅助文字向正文色混合 12%，全应用色板及深色辅助文字不变。
- `services/CardData.ets`：下发 cGradientStart / cGradientMiddle / cGradientEnd 与匹配的 cSoft；保留 cPanel 兼容旧缓存。
- `widget/pages/WidgetCard.ets`：三段线性渐变；跟随系统时引用对应主题色资源。
- `resources/base/element/color.json` 与 `resources/dark/element/color.json`：四配色、每套三个色点，以及与推送一致的辅助文字色；其它颜色值保留。
- `scripts/sync-card-theme.mjs`：读取真实 Theme / CardAppearance，生成卡片系统主题资源；不新增依赖、不连接网络。
- `scripts/test-card.mjs`：保留 47 项，新增 6 项资源、对比度和一致性检查。

修改 Theme.ets 或 CardAppearance.ets 后运行 `node scripts/sync-card-theme.mjs`，再执行 `node scripts/test-card.mjs`、ArkTS 检查与构建。不要只改推送色或只改资源中的一份。

## 首轮真机观察（增强前）

设备 Mate 80 Pro Max，已有 2*4 桌面卡片，当前系统浅色。已安装签名包、启动 Smoke PASS，在已有卡片上检查墨影浅色 / 深色，以及森林、日落、海盐浅色。颜色有轻微层次且文字清晰，没有毛玻璃试验中的白底浅字问题。未新增、移除或移动桌面卡片。

按钮部分初始位于悬浮栏后，早期点击森林不生效；随后将主题按钮完整滚入可操作区，再验证实际配色。`.tooling/widget-gradient/forest-dark.png` 和 `forest-light.png` 属于过程截图，不作为该配色通过的证据。最终可用截图：`ink-light.png`、`ink-dark.png`、`forest-light-verified.png`、`sunset-light.png`、`seasalt-light.png`、`final-verified.png`。含系统通知的过程截图已删除。

最终恢复用户原有墨影、跟随系统模式；`device-original.json` 与 `device-final-verified.json` 内容完全一致，没有回灌旧数据或改动现有日程。手机停留在原桌面。

小卡 / 大卡共用的资源与视图代码已构建，数据 / 配色一致性有本地回归；未为验证改变现有桌面布局，因此本轮没有这两种规格的独立真机截图。没有验证真实系统深浅切换、动画帧率、不同设备 / 最低兼容版本和大字体。

## 首轮检查结果（增强前）

- ArkTS：32 文件通过，0 error。
- Lint：0 error / 5 warning，均为现有组件结构性能建议，没有关闭规则。
- API 26 签名构建：BUILD SUCCESSFUL；2 条既有输入控制器 SysCap 提示保留。
- 8 个脚本合计 595 项断言通过：139 + 18 + 93 + 202 + 27 + 53 + 36 + 27。
- Hypium Local Test：5 pass，0 failure / error。
- 八套渐变的色点与中点计算：正文最低对比度 11.58:1，辅助文字最低 4.51:1；这些计算针对 cText / cSoft，不对已完成淡色、不同字体渲染和设备实测亮度做额外保证。

日志、备份与截图在忽略目录 `.tooling/widget-gradient/`；最终产物 `entry/build/default/outputs/default/entry-default-signed.hap`。

## API 26 文档示例复核与渐变增强（2026-10-22）

用户提供的示例在独立实验中原样使用 `systemMaterial(new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR, colorInvert: true }))`，没有改变项目最低兼容版本、签名、能力声明或严格检查配置。实验失败后已恢复完整卡片源码，正式产物保留渐变。

### 官方接口与编译结果

- 工具链：项目 README 所列 DevEco CLI 1.3.4、SDK 26.0.0.105；编译 / 目标 26.0.0，最低兼容 6.1.1(24)。
- DevEco CLI 官方文档标识：`API参考/ArkUI_方舟UI框架/ArkTS_API/UI界面/ohos_arkui_uiMaterial_系统材质_/arkts-apis-uimaterial`。文档快照：`.tooling/widget-material-reference/official-uiMaterial.txt`。
- SDK `ets/component/common.d.ts` 的 `systemMaterial` 通用属性带 `@form`；`ets/api/@ohos.arkui.uiMaterial.d.ts` 的 `Material` 基类 / empty 具有卡片能力标注，但 `ImmersiveMaterial` 构造器和 `ImmersiveStyle` 没有对应标注。不能将属性或基类的支持范围直接扩展到具体材质构造器。
- 原样示例编译报 **11706006**：`ImmersiveMaterial`、`ImmersiveStyle`、`REGULAR` 均提示 `can't support form application`；同时报 **11706011** 最低兼容版本保护错误。两类限制独立存在，提高最低版本或做运行时设备判断不能消除卡片接口限制。完整日志：`.tooling/widget-material-reference/exact-example-build.log`。
- 模块已有 `ohos.arkui.UIMaterial.state=enable`。官方文档还对普通组件的材质生效位置作出限制，不能仅依据“常规内容区域和卡片建议 REGULAR”认定它支持桌面 Form 卡片。
- 结论只针对本机当前 SDK / 工具链：本次不交付无法编译的沉浸材质分支，所有设备继续使用渐变。以后 SDK 明确开放构造器的卡片能力并通过编译、真机验证后，再接入沉浸材质与设备回退判断。

### 交付与验证

渐变右下色点提高到完整主题柔色，左上仍接近面板色，中段分别使用浅色 30%、深色 38% 的主题柔色；浅色卡片辅助文字略加深。三规格、四配色及深浅资源共用同一规则，应用内其它主题颜色不变。当前八套渐变端点与中点计算的正文最低对比度 **10.86:1**，辅助文字 **4.66:1**；不据此额外保证完成态淡色和设备实测亮度。

- `test-card.mjs` 53 项、`test-card-write.mjs` 36 项、`test-scroll-form.mjs` 27 项，共 **116 项**相关断言通过；本次未重跑首轮其它脚本与 Hypium。
- ArkTS 检查：32 文件通过，0 error。Lint：0 error / 5 条既有组件结构性能 warning；未关闭检查。
- 失败实验曾留下卡片生成缓存，后续增量构建错误复用了示例视图。真机发现后使用官方 `build clean --modules entry` 清理，重新检查、全量签名构建，并确认生成的 WidgetCard 不含示例文案、包含渐变逻辑后覆盖安装。最终 `BUILD SUCCESSFUL`，安装 / 启动 `Smoke: PASS`；2 条既有输入控制器 SysCap 提示保留。
- 最终真机仅检查已有 **2*4 中卡、墨影、跟随系统（系统当前浅色）**：右下浅紫渐变更明显，真实日程、勾选状态及进度环正常。没有新增、移动或移除桌面卡片，没有切换主题。本次不据此声明其它规格、其它配色、深色或其它设备已完成新一轮真机验收。
- `device-before.json` 与最终 `device-final-clean.json` 内容完全一致（9571 字节）；没有修改或回灌日程、设置。手机停留在原桌面。

本次日志、备份和截图在 `.tooling/widget-material-reference/`。最终截图为 `stronger-gradient-clean.png`；`stronger-gradient-final.png` 是清理前缓存错误的过程证据，不代表交付效果。最终构建 / 安装日志为 `build-clean.log` / `install-clean.log`，最终 ArkTS 日志为 `arkts-clean.log`。签名产物仍为 `entry/build/default/outputs/default/entry-default-signed.hap`。

若以后再次做卡片实验，恢复源码后先执行官方干净构建，再核对卡片生成物并安装，避免失败编译缓存污染正式包。
