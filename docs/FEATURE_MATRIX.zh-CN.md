# One MCP 功能与验收矩阵（2026-10-15）

内部工程target及原存储目录继续叫MCPHarbor，以保留兼容性。此表区分已有源码、实际Linux模拟测试和未完成的原生/真实服务验收，不将修复若干断点等同于全功能生产完成。

| 用户流程 | 实际代码链路 | 本轮证据与待验收 | 缺失/限制 |
|---|---|---|---|
| 添加本地MCP | HarborView服务器编辑 → HarborStore.startServer → gateway/src/index.ts start/stdio client | 网关模拟进程握手实际测试；原生编辑/确认/启动待Mac | 用户手动选择已安装命令；不自动安装依赖、扫描所有客户端配置或发现机器上所有MCP |
| 发现/预览/合并已有MCP | HarborView发现入口 → ImportServices原生多文件选择 → ConfigurationDiscovery解析/去重 → ImportPreview逐项选择 → mergeSelectedCandidates验证/保存 | 6组Swift XCTest已编写但未在Linux执行；原生多文件/失败/重复流程待Mac | 仅访问主动选择的文件，支持mcpServers及VS Code servers；env值不复制，敏感参数脱敏且禁止导入；不后台扫盘或自动安装 |
| 恢复整个配置 | WorkspaceServices.importConfiguration → 原生JSON或mcpServers stdio →验证→替换保存 | 明确标记恢复/替换入口并要求确认；原生操作待Mac | env值丢弃、白名单清空；疑似凭据参数拒绝；不自动导入远端URL MCP |
| 工具发现与刷新 | gateway discover/listTools分页 → tools事件 → HarborStore工具目录 → HarborView白名单 | Linux mock实际覆盖；真实MCP兼容性待用户服务 | 仅代理tools，不实现resources/prompts/roots/sampling/elicitation |
| 聚合出口 | gateway catalogue/publicName → /mcp路由 →已授权工具分发 | Linux模拟列表/调用/同名路由测试 | 单用户本机共享进程，非多租户网关 |
| 独立出口 | /servers/{id}/mcp →该server白名单 →独立Tunnel参数 | Linux模拟隔离/错误路由测试 | 两类loopback路由始终存在；UI模式不是关闭另一类路由 |
| 进程生命周期 | ManagedProcess专用stdin/stdout/stderr →HarborStore请求追踪→网关start/stop/shutdown | 网关实际测试；原生代际回调、管道排空和退出待Mac | 不自动重启/登录自启；脱离父进程的后代不保证清理 |
| 官方Tunnel | HarborStore.tunnelAction init/doctor/run →真实退出码阶段与目标签名 →tunnelNextStep；TunnelHealth轮询readyz；官方安装文档按钮 | 参数/状态代码复核；未调用真实tunnel-client或账号 | 用户自行装官方CLI、创建Tunnel和关联ChatGPT；不提供虚假OAuth或公网部署 |
| 配置与工作空间 | WorkspaceServices + HarborStore.save →独立配置/索引 →切换/导入/导出 | 保存失败不假成功代码复核；Keychain/磁盘故障待Mac | 不含自动同步；跨多个文件保存非数据库事务 |
| 权限与凭据 | 空白名单默认拒绝；显式工具选择；workspace+server+env隔离；Keychain手动保存/载入 | 网关拒绝/路由测试；原生凭据隔离源码核对 | 旧共享env凭据不自动迁移；工具名白名单无法约束工具内部行为；App未沙箱化 |
| 日志与工具说明 | 网关隐藏原始stderr，原生限长/脱敏/导出；tools metadata导出 | mock错误脱敏测试；真实CLI输出仍需检查 | 未知格式秘密无法保证全部识别；不要发布原始私人日志 |
| 错误恢复 | 请求ID/失败/60秒待确认状态；端口冲突、退出状态、全部停止；损坏配置备份后恢复 | 网关本轮运行结果见validation报告；原生错误提示待Mac | 不无条件自动重试副作用调用，不假报服务恢复 |
| 原生界面与打包 | SwiftUI HarborView、MenuBarExtra、Liquid Glass；build-macos-app.sh | plist、shell语法及Linux拒绝分支检查；SwiftUI完整编译待用户 | 无签名安装包、公证、DMG、自动更新；未实际运行UI |
| ChatGPT端到端调用 | loopback网关 →官方Tunnel →用户ChatGPT连接与只读调用 | 未验证 | 依赖账号/工作区实际开放能力；本轮没有创建凭据或运行公网服务 |

本轮具体测试结果见 gateway/validation/RESULTS-2026-10-15.md；原生变化见 IMPLEMENTATION-2026-10-15.md；用户验收见 ACCEPTANCE.md。Linux mock通过不等于真实MCP、隧道或macOS App端到端通过。
