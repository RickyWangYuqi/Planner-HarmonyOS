# PlanerHarmony 项目长期记忆

## HarmonyOS 开发工具链（本机实测，2026-10-22）

- **统一入口用 `devecocli`**（npm 全局包 @deveco/deveco-cli，v1.3.9）：`cmd //c "D:\Software\NodeJS\node_global\devecocli.cmd <子命令>"`，封装 build/run/device/emulator/skills/docs/log/ui/check/signature 等。
- **代理坑**：本 shell 默认 http_proxy/https_proxy=127.0.0.1:48924，devecocli 远程子命令（skills 拉取等）会报 "Invalid proxy authorization"，调用前需 `env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY` 绕过；本地 docs 检索不受影响。
- `docs search` 的 documentId 是完整中文路径（如 `开发指南/构建应用/.../xxx`），`docs read` 必须用该完整 ID，只用末段会报 not found。
- DevEco Studio 26.0.0.821 位于 `D:\Software\DevEco Studio`（官方最新 patch 为 26.0.0.851，SDK 26.0.0.105 与官方一致）；hdc/ohpm/hvigor 均不在 PATH，需绝对路径。
- deveco-cli skill 文档：`C:\Users\35101\.claude\skills\deveco-cli\SKILL.md`。
