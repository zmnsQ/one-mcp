import SwiftUI

/// Only the header is a button. Expanded controls remain siblings, never nested
/// inside a button or a parent tap gesture that could steal their clicks.
struct FullRowDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureHeader(isExpanded: Binding(get: { configuration.isExpanded }, set: { configuration.isExpanded = $0 })) {
                configuration.label
            }
            if configuration.isExpanded {
                configuration.content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DisclosureHeader<Label: View>: View {
    @Binding var isExpanded: Bool
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder let label: Label

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { isExpanded.toggle() }
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
                    .accessibilityHidden(true)
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .background(isFocused ? Color.accentColor.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .accessibilityValue(isExpanded ? "已展开" : "已收起")
        .accessibilityHint("按空格键展开或收起，也可使用左右方向键")
        .onKeyPress(.rightArrow) { isExpanded = true; return .handled }
        .onKeyPress(.leftArrow) { isExpanded = false; return .handled }
    }
}

/// A shared surface keeps settings visually grouped without changing their data
/// or actions. Dynamic system colors adapt to light, dark and increased contrast.
struct SettingsSurface<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .harborSurface()
    }
}

struct SettingsSectionLabel: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
