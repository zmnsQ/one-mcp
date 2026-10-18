# 远程连接：从准备到验证

One MCP 提供两条连接路线：OpenAI 官方 Tunnel，或 Cloudflare Tunnel 配合外部 OAuth 授权服务器。第一次使用建议按应用「连接 ChatGPT」中的步骤完成；保存配置不会自动开放公网。

## OpenAI 官方 Tunnel

1. 安装官方 [tunnel-client](https://github.com/openai/tunnel-client)，在应用选择可执行文件。先检测程序，再准备账户。
2. 应用提供 [API Keys 页面](https://platform.openai.com/settings/organization/api-keys) 与官方说明入口。请使用对应账户创建满足 Tunnel 权限要求的 Runtime API Key，并在官方控制台创建 Tunnel ID。普通模型调用 Key 不保证具有 Tunnel 权限；以官方账户权限和 doctor 检查结果为准。
3. 自己将 Key 输入应用安全字段。选择「保存并自动填入」后密钥只保存在当前工作空间的 macOS 钥匙串，不写入 settings.json、Git 或诊断导出。升级沿用稳定的钥匙串账户标识；macOS 如要求重新授权读取，请点击从钥匙串载入并在系统提示中确认。
4. 新建 Profile 或选择已存在的 Profile 文件。已有文件不执行 init；新 Profile 执行初始化、doctor，再运行。
5. 查看内建状态和日志。进程启动、HTTP ready、ChatGPT 真正调用工具是不同阶段；最后在 ChatGPT 实际读取一次工具确认。

Runtime API Key 是官方 Tunnel 控制平面凭据；OAuth Access Token 是访问 MCP 工具的用户授权凭据；Cloudflare credentials JSON 是运行指定隧道的本机凭据。三者不能互换。

## OAuth 入站认证

此版本实现 MCP OAuth **资源服务器**，不在应用中自制登录/密码/授权码服务。你需要已配置好的 OAuth 2.1 授权服务器。授权服务器负责用户登录、明确同意、PKCE S256、精确 Redirect URI 校验、客户端注册与刷新/撤销。应用不会自动创建授权、注册客户端或填入凭据。

在 OAuth 设置填写：

- 公网 MCP URL：完整资源标识，例如 https://mcp.example.com/mcp，也必须是访问令牌的 audience。
- Issuer：授权服务器公布的准确 issuer，末尾斜线也须一致。
- JWKS URL：该授权服务器的 HTTPS 公钥集合地址，不是私钥或 access token。
- Scope：要求的权限，默认 mcp:tools；多个权限以单个空格分隔，必须全部具备。

启用并保存后，明确重启网关使安全策略生效。运行中的策略不会因 AI 修改配置而悄悄放宽。配置页面立即展示保存值，并提示待重启项目。

支持 RFC 9068 JWT Access Token：RS256 或 ES256、typ=at+jwt（或 application/at+jwt），包含 iss、aud、exp、iat、sub、client_id、jti、scope。支持可选 nbf。普通 ID Token、opaque token、仅 HS256 的提供商配置不兼容此版本。请先确认授权服务器能够签发这个访问令牌格式；不能仅把任意登录服务的 JWKS URL 填入后就认为兼容。

网关提供 /.well-known/oauth-protected-resource 与 /.well-known/oauth-protected-resource/mcp，并在 401 中返回 WWW-Authenticate 指向元数据。JWKS 只从已配置地址加载，有超时、大小限制和缓存；拒绝 token 自带 jku/jwk/x5u 和重定向。该策略保护整个聚合 /mcp，启用 OAuth 时不提供单独 /servers/.../mcp 入口。拥有要求 Scope 的有效令牌可访问聚合白名单中的工具；此版本不提供逐用户或逐服务器权限分区。令牌不转发给上游 MCP。现有上游仍是 stdio，读取显式环境变量；本版本未增加远程 HTTP 上游的 OAuth 登录。

## Cloudflare Tunnel

先安装官方 [cloudflared](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/)，应用检测只执行 --version，不自动安装或创建账户。Cloudflare 必须先启用上面的 OAuth 保护，才允许开始运行。

### 命名隧道（推荐长期使用）

通过 [Cloudflare 官方本地管理说明](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/local-management/create-local-tunnel/) 完成账户授权、隧道和 DNS 设置。应用不代替你授权或购买域名。

填写 cloudflared 路径、隧道 UUID、只读凭据 JSON 的绝对路径，以及公网 Origin（例如 https://mcp.example.com，不带 /mcp）。这个 Origin 加 /mcp 必须与 OAuth 资源 URL 一致。只保存凭据文件路径，不读取或展示 JSON 内容；cloudflared 自己读取该文件。公网主机将转发到本机 loopback 网关，管理控制 socket 不对外开放。

### 临时隧道（开发验证）

[Quick Tunnel](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/) 会分配随机 trycloudflare.com 域名；不适合稳定连接，也不支持 SSE。本网关使用 stateless POST。初始 OAuth 必须已配置启用，运行后仅本次会话将 OAuth 资源 URL 切换为发现的域名 /mcp。你仍需在授权服务器允许这个新 audience，再完成客户端真实授权。停止隧道会恢复保存的 OAuth URL。下一次随机域名可能改变，推荐正式使用命名隧道。

### 如何判断成功

状态分开显示：本机 cloudflared ready、外部受保护资源元数据可达、OAuth 登录与真正工具调用待验证。元数据可达并不证明用户已授权，也不证明 DNS/客户端后续永远正常。原始 cloudflared 输出不直接写入应用日志，避免凭据泄露。停止按钮会等待子进程退出再恢复策略。

## AI / CLI 管理

所有操作继续使用同一网关和私有管理 socket，不再启动第二套服务。CLI 默认预览，真正修改需 --apply；保存配置需要当前 revision。

- onemcp cloudflare doctor --json
- onemcp cloudflare start --apply --json
- onemcp cloudflare stop --apply --json
- onemcp config set --field remoteConnection --value '<非敏感 JSON>' --expect-revision <revision> --apply --json

remoteConnection 可包含 preferredTransport（openai/cloudflare）、oauth 与 cloudflare。不要在 JSON 中放 Runtime Key、OAuth Token 或 Cloudflare Token。使用应用安全输入与系统授权流程。

## 验收

云端只验证 TypeScript、隔离的签名/HTTP/子进程 mock 和回归。真实 macOS App、钥匙串读取、外部 OAuth 账户和 Cloudflare DNS/隧道必须在测试 Mac 上由已授权用户验收。测试时不要覆盖已有未提交开发文件；使用单独 worktree/构建目录。
