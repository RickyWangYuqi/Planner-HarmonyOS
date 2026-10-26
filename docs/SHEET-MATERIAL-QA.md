# 半模态材质降级一致性修复

日期：2026-10-26。范围：新增、编辑等共用日程半模态，以及新手教程；底部悬浮 Tabs 作为观感参照。

## 环境与复现

- 使用本机通过 npm 安装的 `@deveco/deveco-cli 1.3.9`，入口为 `devecocli`，项目通过 `scripts/deveco.ps1` 调用。文档查询、检查、构建和设备验证均以该 CLI 为入口；它调用已安装的 SDK/构建工具，不是以 Studio 自带 CLI 替代 npm CLI。
- 连接设备为 HUAWEI MatePad Pro，API 26。临时运行日志确认 `isImmersiveMaterialSupported() = true`、`getGlobalMaterialLevel() = 1 (GENTLE)`、应用材质状态 `ENABLE`。诊断探针已移除。
- 将此前已有修复重新构建并安装后，仍能复现：底栏正常；新增/编辑外层背板仅剩半透明赋色；新手教程呈纯色。问题不是旧安装包未更新，也不是设备不支持材质。

## 根因与依据

此前已把中低档半模态改为与底栏相同的 `ULTRA_THIN`，并在全局 `SMOOTH` 时不传 `materialColor`，但这没有覆盖组件内部的再次降档。

DevEco CLI 的系统材质 API 与沉浸光感 FAQ 说明：低档不使用材质滤镜，显式 `materialColor` 直接成为背景色；不传赋色时才使用系统默认背板。进一步对照 OpenHarmony 公开实现发现：

