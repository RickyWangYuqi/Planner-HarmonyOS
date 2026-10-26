# 表单布局与按钮四角高光验收

日期：2026-10-22；应用 V1.1.0；编译 / 目标 SDK 26.0.0，最低兼容 6.1.1(24)。修改仅在 PlanerHarmony，未改动桌面项目、签名、版本和权限配置。

## 最终实现

### 高光圆角

`theme/Appearance.ets` 的 `PlanerControlModifier` 清除分组标签 / 新建按钮的额外描边时，原先使用 `border({ width: 0 })`，没有显式保留原按钮圆角。现改为 `border({ width: 0, radius: 12 })`，使真实按钮形状与宿主 12vp 圆角匹配，系统高光沿圆角连续绘制。

`MaterialButtonScope` 保留原生标题作用域与圆角裁切。曾尝试关闭宿主裁切，真机会露出方形背板残影，因此该尝试已撤回；最终不是简单移除 clip。普通取消、添加 / 保存、删除、关闭按钮保持各自圆角。分组删除叉号的外层额外白框同时移除，继续保留红色图标与右上方布局。

`HistoryBackButton` 最终配置与本轮前相同；没有更换它的图标或业务行为。

### 表单结构

`components/TaskEditor.ets` 复用同一个真实表单：

- 内容、时间、分组、进度使用一致的轻色圆角分区，正文间距 16vp，分区内边距 14vp、圆角 18vp；正文外边距 20vp。
- 内容区标注必填，输入区高度 96vp，内边距 12vp；移动模式继续只读展示原内容。
- 未来起始 / 截止改为两个日期选择项共用一份日历，默认展示必填的截止日期；选择起始项后可清除起始日期。起始可不填、默认次日、截止不早于起始的业务规则不变。缺少截止时自动切回截止项，再沿用原键盘收起、错误提示与滚动定位流程。
- 分组放在内容 / 时间之后，标注可选；收紧标签留白，简化组状态提示，不再为提示额外套大色块。分组选择、新建草稿、取消与长按删除规则保持不变。
- 编辑模式在下方显示独立进度分区；删除位于滚动内容末尾的「日程管理」，保留危险提示与原确认流程。
- 底部只固定取消与添加 / 保存，保持键盘避让、触摸尺寸和既有提交逻辑。编辑 / 新建 / 移动仍使用宿主统一 84% 高度，没有独立路由或新的数据存储。

保留用户已自行调整的半模态 `REGULAR / #90`，没有将其重设为前轮的 THICK / #58。相关源注释改为说明可调参数而不写死旧值；材质测试验证合法半透明赋色与正确分发，不再锁定某个设计厚度。

## 检查与回归

- `node scripts/test-editor.mjs`：**99** 项通过，原 93 项加 6 项共用日历状态与校验回归。新增覆盖默认截止焦点、切换不改日期、起止联动、清除起始保留截止、选择路由，以及必填失败自动回切并定位。
- `node scripts/test-materials.mjs`：**28** 项通过，补充清除标签轮廓时显式保留圆角；仍覆盖官方自动分档与旧版本保护。
- 本轮合计 **127** 项相关断言，未重跑不受影响的其它脚本或 Hypium。
- DevEco `check arkts`：最终 32 文件，0 error。
- DevEco `check lint`：0 error / 5 条既有组件结构性能 warning，未禁用规则。
- API 26 签名构建 BUILD SUCCESSFUL，覆盖安装与启动 Smoke PASS；2 条既有输入控制器 SysCap 提示保留。

## 真机范围

设备 Mate 80 Pro Max，当前墨影配色、跟随系统浅色。

