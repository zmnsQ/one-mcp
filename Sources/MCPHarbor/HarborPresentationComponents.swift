import SwiftUI

/// Shared graphical heading for native sheets; callers own dismissal and actions.
struct HarborSheetHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    var tint: Color = .accentColor
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol).font(.system(size: 25, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 60, height: 60)
                .background(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 19))
                .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(tint.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine)
    }
}

struct HarborNotice: View {
    let title: String
    let detail: String
    let symbol: String
    var tint: Color = .accentColor
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint).frame(width: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(14).background(tint.opacity(0.065), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Native sheet confirmation; explicit cancel/continue, no automatic execution or timer.
struct HarborConfirmationSheet: View {
    let message: String
    let onCancel: () -> Void
    let onContinue: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HarborSheetHeader(title: "确认这次操作", subtitle: "核对影响范围后，再决定是否继续。", symbol: "hand.raised.fill", tint: .orange)
                .padding(24).background(.thinMaterial)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HarborNotice(title: "操作影响", detail: message, symbol: "exclamationmark.shield", tint: .orange)
                    Label("取消不会执行任何操作", systemImage: "arrow.uturn.backward")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.frame(maxHeight: 300)
            Divider()
            HStack {
                Button("取消", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("确认并继续", action: onContinue).buttonStyle(.borderedProminent).tint(.orange)
            }.padding(20).background(.bar)
        }.frame(width: 560).fixedSize(horizontal: false, vertical: true)
    }
}

struct HarborNavigationRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var focused: Bool
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 18, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 36, height: 36)
                    .background(selected ? Color.accentColor.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                    .offset(x: selected && !reduceMotion ? 2 : 0)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: selected ? .semibold : .medium))
                    if selected { Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if selected { Capsule().fill(Color.accentColor).frame(width: 3, height: 22) }
            }.foregroundStyle(.primary)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 15).fill(selected ? Color(nsColor: .controlBackgroundColor) : Color.primary.opacity(hovered ? 0.035 : 0))
                }
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(focused ? Color.accentColor : (selected && contrast == .increased ? Color.primary : Color.clear), lineWidth: 2))
                .shadow(color: .black.opacity(selected ? 0.06 : 0), radius: 8, y: 3)
                .contentShape(RoundedRectangle(cornerRadius: 15))
        }.buttonStyle(.plain).focused($focused)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.20), value: selected)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
            .accessibilityLabel(title).accessibilityValue(selected ? "已选中" : "")
            .accessibilityHint(subtitle)
    }
}
