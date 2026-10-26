import SwiftUI

/// Native semantic colors and restrained depth, not the reference app's brand.
/// Hover changes light/shadow, not card position, so surrounding content stays still.
private struct HarborSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(LinearGradient(colors: [Color.accentColor.opacity(hovered ? 0.07 : 0.025), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .allowsHitTesting(false)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(contrast == .increased ? Color.primary : Color(nsColor: .separatorColor).opacity(hovered ? 0.9 : 0.5), lineWidth: contrast == .increased ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(hovered ? 0.08 : 0.025), radius: hovered ? 14 : 5, y: hovered ? 5 : 2)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovered)
    }
}

extension View {
    func harborSurface() -> some View { modifier(HarborSurface()) }
}

/// A small tactile response for the single primary action, never an ambient loop.
struct HarborPrimaryButtonStyle: ButtonStyle {
    var focused = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isEnabled ? Color.accentColor : Color(nsColor: .quaternaryLabelColor))
                    .overlay {
                        if isEnabled && contrast != .increased {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(colors: [.white.opacity(configuration.isPressed ? 0.02 : 0.18), .clear], startPoint: .top, endPoint: .bottom))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder((focused || isFocused) ? Color.accentColor : .clear, lineWidth: 2)
                    .padding(-3)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.accentColor.opacity(isEnabled && !configuration.isPressed ? 0.18 : 0), radius: 5, y: 2)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.97)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// Command feedback reflects the existing pending state, never a cosmetic timer.
struct RuntimeActionLabel: View {
    let title: String
    let busy: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 6) {
            if busy {
                if reduceMotion {
                    Image(systemName: "hourglass").accessibilityHidden(true)
                } else {
                    ProgressView().controlSize(.mini).accessibilityHidden(true)
                }
            }
            Text(title).fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(busy ? "等待网关确认" : "")
    }
}