1. 打开第一条已有当日日程编辑：内容、分组、进度与日程管理分区清晰，删除入口位于正文末尾；未分组标签、新建分组、关闭、取消、保存和删除按钮四角高光完整，无关闭裁切实验中的方形残影。没有点击保存、完成或删除。
2. 打开新建当日日程：只显示内容与分组，底部添加在空内容时保持禁用。
3. 打开新建未来日程：时间安排位于内容之后，默认截止项高亮；点击起始项后，高亮及日历说明正确切换为起始。没有输入或保存测试项。
4. 所有表单均点击取消，最终返回主页。`device-before.json` 与 `device-after.json` 内容完全一致，均 9571 字节；没有回灌备份或改变日程、主题及桌面布局。

本轮没有新建命名分组，没有做命名标签长按、长名称换行、新增日期后真实提交、未来编辑 / 移动全流程或输入法操作的新一轮真机验收；对应业务路径有现有及新增本地回归。低算力设备、深色、大字体和其它分辨率也尚待实测。不据静态截图宣称按压全程、帧率或所有设备上的高光渲染均已验收。

## 证据

私有日志 / 截图在忽略目录 `.tooling/editor-layout/`：

- 最终：`edit-final.png`、`add-today.png`、`add-future.png`、`start-field.png`、`final-home.png`。
- `edit.png` 是关闭裁切后出现方形背板的失败实验截图，不代表交付效果。
- 最终 ArkTS / 构建 / 安装：`arkts-final.log`、`build-final.log`、`install-final.log`；本地回归与 Lint 见同目录相应日志。

签名产物：`entry/build/default/outputs/default/entry-default-signed.hap`。

## 分区层次增强（2026-10-22 后续修订）

用户反馈分区仍与半模态背景接近，因此新增统一 `EditorSectionModifier`，应用到 `TaskEditor` 的内容、时间、分组、进度和日程管理五个圆角容器；本次只调整外观，排版和操作规则沿用前述实现。

集中调参位置：`entry/src/main/ets/theme/Appearance.ets` 的 `EditorSectionModifier.applyNormalAttribute()`。

- 普通分区底色：浅色 alpha `#B8`（约72%不透明），深色 `#CC`（约80%），取自各主题 panel；原分区仅 #30（约19%），边缘与背景太接近。
- 圆角 18vp，细边线 1vp；浅色使用同面板色的 #B3 亮边，深色使用 #22FFFFFF，让边缘在深背景上仍可辨识。
- 浅色投影：radius 14vp、向下偏移 4vp，颜色为正文主题色加 #18 alpha；深色 radius 16vp、向下偏移 5vp、#60000000。投影在容器圆角下绘制，避免直角块状阴影。
- 日程管理保留更轻的 #42 危险柔色底，沿用相同阴影和圆角，区别于普通内容区域。
- 没有新增模糊采样、依赖或权限。半模态 REGULAR / #90、按钮原生沉浸材质及此前高光圆角修复保持不变。

验证：编辑回归99项、材质回归28项，共127项通过；32文件ArkTS无错误；Lint无错误、5条既有组件结构建议；签名构建BUILD SUCCESSFUL，安装启动Smoke PASS，2条既有输入控制器SysCap提示保留。没有新增仅复述样式参数的测试。

本轮真机仅查看当前墨影 / 系统浅色下的已有当日日程编辑及新建未来表单：分区较背景更清晰、边线与柔和阴影正常，取消返回主页。没有保存、删除或切换主题；验收前后 data.json 完全一致，均9542字节，未使用前轮数据回灌。新建当日共用同一内容 / 分组样式，但本轮没有单独截图；深色参数已实现并构建，尚未新增深色、其它配色、低算力或大字体的真机验收。

本轮私有证据在 `.tooling/editor-depth/`：`edit.png`、`future.png`、`final-home.png`，相关检查 / 构建 / 安装日志及只读数据核对快照。前文 `.tooling/editor-layout/` 对应增强阴影前的历史验收，不能代替本轮截图。

## 分区沉浸光感与输入框区分（2026-10-22 后续修订，仅本地验证）

用户要求将分区与进度快捷按钮使用沉浸光感，同时明确无需截图或操作检查、只需确保构建成功。因此本轮未调用设备安装、截图或 UI 操作；下文只报告代码与本地验证，不把前轮截图作为本轮材质效果的证据。

