import SwiftUI
import AppKit

/// The default NSMenu converts static SwiftUI Labels into disabled menu items.
/// A window-style extra preserves readable semantic text without fake actions.
struct MenuBarPanel: View {
    @EnvironmentObject private var store: HarborStore
    @Environment(\.openWindow) private var openWindow

    @State private var serversExpanded = false
    @State private var tunnelsExpanded = false

    private var workspaceName: String {
        store.workspaces.first(where: { $0.id == store.currentWorkspaceID })?.name ?? store.currentWorkspaceID
    }
    private var summary: RuntimeStatusSummary {
        RuntimeStatusSummary(gateway: store.menuGatewayStatus,
            servers: store.menuServers.map { store.menuServerStatus($0.id) },
            tunnels: store.menuTunnelIDs.map { store.menuTunnelStatus($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    BrandMark().frame(width: 38, height: 38).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("One MCP").font(.system(size: 17, weight: .bold))
                        Label(workspaceName, systemImage: "square.stack.3d.up")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            .help("当前工作空间：" + workspaceName)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: store.menuGatewayStatus.symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(store.menuGatewayStatus.color).accessibilityHidden(true)
                }
                MenuStatusRow(name: "本地网关", status: store.menuGatewayStatus)
                HStack(spacing: 10) {
                    runtimeMetric("MCP", value: "\(summary.runningServers) / \(store.menuServers.count)", symbol: "shippingbox")
                    runtimeMetric("隧道", value: "\(summary.runningTunnels) / \(store.menuTunnelIDs.count)", symbol: "network")
                }
                if summary.hasUnknownStates {
                    Label("连接待确认 · 仅统计已确认运行项", systemImage: "questionmark.circle")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else if summary.failureCount > 0 {
                    Label("\(summary.failureCount) 项异常 · 请查看下方状态", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color(nsColor: .separatorColor).opacity(0.4)))

            HStack(spacing: 12) {
                Button { confirmStart() } label: {
                    TrayActionLabel(title: store.startAllBusy ? "启动中" : "全部启动",
                                    symbol: "play.fill", busy: store.startAllBusy)
                }
                .buttonStyle(TrayActionStyle(tint: .accentColor))
                .disabled(store.startAllBusy || store.gatewayStartBusy || stopping || store.takeoverBusy || store.hasUnsavedChanges)
                .help(store.hasUnsavedChanges ? "请先在主窗口保存修改" : "确认后依次启动网关、MCP 服务与隧道")
                Button(role: .destructive) { confirmStop() } label: {
                    TrayActionLabel(title: stopping ? "停止中" : "全部停止",
                                    symbol: "stop.fill", busy: stopping)
                }
                .buttonStyle(TrayActionStyle(tint: .red))
                .disabled(stopping || (!store.anyProcessRunning && !store.startAllBusy && !store.gatewayStartBusy) || store.takeoverBusy)
                .help("确认后停止共享网关及全部连接")
            }
            Button { openMainWindow() } label: {
                Label("打开主窗口", systemImage: "macwindow").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusSection("MCP 服务", count: store.menuServers.count, symbol: "shippingbox", expanded: $serversExpanded) {
                        if store.menuServers.isEmpty { emptySection("暂无 MCP 服务", detail: "到主窗口添加工具服务", symbol: "shippingbox") }
                        ForEach(store.menuServers, id: \.id) { server in
                            MenuStatusRow(name: server.name, status: store.menuServerStatus(server.id))
                        }
                    }
                    Divider()
                    statusSection("隧道", count: store.menuTunnelIDs.count, symbol: "network", expanded: $tunnelsExpanded) {
                        if store.menuTunnelIDs.isEmpty { emptySection("暂无隧道", detail: "仅本机使用时无需创建", symbol: "network") }
                        ForEach(store.menuTunnelIDs, id: \.self) { id in
                            MenuStatusRow(name: store.menuTunnelName(id), status: store.menuTunnelStatus(id))
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Reserve real space in MenuBarExtra's content-sized window.
            .frame(height: statusListHeight)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))

            Divider()
            HStack {
                Button { openSettings() } label: { Label("设置", systemImage: "gearshape") }
                    .buttonStyle(.borderless)
                Spacer()
                Button("退出 One MCP") { NSApp.terminate(nil) }.keyboardShortcut("q")
                    .buttonStyle(.borderless)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.primary)
        .padding(16)
        .frame(width: 380)
        .background { HarborCanvas() }
    }

    private func runtimeMetric(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit()
        }
        .padding(9).frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func emptySection(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 5)
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettings() {
        HarborNavigationRouter.shared.destination = "settings"
        openMainWindow()
    }

    private func confirmStart() {
        let plan = store.preferences, workspace = store.currentWorkspaceID, revision = store.savedRevision
        let alert = NSAlert()
        alert.messageText = "全部启动当前工作空间？"
        alert.informativeText = store.startAllConfirmation
        alert.addButton(withTitle: "启动")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            store.startAll(expectedPlan: plan, expectedWorkspace: workspace, expectedRevision: revision)
        }
    }

    private var stopping: Bool { store.menuGatewayStatus == .stopping }

    private var statusListHeight: CGFloat {
        let servers = serversExpanded ? 12 + 36 * max(1, store.menuServers.count) : 0
        let tunnels = tunnelsExpanded ? 12 + 36 * max(1, store.menuTunnelIDs.count) : 0
        return CGFloat(min(320, 145 + servers + tunnels))
    }

    private func statusSection<Content: View>(_ title: String, count: Int, symbol: String,
                                              expanded: Binding<Bool>,
                                              @ViewBuilder content: () -> Content) -> some View {
        DisclosureGroup(isExpanded: expanded) {
            content()
        } label: {
            HStack(spacing: 8) {
                Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text("\(count)").font(.caption.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
        .disclosureGroupStyle(FullRowDisclosureStyle())
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

/// Large, explicit actions: pending comes from runtime state, never a visual timer.
struct TrayActionLabel: View {
    let title: String
    let symbol: String
    let busy: Bool
    var height: CGFloat = 90
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 9) {
            Group {
                if busy && !reduceMotion {
                    ProgressView().controlSize(.regular)
                } else {
                    Image(systemName: busy ? "hourglass" : symbol)
                        .font(.system(size: 27, weight: .semibold))
                }
            }.frame(width: 36, height: 36).accessibilityHidden(true)
            Text(title).font(.system(size: 13, weight: .semibold))
        }
        .frame(maxWidth: .infinity, minHeight: height)
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct TrayActionStyle: ButtonStyle {
    let tint: Color
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? tint : Color.secondary)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        if isEnabled && contrast != .increased {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(LinearGradient(colors: [tint.opacity(0.2), tint.opacity(0.04)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
            }
            .overlay(RoundedRectangle(cornerRadius: 18)
                .strokeBorder(isEnabled ? tint.opacity(contrast == .increased ? 1 : 0.35) : Color.secondary.opacity(0.2)))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isFocused ? tint : .clear, lineWidth: 2)
                    .padding(-3).allowsHitTesting(false)
            }
            .shadow(color: tint.opacity(isEnabled && !configuration.isPressed ? 0.12 : 0), radius: 6, y: 3)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.96)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
