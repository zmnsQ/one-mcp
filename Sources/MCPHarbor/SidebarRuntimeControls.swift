import SwiftUI

/// Global controls live once, below navigation, rather than repeating above every page.
struct SidebarRuntimeControls: View {
    @EnvironmentObject private var store: HarborStore
    @State private var showDetails = false
    let confirm: (String, @escaping () -> Void) -> Void

    private var summary: RuntimeStatusSummary {
        RuntimeStatusSummary(gateway: store.menuGatewayStatus,
            servers: store.menuServers.map { store.menuServerStatus($0.id) },
            tunnels: store.menuTunnelIDs.map { store.menuTunnelStatus($0) })
    }
    private var failedSteps: Int { store.startAllSteps.filter { $0.status == "failed" }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { showDetails = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: store.menuGatewayStatus.symbol)
                        .foregroundStyle(store.menuGatewayStatus.color).accessibilityHidden(true)
                    Text("网关 · " + store.menuGatewayStatus.title).font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    if summary.failureCount > 0 || failedSteps > 0 {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            .accessibilityLabel("有异常或上次启动失败，请查看详情")
                    }
                    Image(systemName: "chevron.right").font(.caption2).accessibilityHidden(true)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(summary.activityText + " · 查看当前状态与上次启动结果")
            HStack(spacing: 8) { startAllButton; stopAllButton }
            .controlSize(.regular)
            if !store.isGatewayRunning {
                Button(store.gatewayState == "Disconnected" ? "仅重新连接 / 启动网关" : "仅启动网关") {
                    confirm("启动本机 OneMCP 网关？不会自动连接远端隧道或启动 MCP 服务。") { store.startGateway() }
                }
                .disabled(!store.runtimeFilesReady || store.takeoverBusy || store.gatewayStartBusy)
            }
            if store.hasUnsavedChanges {
                Text("先保存修改，再全部启动").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Divider()
            SidebarActivityView(confirm: confirm)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
        .padding(.horizontal, 12).padding(.bottom, 8)
        .sheet(isPresented: $showDetails) {
            RuntimeStatusDetails().environmentObject(store)
                .disclosureGroupStyle(FullRowDisclosureStyle())
        }
    }
    private var startAllButton: some View {
        Button {
            let plan = store.preferences, workspace = store.currentWorkspaceID, revision = store.savedRevision
            confirm(store.startAllConfirmation) {
                store.startAll(expectedPlan: plan, expectedWorkspace: workspace, expectedRevision: revision)
            }
        } label: {
            Label(store.startAllBusy ? "启动中" : "全部启动", systemImage: store.startAllBusy ? "hourglass" : "play.fill")
                .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(TrayActionStyle(tint: .blue))
        .disabled(store.startAllBusy || store.takeoverBusy || store.hasUnsavedChanges)
        .help(store.hasUnsavedChanges ? "请先保存修改，再全部启动" : "依次启动网关、参与的 MCP 和隧道")
    }

    private var stopAllButton: some View {
        Button {
            confirm("停止共享网关及全部连接？所有连接到此实例的 AI 和应用都会受到影响。将取消后续启动并请求停止当前进程；配置会保留。") { store.shutdown() }
        } label: {
            Label(store.menuGatewayStatus == .stopping ? "停止中" : "全部停止", systemImage: store.menuGatewayStatus == .stopping ? "hourglass" : "stop.fill")
                .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(TrayActionStyle(tint: .red))
        .disabled(store.menuGatewayStatus == .stopping || (!store.anyProcessRunning && !store.startAllBusy && !store.gatewayStartBusy) || store.takeoverBusy)
    }

}

private struct RuntimeStatusDetails: View {
    @EnvironmentObject private var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                HarborSheetHeader(title: "运行状态与启动结果", subtitle: "当前连接与上次启动结果分开查看，避免把提交当成就绪。", symbol: "waveform.path.ecg", tint: .teal)
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSurface {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("当前状态").font(.headline)
                            MenuStatusRow(name: "本地网关", status: store.menuGatewayStatus)
                            ForEach(store.menuServers, id: \.id) { server in
                                MenuStatusRow(name: "MCP · " + server.name, status: store.menuServerStatus(server.id))
                            }
                            ForEach(store.menuTunnelIDs, id: \.self) { id in
                                MenuStatusRow(name: "隧道 · " + store.menuTunnelName(id), status: store.menuTunnelStatus(id))
                            }
                        }
                    }
                    SettingsSurface {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(store.startAllBusy ? "全部启动进行中…" : "上次全部启动结果").font(.headline)
                            if store.startAllSteps.isEmpty {
                                Text("还没有全部启动记录。单独启停项目不会生成此记录。").foregroundStyle(.secondary)
                            }
                            ForEach(store.startAllSteps) { step in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: step.presentationStatus.symbol)
                                        .foregroundStyle(step.presentationStatus.color).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(step.title + " · " + step.statusTitle).fontWeight(.medium)
                                        Text(step.detail).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            if store.startAllBusy {
                                Button("取消后续启动") { store.cancelStartAll() }
                            }
                            Text("修正问题后可再次全部启动。")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    HarborNotice(title: "本机状态 ≠ 远端调用验证", detail: "就绪不代表远端调用已验证。停止或重启服务可能影响依赖它的客户端。", symbol: "info.circle", tint: .teal)
                }
            }
        }
        .padding(24).frame(width: 620, height: 640)
    }
}
