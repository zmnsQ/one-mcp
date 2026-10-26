#if DEBUG
import SwiftUI

/// Interactive native harness. All sample states are explicitly demonstration data.
/// System accessibility settings remain read-only and are never changed here.
struct HarborDesignPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var expanded = false
    @State private var demonstrationRunning = false
    @State private var sampleCount = 2
    @FocusState private var focusedAction: Action?
    private enum Action: Hashable { case toggle, add }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("交互预览 · 仅演示数据").font(.title2.bold())
                Text("点击、悬停和按压下面的真实组件检查动效，不会启动服务、连接设备或保存配置。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("聚焦演示主按钮") { focusedAction = .toggle }
                    Spacer()
                    Text(focusedAction == .toggle ? "焦点：演示状态按钮" : (focusedAction == .add ? "焦点：增加指标按钮" : "焦点：其他位置"))
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("preview-focus-status")
                }
                Text("减少动态效果：\(reduceMotion ? "开" : "关") · 对比度：\(contrast == .increased ? "增强" : "标准")（只读系统值）")
                    .font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("微信消息与个人知识库", systemImage: "shippingbox.fill").font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                        StatusBadge(status: demonstrationRunning ? .running : .stopped)
                        Text("手动演示状态切换，不是运行结果").font(.caption).foregroundStyle(.secondary)
                        Button {
                            demonstrationRunning.toggle()
                        } label: { Text(demonstrationRunning ? "演示停止状态" : "演示运行状态") }
                        .buttonStyle(HarborPrimaryButtonStyle(focused: focusedAction == .toggle))
                        .focusable(true, interactions: .activate)
                        .focused($focusedAction, equals: .toggle)
                        .accessibilityIdentifier("preview-state-button")
                    }.harborSurface()
                    VStack(alignment: .leading, spacing: 16) {
                        Label("指标变化与等待反馈", systemImage: "chart.bar.fill").font(.headline)
                        Text("\(sampleCount)").font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: sampleCount)
                        HStack {
                            Button("增加演示指标") { sampleCount += 1 }
                                .focusable(true, interactions: .activate)
                                .focused($focusedAction, equals: .add)
                            Spacer()
                            Button {} label: { RuntimeActionLabel(title: "处理中", busy: true) }
                                .buttonStyle(HarborPrimaryButtonStyle()).disabled(true)
                        }
                    }.harborSurface()
                }
                SettingsSurface {
                    DisclosureGroup(isExpanded: $expanded) {
                        Text("展开只改变显示，不自动连接或修改授权。观察箭头旋转、内容展开与收起。")
                            .font(.callout).foregroundStyle(.secondary)
                    } label: {
                        SettingsSectionLabel(title: "进阶设置", subtitle: "整行点击展开 · 次要信息按需出现", symbol: "slider.horizontal.3")
                    }
                }
            }.padding(24)
        }
        .frame(minWidth: 360, idealWidth: 760, minHeight: 480, idealHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .disclosureGroupStyle(FullRowDisclosureStyle())
    }
}

struct HarborDesignSystemPreviews: PreviewProvider {
    static var previews: some View {
        Group {
            HarborDesignPreview().preferredColorScheme(.light).previewDisplayName("浅色 · 可交互与缩放")
            HarborDesignPreview().preferredColorScheme(.dark).previewDisplayName("深色 · 可交互与缩放")
        }
    }
}
#endif
