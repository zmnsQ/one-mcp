# One MCP 增量实现与验证 · 2026-10-15

本轮在 Linux 云端修改既有 SwiftUI/Liquid Glass 工程，没有访问用户 Mac，没有连接 OpenAI 隧道、运行凭据或公开部署。macOS 编译和实机验收交给用户；不将历史日志当作本轮测试结果。

## 原生应用补齐

- 配置创建/导入只有实际保存成功才展示成功；失败保留原界面配置，创建面板不提前消失。切换先验证配置并落盘工作空间索引，再切换内存状态。
- 文件存在但不可读不再当成“新安装”；损坏配置保持恢复保护。工作空间重复 ID 被拒绝。
- 保存快照与实时配置比较，显示未保存修改；退出提供保存、取消、不保存。空闲退出不再固定等待15秒。
- 网关控制请求按 ID 追踪真实响应、失败和超时。未确认操作保留 pending 状态，防止重复启动；退出清理 pending。发送失败不显示 starting。
- 启动网关、MCP、隧道前检查必要配置并保存；可执行路径、网关脚本、模式、工具白名单、服务器数量等校验错误可见。
- 删除服务器前撤回所有隧道；清理旧工具状态。隧道启动按钮在运行中禁用，停止仍可用。
- ManagedProcess 用每次启动的 generation 隔离旧 stdout/stderr/退出事件，清理管道及缓冲区，排空 EOF 尾行；保留有界排空等待，避免派生进程持有管道导致永久等待。
- 旧网关事件、旧隧道健康检查不能覆盖新进程状态。敏感命令错误先脱敏再显示。
- 运行时环境凭据与 Keychain account 按工作空间+服务器ID+变量名隔离；两台服务器的同名 API_KEY 不再串用。旧版共享变量凭据不会静默迁移，需重新输入并明确保存；删除工作空间凭据仍覆盖旧条目。
- 产品显示名称为 One MCP；原有 target、bundle ID、Application Support 与 Keychain 命名空间不改，保留历史配置兼容性。
- `.gitignore` 排除依赖、缓存、构建、用户配置、密钥和旧日志。构建脚本使用锁定依赖、禁止 npm install scripts，生成独立目录，不自动启动。

## 本轮实际检查

- `bash -n scripts/build-macos-app.sh`：通过。
- `python` + `plistlib` 解析 Info.plist，确认显示名 One MCP、内部可执行名 MCPHarbor：通过。
- Linux 执行 `bash scripts/build-macos-app.sh`：按设计返回2并明确要求 macOS，未尝试伪编译 Apple SDK。
- Swift/SwiftUI/AppKit/Security 编译、Keychain、退出流程、Liquid Glass 视觉效果：未执行。当前环境无 Swift 可执行文件及 Apple SDK。
- Gateway：本轮 `npm test` 退出0，包含 TypeScript 构建与35项真实本地测试（9基础+8高级+18工作流），覆盖实际60秒调用超时、取消、恢复。详见 `gateway/validation/RESULTS-2026-10-15.md`；旧 `validation/*.log` 不作为新证据。

## 用户本机验收

1. `npm ci --ignore-scripts` 与 `npm run build`（gateway目录），随后在 macOS 26 / Xcode 26 打开 Package.swift，Build / Run，或执行构建脚本。
2. 按 `docs/ACCEPTANCE.md` 检查工作空间、持久化失败、重复点击、进程快速重启、Keychain和退出。
3. 使用可信只读 MCP 验证发现→停止→选择白名单→重新启动→本机HTTP调用。
4. 自行配置官方 tunnel-client 后，区分 profile 初始化、doctor退出码、readyz和ChatGPT真实调用四个阶段，不把其中一个当作端到端成功。

## 仍然明确的边界

无公证、自动更新、远程多用户隔离、凭据创建或MCP自动安装。上游MCP具有用户账户权限，白名单不隔离其本机行为。强制终止只针对直接管理的进程；第三方程序自行脱离的后代进程需要本机检查。配置文件与工作空间索引分别原子写入，不是跨文件数据库事务；磁盘/权限错误后应查看提示并检查恢复文件。


## 第二轮核心体验补齐

新增 ConfigurationDiscovery（纯解析）、ImportServices（主动多文件选择与合并持久化）、ImportPreview（逐项选择与错误预览）和6组原生解析XCTest源码。支持 mcpServers 与 VS Code servers 的stdio候选，去重、默认零选择、保留现有配置、env值不复制、新增白名单为空。敏感参数/URL预览脱敏且禁止导入，恢复入口也拒绝疑似凭据参数。未后台扫描文件、未访问用户实际配置或Keychain。

隧道已有init/doctor/run+readyz执行链路增加目标签名和阶段下一步；目标变更不能沿用旧Doctor结论，添加官方CLI安装文档按钮。没有模拟账号登录或自动建tunnel。

验证边界：本轮新增Swift解析器、文件选择、预览和阶段UI没有在Linux编译/运行；新增测试为可在Mac执行的回归源码，不计入已运行的35项gateway测试。最终由父任务重做结构/语法检查。
