# PlanerHarmony 项目长期记忆

## HarmonyOS 开发工具链（本机实测，2026-10-22）

- **统一入口用 `devecocli`**（npm 全局包 @deveco/deveco-cli，v1.3.9）：`cmd //c "D:\Software\NodeJS\node_global\devecocli.cmd <子命令>"`，封装 build/run/device/emulator/skills/docs/log/ui/check/signature 等。
- **代理坑**：本 shell 默认 http_proxy/https_proxy=127.0.0.1:48924，devecocli 远程子命令（skills 拉取等）会报 "Invalid proxy authorization"，调用前需 `env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY` 绕过；本地 docs 检索不受影响。
- `docs search` 的 documentId 是完整中文路径（如 `开发指南/构建应用/.../xxx`），`docs read` 必须用该完整 ID，只用末段会报 not found。
- DevEco Studio 26.0.0.821 位于 `D:\Software\DevEco Studio`（官方最新 patch 为 26.0.0.851，SDK 26.0.0.105 与官方一致）；hdc/ohpm/hvigor 均不在 PATH，需绝对路径。
- deveco-cli skill 文档：`C:\Users\35101\.claude\skills\deveco-cli\SKILL.md`。

## 桌面卡片（Form Kit）硬约束（实测，2026-10-22）

- **卡片工程禁止 uiMaterial**：`uiMaterial`/`ImmersiveMaterial`/`ImmersiveStyle`/`systemMaterial`/`attributeModifier`/`ThemeColorMode` 在卡片页面编译期报 11706006 `can't support form application`；卡片背板只能用 `backgroundBlurStyle`。`hdsMaterial` 的枚举虽标注卡片能力，但承载它的 HDS 组件不可用。
- 单卡片多尺寸：form_config `supportDimensions` 列 3 项 + `resizable: true`；`isDefault` 必填且每 UIAbility 只能一个默认卡片；`updateEnabled: true` 时 `updateDuration`/`scheduledUpdateTime` 不可同时为空。
- 尺寸变化无回调：`onUpdateForm` 的 `wantParams` 只带宿主反色等参数，需用 `formProvider.getFormRect(formId)` 反推；`onAddForm` 用 `want.parameters[formInfo.FormParam.DIMENSION_KEY]`。
- 卡片进程回调后约 10 秒退出，长任务交主应用；formId 由 `onAddForm/onRemoveForm` 存 Preferences，主应用据此 `updateForm` 推送。
- 卡片读数据要自己读 `filesDir/data.json`（`PlanerStorage` 依赖 UIAbilityContext），并在内存里 `reduce(ROLLOVER_TO)` 顺延到真实今天，不写回。
- 真机 shell 无 `input` 命令、无法启动 launcher → 桌面卡片交互只能手工验收；`devecocli ui screenshot/click/longclick` 仅在应用内可用。
- **跨进程共享 Preferences 必须用 `context.getApplicationContext()`**，否则卡片扩展与主应用各存一份、推送不到卡片。
- **卡片深浅色不能读扩展进程的 `config.colorMode`**（那是系统值），要先看 `data.settings.themeMode`，仅 system 回落系统值。
- **卡片背板别用 `backgroundBlurStyle`**：材质色由系统给、不受色板控制，深色下会发灰压低对比度；改用色板半透明值（`#EB/#F2` + panel）并去掉自绘圆角/边框（系统会裁剪，双半径会错位）。
- 卡片内交互：行点击 `postCardAction({action:'message', params:{...}})` → `onFormEvent` → 写 `data.json`（独立 `.card.tmp` 原子替换）→ `updateForm` 全量推送；主应用回前台用文件比对采纳外部写入。
- **卡片深浅色必须走 dark 资源，不能靠 onConfigurationUpdate**：该回调官方文档写明“仅当 FormExtensionAbility 存活时才会触发”，进程退出后系统深浅切换收不到（实测现象：必须重开应用才刷新）。做法：base/dark `element/color.json` 定义 `card_<preset>_<slot>` 同名色，payload 带 `followSystem`/`preset`，卡片内用 `$r('app.color.card_*')`。依据：form_config 的 `colorMode` 自 API20 废弃、仅对 JS 卡片生效，ArkTS 卡片主题统一跟随系统、资源自动重新解析。
- **卡片点击热区别挂在小方块上**：16vp 方框 + `responseRegion` 在卡片内命中不可靠（用户表现为“点不动”）。改为整行 `Row.onClick` 内直接 `postCardAction`（`postCardAction` 只能写在 onClick 回调里），方框只负责绘制。**整行 onClick 不会影响 List 滑动**（实测，之前判断是被自动化坐标误导）。
- **卡片可滚动列表必须显式给高度**：卡片根容器高度按内容自适应，`layoutWeight(1)` 拿不到“剩余空间”，List 会撑高把进度条/页脚挤出卡片。做法：`height(Math.min(内容高度, 上限))`——内容少不空白、内容多则滚动；`List`/`ListItem` 自 API 9/10 起支持卡片。条数也不再按尺寸截断（去掉 `moreText`）。
- 卡片真机验收可用：`hdc.exe uitest uiInput keyEvent Home` 回桌面、`uitest uiInput swipe/click` 操作卡片（`devecocli ui` 的点击在 launcher 不生效）；坐标必须换算到设备像素并落在卡片矩形内，截图预览 400px ↔ 设备 1320px（×3.3）。
- **卡片动画的两个写法要点**：① 用 `if` 条件渲染的节点在隐藏时根本不存在，无法过渡——要动画的图标必须常驻，用 `opacity`/`scale` 切换再加 `.animation()`；② `TextDecorationType` 是离散值不能动画，删除线要固定 `LineThrough` 只过渡颜色（`transparent` ↔ 实色）实现“渐显/渐隐”。卡片内可用 `ProgressType.Ring`（API9+）与 `@State` 本地状态做点击即时反馈。
- 卡片里 `height('100%')` 常因父高度由内容决定而退化（把嵌套列表裁掉导致“滑不动”），可滚动区域给显式高度更稳。

## 文档约定

- README 的变更记录**只写功能层面**（新增 / 调整 / 移除），不写缺陷修复与排查过程；用户明确要求过这一点。
- 功能章节要随实现合并更新（例如「桌面卡片」的尺寸表、条目规则、同步策略），不要让 README 停留在早期形态。
- **`onFormEvent` 的 message 可能被 `params` 包裹**，解析要兼容 `{"params":{...}}` 与扁平两种形态，否则事件到达了也静默无响应。
- **重命名卡片里的颜色取值方法避开组件属性名**：成员方法名 `borderColor` 会与 `CustomComponent` 继承的 `borderColor` 属性签名冲突，编译报 10505001（改成 `lineColor` 之类即可）。
- `scripts/deveco.ps1` 是 UTF-8 无 BOM，Windows PowerShell 5.1 会按 ANSI 解析中文注释而报语法错误；需用 pwsh 或直接以同等环境变量调用 `cli.js`。