### 实现

- 新增 `components/MaterialSection.ets`，参考 DeepSeekUsage 的 NativeMaterialSurface，将每个分区的唯一真实业务子树放在小尺寸 Navigation 的原生标题作用域内，避免在普通内容区域直接设置 `systemMaterial` 而不生效。没有复制输入框、添加交互遮罩或增加页面路由。
- 容器按实际宽度测量业务内容的自然高度；通过 onMeasureSize 与尺寸回调同步原生标题高度，覆盖日期提示、分组草稿、进度展开等内容变化。使用18vp圆角与对应裁切，宿主不继承键盘安全区。
- `Materials.section()` 使用 REGULAR、普通分区 #40 面板赋色、日程管理 #24 危险柔色赋色，由系统接管背板和阴影，不再叠加前轮自绘底色与边框。分区不启用按钮式形变或触摸高光；保留原有半模态 REGULAR / #90。
- 继续使用官方自动分档：低档不传入赋色，使用系统默认背板；真正不支持原生材质时，EditorSectionModifier 保留前轮轻色、亮边和投影回退。
- 0 / 25 / 50 / 75 / 100% 进度快捷按钮通过真实的进度分区标题作用域应用现有 PlanerControlModifier，使用超薄材质及主题色选中态，不再只是普通轻色背景。原进度更新、完成与取消逻辑不变。
- `EditorMaterialRefresh` 按帧合并滚动与位置变化后的重绘，只刷新滚动区相交的已挂载分区，离场清理登记；不使用常驻计时器轮询。
- 日程 TextArea 使用 `Materials.input()` 的 #F2 主题底色：浅色取 bgSoft，深色取更深的 bg；细边线与外层材质区分，聚焦后改为主题强调色，输入文字不降低透明度。占位文字使用可读辅助色，仍为12vp内圆角。

### 本地验证

- `test-editor.mjs`：99 项；`test-materials.mjs`：28 项，合计127项通过，未增加仅复述视觉参数的测试。
- DevEco `check arkts`：33 文件通过，0 error。
- DevEco `check lint`：0 error / 5条既有组件结构性能建议，未禁用规则。
- DevEco API26 签名构建：BUILD SUCCESSFUL；2条既有输入控制器 SysCap 提示保留。
- 产物：`entry/build/default/outputs/default/entry-default-signed.hap`。
- 日志：`.tooling/editor-immersive/` 中的 `test-editor.log`、`test-materials.log`、`arkts.log`、`lint.log`、`build.log`，以及修改前源码备份。

本轮不声明完成原生材质渲染、嵌套标题作用域、自然高度初次测量与动态展开、输入焦点、键盘避让或滚动刷新真机验收；这些仍需之后实际运行确认。没有访问或修改设备中的用户数据。

## 进度与分组展开受限修复（2026-10-22，仅本地验证）

用户反馈打开进度开关和新建分组均不能展开。共同问题在上一轮 MaterialSection：真实业务内容被放在固定高度的原生标题内，onMeasureSize 又使用已有测量结果给标题及子节点施加相同的 minHeight / maxHeight，形成旧高度限制；外层 onSizeChange 也不能可靠地感知被裁切内容的增高。

本次移除自定义 onMeasureSize、手动 FrameNode.measure、缓存的 measuredWidth / measuredHeight，以及真实正文的固定标题承载。业务内容直接放在自然高度 Column 中，原生材质改由官方 background(CustomBuilder) 提供无交互背板；背板 Navigation 和标题按100%尺寸填充正文区域，不反过来约束正文。只构建一份业务子树，背景不包含输入框或进度 / 分组控件，不拦截触摸。旧版本回退也继续使用自然高度。

因为进度按钮随正文移出了分区标题作用域，五个快捷按钮分别使用已有固定44vp MaterialButtonScope，保持超薄材质、选中反馈和原进度逻辑。分组选择 / 新建已有独立按钮作用域，保持不变；输入框对比样式及半模态 REGULAR / #90 未改变。

