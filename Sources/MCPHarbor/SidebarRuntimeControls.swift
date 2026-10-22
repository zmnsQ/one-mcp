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
    private var skippedSteps: Int { store.startAllSteps.filter { $0.status == "skipped" }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidebarActivityView(confirm: confirm)
            Divider()
            Button { showDetails = true } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Image(systemName: store.menuGatewayStatus.symbol)
                            .foregroundStyle(store.menuGatewayStatus.color).accessibilityHidden(true)
                        Text("网关 · \(store.menuGatewayStatus.title)").font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
                    }
                    Text(summary.activityText).font(.system(size: 12))
                    if summary.failureCount > 0 {
                        Label("\(summary.failureCount) 项异常 · 查看状态", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .medium))
                    } else if failedSteps > 0 {
                        Label("上次启动 \(failedSteps) 项失败 · 查看结果", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .medium))
                    } else if store.startAllBusy {
                        Text("正在依次启动 · 查看进度").font(.system(size: 12))
                    } else if skippedSteps > 0 {
                        Text("上次启动 \(skippedSteps) 项跳过 · 查看结果").font(.system(size: 12))
                    } else if !store.startAllSteps.isEmpty {
                        Text("查看上次启动结果").font(.system(size: 12))
                    }
                }
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .help("查看当前连接状态和上次全部启动的详细结果")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { startAllButton; stopAllButton }
                VStack(alignment: .leading, spacing: 8) { startAllButton; stopAllButton }
            }
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
            Text("仅监听本机 · 工具默认不开放").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.bottom, 14)
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
            Label(store.startAllBusy ? "启动中" : "全部启动", systemImage: "play.fill")
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.borderedProminent)
        .disabled(store.startAllBusy || store.takeoverBusy || store.hasUnsavedChanges)
        .help(store.hasUnsavedChanges ? "请先保存修改，再全部启动" : "依次启动网关、参与的 MCP 和隧道")
    }

    private var stopAllButton: some View {
        Button {
            confirm("停止共享网关及全部连接？所有连接到此实例的 AI 和应用都会受到影响。将取消后续启动并请求停止当前进程；配置会保留。") { store.shutdown() }
        } label: {
            Label("全部停止", systemImage: "stop.fill").fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
        .disabled((!store.anyProcessRunning && !store.startAllBusy && !store.gatewayStartBusy) || store.takeoverBusy)
    }

}

private struct RuntimeStatusDetails: View {
    @EnvironmentObject private var store: HarborStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("运行状态与启动结果").font(.title2.bold())
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
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
                    Text("就绪不代表远端调用已验证。停止或重启服务可能影响依赖它的客户端。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(24).frame(width: 600, height: 560)
    }
}
