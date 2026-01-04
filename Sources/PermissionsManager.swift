// Checks accessibility permission.

import ApplicationServices
import AppKit

final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published var isAccessibilityTrusted: Bool = false
    private var timer: Timer?

    init() {
        checkStatus()
        startPolling()
    }

    deinit {
        timer?.invalidate()
    }

    func checkStatus() {
        isAccessibilityTrusted = AXIsProcessTrusted()
    }

    func checkAndRequestAccessibility() {
        if !AXIsProcessTrusted() {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options)
        }
    }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }
}