接口核对采用当前 SDK common.d.ts 的 background / BackgroundOptions 与 navigation.d.ts 的 NavigationCustomTitle，并阅读 OpenHarmony 官方上游背景设置文档：
https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-background.md

本地验证：编辑99项、材质28项，共127项通过；33文件ArkTS无错误；Lint无错误、5条既有建议；最终签名构建BUILD SUCCESSFUL，2条既有输入控制器SysCap提示保留。本轮没有设备操作、截图或安装，不能据此声明已完成展开渲染、动画和材质背板同步的真机复验。

日志与改动前备份在 `.tooling/material-expand-fix/`，构建产物仍为 `entry/build/default/outputs/default/entry-default-signed.hap`。

## 分区背景未显示的真机修复（2026-10-22）

用户授权手机操作后，在已安装版本复现：进度及分组已能展开，但圆角分区背板没有显示，因而视觉上退回扁平布局。本轮确认上一版的 background(CustomBuilder) + 百分比 Navigation 标题组合没有在该真机上绘制出预期材质；不能用编译通过推断原生材质实际生效。

### 修复

- MaterialSection 改为同一组件树内的双层 Column：真实正文保留自然高度，原生背板通过 position 绝对定位且不占位；正文的 onSizeChange 单向更新背板与 Navigation 标题的数值高度。
- 背板没有输入、按钮或任何业务内容，设置 HitTestMode.None 并从无障碍树排除；唯一的真实表单在前景，保持触摸、输入与滚动。
- 不再将原生 Navigation 放进离屏自定义背景，也不恢复原先正文固定标题高度的测量循环。旧背板高度不会决定正文高度，支持展开后收起。
- 原生分区 REGULAR / #40（管理区 #24）、半模态 REGULAR / #90、官方算力分档与不支持时的有色阴影回退、输入框区分及按钮样式未变。

布局行为核对了官方 position 文档：Row / Column / Flex 下绝对定位的子节点不占位。
https://raw.githubusercontent.com/openharmony/docs/master/zh-cn/application-dev/reference/apis-arkui/arkui-ts/ts-universal-attributes-location.md#position

### 验证范围

- 编辑回归99项、材质回归28项，共127项通过；33文件ArkTS无错误，Lint无错误、5条既有建议；API26签名构建 BUILD SUCCESSFUL，2条既有输入控制器SysCap提示保留。安装启动 Smoke PASS。
- Mate 80 Pro Max 当前墨影 / 系统浅色：编辑日程的内容、分组、进度、管理区域均有圆角原生材质背板；TextArea 与外层可区分。
- 进度开关展开后出现滑块与5个快捷按钮，点击50%后数值、滑块与选中态同步；关闭后背板高度缩回。滚动时分区背景随内容位置移动。
- 新建分组后输入区域和取消 / 创建按钮完整显示，背板同步增高；新建当日表单中点击分组内取消后区域与背板正常收起。未创建任何分组。
- 新建当日、未来的材质正常；未来表单起始 / 截止选择项可切换。所有表单取消返回主页，没有保存、删除或调整主题。
- 本轮开始读取当前 data.json 作为基线，结束再次读取逐字节比较：完全一致，均9542字节。没有用旧备份覆盖用户数据。
- 本轮没有追加深色、其它配色、低性能设备、大字体或录屏帧率测试；这些效果不由当前手机截图证明。

私有日志与截图：`.tooling/material-runtime-fix/`。`installed-home.png`、`progress-before.png`、`groups-before.png` 是修复前；最终查看证据为 `edit-after.png`、`scrolled.png`、`selected-final.png`、`collapse-final.png`、`group-expanded-final.png`、`today.png`、`today-group-open.png`、`today-group-closed.png`、`future.png`。早期 `progress-after.png` 拍摄时未呈现展开结果，不作为最终进度通过证据；最终以选值、关闭与实际布局结果为准。检查、构建、安装日志和本轮数据一致性日志均在同目录。签名产物仍为 `entry/build/default/outputs/default/entry-default-signed.hap`。

