# 隧道创建与同账号凭据复用（2026-10-21）

## 新流程

1. 选择连接方式。OpenAI 下先选择/填写本机账号标签，再选择同账号已有钥匙串凭据引用，或输入本次 Runtime API Key。
2. 填写隧道名称，明确选择需要绑定的 MCP/CLI 服务和已有 OpenAI Tunnel ID。
3. 新建默认选择“创建本地 Profile”。直接点击“创建并保存本地 Profile”，无需展开高级/维护。

主动作先原子保存配置，再调用官方 tunnel-client init。界面等待本轮 init 的真实退出结果，不把提交成功当创建成功。成功提示“本地 Profile 已创建并保存，隧道尚未启动”。这不是 OpenAI Platform 远端 Tunnel 创建，也不生成 API Key；已有远端 Tunnel ID 仍需用户提供。启动独立且保留现有确认与“参与全部启动”设置。

已有 Profile 可直接选择“使用已有 Profile / 仅保存更改”，保留 named profile 和绝对文件路径两种模式。Cloudflare 仍只保存配置，启动另行确认。已有记录打开编辑时默认不初始化，历史配置迁移/打开应用不自动创建任何 Profile。

## 凭据模型

- accountID 是用户声明的本机账号标签，不代表服务端验证的身份；标签区分大小写，仅修剪首尾空白。
- credentialSourceRecordID 仅保存来源记录 ID，不保存、显示或复制 secret。仅允许同一工作空间内、相同非空账号标签、已明确关联且允许记忆的直接来源。禁止自身引用、链式引用、跨账号/跨工作空间自动回退。
- 旧记录没有账号时，编辑原隧道，填写账号并点击“将已有钥匙串密钥关联到此账号”。确认后只保存账号/来源元数据，不读取或复制密钥；下次同账号添加即可选择引用。只有一个可复用来源时自动选择，多来源时用户选择。
- 新输入默认仅本次会话；保存到钥匙串仍需明确确认。引用在执行动作时解析，Keychain 拒绝、来源被删除/忘记/改变账号时清楚报错，不能静默换用其他 key。
- 会话密钥也带账号来源标记。外部配置更改、编辑重新打开、批量载入/保存都不能把旧账号缓存重新标记为新账号。
- 旧版 workspace key 的显式关联保留原 Keychain 身份；不迁移、不复制。替换或忘记旧 key 会撤销关联资格。

## 失败与恢复

- 保存失败：不调用 init，保留草稿。
- 保存成功但 init 失败：保留同一记录 ID；不再追加记录。错误出现在编辑器内，可修正后重试。
- 初始化前检查 named Profile 路径是否已存在，包括目录和损坏符号链接；存在即拒绝覆盖。读取路径状态失败时也不创建。检查只读文件属性，不读取 Profile 内的密钥。
- 先预留 record/profile/tunnel 标识，再做异步文件检查，防止双击或并发命令穿透。中断或返回不明后重试也重新检查磁盘，不能盲目重新初始化已有文件。
- 每次 UI 创建带独立 operationID；旧运行快照不算本轮完成。新 App 仅在网关声明 tunnelProfileCreationVersion=1 时允许 init，旧网关需用户明确停止/更新重启。
- 创建中禁止修改/重复提交，但可以关闭窗口；关闭不会撤销已保存的操作。断连显示结果待确认。已有 Profile 可选择保留并检查连接，不能仅凭文件存在宣称初始化成功。

## 验证与边界

在助手 Linux 工作副本完成，没有访问用户 Mac、真实 Keychain、真实账号、远端 Tunnel 或 GitHub Actions。

已执行：
- 全部 Swift 源码 swiftc -frontend -parse；不等于 macOS 编译或 SwiftUI 类型检查。
- scripts/check-tunnel-creation.py：生产 Foundation 状态机、旧快照关联、先保存再单次 init、无隐式 run、旧记录默认不创建等检查。
- scripts/check-ui-usability.py：12 项现有可用性源契约及生产模型检查。
- 生产 credential policy XCTest 与 fake-vault 集成；复现脚本见 scripts/check-tunnel-credentials.py。
- npm run build；tunnel-init（9 组）、credential-references、tunnel、tunnel-errors、tunnel-records、cli-service mock 回归；保留独立服务绑定与 CLI 功能。
- verify-gateway-package 检查。

全套 npm test 在基础、advanced、workflow 测试通过后，停在 cli-smoke 的 Unix socket 创建受当前沙箱限制；不宣称全套通过。首次并行编译有一次进程被杀，协调后最终单次 gateway 构建成功。原生 macOS SwiftPM、真实 Keychain 授权、SwiftUI 视觉与真实官方客户端连接均未验证。没有触发 Actions。

macOS 后续验收：旧记录一次性关联账号；同账号新增不输入 key；不同账号不出现该引用；主动作自动 init 且不启动；创建中关闭/重开；已有文件拒绝覆盖；init 失败修正重试；外部改账号后缓存拒绝；旧配置打开不创建。
