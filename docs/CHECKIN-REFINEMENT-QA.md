# 打卡原位操作与半模态一致性验收

日期：2026-10-27。工具：本机 npm 安装的 `@deveco/deveco-cli`，经 `scripts/deveco.ps1` 调用。设备：HUAWEI Mate 80 Pro Max，API 26 Release。此次在手机验证，不以此前平板结果代替。

## 逐项处理

| 用户项 | 实现与自检 |
| --- | --- |
| 1 教程图标 | 打卡沿用系统勾选，分组使用系统四格图标；实际符号映射回归及手机画面确认两者不同。 |
| 2 详情入口 | 复用日程卡片的 `IconButton(icon: edit)`，44vp 容器水平、垂直居中；手机检查图标位置。 |
| 3 半模态规范 | 打卡详情统计、计划管理、时间线与异常内容调整使用 `MaterialSection`；日期选择及历史恢复表单补齐卡片分区。新建/编辑日程、移动至未来、打卡编辑与补卡已采用同一分区组件。按钮复用现有材质和图标。三条约定写入根目录 `AGENT.md`；按要求本轮不排查标题下穿规范。 |
| 4 原位完成/撤销 | 正常今日周期直接提交，不打开完成页面；保留卡片原顺序与按钮位置，仅内部图标文字切换。撤销无需弹窗。数值超限、待调整内容的特殊周期仍明确显示“调整本期内容”。 |
| 5 按钮样式 | 完成和撤销共用 136×44vp 普通沉浸材质按钮，文字/图标为柔和中性色，不用高饱和整行色块。 |
| 6 补卡渐隐 | 滚动区域底缘使用透明度渐隐，固定提示及操作区位于合成作用域外，不被渐隐遮掉；移除底部分割硬线，不叠加主题色蒙版。 |
| 7 四个管理按钮 | 编辑计划/补卡、暂停或恢复/删除排成两行等宽按钮，图标与文字居中，危险操作保留淡红提示及删除确认。 |
| 8 新建入场 | 新建只跟随原生半模态上升，不再附加横向转场；从详情进入编辑仍保留二级横向弹簧及返回。真实转场表达式和返回逻辑有回归。 |
| 9 补卡日期内容 | 选中已有记录展示当日原名称，已完成记录只读；非周期日显示“当日无打卡项”。去掉核对/已填入及“补卡不改变当前进度”。有效但没有历史快照的日期留空填写实际内容，不把今天数字冒充历史；空内容不能提交。 |
| 11 自动递增/接续 | 标签、空输入提示、编号/区间前缀、点击开启文字与多组数字提示按本轮要求调整；功能仍默认关闭，开启提示下一期名称。 |

## 真机流程与证据

本轮专用测试计划为 `本轮验证-背单词289-298`，ID `checkin-mvplavjg-yu6qe8`，开始于 10 月 24 日。完成后卡片边界仍为 `[54,1608,1266,2054]`、按钮仍为 `[753,1851,1212,2000]`，文字变为“撤销”，没有打开弹层；再次点击恢复待打卡。原有“看网课第5节”未执行完成、编辑或删除。

10 月 26 日补卡填写独立名称 `本轮验证-背单词279-288`；重新点击该日期显示这一历史名称，重复补卡被禁止；今天仍为 289–298。10 月 23 日显示“当日无打卡项”；10 月 27 日可查看已生成名称并提示今天在打卡页完成。补卡与编辑均通过系统返回回到详情。

日期选择表单打开后取消，历史恢复表单切换“恢复到未来”检查日期分区后取消，没有提交用户历史日程的恢复。教程通过设置回看。最终删除专用计划及全部关联记录，打卡页只剩原有计划、共 1 期且未完成；手机留在打卡页。

| 画面 | 证据 |
| --- | --- |
| 同款编辑图标、低饱和原位撤销 | [卡片完成后](screenshots/checkin-refinement/completed.png) |
| 统计、管理按钮、时间线材质分区 | [最终详情](screenshots/checkin-refinement/detail-final.png) |
| 非周期日 | [当日无打卡项](screenshots/checkin-refinement/backfill-off.png) |
| 当日名称与前景提示 | [已有周期](screenshots/checkin-refinement/backfill-today.png) |
| 已补卡的独立历史名称 | [历史内容](screenshots/checkin-refinement/backfill-record.png) |
| 接续文案与圆角分区 | [编辑计划](screenshots/checkin-refinement/editor.png) |
| 日期选择卡片 | [选择日期](screenshots/checkin-refinement/date-sheet.png) |
| 教程图标区别 | [教程](screenshots/checkin-refinement/tutorial.png) |
| 恢复表单卡片 | [恢复日程](screenshots/checkin-refinement/restore.png) |

手机清理时发现空历史分区在普通回调里直接调用 `Text(...).fontSize(...)`，编译可通过但删除后进入空分支会运行时崩溃。已提取为显式 `@Builder emptyHistory`，重新构建安装后同一测试计划删除成功、页面正常。新增回归检查全项目 39 处材质容器内容回调绑定；在内存中恢复旧写法和移除 Builder 装饰器均能被测试拦截。最终版本后续运行日志未发现新的错误。

## 检查结果

- 15 个回归脚本，共 **1031 个 assert 调用**通过：engine 139、storage 18、editor 116、drag 206、tutorial 31、tablet 26、materials 48、card 53、card-write 36、scroll-form 27、checkin 76、checkin-view 113、checkin-backfill 54、checkin-navigation 66、index-sheets 22。
- npm DevEco CLI `check arkts`：42 文件，0 错误。
- `check lint`：0 错误、10 条既有建议（组件结构 4 条、日期对象复用 6 条），未禁用规则。
- release 构建、签名、覆盖安装、启动：通过，`Smoke: PASS`。构建保留现有输入控制器系统能力和混淆配置提示。
- 最终包：`entry/build/default/outputs/default/entry-default-signed.hap`。
- SHA-256：`FC901D168F0828031F9D4E81D12D248DBDA8D6874C43CAC63C1B7E9E63D6B535`。
- `git diff --check` 无空白错误；工作区原有改动未回退。

本轮截图确认最终布局和交互结果，未进行逐帧性能采样；新建无横向和二级转场由真实属性表达式及手机进出流程共同检查。未重复测 API 24、平板多窗口或系统中低算力材质档位；相关材质路径沿用现有组件与既有回归。

## CLI 文档依据

- `FAQ/UI框架/UI界面/页面部分内容切换时_画面闪烁/faqs-arkui-622`：子节点插入/移除使用 `TransitionEffect`，支持非对称动画。
- CLI 文档 `faqs-arkui-343` 的透明度合成示例及项目 Index 已有渐隐：使用 `DST_IN` / `SRC_OVER` 的 alpha 合成，不添加着色遮罩。
- 本机 SDK 系统符号目录核对 `sys.symbol.pause`，教程网格复用已有 `sys.symbol.square_grid_2x2`。

仓库行为说明见 [README](../README.md)，后续页面规范见 [AGENT.md](../AGENT.md)。