## 分区轮廓展开 / 收起动画修复（2026-10-22）

用户反馈内容有出现 / 消失动画，但矩形轮廓直接跳变。原因是正文的 onSizeChange 在原展开 animateTo 闭包外更新了背板高度；直接赋值没有获得正文弹簧动画。初步增加显式动画后，录屏又发现 Navigation 自定义标题的高度会提前按收起后的最终尺寸裁切材质，仍会让收起轮廓突然变小。因此最终修复分为动画高度与裁切范围两部分。

- MaterialSection 的 updateSurfaceHeight 以项目统一 Motion.spring 驱动实际原生材质节点的高度变化；首次有效测量直接就位，避免半模态入场时再从1vp展开。
- scopeHeight 只决定原生标题与承载区域的可绘制范围：展开前立即提供足够空间，收起时保留原范围，待弹簧结束再收紧。标题内透明容器顶部对齐，材质节点自身绘制连续变化的圆角轮廓，不靠缩放整张表单模拟。
- 正文仍保持自然布局，背板绝对定位、不占位、不截获触摸，不重新引入正文固定标题高度或自定义 background 的回归。
- 动画完成回调校验修订号和组件存活状态，防止先前动画结束时覆盖后续操作的裁切范围。重复尺寸与无效测量不重复启动动画。
- 分区材质、半模态厚度、输入框对比、按钮风格及数据逻辑不变。

验证：最终源码编辑99项、材质28项，共127项回归通过；33文件ArkTS无错误，Lint无错误、5条既有建议；API26签名构建 BUILD SUCCESSFUL，2条既有输入控制器SysCap提示保留。最终签名包已安装，Smoke PASS。

Mate 80 Pro Max 当前主题下录屏检查进度展开 / 收起、新建分组展开 / 取消收起的中间帧：轮廓连续增高与缩短，不再被原生标题提前裁切。另连续切换进度4次后，滑块状态与四个分区的最终边界均与操作前相同，没有残留空白。各次点击间隔约0.45至0.60秒，不将其表述为已经覆盖任意高频输入。所有编辑操作留在草稿中并最终取消；验收前后 data.json 逐字节完全一致，均9542字节，没有回灌历史备份。本轮未新增其它主题、旧系统或低性能设备验收，也不根据录屏平均帧率推断运行帧率。

私有证据 `.tooling/material-spring-fix/`：最终录屏 sections-final.mp4、rapid-final.mp4；逐帧对照 final-event-0.jpg 至 final-event-3.jpg；最终检查 / 构建 / 安装日志的文件名带 final；数据核对 data-check.log。sections.mp4 及未带 final 的逐帧图对应首次实验，其中收起仍有提前裁切，不代表交付效果。录屏为可变帧率，最终逐帧对照按顺序解码和实际时间戳提取，不用平均帧率随机定位帧。官方接口说明通过 DevEco CLI 的显式动画文档核对，快照为 animate-doc.txt。

## 收起阴影拖尾与结束闪消修复（2026-10-22）

用户反馈轮廓动画恢复后，收起时底部阴影拖尾，结束时突然消失。原实现保留较大的 scopeHeight 以避免原生标题提前裁切轮廓，但原生材质阴影仍处于该标题的裁切范围内，结束时 scopeHeight 收紧又会裁掉残留投影。保留旧裁切范围仅适用于材质轮廓，不能同时把动态阴影留在该范围内。

最终实现：

