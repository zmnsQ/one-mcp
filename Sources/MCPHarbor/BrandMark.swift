import SwiftUI
import AppKit

/// Original One MCP identity: three channels resolve into one outlet.
/// Kept vector-based so the sidebar stays crisp at every display scale.
struct BrandMark: View {
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width, geometry.size.height) / 256
            ZStack {
                RoundedRectangle(cornerRadius: 54 * scale)
                    .fill(Color(red: 20 / 255, green: 35 / 255, blue: 48 / 255))
                    .padding(12 * scale)
                Canvas { context, _ in
                    context.scaleBy(x: scale, y: scale)
                    for (index, path) in Self.paths.enumerated() {
                        context.stroke(path, with: .color(index == 2 ? Color(red: 244 / 255, green: 250 / 255, blue: 250 / 255) : Color(red: 101 / 255, green: 217 / 255, blue: 202 / 255)), style: StrokeStyle(lineWidth: 17, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    static var paths: [Path] {
        var top = Path()
        top.move(to: CGPoint(x: 66, y: 72)); top.addLine(to: CGPoint(x: 112, y: 72))
        top.addCurve(to: CGPoint(x: 174, y: 128), control1: CGPoint(x: 148, y: 72), control2: CGPoint(x: 140, y: 128))
        top.addLine(to: CGPoint(x: 202, y: 128))
        var bottom = Path()
        bottom.move(to: CGPoint(x: 66, y: 184)); bottom.addLine(to: CGPoint(x: 112, y: 184))
        bottom.addCurve(to: CGPoint(x: 174, y: 128), control1: CGPoint(x: 148, y: 184), control2: CGPoint(x: 140, y: 128))
        var center = Path()
        center.move(to: CGPoint(x: 66, y: 128)); center.addLine(to: CGPoint(x: 202, y: 128))
        return [top, bottom, center]
    }

    /// Template monochrome mark: the menu bar supplies light/dark coloring.
    static var menuBarImage: NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.translateBy(x: -3, y: -4)
            context.scaleBy(x: 0.105, y: 0.105)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(17); context.setLineCap(.round); context.setLineJoin(.round)
            for path in paths { context.addPath(path.cgPath); context.strokePath() }
            return true
        }
        image.isTemplate = true
        return image
    }
}