1. [`MaterialUtils::LowerGearLevel`](https://github.com/openharmony/arkui_ace_engine/blob/21b150e7bb1d5308846f8e5be8ef0482fb433315/frameworks/core/components/common/properties/ui_material.cpp#L350) 对 `GENTLE` 的 `SHEET_PAGE_TAG` 额外降为 `SMOOTH`，而 Tabs 和通用 Column 保持设备档位。因此按全局 GENTLE 保留的半透明赋色，在原生 Sheet 内会成为无滤镜背景。
2. [`UpdateSheetBackgroundColor`](https://github.com/openharmony/arkui_ace_engine/blob/21b150e7bb1d5308846f8e5be8ef0482fb433315/frameworks/core/components_ng/pattern/sheet/sheet_presentation_pattern.cpp#L1897) 与 [Sheet 渲染更新](https://github.com/openharmony/arkui_ace_engine/blob/21b150e7bb1d5308846f8e5be8ef0482fb433315/frameworks/core/components_ng/pattern/overlay/overlay_manager.cpp#L4672) 会在非高档且存在材质对象时恢复 Sheet 默认底色，解释了仅替换材质参数无法保证相同观感。
3. 当前 [ArkTS JS 的 Sheet 参数解析](https://github.com/openharmony/arkui_ace_engine/blob/21b150e7bb1d5308846f8e5be8ef0482fb433315/frameworks/bridge/declarative_frontend/jsview/js_popups.cpp#L2743) 对未传材质保留空指针。`Material.empty` 则仍是对象，在上述更新分支中可能被当作存在材质而回填默认底色。

引用固定到公开提交 `21b150e7bb1d5308846f8e5be8ef0482fb433315`。这是 OpenHarmony 公开源码，并非读取或反编译平板商业系统源码；定位结论结合了公开实现、CLI 官方文档、设备档位日志及修改前后的实机结果。

## 修复方式与边界

- 新增共用 `SheetMaterialSurface`，日程表单和新手教程统一使用。中低档由 Navigation 标题合法作用域内的通用 Column 承载背板，使用与底栏一致的超薄样式和自适应赋色，避免 SheetPage 的额外降档。
- 此分支的原生 Sheet 不传 `systemMaterial`，明确设透明背景与 `BlurStyle.NONE`。原生 Sheet 继续负责尺寸、遮罩、拖动关闭和键盘配置；装饰背板不接收触摸，也不进入无障碍树。没有额外叠加传统背景模糊。
- GENTLE 保持系统中档效果；SMOOTH 仍交给系统低档背景、边框与阴影，不强制提升算力等级。高档继续使用原生 Sheet 的既有材质与厚度。旧 API、设备不支持或应用禁用材质时继续使用普通可读背景。
- 档位查询异常时采用内容背板，赋色由系统决定。底栏本身未改动。

## 本轮验证

| 项目 | 结果 |
| --- | --- |
| 旧修复重新构建、安装及启动 | 成功，原问题仍可复现 |
| API 26 GENTLE 平板新增日程 | 已验证：外层背板出现背景模糊与白色边缘，符合底栏的降级观感 |
| 同机新手教程 | 已验证：背板出现背景模糊与白色边缘，不再是原先的纯色面板 |
| 当日日程新增、已有日程编辑 | 背板模糊与边缘正常，窄面板、宽面板内容及底部操作保留；只打开并取消，未提交或删除日程 |
| 编辑输入框键盘 | 键盘弹出后取消、保存仍可见；点击取消可退出，主页未被键盘重新缩放 |
| 日期面板 | 共用背板生效，日历及关闭区域正常；未改变所选日期 |
| 教程主题与关闭 | 深色、恢复跟随系统后的浅色均重新打开验证；顶部无透明空带，正文保持原有居中；下滑关闭与“稍后”均有效 |
| 自动回归 | 材质 43、编辑 107、教程 27，合计 177 项通过 |
| ArkTS / Lint | ArkTS 35 文件无错误；Lint 0 error，保留 5 条既有组件结构建议 |
| Debug / Release 签名构建 | 均 BUILD SUCCESSFUL；保留 2 条既有输入控制器 SysCap 提示，Release 另提示未开启混淆，未改动构建配置 |
| 最终 Release 安装与启动 | 覆盖安装成功，Smoke: PASS；未卸载或清空应用数据 |

本轮已确认的是该 GENTLE 平板上的渲染结果；不据此声称完成 EXQUISITE 或 SMOOTH 真机验收。高低档与不支持设备的分支保留情况，应与最终自动回归结果分别记录。

材质测试补入明确标注的平台节点分档模型，先复现“相同参数放在 SheetPage 仍无滤镜”的旧缺陷，再验证通用背板分支、原生背景清理、主题回填条件与低档默认赋色。模型不模拟 GPU；真实布局及滤镜效果由上述设备截图补充。README 仅同步相关材质描述与 43 项测试数量。

## 本地证据与产物

证据位于被忽略的 `.tooling/sheet-material-20261026/`，不将含现有日程的设备截图放入公开素材：

- `material-editor-current.png`、`material-tutorial-current.png`：重新安装此前修复后仍然复现的基线。
- `material-editor-surface1.png`、`material-edit-final.png`、`material-today-final.png`：未来新增、编辑、当日新增的修复效果。
- `material-keyboard-final.png`、`material-date-final.png`：键盘及日期面板。
- `material-tutorial-final.png`、`material-tutorial-dark-final.png`：居中布局修正后的教程浅色与深色。
- `build-release.log`、`install-release.log`：最终构建及安装、启动记录。

最终签名包：`entry/build/default/outputs/default/entry-default-signed.hap`。

SHA-256：`D048FFA7BE122BE82476ACF662FB9D5D91B2500A75C54339B001670000A4EF2B`。

验证结束恢复“跟随系统”主题并返回主页；原有当日日程仍为 0/1 完成，未来列表为空。未新增、提交、删除或勾选日程。

## 同日后续：恢复中性背板颜色

按根目录「原版背景颜色.jpg」调整教程、新增、编辑及共用半模态的背景赋色。中高档改用浅色 #90FFFFFF、深色 #90202020，不再混入主题强调色；不支持材质时使用对应的白色或深灰底色。低档仍交给系统默认背板。材质厚度枚举、光效、阴影、通用背板承载和上文的降级修复均未改动。

通过 npm DevEco CLI 检查 35 个 ArkTS 文件无错误，原有材质回归 43 项通过；Release 签名构建、覆盖安装及启动 Smoke PASS。API 26 GENTLE 平板竖屏已查看新增、编辑和教程：面板恢复接近参考图的中性浅白，背后内容仍有模糊，边缘光感保留。深色使用中性灰的代码分支，本次未另外切换深色实测。未改日程或主题设置，验证后回到主页。

本次证据在 `.tooling/sheet-neutral-20261026/`：`add-neutral.png`、`edit-neutral.png`、`tutorial-neutral.png`、`test-materials.log`、`build-release.log`、`install-release.log`。README 同步中性色描述，测试数量不变。

本次产物覆盖了上文降级修复阶段的同路径签名包；当前 SHA-256 为 `F61717BA65BA3C1629A89C9E504447C89E96A631E606D3F8812DB471A10DC6BE`。