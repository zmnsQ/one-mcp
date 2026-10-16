# 验证记录与边界

2026-10-14，用户允许在云端 Linux 构建/运行本地验证；仍不访问用户 Mac，不连接真实 OpenAI 隧道或真实私人 MCP。

## 已完成

- 云端环境检查：Linux，未发现系统 swift 可执行文件。
- Swift 源码通过 tree-sitter-swift 语法解析（8 个 Swift 文件，含 Package.swift）；没有 ERROR/missing 节点。这不是 Swift 编译器类型检查，不证明 SwiftUI API 或 macOS 运行行为正确。
- `bash -n scripts/build-macos-app.sh` 通过。
- Python plistlib 解析 Info.plist 通过。
- 人工核对 IPC、隧道 init/run/doctor 参数、官方配置优先级、loopback ephemeral health 端口、生命周期关闭等待。
- TypeScript 网关 `npm run build` 实际通过。`gateway/validation/smoke.mjs` 9项与 `advanced-smoke.mjs` 8项均通过，日志同目录。包含原生 IPC metadata、空白名单、重复名、错误状态恢复和多子进程清理；不等于 Mac 原生验证。

## 必须在 Mac 完成

- Swift 6.2 / Xcode 26 完整编译与链接、SwiftUI布局、菜单栏和退出。
- Keychain增改读删及应用签名身份变化时的提示。
- 真实Node/MCP子进程启动停止、sleep/wake与崩溃处理。
- 官方tunnel-client安装版本参数兼容、doctor退出与readyz健康路径。
- ChatGPT工作区权限与一次真实的只读工具调用。

没有取得这些证据前，不宣称“Mac App已测试完成”“生产就绪”或“ChatGPT已连通”。

## Read-only launch hotfix (2026-10-16)
Opening the app now reads a double-checked configuration/index snapshot without acquiring a writer lease, creating directories, or persisting runtime-path migration. The next explicit save/start uses the existing revision-checked transaction. Initial-read retries are bounded and never overwrite local edits. Existing active/unknown locks are not removed. This fixes the unconditional launch lock alert; it does not diagnose the owner of a user's existing lock from a screenshot. Native execution remains unverified.

## Shared runtime attachment (2026-10-16)
Executed two independent RuntimeClient instances against one real Node gateway process over its stdin management channel: equal PID/instance, shared start/catalogue/stop state, mismatched workspace/root/protocol rejection, stale instance command rejection, replacement instance rejection, and explicit shutdown. This test injects the root identity because its transport is stdin; it is not a Unix-socket transport or native macOS GUI test. Existing owner/mode socket validation is reused by the production adapter. Native attachment, UI and socket integration remain pending macOS verification.
Native detach/quit and adapter EOF source-contract checks also pass; they are not runtime execution. Full Linux test suite passes with the Unix-socket fixture explicitly skipped due to environment restrictions. Packaged runtime adapter/dependencies verifier and shell syntax checks pass. Existing pre-protocol gateways require a one-time explicit stop and restart from the updated build; the app never force-kills or silently replaces them.

## Explicit legacy takeover (2026-10-16)
Executed protocol mocks for supported legacy status, wrong workspace/protocol/PID, changed socket identity, unsafe-owner inspection failure, one shutdown request, shutdown error, socket timeout and process-exit timeout. The helper never starts a replacement; native callback requires confirmed stop, exit status0 and unchanged configuration before calling startGateway. Production shutdown rechecks owner/mode/inode after connecting. These are protocol/source checks, not macOS or Unix-socket integration.

## Existing-profile credential resolution (2026-10-16)
Verified a false-rejection path in OneMCP: all tunnel actions previously required a nonempty session key before invoking the official client. Official configuration documentation supports YAML `control_plane.api_key` file/env/literal resolution; an empty override is now omitted. A mock executable test verifies Doctor and run receive no CONTROL_PLANE_API_KEY variable when omitted, and tests field-specific failures, unavailable profile/executable, existing-profile init refusal, key-required diagnostic classification and secret suppression. This does not establish the exact cause of a user's screenshot or verify real credentials/connectivity. Raw official output is never displayed. Native macOS execution remains unverified.
