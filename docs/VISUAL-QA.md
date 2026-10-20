# 界面与动画改造验收

日期：2026-10-15。设备：HUAWEI Mate 80 Pro Max，API 26 Release，1320×2848 竖屏。当前记录针对官方图标、沉浸材质、底部页签、圆角与动效改造；前一轮完整业务验收见 [DEVICE-QA.md](DEVICE-QA.md)。

## 六项需求与实现

| 需求 | 实现与实际覆盖 |
| --- | --- |
| 使用官方图标 | 使用用户提供的 house、gearshape、calendar、square_and_pencil、trash、plus SVG；关闭、方向、移动、恢复、勾选和历史使用 API 26 官方 sys.symbol。SVG 2 解码后着色，保留镂空；页签副本仅调整根尺寸为 viewBox，原图不修改。真机确认首页、设置、日历、编辑、移动及历史图标显示正常。 |
| 毛玻璃及沉浸光感 | module.json5 开启 ohos.arkui.UIMaterial.state；原生浮动 Tabs、bindSheet 和确认弹窗使用 ImmersiveMaterial。普通卡片、输入框周边及按钮使用半透明底色与 COMPONENT_THIN，按官方允许范围接入，未把普通内容区的无效 systemMaterial 调用当作实现。 |
| 主页／设置同级底栏 | 原生 Tabs，左主页、右设置；barOverlap + barFloatingStyle 提供悬浮光感材质。历史是设置子页。真机双向切换、历史进入返回通过，19/20 为最终复验截图。 |
| 补充非线性动画 | Motion 统一主题颜色 360ms 三次贝塞尔、位移和按压弹簧；覆盖页签、历史进退、列表变化、完成标记、月历换月、分组／进度展开、选择反馈。Scroll/List 统一 Spring 边界回弹。面板与系统弹窗保留原生过渡。没有进行帧率或逐帧轨迹量测。 |
| 圆角矩形 | 卡片、输入、按钮、分组和日期选择采用统一圆角矩形；底栏按用户指定的浮动胶囊形态保留原生外观。系统 Toggle/Slider 保留平台组件形态。 |
| 精简主页文案 | 移除右上角“本地 · 自动保存”和重复的设置入口；保存失败提示仍保留。自动保存行为不变。 |

当前图标全部可由下载资源和 SDK 官方符号覆盖，无须补充下载。

## 构建与检查

| 命令 | 结果 |
| --- | --- |
| scripts/deveco.ps1 check arkts | 15 个文件，0 error |
| scripts/deveco.ps1 check lint | 0 error / 3 warning；HistoryView、PlanerIcon、SettingsView 的组件抽取性能建议 |
| scripts/deveco.ps1 build / run | 最终签名构建 BUILD SUCCESSFUL |
| scripts/deveco.ps1 run | 安装、启动成功，Smoke: PASS |
| node scripts/test-engine.mjs | 103 项断言通过 |
| node scripts/test-storage.mjs | 18 项断言通过；内存文件接口模拟，不等同于设备故障注入 |
| scripts/deveco.ps1 hvigor test -p module=entry -p coverage=false --no-daemon | 本轮重跑 Hypium 5 pass / 0 failure / 0 error |

Hypium 报告：[test_result.txt](../entry/.test/default/intermediates/test/coverage_data/test_result.txt)。
已签名产物：[entry-default-signed.hap](../entry/build/default/outputs/default/entry-default-signed.hap)。

签名继续使用用户在 DevEco Studio 配置的材料。中途无线调试断开，用户重连后最终构建已重新部署成功。未修改桌面 Planer 源码或重新生成用户签名。

## 真机实际操作

1. 点击底栏设置／主页双向切换，检查页面、线框／填充官方图标和文字选中颜色一致。
2. 海盐切深色，再恢复跟随系统；森林切深色，再恢复海盐与跟随系统。确认页面、浮动底栏与状态／手势区配色。
3. 新建“验收材质动画”，软键盘弹出时取消和添加按钮保持可见，提交成功。
4. 操作菜单进入“移到未来日程”，半模态从内容高度平滑调整为日期表单高度；执行下个月点击后取消，未改任务日期。
5. 重新打开该验收任务的操作菜单，确认沉浸光感删除弹窗文案只指向该任务，确认删除成功。
6. 设置滚动到底部，再向上滑动触及边界，页面返回稳定位置；进入空历史并返回设置，滚动位置保留。
7. 最终回到主页，确认仅剩用户原有的“1”“2”两条日程，未来和历史仍为空。

本轮没有改动原有两条任务内容、完成状态或排序。验收新增项已清理；日期为 10/15，配色海盐、主题跟随系统、分组关闭。

## 本轮发现并修复

- 原生页签属性变化会回到传入索引：改用双向绑定 index，并将动效期间的图标显示索引与控制索引分开；在 onAnimationStart 更新图标，在 onChange 同步最终页面。最终双向切换和配色变更后均正常。
- 手动设置应用颜色会污染普通配置回调中的“系统色”：EntryAbility 只订阅真实系统配置变化，应用覆盖与系统模式分开维护。
- 官方 SVG 自带 48px 根尺寸会影响原生页签默认尺寸：保留原素材并创建只调整根尺寸的 _tab 副本。
- 离场过渡可能让旧分组节点暂时保留：分组标题增加索引边界保护，拖动槽按任务 ID 查询实时位置。
- 半模态快速关闭再打开时，旧 onDisappear 不再清空新面板状态。

## 截图

- [最终主页及清理结果](screenshots/24-final-material-clean.png)
- [最终设置页签](screenshots/19-tabs-bound-settings.png)
- [最终主页页签](screenshots/20-tabs-bound-home.png)
- [新增毛玻璃面板](screenshots/14-add-sheet.png)
- [软键盘避让](screenshots/15-sheet-keyboard.png)
- [日期移动面板](screenshots/21-move-calendar.png)
- [删除确认光感弹窗](screenshots/22-delete-dialog.png)
- [森林深色设置](screenshots/23-forest-dark.png)

10–18 为开发过程截图；其中 11、12、16–18 含修复前的页签选中状态，不代表最终导航效果。14/15 对应的半模态和键盘布局在最终版本保持相同。

## 复现方式与边界

在 PlanerHarmony 目录执行：

    .\scripts\deveco.ps1 check arkts
    .\scripts\deveco.ps1 check lint
    .\scripts\deveco.ps1 run

设备已连接时，run 会构建、安装、启动并执行冒烟检查。签名产物已经生成，仅安装已有产物可使用 run --skip-build。

动画曲线、边界回弹及材质 API 已接入并完成上述交互；截图只能记录静态结果，不作为稳定帧率或每一帧运动轨迹的证明。未覆盖其他屏幕尺寸／大字体、低端设备材质回退、真实系统深浅色实时切换、低电量模式、长列表性能与复杂整组拖动。此前业务验收中的未覆盖项仍以 DEVICE-QA.md 为准。