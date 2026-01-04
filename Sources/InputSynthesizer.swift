// Generates mouse clicks and scroll events.

import CoreGraphics
import ApplicationServices

final class InputSynthesizer {

    /// Checks if accessibility permission is granted before attempting input synthesis
    private var canSynthesizeInput: Bool {
        AXIsProcessTrusted()
    }

    func scroll(deltaY: Int32, deltaX: Int32 = 0) {
        guard canSynthesizeInput else { return }

        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        guard let event = CGEvent(
            scrollWheelEvent2Source: source,
            units: .line,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: -deltaX,
            wheel3: 0
        ) else { return }

        event.post(tap: .cgSessionEventTap)
    }

    func leftClick() {
        guard canSynthesizeInput else { return }
        performClick(downType: .leftMouseDown, upType: .leftMouseUp, button: .left)
    }

    func rightClick() {
        guard canSynthesizeInput else { return }
        performClick(downType: .rightMouseDown, upType: .rightMouseUp, button: .right)
    }

    private func performClick(downType: CGEventType, upType: CGEventType, button: CGMouseButton) {
        guard let currentPos = CGEvent(source: nil)?.location else { return }

        guard let mouseDown = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: currentPos, mouseButton: button),
              let mouseUp = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: currentPos, mouseButton: button) else { return }

        mouseDown.post(tap: .cgSessionEventTap)
        mouseUp.post(tap: .cgSessionEventTap)
    }
}
