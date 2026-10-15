# Linux 编译与模拟验证记录

2026-10-14；在用户后续明确授权云端运行验证后执行。未使用用户Mac、手机或真实MCP服务；未开放公网端口。

## 实际环境与安装
- x86_64 Linux，Node24.19.0，npm11.9.0。
- npm install --ignore-scripts --no-audit --no-fund：98个包安装成功。首次因默认npm缓存目录不可写失败，改用云端可写缓存后成功。
- 保留package-lock.json，后续可npm ci --ignore-scripts复现。没有运行依赖安装脚本。

## 构建发现与修复
第一次真实tsc报TS2322：管理命令Promise链的catch回调返回了stdout.write的boolean，与Promise<void>不符。
已改为块回调，返回void；另加noEmitOnError:true防止带编译错误生成新产物。

修正后 npm run build **退出码0**。

## 本地隔离smoke：9项通过
纯内存echo MCP fixture由本包SDK启动，不读取用户文件、不调用外部服务、不产生远程写入。网关只监听127.0.0.1临时端口。

1. 管理IPC启动与上游初始化
2. HTTP MCP initialize
3. 聚合工具目录、白名单与publicName
4. 聚合只读echo调用
5. 单服务端点调用
6. 未允许工具调用被拒绝
7. 带浏览器Origin请求返回403
8. 停止受管理的模拟服务
9. 网关正常退出

脚本与日志：gateway/validation/mock-server.mjs、smoke.mjs、build.log、smoke.log。
复现：在gateway目录执行npm ci --ignore-scripts，然后npm run build、node validation/smoke.mjs。

## 没有验证的内容
- macOS SwiftUI应用、Keychain、原生窗口、Swift Process IPC前端没有在Linux编译或运行。
- 未接入真实外部MCP、真实凭据或有副作用的工具。
- 未做完整攻击面测试、压力测试、并发取消验证、恶意服务测试或长期可靠性测试。
- 本地进程仍可访问白名单HTTP工具；loopback与Origin检查不是身份认证，取消不保证撤销已执行操作。

`.github/workflows/macos-compile.yml`提供用户日后可手动触发的macOS SwiftPM与gateway编译流程源码。没有上传或触发GitHub Actions，没有产生CI费用。是否使用须自行确认账户配额、费用与源码上传范围。

因此状态应写为：**gateway已在Linux编译并通过上述本地模拟验证；原生macOS App仍未构建运行**。此前纯静态报告保留作为历史记录，不能继续概括全部组件“从未执行”。
