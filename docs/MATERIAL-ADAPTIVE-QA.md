# 材质自动分档、半模态厚度与分组轮廓

日期：2026-10-22；应用 V1.1.0；编译 / 目标 SDK 26.0.0，最低兼容 6.1.1(24)。修改范围仅 PlanerHarmony，未改变版本、签名、权限或 SDK 配置。

## 官方接口确认与用户选择

用户最终选择「保留官方自动降档，修正透明背景」，因此本次没有增加低档毛玻璃分支，也不手动指定算力或强制高档。

通过 DevEco CLI 阅读的官方文档：

- `开发指南/ArkUI_方舟UI框架/UI开发_ArkTS声明式开发范式/沉浸光感/沉浸光感常见问题/arkts-immersive-light-sense-faq`。
- `API参考/ArkUI_方舟UI框架/ArkTS_API/UI界面/ohos_arkui_uiMaterial_系统材质_/arkts-apis-uimaterial`，此前快照见 `.tooling/widget-material-reference/official-uiMaterial.txt`。

`uiMaterial` 的 EXQUISITE / GENTLE / SMOOTH 由设备自动确定，`getGlobalMaterialLevel()` 只能读取。HDS 的 `MaterialLevel.ADAPTIVE` 是另一套接口中显式选择自适应的方式。官方自动降档在低算力设备上只作用于背景色、边框、阴影；不会自动切换成 `backgroundBlurStyle` 毛玻璃。低档的 `materialColor` 若有值，会直接作为背景色；因此原先显式透明的赋色会覆盖默认可读背板。

## 实现与调整位置

### 统一自适应赋色

`entry/src/main/ets/theme/Appearance.ets`：

- `Materials.adaptiveTint()`：中高档保留请求的赋色；低档返回 undefined，交给系统默认材质背景处理，不另绘制背景层。档位读取异常同样使用系统默认色，不沿用透明值。
- `Materials.supported()`：保留版本及设备能力判断，补充应用级 DISABLE 和能力查询失败保护；这与低档自动降级是两个不同概念。
- 底部 Tabs、普通确认弹窗、半模态、历史返回按钮，以及统一操作按钮都使用该赋色规则。桌面 Form 卡片继续使用此前的主题渐变，不受此轮应用内材质改动影响。
- `PlanerControlModifier` 的材质缓存以最终赋色为键，低档默认值与高档透明值分开，避免误复用透明材质。

### 半模态背景稍加厚

`Materials.sheetMaterial()` 是统一入口；`Materials.sheet()` 将它用于编辑、新建、日期、移动、恢复等共用半模态及新手教程。

- `style: uiMaterial.ImmersiveStyle.THICK`：原来通过 dialog 使用 REGULAR，现在提高一档。可在 REGULAR / THICK / ULTRA_THICK 中调整；越厚越能遮挡后方细节。该样式参数只在官方中高算力档生效。
- `materialColor: Materials.adaptiveTint('#58' + palette.panel.substring(1))`：原来赋色 alpha 为 0x40（约 25% 不透明），现在为 0x58（约 35% 不透明）。可调整前两位十六进制 alpha，值越大越厚实；不要改成 FF，否则会遮住材质滤镜。低档不使用此赋色，继续采用系统默认背板。
- `blurStyle: NONE`：保持无额外毛玻璃叠层；不通过整张面板 `.opacity()` 改透明度，避免文字也变淡。
- 普通确认弹窗仍走 `Materials.dialog()` 的 REGULAR / #40，按钮仍为 ULTRA_THIN，互不牵连。原半模态高度、圆角、安全区、键盘行为、入场和关闭回调不变。

### 分组轮廓

`components/TaskEditor.ets` 的 `groupChip()` 与新建入口移除 MaterialButtonScope 外层静态描边。材质按钮由 `PlanerControlModifier` 清理自定义轮廓后绘制系统高光，选中状态用 #2A 主题淡染和原文字强调表达；高光与按钮形变属于同一节点，不再叠加一圈静态蓝框。

不支持原生材质时，实线标签 / 虚线新建入口的轮廓直接画在真实 Button 上，沿用 12vp 圆角；新建入口在各档位都保留加号。分组选择、草稿创建、长按删除与取消规则不变。

## 验证结果

- `node scripts/test-materials.mjs`：28 项通过；执行真实 Appearance.ets 工厂与修饰器，在内存中模拟官方档位、API 可用性与查询异常。覆盖默认色、缓存隔离、半模态参数、按钮轮廓及旧版本不调用新接口；不模拟 GPU 实际材质效果。
- `node scripts/test-editor.mjs`：93 项通过；`node scripts/test-tutorial.mjs`：27 项通过。本轮合计 148 项相关断言，未重跑不受影响的其它脚本或 Hypium。
- DevEco `check arkts`：32 文件，0 error。
- DevEco `check lint`：0 error / 5 条既有组件结构性能 warning，未禁用规则。
- API 26 签名构建 BUILD SUCCESSFUL，2 条既有输入控制器 SysCap 提示保留。覆盖安装与启动 Smoke PASS。
- Mate 80 Pro Max 当前墨影 / 跟随系统浅色：打开第一条已有当日日程，半模态后方内容更柔和、可辨但不干扰正文；「未分组」选中标签无额外蓝色框，新建入口保留加号。当前没有已保存分组，未为验收创建数据，因此不据此声明已有命名分组长按 / 删除已完成本轮真机复验。
- 已点击「取消」返回主页，未切换主题、未提交表单、未点击完成或删除。验收前后 data.json 内容完全一致，均 9571 字节；未回灌旧备份，手机停留主页。

本轮没有低算力真机，SMOOTH 档仅有官方语义核验与模拟回归，不声称完成低档实机渲染验收。系统真实深浅切换、其它屏幕 / 大字体及动画帧率也未新增验证。

日志及私有截图位于忽略目录 `.tooling/material-adaptive/`：`test-materials.log`、`test-editor.log`、`test-tutorial.log`、`arkts.log`、`lint.log`、`build.log`、`install.log`、`editor.png`、`final-home.png`，以及只读数据核对快照。构建产物仍是 `entry/build/default/outputs/default/entry-default-signed.hap`。
