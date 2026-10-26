import SwiftUI

extension HarborStore {
    func recordServiceLogSnapshotEvent(_ event: [String: Any], instanceID: String, sequence: Int) {
        let known = Set(preferences.servers.map(\.id) + sharedRuntimeServers.map(\.id))
        serviceLogs.retain(serverIDs: known)
        serviceLogs.ingestSnapshot(event, instanceID: instanceID, sequence: sequence, knownServerIDs: known)
    }

    func recordServiceLogEvent(_ event: [String: Any]) {
        let known = Set(preferences.servers.map(\.id) + sharedRuntimeServers.map(\.id))
        serviceLogs.retain(serverIDs: known)
        serviceLogs.ingest(event, knownServerIDs: known)
    }
}

struct ServiceLogView: View {
    @EnvironmentObject private var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    let server: ServerConfig
    @State private var errorsOnly = false
    @State private var follow = ServiceLogFollowState()
    private var allLines: [ServiceLogEntry] { store.serviceLogs.lines(for: server.id) }
    private var lines: [ServiceLogEntry] { errorsOnly ? allLines.filter { $0.level == "错误" } : allLines }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("\(server.name) · 服务日志", systemImage: "doc.text.magnifyingglass").font(.title2.bold())
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("实时更新 · 最近 \(ServiceLogBuffer.defaultLimit) 条 · 仅本次会话")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("记录范围") {
                Text("记录本机网关观察到的生命周期、调用结果和安全诊断。时间为本应用的接收时间，不是远端事件发生时间。不会显示 MCP 标准输出、原始标准错误、请求参数或返回内容；不读取远端服务内部日志。共享网关只提供当前可用的近期事件，并非完整历史。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.font(.caption)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("显示 \(lines.count) / \(allLines.count) 条").font(.caption).monospacedDigit()
                    Spacer()
                    Button("清空此服务日志") { store.serviceLogs.clear(serverID: server.id) }.disabled(allLines.isEmpty)
                }
                HStack(spacing: 20) {
                    Toggle("仅错误", isOn: $errorsOnly).toggleStyle(.checkbox).font(.caption)
                    Toggle("跟随最新", isOn: Binding(get: { follow.isFollowing }, set: { follow.setFollowing($0) }))
                        .toggleStyle(.checkbox).font(.caption)
                        .help("手动滚动会暂停跟随，避免打断阅读；开启后跳到最新日志。")
                }
            }
            if lines.isEmpty {
                ContentUnavailableView(errorsOnly ? "暂无错误日志" : "暂无服务日志", systemImage: "doc.text", description: Text(errorsOnly ? "当前记录中没有错误；可关闭“仅错误”查看全部运行事件。" : "后续收到此服务的运行事件后会显示在这里。其他服务的日志不会混入。"))
            } else {
                ScrollViewReader { proxy in
                    VStack(spacing: 8) {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(lines) { line in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text(line.time, style: .time).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                                        Text(line.level).foregroundStyle(line.level == "错误" ? Color.orange : Color.secondary).frame(width: 40)
                                        Text(line.text).frame(maxWidth: .infinity, alignment: .leading)
                                    }.font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                        .accessibilityElement(children: .combine)
                                }
                                Color.clear.frame(height: 1).id("service-log-bottom")
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        }
                        .onScrollPhaseChange { _, phase in
                            // Only user interaction releases follow. Programmatic scrolling
                            // and incoming rows must never switch it back on implicitly.
                            if phase == .interacting { follow.setFollowing(false) }
                        }
                        .background(Color.secondary.opacity(0.05)).clipShape(RoundedRectangle(cornerRadius: 10))
                        HStack {
                            Label(follow.isFollowing ? "正在跟随最新日志" : "跟随已暂停 · 可安心阅读", systemImage: follow.isFollowing ? "arrow.down.to.line" : "pause.circle")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if !follow.isFollowing {
                                Button(follow.unseenCount > 0 ? "查看最新（\(follow.unseenCount) 条新记录）" : "跳到最新") {
                                    follow.setFollowing(true)
                                }.accessibilityHint("滚动至最新日志，并恢复自动跟随")
                            }
                        }
                    }
                    .onAppear { if follow.isFollowing { proxy.scrollTo("service-log-bottom", anchor: .bottom) } }
                    .onChange(of: lines.map(\.id)) { _, _ in
                        if follow.isFollowing { proxy.scrollTo("service-log-bottom", anchor: .bottom) }
                    }
                    .onChange(of: follow.isFollowing) { _, enabled in
                        if enabled { proxy.scrollTo("service-log-bottom", anchor: .bottom) }
                    }
                }
            }
        }
        // Observe outside the nonempty branch: clearing or filtering to zero
        // must reset unread IDs even when the scroll reader is removed.
        .onChange(of: ServiceLogDisplaySnapshot(ids: lines.map(\.id), errorsOnly: errorsOnly)) { old, new in
            if old.errorsOnly != new.errorsOnly {
                follow.resetUnread()
            } else {
                follow.receive(oldIDs: old.ids, newIDs: new.ids)
            }
        }
        .padding(24).frame(minWidth: 520, idealWidth: 720, minHeight: 460, idealHeight: 560)
    }
}
