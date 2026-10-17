# 共享连接断开与重新启动修复

基于 3529694 的代码检查；截图只能证明界面共享连接断开，不能证明网关进程已退出。

## 已发现的可复现代码路径

- 共享快照曾包含全部工具 schema，管理 IPC 响应限制为 4 MiB，原生行缓冲也有 4 MiB 上限。大型目录可使界面断开，而网关仍然运行；再次连接会重复失败。
- 状态查询曾排在所有管理写操作之后。较慢的初始化、doctor 或连续操作会延迟快照，直到适配器查询超时。
- 启动曾只检查 control.sock 文件是否存在。异常退出残留的 Unix socket 会让每次启动都变成连接不存在的监听者。
- CLI gateway run 仍为前台生命周期；其父进程/输入关闭会关闭网关。本次没有改成后台服务或自动恢复 MCP/隧道。

## 修改边界

1. status/snapshot 为只读查询，可在管理写队列繁忙时读取当前状态；启动/停止等写操作仍串行。
2. 仅 GUI snapshot 使用 3 MiB 预算。优先保留所有工具名称、公有别名、运行状态和白名单；必要时省略部分元数据并给出提示。极端目录无法容纳名称时明确标记目录省略，界面不保留旧目录。外部 MCP schema、工具调用、真实目录和权限均不修改。若连权威状态本身都超限，明确失败，绝不裁剪权限伪装成功。
3. 用户明确启动时，GUI/CLI 先持有原有配置/启动租约，再检查 socket。可连接的实例只连接或报告已运行；仅 owner/type/mode 检查通过、连接明确 ECONNREFUSED、inode 未改变的 socket 才移为带随机后缀的 .stale 文件。保留原对象，不删除配置、不读取凭据、不终止现有网关。未知、超时、权限错误均停止恢复。
4. GUI 启动检查有取消/超时控制，辅助进程退出前不释放租约，取消后不会迟到启动。恢复/连接不自动重放管理操作，也不自动启动 MCP 或隧道。
5. 断开界面显示“网关状态未确认”，并区分端点不可用、身份变化、快照过大及超时。

租约防止遵循同一协议的启动者竞争；不声称能对抗绕过协议、恶意替换路径的同用户进程。

## 验证方式

- `npm run build`
- `npm test`
- `node validation/runtime-start-smoke.mjs --pure`
- `node validation/runtime-snapshot-smoke.mjs --pure`
- `node validation/runtime-read-smoke.mjs`
- 原生测试：`swift test`（需支持项目要求的 macOS/Swift 环境）。

不支持 Unix socket 的测试环境可明确设置 `ONEMCP_SKIP_SOCKET_TEST=1`，但必须把 Unix IPC/异常退出残留 socket 的真实集成验证标记为未验证。纯测试覆盖决策/错误/身份变化，不等价于真实 Unix socket；Swift 源码检查也不等价于运行原生窗口。

## 本次执行结果

- TypeScript 构建通过。
- 首次不跳过 socket 的整套测试在 CLI Unix socket 启动处因运行环境限制失败（EPERM）；前面的基础、进阶及 18 项工作流检查已通过。
- 明确设置 `ONEMCP_SKIP_SOCKET_TEST=1` 后整套测试退出码 0，含新增快照预算、恢复决策与真实网关慢操作期间状态可读测试。
- Unix socket 真实集成、macOS 编译、Swift 测试及原生窗口均未验证；没有声称用户机器上的故障已现场复现。
