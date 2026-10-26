import SwiftUI
import AppKit

/// One continuous canvas shared by titlebar, navigation and content. No forced appearance.
enum HarborPalette {
    static let selection = Color(red: 0.06, green: 0.30, blue: 0.72)
    static let canvas = NSColor(name: "HarborCanvas") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.085, green: 0.115, blue: 0.17, alpha: 1)
            : NSColor(srgbRed: 0.935, green: 0.96, blue: 0.995, alpha: 1)
    }
}

struct HarborCanvas: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Color(nsColor: HarborPalette.canvas)
            .overlay {
                if contrast != .increased {
                    LinearGradient(colors: [.clear, Color.blue.opacity(scheme == .dark ? 0.045 : 0.035)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .allowsHitTesting(false)
    }
}

/// Style only the host window; no service, permission or system-appearance changes.
struct HarborWindowChrome: NSViewRepresentable {
    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = HarborPalette.canvas
            window.toolbar?.showsBaselineSeparator = false
        }
    }
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ nsView: ChromeView, context: Context) {
        nsView.window?.titlebarAppearsTransparent = true
        nsView.window?.titleVisibility = .hidden
        nsView.window?.backgroundColor = HarborPalette.canvas
        nsView.window?.toolbar?.showsBaselineSeparator = false
    }
}

/// Pearl-glass surfaces: blue-tinted depth without repeated dark outlined boxes.
private struct HarborSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(scheme == .dark ? Color.white.opacity(0.065) : Color.white.opacity(0.82))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(LinearGradient(colors: [Color.blue.opacity(hovered ? 0.07 : 0.025), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .allowsHitTesting(false)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(contrast == .increased ? Color.primary : Color.white.opacity(scheme == .dark ? 0.11 : 0.92), lineWidth: contrast == .increased ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.blue.opacity(scheme == .dark ? 0.025 : (hovered ? 0.10 : 0.045)), radius: hovered ? 18 : 10, y: hovered ? 6 : 3)
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