- 仅 Materials.section 的 ImmersiveOptions 设置 applyShadow:false，半模态、按钮、底栏、确认框的原生阴影配置不变。官方 uiMaterial 文档明确该值关闭材质自带阴影并允许普通 shadow 属性生效，且适用于全部材质算力档。
- EditorSectionModifier 在原生材质节点清除普通阴影；MaterialSection 在 Navigation 之外增加一个无交互、无可见底色的圆角投影节点，与真实材质背板共用 surfaceHeight 和原有 Motion.spring 动画。投影不依赖 scopeHeight，也不受标题完成回调的裁切变化影响。
- 普通阴影参数统一由 Materials.sectionShadow 提供，fill:false 避免染黑透明材质内部；沿用原有浅深色柔和投影参数。原生材质的赋色、厚度、高光、圆角以及先前的自然布局和高度动画均保留。真正不支持原生材质时继续使用有色底板与相同普通阴影。
- 不通过动画期间隐藏阴影、计时器或结束时切换透明度掩盖问题。

本地验证：编辑99项、材质32项，共131项通过；新增4项材质回归覆盖只关闭分区材质阴影、清除标题内重复阴影与独立投影非填充、低档默认有色背板和真正不支持时的回退。README当前测试表已从28更新为32，历史记录中的旧数字不改。33文件ArkTS无错误；Lint无错误、5条既有建议；API26签名构建 BUILD SUCCESSFUL，2条既有输入控制器SysCap提示保留，安装启动 Smoke PASS。

Mate 80 Pro Max 当前墨影 / 系统浅色下录制了进度展开 / 收起及分组展开 / 取消收起：底部投影随实际底边移动，没有再观察到大矩形位置的阴影滞留；进度收起后约0.3、0.7、1.7、2.7秒的实际帧对照，阴影保持稳定，不随标题范围收紧突然消失。当前浅色下静止分区仍有柔和层次，输入框与分区可区分。没有新增深色、低档设备、大字体或帧率性能验收，不把静态代理回归当作这些设备的渲染证明。

所有验收只修改编辑草稿，最后取消回主页；本轮数据基线重新读取，前后逐字节一致，均9543字节（用户在前轮之后的数据变化不回滚）。没有创建、删除日程或分组，没有切换主题。录屏已停止。

私有证据在 `.tooling/material-shadow-fix/`：shadow-before.mp4 为原问题；shadow-final.mp4、shadow-final-close-1.jpg、shadow-final-close-3.jpg、settled-shadow-final.jpg 为最终进度 / 分组收起与收尾对照；editor-final.png 为静止材质与投影，final-home.png 为取消返回。录屏按顺序解码并使用真实时间戳，文件平均帧率不代表运行帧率。最终检查 / 构建 / 安装 / 回归日志名带 final，data-check.log 为数据一致性结果。首次普通阴影直接留在标题内的中间版本仅本地构建，没有安装；最终投影节点在标题之外。

## 分组标题删除按钮背板修复（2026-10-22）

用户指出分组删除图标未被背景完整包裹。原分组入口使用22vp按钮和固定21vp图标，几乎没有内边距；原44vp responseRegion只扩大响应范围，不会扩大可见背景。

IconButton新增可选iconSize与cornerRadius，默认仍为21与12；仅主页两区的分组标题删除入口改为32vp可见背板、18vp官方图标与10vp圆角，原生MaterialButtonScope同步使用同一圆角。标题行居中容纳按钮，行后间距从12收紧为6，避免因扩背景增加过多留白。最小44vp响应区、删除确认、任务归未分组以及取消逻辑不变。

202项拖动回归与32项材质回归通过；33文件ArkTS无错误，Lint无错误 / 5条既有建议；API26签名构建BUILD SUCCESSFUL，2条既有输入控制器SysCap提示保留；安装启动Smoke PASS。Mate 80 Pro Max纯示例分组下，真实按钮108×108px对应32vp，图标四周内边距清晰，点击打开删除确认并取消。没有删除任何分组。修复后的图二已重新实拍合成。

两轮示例拍摄使用各自最新备份恢复。最终日程、上一份备份、教程与两份组件注册首选项回读SHA256五项一致；可见桌面组件不再显示示例内容，已返回应用。私有代码备份、回归 / 构建日志与组件素材在`.tooling/store-widgets-three-20261022/`，图二拍摄、确认框与最终恢复证据在其`button-capture/`。没有新增深色、旧系统或低性能设备按钮真机验证。
