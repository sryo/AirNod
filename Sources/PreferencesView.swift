// Settings window with General, Permissions, and About tabs.

import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(0)
            
            PermissionsSettingsView()
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
                .tag(1)
            
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(2)
        }
        .frame(width: 450, height: 500)
        .padding()
        .onAppear {
            // Show permissions tab if any permission is missing OR first launch
            let permissionsManager = PermissionsManager.shared
            let isFirstLaunch = !UserDefaults.standard.bool(forKey: UserDefaultsKeys.hasLaunched)
            
            if isFirstLaunch || !permissionsManager.isAccessibilityTrusted {
                selectedTab = 1 // Permissions tab
            }
        }
    }
}

struct GeneralSettingsView: View {
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var showResetConfirmation = false
    @ObservedObject private var motionManager = HeadphoneMotionManager.shared

    var body: some View {
        Form {
            // Startup Section
            Section {
                LabeledContent("Start AirNod at Login") {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { newValue in
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }
                .accessibilityLabel("Start AirNod at Login")
                .accessibilityHint("When enabled, AirNod will start automatically when you log in")
            } header: {
                Text("Startup")
            }

            // Head Position Visualizer
            Section {
                HeadVisualizerView(motionManager: motionManager)
                    .frame(maxWidth: .infinity)
            } header: {
                Text("Head Position")
            }

            // Sensitivity Section
            Section {
                // Tilt Threshold (for clicks)
                LabeledContent("Tilt") {
                    HStack(spacing: 4) {
                        Text("Easy")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: Binding(
                            get: { motionManager.clickThreshold * 180.0 / .pi },
                            set: { motionManager.clickThreshold = $0 * .pi / 180.0 }
                        ), in: 5.0...45.0, step: 1.0)
                        Text("Hard")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Scroll Threshold
                LabeledContent("Scroll") {
                    HStack(spacing: 4) {
                        Text("Small")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: Binding(
                            get: { motionManager.scrollThreshold * 180.0 / .pi },
                            set: { motionManager.scrollThreshold = $0 * .pi / 180.0 }
                        ), in: 0.5...5.0, step: 0.25)
                        Text("Large")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Scroll Speed
                LabeledContent("Speed") {
                    HStack(spacing: 4) {
                        Text("Slow")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $motionManager.scrollSensitivity, in: 0.1...3.0, step: 0.1)
                        Text("Fast")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Toggles
                Toggle("Invert Scroll Direction", isOn: $motionManager.invertScroll)
                Toggle("Pause when looking away", isOn: $motionManager.lookAwayPauseEnabled)
            } header: {
                Text("Sensitivity")
            }

            // Reset Section
            Section {
                Button("Reset All Settings to Defaults") {
                    showResetConfirmation = true
                }
                .foregroundColor(.red)
            }
        }
        .formStyle(.grouped)
        .alert("Reset Settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetToDefaults()
            }
        } message: {
            Text("This will reset all gesture and scrolling settings to their default values.")
        }
    }

    private func resetToDefaults() {
        motionManager.scrollSensitivity = 1.0
        motionManager.scrollThreshold = 1.0 * .pi / 180.0
        motionManager.clickThreshold = 15.0 * .pi / 180.0
        motionManager.tiltLeftAction = .click
        motionManager.tiltRightAction = .rightClick
        motionManager.invertScroll = false
        motionManager.smoothingAlpha = 0.15
        motionManager.lookAwayPauseEnabled = true
    }
}


struct PermissionsSettingsView: View {
    @ObservedObject private var permissionsManager = PermissionsManager.shared
    @ObservedObject private var motionManager = HeadphoneMotionManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("AirNod requires the following permissions:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            // Accessibility Permission
            PermissionRow(
                icon: "hand.tap",
                title: "Accessibility",
                description: "Required to control your mouse and keyboard",
                isGranted: permissionsManager.isAccessibilityTrusted,
                action: {
                    permissionsManager.checkAndRequestAccessibility()
                },
                openSettingsAction: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )

            Divider()

            // AirPods Connection
            PermissionRow(
                icon: "airpodspro",
                title: "AirPods Connection",
                description: "Connect supported AirPods for head tracking",
                isGranted: motionManager.isConnected,
                action: nil,
                openSettingsAction: {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )

            if !motionManager.isConnected {
                Text("Connect AirPods Pro, AirPods (3rd generation), AirPods Max, or Beats Fit Pro to enable motion tracking.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding()
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: (() -> Void)?
    let openSettingsAction: (() -> Void)?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                    
                    Spacer()
                    
                    Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(isGranted ? .green : .orange)
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !isGranted {
                    HStack {
                        if let action = action {
                            Button("Grant Permission") {
                                action()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        
                        if let openSettingsAction = openSettingsAction {
                            Button("Open Settings") {
                                openSettingsAction()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "sensor.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text("AirNod")
                .font(.title)
                .bold()
            
            Text("Version 1.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Control your Mac with head gestures.")
                .font(.body)
            
            Text("© 2025 sryo")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 10)
        }
        .padding()
    }
}
