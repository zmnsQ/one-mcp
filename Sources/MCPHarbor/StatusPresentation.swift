import SwiftUI
import AppKit

extension MenuBarStatus {
    var color: Color { Color(nsColor: indicatorColor) }
    private var indicatorColor: NSColor {
        switch tone {
        case .positive: return .systemGreen
        case .warning: return .systemOrange
        case .negative: return .systemRed
        case .neutral: return .secondaryLabelColor
        }
    }
    /// Native NSMenu can discard SwiftUI foreground styles. Render actual colored pixels,
    /// not a template symbol, while keeping a distinct symbol and a text status.
    @MainActor var menuImage: NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            self.indicatorColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            let mark: String
            switch self {
            case .running, .ready: mark = "✓"
            case .failed: mark = "!"
            case .starting, .checking, .stopping: mark = "…"
            case .stopped: mark = "−"
            case .unknown: mark = "?"
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 11), .foregroundColor: NSColor.white]
            let text = NSAttributedString(string: mark, attributes: attributes)
            let size = text.size()
            text.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = title
        return image
    }
}

struct StatusBadge: View {
    let status: MenuBarStatus
    var body: some View {
        Label(status.title, systemImage: status.symbol)
            .font(.caption.weight(.semibold)).foregroundStyle(status.color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(status.color.opacity(0.10), in: Capsule())
    }
}

/// Confirmation reflects runtime behavior, not a possibly stale configuration snapshot.
enum ServiceStopImpact {
    static func message(name: String) -> String {
        "停止“\(name)”？依赖此服务的隧道及旧版 Cloudflare 入口会先停止，使用这些入口的客户端将断开。其他独立隧道与 MCP 进程继续运行；运行中的绑定以网关实际状态为准。"
    }
}
