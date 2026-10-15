# One MCP — macOS 原生工程

**验证边界：用户后续授权 Linux 本地构建与模拟验证，网关由独立验证流程处理。macOS SwiftUI/AppKit/Keychain 与真实 OpenAI 隧道尚未运行验证，没有访问用户 Mac、部署或公开任何服务。本轮变更与验证详见 docs/IMPLEMENTATION-2026-10-15.md；旧验证报告仅供历史参考。**

SwiftUI 原生界面，macOS 26 Liquid Glass；Swift Package 可由 Xcode 打开，另提供生成 `.app` 的构建脚本。Node 侧车使用官方 MCP SDK，官方 OpenAI `tunnel-client` 负责私有出站通道。没有内置公网代理、没有默认启动服务、没有自建 OAuth 服务。

## 目录

- `Package.swift`：Xcode 可打开的 SwiftPM 可执行工程（非已签名 `.app`）。
- `Sources/MCPHarbor/`：原生界面、配置、内存凭据、Process 管理、日志、隧道生命周期。
- `gateway/`：stdio MCP → loopback Streamable HTTP 工具网关。
- `docs/`：协议和用户验收清单。
- `scripts/build-macos-app.sh`、`Resources/Info.plist`：用户在 Mac 上生成 `.app` 的构建入口。

## 你自行准备和构建

需要 macOS 26+、Xcode 26 / Swift 6.2 SDK、Node.js 22+，以及你自己安装的 MCP 程序。无需系统管理员权限；不要用 root 运行。

