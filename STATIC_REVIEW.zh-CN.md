# Gateway 静态源码审阅

2026-10-14；仅阅读 gateway/src/index.ts、package.json，并比对 MCP TypeScript SDK v1.x 的官方 client/stdio.ts 与 shared/protocol.ts。未安装、编译、执行或测试。该记录不代表SDK版本兼容性已由编译验证。

## 已确认的设计与修正
- 网关只监听127.0.0.1；限制Host且拒绝带Origin的浏览器请求。管理命令走父进程stdin；HTTP只暴露已允许的MCP工具。
- executable要求绝对路径，StdioClientTransport底层shell:false；工具白名单默认决定暴露范围。
- 官方stdio实现支持maxBufferSize，并允许在connect之前监听stderr；不是未定义参数。
- 已将每请求extra.signal传给上游callTool。官方Protocol关闭会中止在途handler，客户端HTTP连接关闭时可沿dispose链发取消。
- 请求计数在读取body前保留，避免先await body后再计数造成限流竞态。
- stderr只记录收到字节数，不再把跨chunk无法可靠脱敏的原始内容写到UI。
- 聚合工具别名带hash，UI工具目录事件包含publicName。
- 增加有界shutdown退出机制。

## 保留限制与建议
1. loopback、Host和Origin检查不是用户身份认证。同一机器上的其他本地进程仍可调用白名单工具；白名单工具可能有写入或高影响副作用。不得把它解释为逐次人工审批或进程沙箱。
2. MCP取消通知不保证撤销已执行的外部操作；取消、连接丢失、超时后的结果仍可能不确定，不应自动重试。
3. 已修：SDK client.onerror仅显示通用事件，默认隐藏可能包含私密工具结果的原始协议响应。
4. 已修：SDK stdio关闭路径约2秒+2秒，网关强退期限已延长至8秒；原生父进程已给10秒再发终止，App正常退出等待15秒。孙进程清理不由此实现保证。
5. tools/list允许刷新，但调用授权仍按名称白名单；上游同名工具的含义/权限变化不受schema固定约束。仅使用信任的上游。
6. 这是无持久session的POST-only facade，未提供SSE恢复、远程OAuth、客户端身份鉴别或沙箱隔离，不应称为完整通用MCP托管平台。

官方源码参考：
- https://github.com/modelcontextprotocol/typescript-sdk/blob/v1.x/src/client/stdio.ts
- https://github.com/modelcontextprotocol/typescript-sdk/blob/v1.x/src/shared/protocol.ts

结论：本轮能确认主要生命周期/限流/日志问题已有源码级改进；剩余限制必须对用户如实说明。构建和端到端客户端互操作留待用户后续验证。
