# One MCP 本地工具网关

本目录为原创 TypeScript 网关。经用户后续授权，已在云端 Linux 安装依赖、构建并运行仅绑定 loopback 的模拟 MCP 测试，没有连接真实私人 MCP、OpenAI 隧道或用户 Mac。

## 依赖

Node.js 22 或更高版本；`@modelcontextprotocol/sdk` 1.32.1，MIT，依据2026-10-14官方v1.x分支源码核对接口；TypeScript与Node类型仅构建使用。已生成 package-lock.json 并完成 Linux 构建。用户需要执行 `npm install`、`npm run build`，将生成的 `gateway/dist/index.js` 配置到原生App。不要把未编译的 `src/index.ts` 当作运行入口。

## 启动和控制

用户在App确认启动后，App运行 `node dist/index.js --port 8787`。仅绑定127.0.0.1，启动网关不会启动任何上游MCP。stdin逐行JSON仅用于本地父进程管理，不通过HTTP开放管理接口。stdout仅输出JSON事件；禁止向stdout输出普通调试文字。

管理方法：
- startServer：params.server包含id/name/executable/arguments/environment/workingDirectory/allowedTools。
- stopServer：params.serverId，格式与配置id相同；有效但已停止的id可重复停止。
- updateAllowedTools：params包含serverId、allowedTools和expectedAllowedTools，可选expectedInstanceID；仅更新正在运行实例的白名单，不重启进程或隧道。两个数组均须不重复、最多500项、每项1–256字符且不能包含NUL或为星号；拒绝额外字段。expectedAllowedTools按集合比较，冲突则不修改，需刷新状态后重试。CLI工具必须在已配置描述符中。
- listTools：params.serverId，重新发现分页工具。
- shutdown：先返回成功响应，再关闭HTTP和子进程。

重复startServer会返回失败，保留已运行实例及其状态；启动失败的实例会清理进程和路由。启动中、停止中或已断开的实例不会暴露HTTP工具。

每个请求有字符串id。响应为type=response,id,ok,error?。事件ready包含port；serverStatus包含serverId/status/message?；tools包含serverId/tools[{name,description?,publicName,inputSchema,outputSchema?,annotations?}]；log包含serverId?/message。仅启动本App管理的进程，不扫描或停止系统中无关MCP或隧道。

executable须为用户选择的绝对路径，参数数组直接传给进程，不经过shell。SDK只继承HOME/PATH等基础环境及用户明确提供的environment，不能继承全部父进程凭据。不要将密钥写进arguments；上游进程本身可能不安全，必须审查安装来源与权限。

## 两种出口

- 聚合：`http://127.0.0.1:8787/mcp`
- 独立：`http://127.0.0.1:8787/servers/<server-id>/mcp`

两者为stateless Streamable HTTP，POST为主要方法；GET/DELETE返回405，不提供SSE恢复或服务器主动推送。客户端发notifications/initialized时由SDK处理。工具清单读取下游原始JSON schema及描述；仅allowedTools白名单内工具可见可调用。默认空白名单即不暴露工具，不能用星号表示全开。可通过updateAllowedTools即时修改运行时白名单；后续tools/list和tools/call在聚合、独立及隧道绑定出口使用新集合，已准入调用可完成。管理响应及serverStatus事件返回权威allowedTools、configurationFingerprints和clientRefreshRequired:true。客户端需重新获取工具列表或重连，本实现不声明listChanged能力、不发送服务器主动通知。运行时修改不自动写入磁盘；应用负责保存配置。旧网关须升级一次，ready/status中的liveToolSelectionVersion配置指纹用于检测支持。

聚合名称是server-id前10字符、工具名规范化前39字符与10位哈希组成，避免重复名和超长；不要用简单的UUID__原名猜测远程工具名。调用只路由到对应服务器的原始工具名。单独出口保留原始工具名。发现时拒绝重复工具名、循环分页、超过20页或1000个工具的目录。

