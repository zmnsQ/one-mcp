# One MCP

### 把本地 MCP 和隧道，放进一个原生 Mac 工作台。

One MCP 用于管理本机 MCP 服务、工具白名单和私有出站隧道。既可以将多个服务聚合为一个出口，也可以给每个服务单独配置隧道。

[English](README.md) · [快速开始](docs/GETTING_STARTED.md) · [系统架构](docs/ARCHITECTURE.md) · [验证状态](docs/TESTING.md)

> **当前状态：开发中。** TypeScript 网关已有 Linux 构建与 35 项隔离 fixture 检查通过记录。macOS 原生编译、Keychain、官方隧道和 ChatGPT 实际远程调用仍待验收；暂无签名、公证后的正式安装包。

## 主要功能

- **工作空间管理**：按项目组织服务配置，独立凭据命名空间，切换前停止相关进程。
- **配置发现与合并**：选择已有客户端的 JSON 配置，预览去重后合并，不后台扫描，不复制秘密值，不自动启动程序。
- **工具级白名单**：默认不开放工具，用户明确选择后才可通过网关调用。
- **聚合或独立出口**：支持 `/mcp` 聚合工具目录与 `/servers/{id}/mcp` 单服务路由。
- **隧道生命周期**：管理官方客户端的初始化、Doctor、运行和停止，区分进程启动与真实健康状态。
- **显式凭据管理**：默认仅保存在会话内存中，可由用户明确保存到 macOS Keychain，之后手动载入。

## 架构

SwiftUI 工作台 → Node.js 本机网关 → 已安装的 stdio MCP 服务。

ChatGPT 通过官方私有 Tunnel 访问本机网关。网关只监听 loopback，隧道由客户端主动向外建立连接，无需开放公网入站端口。账户是否具备相关功能，以实际 OpenAI 账户与工作区权限为准。

## 快速开始

需要 macOS 26+、Xcode 26 / Swift 6.2、Node.js 22+，以及准备接入的 MCP 程序。

```sh
git clone https://github.com/zmnsQ/one-mcp.git
cd one-mcp
(cd gateway && npm ci --ignore-scripts && npm run build)
bash scripts/build-macos-app.sh
```

脚本在独立时间戳目录生成 `.app`，不会自动运行。原生编译尚未验证。也可以用 Xcode 打开 `Package.swift`，选择 `MCPHarbor` scheme。

接下来按[开始使用](docs/GETTING_STARTED.md)配置 Node、网关和官方 tunnel-client 路径，添加一个可信服务，先开放一个无副作用的只读工具进行验证。

## 使用边界

- 目前仅代理工具列举和调用，不代理 resources、prompts、sampling 等完整 MCP 功能，也不提供多租户隔离或共享网关 OAuth。
- MCP 子进程具有当前用户的系统权限；工具白名单不等于文件沙箱，取消请求不保证撤销已发生的副作用。
- 聚合与独立路由同时存在于本机；界面模式切换用于管理隧道组织方式，不是关闭另一类路由。
- 私有隧道并不自动满足公开插件上架条件。项目不会替用户创建密钥、账户、隧道或扩大权限。
- 不要在命令参数、路径和显示名中填写秘密。导出的日志和配置仍应在分享前检查。

## 文档

- [快速开始](docs/GETTING_STARTED.md)
- [系统架构](docs/ARCHITECTURE.md)
- [测试与验收](docs/TESTING.md)
- [完整操作指南](docs/OPERATIONS.zh-CN.md)
- [功能核对表](docs/FEATURE_MATRIX.zh-CN.md)
- [网关验证记录](gateway/validation/RESULTS-2026-10-15.md)

为兼容已有配置，内部 Swift target、bundle identifier 和 Application Support 目录保留 MCPHarbor。正式产品名称为 **One MCP**。

## 开发与许可

网关可在 `gateway/` 下运行 `npm ci --ignore-scripts` 和 `npm test`。原生 Swift 测试需在 Mac 执行；已有网关测试不能代替原生界面或真实隧道验收。Apple workflow 仅手动触发，使用前请核对账户计费。

项目尚未选定许可证。仓库公开不等于自动授予开源许可；第三方依赖沿用各自许可。

## CLI 与 AI 管理

界面聚焦 MCP 服务、ChatGPT 连接和设置，工具授权直接放在对应服务详情内。CLI 复用相同工作空间和网关，不另建一套配置。构建 gateway 后运行 `./bin/onemcp help`，参阅 [CLI 文档](docs/CLI.md) 与可选 [AI Skill](skills/one-mcp/SKILL.md)。修改先预览，保存需明确配置版本；设置页支持只读发现官方 tunnel-client 与已有 profile 元数据，选择后仍需核对保存。
