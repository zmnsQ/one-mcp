import SwiftUI

struct SidebarActivityView: View {
    @EnvironmentObject private var store: HarborStore
    @State private var expanded = false
    let confirm: (String, @escaping () -> Void) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { expanded.toggle() } label: {
                HStack {
                    Label("操作动态", systemImage: "clock.arrow.circlepath").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(expanded ? "收起操作动态" : "展开操作动态")
            if let latest = store.activities.first {
                Text(latest.summary).font(.system(size: 12)).lineLimit(2)
                Text(latest.source.rawValue + " · " + latest.outcome.rawValue)
                    .font(.system(size: 11)).foregroundStyle(latest.outcome == .failed ? .red : .secondary)
            } else { Text("暂无操作记录").font(.system(size: 12)).foregroundStyle(.secondary) }
            if store.hasUnsavedChanges {
                Label("本地草稿尚未保存", systemImage: "pencil").font(.system(size: 11)).foregroundStyle(.orange)
            }
            if store.externalConfigurationNotice != nil {
                Text("磁盘配置需核对；本地内容已保留。")
                    .font(.system(size: 12)).foregroundStyle(.orange)
                if store.initialConfigurationLoaded || !store.anyProcessRunning {
                    Button("载入磁盘版本") {
                        confirm("载入磁盘中最新的配置？这会丢弃当前工作空间尚未保存的本地修改，以磁盘版本替换界面内容。不会启动或重启服务。") {
                            store.reloadExternalConfiguration(discardLocalChanges: true)
                        }
                    }.font(.system(size: 12))
                }
            }
            if let notice = store.notice {
                DisclosureGroup("运行提示") {
                    Text(ActivityPolicy.noticeDetail(notice)).font(.system(size: 11))
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("清除提示") { store.notice = nil }.font(.system(size: 11))
                }
                .font(.system(size: 12))
            }
            if expanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(store.activities) { record in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.source.rawValue + " · " + record.outcome.rawValue)
                                    Text(record.time, style: .time)
                                    ForEach(Array(record.details.enumerated()), id: \.offset) { _, detail in Text(detail) }
                                }.font(.system(size: 11)).foregroundStyle(.secondary)
                            } label: { Text(record.summary).font(.system(size: 12)) }
                        }
                    }
                }.frame(height: CGFloat(min(200, max(64, store.activities.count * 46))))
                Text("本次会话 · 最近 80 项")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
