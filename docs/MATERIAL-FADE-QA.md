# 按钮采样、桌面材质研究与列表渐隐验收

日期：2026-10-22；应用 V1.1.0，编译 / 目标 26.0.0，最低兼容 6.1.1(24)。仅修改 PlanerHarmony，DeepSeekUsage 只读参考。

## 实现与边界

| 需求 | 本次结果 |
| --- | --- |
| 按钮更通透、随背景透色 | `Appearance.ets` 的普通按钮和历史返回按钮改用 ULTRA_THIN；普通按钮取消白色赋色，强调 / 危险态仅保留低透明度轻色；透明默认背景与原生标题承载保持不变。没有额外叠加毛玻璃。 |
| 桌面组件能否复用参考项目方案 | 已阅读 NativeMaterial、MaterialTransparency、MaterialScrollRefresh、MaterialProbePage 及项目附带沉浸光感经验文档，并完成隔离编译；当前工具链无法用于桌面卡片，保留现有可读背板。 |
| 日程渐隐圆角与底栏异常 | 从有色圆角遮盖层改为只作用于列表的 DST_IN 透明度蒙版；完整列表视口统一离屏混合，保留真实卡片圆角，未来渐隐连续延伸经过底栏后方直至屏幕底边；不对 Tabs 或根背景混合。 |

按钮采样由原生材质执行。当前 `ImmersiveOptions` 没有指定采样源节点的公开字段，因此未实现“绕过半模态材质、单独指定主页节点采样”；面板材质保持用户原参数。效果强度仍受系统设置、设备能力和背后实际内容影响，本次不能将更通透等同于跨层直接采样。深色及不支持材质设备的实效尚未覆盖，兼容回退分支保留。

## 桌面卡片研究证据

参考项目修复的是应用内容区 `out of scope`：将单份真实内容放入小尺寸 Navigation 的自定义标题，获得已支持的材质作用域。它没有桌面 Form 卡片实现。

本次在 WidgetCard 中隔离验证同样的 Navigation 标题承载，实际完整构建报 **11706006**：Navigation、title、titleMode、NavigationTitleMode 等不支持 form application。该失败发生在组件编译阶段，无法通过移动位置解决；之前 `ImmersiveMaterial` / `ImmersiveStyle` 构造本身也被同一编译器拒绝。

实验使用 finally 恢复原 WidgetCard，未将实验包安装到手机，没有修改最低兼容版本或关闭检查。证据日志：`.tooling/material-fade/widget-navigation-probe.log`。最终 WidgetCard 与实验前文件内容一致。

另查 HDS 材质接口：当前 SDK 的 `hdsMaterial` 为材质类型枚举及设备能力查询，不能给任意背板传入 `uiMaterial.ImmersiveMaterial`。官方“背板透明卡片”是另一项能力，需要申请开放能力和相应手动签名；透明背板不等于沉浸光感，本次没有擅自修改配置或签名。

官方资料由 DevEco CLI 读取并保存在本地：

- [开启沉浸光感](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-enable)
- [沉浸光感常见问题](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-faq)
- CLI FAQ `faqs-arkui-343`：List 与 DST_IN / OFFSCREEN 渐变遮罩示例。
- CLI 指南 `arkts-ui-transparent-backplate-form-development`：背板透明卡片申请、签名与配置约束。

## 蒙版修订与真机范围

旧渐隐是一块独立圆角渐变色 Row，颜色不随根背景的实际位置变化，产生卡片两侧色块与悬浮栏顶部截线。新版蒙版只衰减列表自身像素，页面原渐变和 Tabs 的原生材质仍各自绘制。

初版将蒙版放在带 padding 的 List 上，真机发现右侧未混合窄条；已移至无 padding 的完整视口。随后发现蒙版命中容器阻挡交互；最终采用直接 Stack 子节点，容器 `HitTestMode.Transparent`，Blank / Row 子节点均 `HitTestMode.None`。构建成功不能替代这类命中验证。

Mate 80 Pro Max、当前系统主题 / 墨影色板实测：

- 有后续日程时，卡片自身渐隐，无额外有色色块或圆角直边。
- 当日、未来两区分别向上滚到底，末项完整进入可操作区时恢复完整显示；回滚后提示恢复。
- 未来内容在悬浮底栏后连续经过，无原有顶部水平截线；可将最后一条滑到胶囊上方操作。
- 新增、真实列表编辑、取消按钮可用；编辑器按钮可透出后方色彩，空表单添加仍禁用。未保存草稿或新增测试项。
- 结束时恢复两区列表顶部。`device-before.json` 与 `device-final.json` 内容完全相同。

最终有效截图（忽略目录 `.tooling/material-fade/`）：`verified-final-home.png`、`today-transparent-mask.png`、`future-transparent-mask.png`、`list-edit-verified.png`、`button-editor.png`。较早带 `after`、`viewport`、`direct`、`scroll-check` 的截图是过程证据，不作为最终交互通过依据。

未量测动画帧率 / 功耗，也未验证其他分辨率、大字体、真实系统深浅切换及最低兼容设备。

## 最终检查

- ArkTS：31 文件，0 error。
- Lint：0 error / 5 warning，4 条既有组件结构建议及 1 条原生材质承载结构建议；未禁用规则。
- API 26 签名构建：BUILD SUCCESSFUL，保留输入控制器的 2 条既有 SysCap 提示。
- 8 个脚本：589 项断言通过（139 + 18 + 93 + 202 + 27 + 47 + 36 + 27）。新增 5 项渐隐范围边界；保留 240 种拖动组合。
- Hypium Local Test：5 pass，0 failure / error。
- 最终修复包已覆盖安装、启动 Smoke PASS，并完成上述真机验证。

日志：`.tooling/material-fade/arkts.log`、`lint.log`、`build.log`、`test-*.log`、`local-test.log`。产物：`entry/build/default/outputs/default/entry-default-signed.hap`。