1. 使用 Xcode 打开本目录 `Package.swift`，选择 MCPHarbor 可执行 scheme。源码刻意使用 Swift 5 language mode，工具链是 Swift 6.2。
2. 自行检查 `gateway/package.json`，在 `gateway` 目录运行 `npm ci --ignore-scripts`，然后 `npm run build`。这些是你在 Mac 上的构建步骤；云端网关验证结果另外记录。
3. 由你在 Xcode 中 Build / Run。也可从工程根目录运行 `./scripts/build-macos-app.sh`：它构建侧车与 Swift 可执行程序，生成带网关资源的 `.app`，不会启动应用。输出在独立时间戳目录，不覆盖旧构建。macOS 编译尚未验证。
4. 从 [Platform tunnel settings](https://platform.openai.com/settings/organization/tunnels) 或其链接的 [官方 release](https://github.com/openai/tunnel-client/releases/latest) 安装适合 Mac 架构的 tunnel-client；不要绕过 Gatekeeper 或关闭系统安全功能。
5. App 的“连接设置”页面填写 Node、`gateway/dist/index.js`、tunnel-client 的绝对路径。Intel Homebrew 的 Node 通常不同于 Apple Silicon，必须填本机实际路径。

## 最小工作流

1. 在 Connection 点击 Start gateway 并确认。监听只允许 `127.0.0.1:8787`（端口可改），不启动任何 MCP。
2. Add MCP Server，填写已安装程序的绝对路径、工作目录和逐行参数。参数不经 shell 展开；不要写 `export`、`&&`、引号包装或把整个命令粘在一行。
3. 若 MCP 需要凭据，只在 Environment variable names 添加变量名，然后在 Session-only environment values 输入值。值默认只存在当前 App 内存并通过 stdin/子进程环境传递，不写配置。只有你点击并确认“保存当前凭据到 Keychain”才会持久保存；以后需手动载入。
4. 点击 Discover / Start，确认执行命令。它会运行程序以发现工具，**发现本身也会执行该程序**。默认白名单为空，不向 HTTP 出口公布工具。
5. Stop，选择需要的工具，再 Start。写文件、任意 shell、删除、数据库写入等工具请保持未选，除非你明确需要且信任其实现。工具说明/annotations 不构成安全隔离。
6. 模式 A Aggregate：一个本地 `/mcp` 出口；模式 B Individual：每个服务器 `/servers/{id}/mcp`。两组路由都存在于 loopback；模式选择控制 UI 中管理哪组隧道，不是关闭另一组本地路由。
7. 自行在 OpenAI Platform 创建/选择 tunnel，给运行凭据最小 Tunnels Read + Use 权限，并关联目标 ChatGPT workspace；创建或修改 tunnel 另需 Read + Manage。不要把 key 发给聊天。
8. 输入该模式的 tunnel ID、唯一 profile 名及 Session runtime key。单独模式每个服务器使用**独立 tunnel ID 和 profile**。Initialize profile 调用官方 `init --sample sample_mcp_remote_no_auth --profile … --tunnel-id … --mcp-server-url http://127.0.0.1:…`。
9. Doctor 会读取本机端点并可能联网；Run 会开始向 OpenAI 出站连接。每一步都会确认。不要将初始化成功视为隧道已连通。
10. 在 [ChatGPT Plugins](https://chatgpt.com/plugins) → Add custom MCP server → Connection: Tunnel 中选择同一 tunnel。确认工作区关联、权限和工具列表，自己进行一次安全只读调用。界面随官方版本变化；以当前官方步骤为准。
11. 工具或描述有变动，停止/重启相关 MCP 并在 ChatGPT Refresh，重新开始会话核对。Toolbar 的 Export tool guide 导出上次发现的工具说明和聚合别名，不导出参数/凭据。

## 官方隧道边界

- 官方 `tunnel-client` 支持私有 HTTP 或 stdio，使用出站 HTTPS，无需公网入站端口。本项目选择 HTTP 连接本机网关。
- App 只管理你提供的已有 CLI，不下载它、不创建 tunnel/密钥、不授予权限。
- 进程启动和连通状态分开：doctor 成功按真实退出码 0 展示；run 后每 3 秒读取官方 CLI 生成的本机 URL 并请求 `/readyz`，仅 HTTP 200 亮绿灯。HTTP 重定向被拒绝，健康检查不能离开 loopback。仍以 ChatGPT 安全调用为最终验收。
- 私有 tunnel 不替代公开插件上架所需稳定公开 HTTPS endpoint。本项目不做公开发布。
- 隧道传输权限与上游 MCP 的业务授权是不同层。该原型面向单用户可信本机 stdio 服务，不提供多用户隔离/OAuth；不要用作共享网关。
- 原型拒绝带 browser Origin 或非本地 Host 的 HTTP 请求。官方 tunnel-client 实际转发 Host/Origin 行为需要你验收；若不兼容，先检查官方配置，不能简单移除保护来解决。
- 个人账户/组织可见性取决于实际 Platform 和 ChatGPT 权限，源码不能保证每个账户已开放。

## 安全和已知限制

- 配置文件在 `~/Library/Application Support/MCPHarbor/settings.json`，权限 0600；只存非秘密设置。**不要在 arguments、路径或名称里填密钥**，这些字段会持久化。参数中令牌也可能出现在进程列表。
- 环境值和 tunnel key 默认仅内存；可显式选择保存到 macOS Keychain，按工作空间与服务器ID独立命名空间，同名环境变量不共享，不自动载入。未保存的值退出需重填。子进程环境和本机内存不是对同一用户/管理员的安全隔离。
- 日志只在内存保留 1000 行，尽力脱敏；原始 MCP stderr 在侧车中隐藏，仅报告字节数；隧道 CLI 日志仍需谨慎检查，不要分享未经检查的日志。
- 只支持 tools 列举与调用代理；不代理 resources、prompts、roots、sampling、elicitation 或双向通知；无 SSE resumability / 有状态会话兼容保证。这里的 Streamable HTTP 是 stateless POST/JSON 模式。
- 每个已启动 MCP 只有一个本地进程/会话，所有获准调用共享它。不要用于跨用户隔离。
- App 未沙箱化，MCP 进程具有你的账户权限。文件范围应由具体 MCP 自身约束，当前网关白名单只能限制工具名，不能拦截工具内部任意文件行为。
- 不启动登录项，不自动重启崩溃进程，不阻止系统睡眠；Mac 休眠/断网会导致调用失败。保持状态诚实优先于静默重连。
- Stop MCP 会先停止全部隧道以避免继续外部调用；Stop gateway / Quit 会尝试关闭侧车和直接管理的进程。强制杀掉 App、系统崩溃、子进程主动脱离的后代仍可能残留，需用户检查；不是完整进程组沙箱。
- 每次 run 使用官方支持的 `--health.listen-addr 127.0.0.1:0` 和私有目录内的 `--health.url-file`，由操作系统分配独立端口，避免多实例争用。每次也通过环境覆盖所选 tunnel ID 与本机 URL，避免旧 profile 目标漂移。
- 尚无公证、DMG、自动更新、自动安装 MCP 依赖或经 Mac 实机验证的 `.app`。提供 SwiftPM 工程及 `.app` 构建脚本；可通过用户已有 `CODESIGN_IDENTITY` 显式签名，脚本不申请凭据、不做公证。

## 引用与许可

本原型界面/管理代码为新写源码，没有复制 MCPMate、MetaMCP 或其他产品代码。官方 MCP TypeScript SDK 使用 MIT；具体版本及其他依赖见 package.json，完整分发时应保留所有依赖许可证。tunnel-client 由用户从官方渠道独立安装，本原型未捆绑其二进制。

- [Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels)
- [tunnel-client onboarding](https://github.com/openai/tunnel-client/blob/master/docs/onboarding.md)
- [ChatGPT 连接与测试](https://developers.openai.com/plugins/deploy/connect-chatgpt)
- [Apple Liquid Glass](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))
- [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk)

## 工作空间与配置迁移

侧栏可以创建/切换工作空间。切换前必须停止进程；保存旧工作空间成功后才切换。服务器配置、隧道和Keychain命名空间彼此隔离，不会在切换时自动启动或载入秘密。旧单配置版本会保留为默认工作空间。

工具栏支持导入 One MCP / 旧 Harbor JSON 或标准 `mcpServers` stdio JSON。导入前确认替换当前配置；所有 env 值被丢弃，工具白名单清空，远程URL配置不会假装变成stdio。相对命令可导入待修改，但启动前必须填绝对可执行路径。导出不包含凭据，并对参数中已知密钥尽力脱敏；仍应检查参数是否包含其他私人信息。

工具目录可手动刷新。名称/说明变化时显示提醒，但不自动授权新工具。日志可导出，输出前再次脱敏；原始 MCP stderr 保持隐藏。


## 从 Git 更新

在仓库根目录先检查 `git status`，提交或另存自己的源码修改，再执行 `git pull --ff-only`。随后重新运行 `scripts/build-macos-app.sh`，并使用新生成的 One MCP.app。不要把用户配置、Keychain、`.env`、依赖或构建目录提交到 Git。

产品名称为 **One MCP**；为兼容已有工作空间，SwiftPM target、bundle identifier 与 Application Support 内部目录仍保留 MCPHarbor。更新源码不会自动启动程序、迁移凭据或改变已开放工具。

## 功能逐项核对

见 `docs/FEATURE_MATRIX.zh-CN.md`，列出每项源码入口、已验证范围、未实现能力与用户本机验收要求。

## 手动编译工作流与成本

`.github/workflows/macos-compile.yml` 仅由 workflow_dispatch 手动触发，push 不会自动启动原生 CI。GitHub 托管 macOS runner 可能使用账户分钟配额或产生费用，触发前请自行核对计费。工作流不签名、不公证、不启动 App、不部署，也不创建或读取账号凭据；本轮未触发。


## 从已有客户端配置发现 MCP

工具栏「导入与导出」→「从所选配置发现 MCP…」打开原生多文件选择器。主动选择 Claude Desktop、Cursor、Cline 等客户端的 `mcpServers` JSON，或 VS Code 的 `mcp.json`（`servers` 容器）。只读取所选文件，不后台扫描其他目录；目前要求严格 JSON，JSONC 注释会显示解析错误。

预览逐项显示来源、命令、逐行参数、工作目录和 env 变量名称。默认不选中；与现有工作空间或前面候选重复的配置不可选。去重忽略服务器显示名和 env 值，因此同命令但不同秘密值会视作重复；如确需两份，请手动添加独立服务器并分别输入凭据。

点击「合并所选」保留已有服务器，只新增所选条目；新增白名单为空、不启动程序、不复制 env 值、不自动读 Keychain。疑似凭据命令参数、Bearer 或 URL 用户信息/秘密查询项会隐藏并禁止导入，需先手动修正源文件；未知格式仍需用户检查。相对命令可以导入待编辑，启动前必须改为本机绝对路径。错误或超过16个服务器时不显示成功。

「恢复 / 替换整个配置…」是另一个明确的恢复入口，会替换当前配置，请勿用它代替合并发现。

原生候选解析回归源码在 `Tests/MCPHarborTests/ConfigurationDiscoveryTests.swift`，可在 Mac 运行 `swift test`；本轮未在Linux执行这些Swift测试。网关 `npm test` 的35项实际结果不覆盖原生文件选择或Swift解析器。

隧道面板现在按实际阶段显示下一步：安装CLI/启动网关 → profile初始化退出码 → Doctor退出码 → run的readyz → 用户ChatGPT真实调用。更改profile、tunnel、客户端路径或端点后，不沿用旧目标的Doctor结论。官方CLI安装入口不会自动下载、创建账户或创建tunnel。
