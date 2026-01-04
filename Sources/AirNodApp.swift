// Menu bar app entry point.

import SwiftUI

@main
struct AirNodApp: App {
    @ObservedObject private var motionManager = HeadphoneMotionManager.shared
    @ObservedObject private var permissionsManager = PermissionsManager.shared
    private static let sharedAudioLooper = AudioLooper()

    @Environment(\.openWindow) var openWindow

    init() {
        // Restore state on app launch if it was previously active
        if HeadphoneMotionManager.shared.shouldRestoreActiveState {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                HeadphoneMotionManager.shared.startUpdates()
                Self.sharedAudioLooper.start()
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("AirNod", systemImage: "headphones") {
            Button("Recenter") {
                motionManager.recenter()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])

            Divider()

            Toggle("Enable Head Tracking", isOn: Binding(
                get: { motionManager.isActive },
                set: { newValue in
                    if newValue {
                        motionManager.startUpdates()
                        Self.sharedAudioLooper.start()
                    } else {
                        motionManager.stopUpdates()
                        Self.sharedAudioLooper.stop()
                    }
                }
            ))
            .keyboardShortcut("a", modifiers: [.command, .option])

            Divider()

            // Dynamic status display
            if !motionManager.isConnected {
                Label("AirPods Not Connected", systemImage: "airpodspro")
                    .foregroundColor(.secondary)
            } else if !motionManager.isActive {
                Label("Head Tracking Paused", systemImage: "pause.circle")
            } else if !motionManager.isReceivingData {
                Label("Waiting for Motion...", systemImage: "hourglass")
            } else if motionManager.isLookingAway {
                Label("Looking Away (Paused)", systemImage: "eye.slash")
                    .foregroundColor(.secondary)
            } else {
                Label("Tracking Active", systemImage: "checkmark.circle.fill")
            }

            if !permissionsManager.isAccessibilityTrusted {
                Label("Accessibility Required", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
            }

            Divider()

            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            PreferencesView()
        }
    }

    private var menuBarIconName: String {
        if !permissionsManager.isAccessibilityTrusted {
            return "sensor.trianglebadge.exclamationmark"
        } else if !motionManager.isConnected {
            return "sensor"
        } else if motionManager.isActive {
            return "sensor.fill"
        } else {
            return "sensor"
        }
    }
}
