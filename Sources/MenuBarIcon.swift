// Dynamic menu bar icon showing head position.

import SwiftUI
import AppKit

struct MenuBarIconView: View {
    let pitch: Double  // -1 to 1 (normalized)
    let yaw: Double    // -1 to 1 (normalized)
    let roll: Double   // degrees
    let isActive: Bool
    let isConnected: Bool

    private let size: CGFloat = 18
    private let maxOffset: CGFloat = 7
    private let dotSize: CGFloat = 5
    private let lineLength: CGFloat = 7

    // Opacity based on state - macOS will handle the actual color via template
    private var lineOpacity: Double {
        if !isConnected { return 0.3 }
        else if isActive { return 0.5 }
        else { return 0.4 }
    }

    private var dotOpacity: Double {
        if !isConnected { return 0.4 }
        else if isActive { return 1.0 }
        else { return 0.6 }
    }

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            // Apply roll rotation
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: .degrees(isActive ? roll : 0))
            context.translateBy(x: -center.x, y: -center.y)

            // Draw crosshair lines (black - template will be tinted by macOS)
            let lineStyle = StrokeStyle(lineWidth: 1, lineCap: .round)

            // Vertical line
            var vLine = Path()
            vLine.move(to: CGPoint(x: center.x, y: center.y - lineLength))
            vLine.addLine(to: CGPoint(x: center.x, y: center.y + lineLength))
            context.stroke(vLine, with: .color(.black.opacity(lineOpacity)), style: lineStyle)

            // Horizontal line
            var hLine = Path()
            hLine.move(to: CGPoint(x: center.x - lineLength, y: center.y))
            hLine.addLine(to: CGPoint(x: center.x + lineLength, y: center.y))
            context.stroke(hLine, with: .color(.black.opacity(lineOpacity)), style: lineStyle)

            // Calculate dot position (flipped to match head movement direction)
            let dotX = center.x + (isActive ? CGFloat(-yaw) * maxOffset : 0)
            let dotY = center.y + (isActive ? CGFloat(-pitch) * maxOffset : 0)

            // Draw dot
            let dotRect = CGRect(
                x: dotX - dotSize / 2,
                y: dotY - dotSize / 2,
                width: dotSize,
                height: dotSize
            )
            context.fill(Circle().path(in: dotRect), with: .color(.black.opacity(dotOpacity)))
        }
        .frame(width: size, height: size)
    }
}

@MainActor
final class MenuBarIconRenderer: ObservableObject {
    static let shared = MenuBarIconRenderer()

    @Published var currentImage: NSImage

    private var lastUpdateTime: Date = .distantPast
    private let updateInterval: TimeInterval = 0.1  // 10fps

    init() {
        currentImage = Self.renderIcon(pitch: 0, yaw: 0, roll: 0, isActive: false, isConnected: false)
    }

    func update(pitch: Double, yaw: Double, roll: Double, isActive: Bool, isConnected: Bool) {
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= updateInterval else { return }
        lastUpdateTime = now

        // Normalize values to -1...1 range (±15 degrees = full movement)
        let normalizedPitch = max(-1, min(1, pitch / 15.0))
        let normalizedYaw = max(-1, min(1, yaw / 15.0))

        currentImage = Self.renderIcon(
            pitch: normalizedPitch,
            yaw: normalizedYaw,
            roll: roll,
            isActive: isActive,
            isConnected: isConnected
        )
    }

    private static func renderIcon(pitch: Double, yaw: Double, roll: Double, isActive: Bool, isConnected: Bool) -> NSImage {
        let view = MenuBarIconView(
            pitch: pitch,
            yaw: yaw,
            roll: roll,
            isActive: isActive,
            isConnected: isConnected
        )

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0  // Retina

        if let cgImage = renderer.cgImage {
            let image = NSImage(cgImage: cgImage, size: NSSize(width: 18, height: 18))
            image.isTemplate = true  // Let macOS handle light/dark appearance
            return image
        }

        // Fallback
        let fallback = NSImage(systemSymbolName: "headphones", accessibilityDescription: "AirNod")!
        fallback.isTemplate = true
        return fallback
    }
}
