# PlanerHarmony 开发协作约定

## 页面与半模态一致性约定

1. 除新手教程外，所有新增或修改的半模态表单均采用与 TaskEditor 相同的圆角矩形卡片分区，优先复用 MaterialSection。标题、可滚动正文和底部操作区保持清晰分离；小屏、分屏和键盘场景中的内容与主操作必须可达。普通系统确认对话框继续使用确认对话框，无需改造成卡片表单。
2. 按钮、图标及沉浸光感材质尽量复用现有组件和工厂，包括 IconButton、HistoryBackButton、PlanerIcon、MaterialButtonScope、PlanerControlModifier、SheetMaterialSurface 与 Materials。沿用中性背板、系统材质分档、可控按压反馈及离场清理，避免另写相近但不一致的按钮或材质实现。
3. 今后新增或修改允许内容滚动到标题下方的页面，统一采用 Settings 页同款标题与状态栏区域的渐变模糊处理，并保持安全区、滚动绑定与触摸行为一致。该约定适用于后续页面开发，不要求在每次与标题无关的变更中重做既有页面。

## 鸿蒙工具与文档

开发、检查或构建前，参考本机通过 npm 安装的 DevEco CLI 工具和文档，可使用项目 scripts/deveco.ps1 包装脚本；不要与 DevEco Studio 自带的 CLI 混淆。
