# A「清透玻璃」方向实现

基线：main `2fd2341d8b8af795e342d1a6c3fcb2725fd6e914`。用户选择概念 A 后实施，不复用概念图虚构服务、数字、通知、头像或搜索功能。

## 可见变化
- 窗口标题栏透明、隐藏重复窗口标题。标题栏、侧栏和内容统一动态珍珠蓝画布；页面头部不再画独立渐变色块。保留原生窗口控制和导航工具栏，不改系统设置。
- 浅色白蓝表面、细白高光与柔和蓝影；暗色使用对应深蓝画布和轻提亮表面，不强制系统外观。高对比保留明确描边，减少动态效果停用按压/hover过渡。
- 侧栏选中项为蓝色图形条，去小字号截断副标题。全局启停与托盘共用大图标动作语言，保留真实pending、禁用、确认和配置快照。
- 工作台四块等权卡合成单一hero：真实主状态、运行摘要、下一步动作；服务卡分清名称/用途/状态/授权与下一步。
- 隧道增加明确标注的“配置路径”可视图，不冒充真实网络连通测试；保存/凭据/授权逻辑保持。
- 服务列表透明底、设置共享玻璃卡片、主要弹窗与托盘连续同色画布。列表折叠与高级入口保留。

## 验证边界
云端执行 Swift 语法解析、源码契约与纯模型检查和 diff 检查。Linux 无 SwiftUI/AppKit SDK，因此没有本轮 macOS 原生编译、浅深截图、标题栏合成效果或动效流畅度验证；概念图不是程序截图。用户拉取后重点检查：标题栏与内容顶端连续、浅深色文字对比、窄窗口、侧栏滚动、大启停键盘焦点、原确认流程。


## 编译修复
用户原生编译发现 statusSection 的 ViewBuilder 参数被 DisclosureGroup 逃逸闭包捕获；为该参数补 @escaping。审计另两处函数型 ViewBuilder（隧道 detailSection、程序 field）只在 VStack 构建时求值，没有相同的逃逸存储；不无差别改签名。删除 macOS 15 起弃用的 showsBaselineSeparator 设置，不处理无关 Keychain 历史警告。

新增 check-viewbuilder-escaping.py：从真实源码提取参数签名，以 Swift 编译器编译并执行逃逸接收器闭包测试；移除 @escaping 的负对照必须复现原编译错误。它不是 SwiftUI 原生编译替代。当前助手云端为 Linux、无 xcrun/macOS SDK，未操作用户 Mac。


## 原生截图反馈修复（08:40）
- 图1是侧栏，不是托盘。侧栏改为单行状态、32pt横向图标操作，取消厚卡片和外围固定300pt滚动区域；活动默认仅标题、展开才显示摘要。运行详情、异常提示、未保存/外部配置冲突提示保留，托盘90pt动作不变。
- 图2灰块与NavigationSplitView侧栏toolbar区域对齐，说明仅NSWindow底色不足。使用SwiftUI公开 `toolbarBackgroundVisibility(.hidden, for: .windowToolbar)` 控制原生toolbar背景，`containerBackground(..., for: .window)` 指定窗口容器底；两列仅背景延伸顶部safe area。内容仍遵守safe area，不叠盖交通灯、不删除sidebar toggle、不改拖拽或系统外观。
- 官方依据：Apple WWDC24 [Tailor macOS windows with SwiftUI](https://developer.apple.com/videos/play/wwdc2024/10148/) 3:14隐藏toolbar背景、4:33指定window容器背景；[toolbarBackgroundVisibility](https://developer.apple.com/documentation/swiftui/view/toolbarbackgroundvisibility(_:for:))。本轮没有原生macOS渲染验证，不能把源码修复声明为截图已消除色块。

## A 布局与密度进一步落实（08:55 用户反馈）
本节取代前面“总览不放批量动作”的早期取舍。用户指出此前仍是旧纵向结构，因此不再把整套隧道管理卡接在服务列表之后。
- 总览采用单一 AnyLayout：宽屏左约2/3为MCP服务双列，右约1/3为隧道摘要和真实最近活动；窄屏同一视图树回单列，搜索、日志选择不因布局切换复制状态。
- 紧凑横向状态hero放真实计数与启停，原确认/快照检查保留；不添加概念图中的虚构通知、头像或示例服务。
- 共享卡片内边距14、页面边距18、section间距14；页头垂直间距14，去无意义描述最小高度。服务描述限两行，关键操作保持足够点击区域。
- 侧栏保持紧凑dock，托盘仍为大图标并保留折叠列表。此轮尚未原生视觉验收；用户09:02明确批准将布局与侧栏/顶部修复整版推送main，推送后仍需原生编译与画面反馈。