HTTP和管理命令并发发现会合并为同一上游请求。上游tools/list_changed会立即清除旧目录、重新发现并向App发送tools事件。刷新失败也会清除旧路由；聚合出口继续返回其他健康服务器的工具，独立出口返回发现失败。修复上游后可再次listTools；若工具列表无法恢复，可停止并重启该服务器。

每个上游最多并发4个工具调用，HTTP最多32个进行中请求，JSON body上限1 MiB；超过body限制返回413。此无会话实现不能把另一个POST中的notifications/cancelled安全关联到其他客户端的调用；取消依靠原HTTP请求断开及本地停止操作。取消不保证撤销已经发生的上游副作用。

此版代理tools/list和tools/call，未实现resources、prompts、sampling、elicitation、异步task工具、远程OAuth broker或远端HTTP型上游；不应说完整透传所有MCP能力。上游初始化和一次完整分页工具发现分别限时15秒，工具调用限时60秒。HTTP连接断开、停止服务器及关闭网关会转发取消signal；上游工具是否可撤销取决于它自身，停止等待不等于撤销已发生的外部副作用。

## 安全边界

此网关没有自带公网OAuth服务器，不得直接映射到无认证公网。优先由官方Secure MCP Tunnel提供出站连接与入口访问控制，账户/工作区/组织权限仍需要用户配置。隧道只负责传输，不为危险MCP工具自动提供安全审查。

网关拒绝非loopback Host及所有带浏览器Origin的请求，以降低DNS rebinding和跨站调用风险。官方隧道转发是否保留符合要求的Host/Origin需要用户验收；如果不兼容应按官方客户端配置解决，不能关闭校验或把监听改为0.0.0.0作为默认修复。禁止CORS通配符。

本机其他进程可访问loopback，故这不是针对恶意本地进程的隔离边界。不要在不受信任的共享主机上运行。管理IPC由父进程管道承载；MCP工具具有其进程用户的真实文件/网络权限。即使工具声明readOnlyHint=true，也只是提示，不能代替源码审查。默认只启用必要的只读工具，再由用户自行评估写操作。

日志对已配置环境变量值及常见Bearer进行脱敏，重叠变量值先处理较长值；不记录工具参数和返回正文。上游stderr仅报告收到输出且限频为每秒最多一次，不展示原文，避免跨分块凭据泄漏。其他上游错误仍可能包含未知敏感信息，分享日志前必须人工审查。

## 用户验收顺序

先本地构建并启动无工具网关，确认只监听loopback；再启动一个已审查的只读MCP，查看工具清单，手动选一个白名单；检查两出口的tools/list与准确路由；然后配置官方隧道并在ChatGPT开发者模式连接，核对工作区权限；最后验证停止App/子进程崩溃/重复启动/超时/取消/凭据缺失的行为。Linux 本地基础测试已执行；真实 Mac、隧道和 ChatGPT 端到端调用仍待验收。

## 官方依据

- https://github.com/modelcontextprotocol/typescript-sdk/tree/v1.x
- https://github.com/modelcontextprotocol/typescript-sdk/blob/v1.x/src/client/stdio.ts
- https://github.com/modelcontextprotocol/typescript-sdk/blob/v1.x/src/server/streamableHttp.ts
- https://developers.openai.com/api/docs/guides/secure-mcp-tunnels

## Linux 验证证据

2026-10-15重新执行npm ci（ignore-scripts）、npm test；npm test会先构建，再运行smoke.mjs、advanced-smoke.mjs及workflow-smoke.mjs。本轮35项检查通过，包括真实等待60秒的工具调用超时与上游取消，不使用旧日志代替执行。测试只连接本目录的本地fixture，不连接用户真实MCP、Mac、官方隧道或ChatGPT。

完整结果与已知边界见[本轮验证报告](validation/RESULTS-2026-10-15.md)。运行npm test需要约75秒；生成日志不应被当作真实外部服务验收。
