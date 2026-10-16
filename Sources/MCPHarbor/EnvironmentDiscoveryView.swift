import SwiftUI

/// Presents the same read-only discovery results consumed by the CLI.
/// Discovery, parsing and applying settings belong to HarborStore, not this view.
struct EnvironmentDiscoveryView: View {
    @EnvironmentObject private var store: HarborStore
    @State private var selection: DiscoverySelection?

    private enum DiscoverySelection: Identifiable {
        case client(DiscoveredClient)
        case profile(DiscoveredProfile)

        var id: String {
            switch self {
            case .client(let value): "client:\(value.id)"
            case .profile(let value): "profile:\(value.id)"
            }
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("发现已安装的隧道客户端和已有配置，选择需要复用的项目。")
                            .font(.callout)
                        Text("只读检测，不启动程序、不联网、不展示、复制或修改凭据。发现候选路径不代表该程序已经验证。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.detectEnvironment()
                    } label: {
                        Label(store.discoveryBusy ? "正在检测…" : "检测本机环境", systemImage: "magnifyingglass")
                    }.disabled(store.discoveryBusy)
                }
                if let profileFile = store.preferences.aggregateProfileFile {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("聚合隧道正在复用现有文件", systemImage: "doc.badge.gearshape")
                            .font(.callout.bold())
                        detail("当前 Profile 文件", value: profileFile)
                        Text("此路径优先于手动填写的 Profile 名称。复用期间不能初始化该文件。")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("改用命名 Profile") {
                            store.preferences.aggregateProfileFile = nil
                        }.disabled(store.anyProcessRunning)
                        Text("切换仅修改当前界面设置，请保存后使用；原文件不会被删除或修改。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(12).background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                }
                if store.discoveryBusy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在读取本机安装路径与非敏感配置信息…").font(.caption).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .combine)
                }
                if let error = store.discoveryError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                }
                if let result = store.environmentDiscovery {
                    clientResults(result.clients.filter { $0.id.hasPrefix("tunnel-client:") })
                    Divider()
                    profileResults(result.profiles)
                    if !result.warnings.isEmpty {
                        DisclosureGroup("检测说明（\(result.warnings.count)）") {
                            ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, warning in
                                Label(warning, systemImage: "info.circle")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    if store.anyProcessRunning {
                        Label("采用配置前请先停止当前连接。检测结果仍可查看。", systemImage: "pause.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if !store.discoveryBusy && store.discoveryError == nil {
                    Label("尚未检测。你也可以在下方手动设置路径。", systemImage: "desktopcomputer")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }.padding(12)
        } label: {
            Label("本机环境", systemImage: "desktopcomputer.and.arrow.down")
        }
        .sheet(item: $selection) { item in
            VStack(alignment: .leading, spacing: 18) {
                Text("核对后采用配置").font(.title2.bold())
                switch item {
                case .client(let client):
                    Text("将更新当前工作空间的 tunnel-client 路径。")
                    detail("客户端路径", value: client.path)
                    detail("来源", value: client.source)
                case .profile(let profile):
                    Text("将复用此文件的确切路径，并更新聚合隧道 Profile 名称及 Tunnel ID。独立隧道设置保持不变。")
                    detail("Profile", value: profile.name)
                    detail("Tunnel ID", value: profile.tunnelID ?? "未提供")
                    detail("原配置端点（仅供核对）", value: profile.endpoint ?? "未提供")
                    detail("来源文件", value: profile.path)
                }
                Text("仅填入界面供核对；请之后点击工具栏“保存”。不会自动启动、覆盖原 profile 文件或复制凭据。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("取消", role: .cancel) { selection = nil }
                    Spacer()
                    Button("采用到当前工作空间") {
                        switch item {
                        case .client(let client): store.applyDiscoveredClient(client)
                        case .profile(let profile): store.applyDiscoveredProfile(profile)
                        }
                        selection = nil
                    }.buttonStyle(.glassProminent).disabled(store.anyProcessRunning)
                }
            }.padding(24).frame(width: 560)
        }
    }

    private func clientResults(_ clients: [DiscoveredClient]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("隧道客户端 · \(clients.count) 个候选").font(.headline)
            if clients.isEmpty {
                Text("未发现客户端路径。请手动选择已安装的 tunnel-client；此结果不代表它没有安装。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(clients) { client in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        detail("路径", value: client.path)
                        Spacer()
                        Button("采用此路径") { selection = .client(client) }
                            .disabled(store.anyProcessRunning)
                    }
                    Text("来源：\(client.source)").font(.caption).foregroundStyle(.secondary)
                    Text(client.version.map { "检测版本：\($0)" } ?? "版本未验证 · 只发现路径，未执行客户端")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(12).background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func profileResults(_ profiles: [DiscoveredProfile]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("现有 Profile · \(profiles.count) 个").font(.headline)
            if profiles.isEmpty {
                Text("未发现可识别的 profile。可在“隧道连接”中手动填写，或查看检测说明。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(profiles) { profile in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(profile.name, systemImage: "doc.text").font(.callout.bold())
                        Spacer()
                        Button("用于聚合隧道…") { selection = .profile(profile) }
                            .disabled(store.anyProcessRunning || (profile.tunnelID ?? "").isEmpty)
                    }
                    detail("Tunnel ID", value: profile.tunnelID ?? "未提供")
                    if (profile.tunnelID ?? "").isEmpty {
                        Text("缺少 Tunnel ID，暂不能直接采用；请先核对原配置。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    detail("端点", value: profile.endpoint ?? "未提供")
                    DisclosureGroup("来源与检测依据") {
                        detail("来源", value: profile.source)
                        detail("路径", value: profile.path)
                        Text("仅发现本地配置；未验证账号权限、远程隧道有效性或 ChatGPT 连通性。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.font(.caption)
                }.padding(12).background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func detail(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.caption, design: .monospaced))
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
