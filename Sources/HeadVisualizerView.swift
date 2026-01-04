// Head position visualizer.

import SwiftUI

struct HeadVisualizerView: View {
    @ObservedObject var motionManager: HeadphoneMotionManager

    var body: some View {
        VStack(spacing: 16) {
            // Face visualization with gesture pickers on sides
            HStack(spacing: 12) {
                // Left tilt action picker
                VStack(spacing: 4) {
                    Text("Tilt Left")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Picker("", selection: $motionManager.tiltLeftAction) {
                        ForEach(HeadGestureAction.allCases) { action in
                            Text(action.rawValue).tag(action)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 140, height: 140)

                    // Center crosshair (neutral position indicator)
                    Group {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 1, height: 20)
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 20, height: 1)
                    }

                    // The face - moves with pitch/yaw, rotates with roll
                    FaceView(
                        faceColor: faceColor,
                        eyeOffsetX: isTracking ? eyeOffsetX : 0,
                        eyeOffsetY: isTracking ? eyeOffsetY : 0,
                        distanceFromCenter: isTracking ? distanceFromCenter : 0,
                        eyesClosed: !isTracking,
                        leftEyeWink: isTracking && leftEyeWinking,
                        rightEyeWink: isTracking && rightEyeWinking,
                        featureOffsetX: isTracking ? CGFloat(-clampedYaw) * 0.15 : 0,
                        featureOffsetY: isTracking ? CGFloat(-clampedPitch) * 0.15 : 0
                    )
                        .rotationEffect(.degrees(isTracking ? motionManager.currentRoll : 0))
                        .offset(
                            x: isTracking ? CGFloat(-clampedYaw) * 1.5 : 0,
                            y: isTracking ? CGFloat(-clampedPitch) * 1.5 : 0
                        )
                        .animation(.linear(duration: 0.05), value: motionManager.currentPitch)
                        .animation(.linear(duration: 0.05), value: motionManager.currentYaw)
                        .animation(.linear(duration: 0.05), value: motionManager.currentRoll)
                }
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Right tilt action picker
                VStack(spacing: 4) {
                    Text("Tilt Right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Picker("", selection: $motionManager.tiltRightAction) {
                        ForEach(HeadGestureAction.allCases) { action in
                            Text(action.rawValue).tag(action)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
            }

            // Numeric values
            HStack(spacing: 20) {
                AngleLabel(label: "Pitch", value: motionManager.currentPitch)
                AngleLabel(label: "Yaw", value: motionManager.currentYaw)
                AngleLabel(label: "Roll", value: motionManager.currentRoll)
            }
            .font(.caption.monospacedDigit())

            // Status and Recenter
            HStack(spacing: 12) {
                if !motionManager.isConnected {
                    Text("AirPods not connected")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if !motionManager.isActive {
                    Text("Tracking paused")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if motionManager.isLookingAway {
                    Text("Looking away")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if motionManager.isReceivingData {
                    Text("Tracking active")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text("Waiting for motion...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Recenter") {
                    motionManager.recenter()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!motionManager.isActive || !motionManager.isReceivingData)
            }
        }
        .padding()
    }

    private var faceColor: Color {
        if !motionManager.isConnected || !motionManager.isActive {
            return .gray
        } else if motionManager.isLookingAway {
            return .orange
        } else if motionManager.isReceivingData {
            return .green
        } else {
            return .orange
        }
    }

    // Eye pupils shift based on yaw (looking left/right)
    private var eyeOffsetX: CGFloat {
        CGFloat(min(max(-motionManager.currentYaw, -20), 20)) * 0.4
    }

    // Eye pupils shift based on pitch (looking up/down)
    private var eyeOffsetY: CGFloat {
        CGFloat(min(max(-motionManager.currentPitch, -20), 20)) * 0.3
    }

    // Distance from center (0 to 1) for mouth expression
    private var distanceFromCenter: CGFloat {
        let pitchNorm = abs(motionManager.currentPitch) / 40.0
        let yawNorm = abs(motionManager.currentYaw) / 40.0
        return min(sqrt(pitchNorm * pitchNorm + yawNorm * yawNorm), 1.0)
    }

    // Whether we're actively tracking
    private var isTracking: Bool {
        motionManager.isConnected && motionManager.isActive && motionManager.isReceivingData
    }

    private var clampedPitch: Double {
        min(max(motionManager.currentPitch, -40), 40)
    }

    private var clampedYaw: Double {
        min(max(motionManager.currentYaw, -40), 40)
    }

    // Wink when tilt exceeds click threshold
    private var leftEyeWinking: Bool {
        let thresholdDegrees = motionManager.clickThreshold * 180.0 / .pi
        return motionManager.currentRoll < -thresholdDegrees
    }

    private var rightEyeWinking: Bool {
        let thresholdDegrees = motionManager.clickThreshold * 180.0 / .pi
        return motionManager.currentRoll > thresholdDegrees
    }
}

struct FaceView: View {
    let faceColor: Color
    let eyeOffsetX: CGFloat
    let eyeOffsetY: CGFloat
    let distanceFromCenter: CGFloat  // 0 = center, 1 = far away
    let eyesClosed: Bool
    let leftEyeWink: Bool
    let rightEyeWink: Bool
    let featureOffsetX: CGFloat  // Move features on face when looking sideways
    let featureOffsetY: CGFloat  // Move features on face when looking up/down

    // Skin colors
    private let skinDark = Color(red: 1.0, green: 0.4, blue: 0.4)       // #F66
    private let skinMedium = Color(red: 1.0, green: 0.533, blue: 0.533) // #F88
    private let skinLight = Color(red: 1.0, green: 0.667, blue: 0.667)  // #FAA
    private let eyeWhite = Color.white
    private let irisColor = Color(red: 0.4, green: 0.6, blue: 0.8)
    private let pupilColor = Color(red: 0.2, green: 0.12, blue: 0.08)

    var body: some View {
        ZStack {
            // Left ear
            Ellipse()
                .fill(skinDark)
                .frame(width: 12, height: 20)
                .offset(x: -32, y: -5)

            // Right ear
            Ellipse()
                .fill(skinDark)
                .frame(width: 12, height: 20)
                .offset(x: 32, y: -5)

            // Head
            PearHead()
                .fill(skinLight)
                .frame(width: 60, height: 70)

            // Left eye
            Group {
                if eyesClosed || leftEyeWink {
                    ClosedEyeShape()
                        .stroke(skinDark, lineWidth: 2)
                        .frame(width: 16, height: 6)
                } else {
                    ZStack {
                        Ellipse()
                            .fill(eyeWhite)
                            .frame(width: 18, height: 14)
                        Circle()
                            .fill(irisColor)
                            .frame(width: 10, height: 10)
                            .offset(x: eyeOffsetX, y: eyeOffsetY)
                        Circle()
                            .fill(pupilColor)
                            .frame(width: 5, height: 5)
                            .offset(x: eyeOffsetX, y: eyeOffsetY)
                    }
                }
            }
            .offset(x: -12 + featureOffsetX, y: -10 + featureOffsetY)

            // Right eye
            Group {
                if eyesClosed || rightEyeWink {
                    ClosedEyeShape()
                        .stroke(skinDark, lineWidth: 2)
                        .frame(width: 16, height: 6)
                } else {
                    ZStack {
                        Ellipse()
                            .fill(eyeWhite)
                            .frame(width: 18, height: 14)
                        Circle()
                            .fill(irisColor)
                            .frame(width: 10, height: 10)
                            .offset(x: eyeOffsetX, y: eyeOffsetY)
                        Circle()
                            .fill(pupilColor)
                            .frame(width: 5, height: 5)
                            .offset(x: eyeOffsetX, y: eyeOffsetY)
                    }
                }
            }
            .offset(x: 12 + featureOffsetX, y: -10 + featureOffsetY)

            // Mouth
            Ellipse()
                .fill(skinDark)
                .frame(
                    width: 12 + distanceFromCenter * 12,
                    height: 2 + distanceFromCenter * 18
                )
                .offset(x: featureOffsetX, y: 18 + featureOffsetY)
        }
    }
}

struct PearHead: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addCurve(
            to: CGPoint(x: w, y: h * 0.45),
            control1: CGPoint(x: w * 0.75, y: 0),
            control2: CGPoint(x: w * 0.9, y: h * 0.2)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h),
            control1: CGPoint(x: w * 1.05, y: h * 0.7),
            control2: CGPoint(x: w * 0.75, y: h)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: h * 0.45),
            control1: CGPoint(x: w * 0.25, y: h),
            control2: CGPoint(x: w * -0.05, y: h * 0.7)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: 0),
            control1: CGPoint(x: w * 0.1, y: h * 0.2),
            control2: CGPoint(x: w * 0.25, y: 0)
        )

        return path
    }
}

struct ClosedEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.height)
        )
        return path
    }
}

struct AngleLabel: View {
    let label: String
    let value: Double

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .foregroundColor(.secondary)
            Text(String(format: "%+.1f", value))
                .foregroundColor(.primary)
        }
    }
}
