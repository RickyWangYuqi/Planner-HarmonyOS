# 桌面卡片毛玻璃试验

日期：2026-10-22；V1.1.0；SDK 26.0.0，最低兼容 6.1.1(24)。设备：Mate 80 Pro Max，系统当前为浅色，配色墨影，原主题模式为跟随系统。

## 两条实际试验路径

1. 卡片根容器设 `backgroundColor(Color.Transparent)`，调用卡片允许的单参数 `backgroundBlurStyle(BlurStyle.COMPONENT_THIN)`。
2. 同样保持根背景透明，改用 `backdropBlur(24)`，排除系统模糊样式附带赋色的影响。

两份试验代码均通过 ArkTS、完整签名构建，覆盖安装后应用启动 Smoke PASS，并在桌面已有的 2*4 卡片上对比。没有新增、删除或移动桌面组件，没有修改壁纸。

## 真机观察

- 基线、标准模糊样式及纯半径模糊三者都表现为白色卡片，没有观察到卡片下方壁纸图案或颜色经过模糊后显现。
- 标准模糊样式下将应用切为深色，卡片文字 / 圆环收到深色配色，但背板仍呈白色，正文和计数明显发白、可读性下降。随后通过设置恢复原来的跟随系统模式。
- 这证明“API 允许在卡片使用”和“能采样桌面壁纸”不是同一项保证。当前表现更像在卡片宿主自身背板内模糊；这是依据画面的推断，不是对全部系统 / 设备的结论。
- 本次没有通过关闭检查、申请未授权权限或修改签名来绕过宿主约束；也没有把纯透明度效果当作真实毛玻璃。

SDK `common.d.ts` 标明两条 API 支持 ArkTS 卡片，但 `backgroundBlurStyle` 的 `BackgroundBlurStyleOptions` 参数不可用于卡片，因此没有套用主应用的 `colorMode` 等配置。

## 交付状态

两种试验效果均未达到“真实壁纸模糊且深浅色可读”的目标，已逐字节恢复试验前 WidgetCard 源码，重新检查、构建并安装原背板版本。没有新增设置项，没有改日程逻辑，也没有擅自替换成主题渐变色。

若后续要继续改善外观，主题渐变色仍是可独立实现的方案；若要突破宿主背板，应先取得官方允许的卡片能力与实际设备依据，不能仅靠换模糊半径判断可行。

## 证据与检查

本地忽略目录 `.tooling/widget-blur/`：

- `desktop-baseline.png`：试验前。
- `desktop-native-settled.png`：背景模糊样式稳定后。
- `desktop-dark-probe.png`：应用深色与白色背板的对比度问题。
- `desktop-system-restored.png`：恢复主题。
- `desktop-radius-blur.png`：纯半径背景模糊。
- `desktop-final-restored.png`：最终回退。
- `WidgetCard-original.ets`：源码备份；最终哈希一致。
- `device-original.json` / `device-final.json`：数据核对，不回灌旧备份覆盖用户操作。
- `arkts-probe.log`、`build-probe.log`、`arkts-radius.log`、`build-radius.log`：两条路径检查与完整构建日志。
- `arkts-final.log`、`build-final.log`、`lint-final.log`：回退后的最终检查。

验收前后数据文件内容完全一致；原主题恢复为跟随系统 / 墨影，桌面布局保留。

最终验证：ArkTS 31 文件零错误、签名构建通过；卡片数据 47 项和写回 36 项断言通过。Lint 保留 5 条组件结构性能建议，无错误。未覆盖真实系统深色切换、其他规格和不同壁纸；由于主路径未见有效壁纸采样，没有扩展修改桌面布局进行验证。


后续用户选择了主题渐变色，当前实际背板已更新，见 [主题渐变验收](WIDGET-GRADIENT-QA.md)；本文件仅记录此前毛玻璃试验及当时的回退状态。
