import SwiftUI
import AppKit

/// The default NSMenu converts static SwiftUI Labels into disabled menu items.
/// A window-style extra preserves readable semantic text without fake actions.
struct MenuBarPanel: View {
    @EnvironmentObject private var store: HarborStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("One MCP").font(.headline)
                Spacer()
                Text("连接状态").font(.subheadline).foregroundStyle(.secondary)
            }
            MenuStatusRow(name: "本地网关", status: store.menuGatewayStatus)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusSection("MCP 服务", count: store.menuServers.count) {
                        if store.menuServers.isEmpty {
                            Text("尚未添加 MCP 服务").foregroundStyle(.secondary)
                        }
                        ForEach(store.menuServers, id: \.id) { server in
                            MenuStatusRow(name: server.name, status: store.menuServerStatus(server.id))
                        }
                    }
                    Divider()
                    statusSection("隧道", count: store.menuTunnelIDs.count) {
                        if store.menuTunnelIDs.isEmpty {
                            Text("尚未添加隧道").foregroundStyle(.secondary)
                        }
                        ForEach(store.menuTunnelIDs, id: \.self) { id in
                            MenuStatusRow(name: store.menuTunnelName(id), status: store.menuTunnelStatus(id))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)
            Label("就绪不代表远端调用已验证", systemImage: "info.circle")
                .font(.system(size: 13)).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("打开 One MCP", systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            HStack {
                Button("停止全部连接", role: .destructive) { confirmStop() }
                    .disabled(!store.anyProcessRunning && !store.startAllBusy && !store.gatewayStartBusy)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }.keyboardShortcut("q")
            }
        }
        .font(.system(size: 13))
        .padding(18)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func statusSection<Content: View>(_ title: String, count: Int,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(title)（\(count)）").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func confirmStop() {
        let alert = NSAlert()
        alert.messageText = "停止共享网关及全部连接？"
        alert.informativeText = "所有连接到此实例的 AI 和应用都会受到影响。"
        alert.addButton(withTitle: "停止")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { store.shutdown() }
    }
}

struct MenuStatusRow: View {
    let name: String
    let status: MenuBarStatus
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(status.title)
                .font(.system(size: 13, weight: .semibold))
                .fixedSize()
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)，\(status.title)")
    }
}
