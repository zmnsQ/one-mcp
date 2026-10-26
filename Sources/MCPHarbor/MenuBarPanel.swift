import SwiftUI
import AppKit

/// The default NSMenu converts static SwiftUI Labels into disabled menu items.
/// A window-style extra preserves readable semantic text without fake actions.
struct MenuBarPanel: View {
    @EnvironmentObject private var store: HarborStore
    @Environment(\.openWindow) private var openWindow

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

            HStack(spacing: 10) {
                Button { openMainWindow() } label: {
                    Label("打开主窗口", systemImage: "macwindow").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
                Button { confirmStart() } label: {
                    RuntimeActionLabel(title: store.startAllBusy ? "启动中" : "全部启动", busy: store.startAllBusy)
                }
                .buttonStyle(.bordered)
                .disabled(store.startAllBusy || store.takeoverBusy || store.hasUnsavedChanges)
                .help(store.hasUnsavedChanges ? "请先在主窗口保存修改" : "确认后依次启动网关、MCP 服务与隧道")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusSection("MCP 服务", count: store.menuServers.count) {
                        if store.menuServers.isEmpty { emptySection("暂无 MCP 服务", detail: "到主窗口添加工具服务", symbol: "shippingbox") }
                        ForEach(store.menuServers, id: \.id) { server in
                            MenuStatusRow(name: server.name, status: store.menuServerStatus(server.id))
                        }
                    }
                    Divider()
                    statusSection("隧道", count: store.menuTunnelIDs.count) {
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

            Button(role: .destructive) { confirmStop() } label: {
                Label("停止全部连接", systemImage: "stop.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled((!store.anyProcessRunning && !store.startAllBusy && !store.gatewayStartBusy) || store.takeoverBusy)
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
        .background(Color(nsColor: .windowBackgroundColor))
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

    private var statusListHeight: CGFloat {
        CGFloat(min(320, 112 + 36 * (max(1, store.menuTunnelIDs.count) + max(1, store.menuServers.count))))
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
