// Processes AirPods motion data for gesture detection.

import CoreMotion
import Combine

enum HeadGestureAction: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case click = "Click"
    case rightClick = "Right Click"

    var id: String { self.rawValue }
}

final class HeadphoneMotionManager: NSObject, ObservableObject {
    static let shared = HeadphoneMotionManager()

    private let motionManager = CMHeadphoneMotionManager()
    private let inputSynthesizer = InputSynthesizer()

    // Configuration with validation ranges
    private static let sensitivityRange: ClosedRange<Double> = 0.1...4.0
    private static let scrollThresholdRange: ClosedRange<Double> = 0.5 * .pi / 180.0...15.0 * .pi / 180.0
    private static let clickThresholdRange: ClosedRange<Double> = 10.0 * .pi / 180.0...30.0 * .pi / 180.0
    private static let smoothingRange: ClosedRange<Double> = 0.05...0.5

    // Configuration
    @Published var scrollSensitivity: Double = 1.0
    @Published var tiltLeftAction: HeadGestureAction = .click
    @Published var tiltRightAction: HeadGestureAction = .rightClick
    @Published var invertScroll: Bool = false
    @Published var scrollThreshold: Double = 3.0 * .pi / 180.0 // 3 degrees deadzone
    @Published var clickThreshold: Double = 15.0 * .pi / 180.0 // 15 degrees for click gesture
    @Published var smoothingAlpha: Double = 0.15

    // Look-away pause
    @Published var lookAwayPauseEnabled: Bool = true
    @Published var isLookingAway: Bool = false
    private let lookAwayThreshold: Double = 45.0 * .pi / 180.0 // 45 degrees

    // State
    @Published var isConnected: Bool = false
    @Published var isActive: Bool = false {
        didSet {
            // Prevent feedback loop - only save if value actually changed
            if isActive != oldValue {
                UserDefaults.standard.set(isActive, forKey: UserDefaultsKeys.headTrackingEnabled)
            }
        }
    }
    @Published var isReceivingData: Bool = false
    @Published var countdownValue: Int = 0  // 3, 2, 1, 0 (0 = no countdown)
    private var needsRecenter: Bool = false
    private var countdownTimer: Timer?
    private var canTriggerLeft: Bool = true
    private var canTriggerRight: Bool = true
    private var isRestoringState: Bool = false

    // For visualizer
    @Published var currentPitch: Double = 0.0
    @Published var currentYaw: Double = 0.0
    @Published var currentRoll: Double = 0.0

    private var referencePitch: Double = 0.0
    private var referenceYaw: Double = 0.0
    private var referenceRoll: Double = 0.0

    private var smoothedPitch: Double = 0.0
    private var smoothedYaw: Double = 0.0
    private var smoothedRoll: Double = 0.0

    // Event rate limiting
    private var lastScrollTime: Date = Date()
    private let scrollEventInterval: TimeInterval = 0.016 // ~60fps max

    // UI update throttling
    private var lastUIUpdateTime: Date = Date()
    private let uiUpdateInterval: TimeInterval = 0.033 // ~30fps for visualizer

    // Safety
    private var lastActionTime: Date = Date()
    private let sneezeGuardDuration: TimeInterval = 1.0

    private var cancellables = Set<AnyCancellable>()

    // Track if state should be restored on first activation
    private(set) var shouldRestoreActiveState: Bool = false
    
    override init() {
        super.init()
        motionManager.delegate = self
        loadSettings()
        setupPropertyObservers()
        checkInitialConnectionState()
    }

    /// Checks if AirPods are already connected at app launch
    /// Delegate callbacks only fire on state changes, not for already-connected devices
    private func checkInitialConnectionState() {
        guard motionManager.isDeviceMotionAvailable else {
            isConnected = false
            return
        }
        // Briefly start updates to detect if headphones are connected
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self = self else { return }
            if motion != nil {
                self.isConnected = true
            }
            // Stop immediately - we just needed to check connection
            if !self.isActive {
                self.motionManager.stopDeviceMotionUpdates()
            }
        }
        // Give it a moment, then stop if nothing received
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, !self.isActive else { return }
            self.motionManager.stopDeviceMotionUpdates()
        }
    }
    
    private func loadSettings() {
        let defaults = UserDefaults.standard

        // Load and validate settings with bounds checking
        let rawSensitivity = defaults.object(forKey: UserDefaultsKeys.scrollSensitivity) as? Double ?? 1.0
        scrollSensitivity = min(max(rawSensitivity, Self.sensitivityRange.lowerBound), Self.sensitivityRange.upperBound)

        let rawScrollThreshold = defaults.object(forKey: UserDefaultsKeys.scrollThreshold) as? Double ?? (3.0 * .pi / 180.0)
        scrollThreshold = min(max(rawScrollThreshold, Self.scrollThresholdRange.lowerBound), Self.scrollThresholdRange.upperBound)

        let rawClickThreshold = defaults.object(forKey: UserDefaultsKeys.clickThreshold) as? Double ?? (15.0 * .pi / 180.0)
        clickThreshold = min(max(rawClickThreshold, Self.clickThresholdRange.lowerBound), Self.clickThresholdRange.upperBound)

        let rawSmoothing = defaults.object(forKey: UserDefaultsKeys.smoothingAlpha) as? Double ?? 0.15
        smoothingAlpha = min(max(rawSmoothing, Self.smoothingRange.lowerBound), Self.smoothingRange.upperBound)

        invertScroll = defaults.bool(forKey: UserDefaultsKeys.invertScroll)

        // Look-away pause defaults to true if not set
        if defaults.object(forKey: UserDefaultsKeys.lookAwayPauseEnabled) != nil {
            lookAwayPauseEnabled = defaults.bool(forKey: UserDefaultsKeys.lookAwayPauseEnabled)
        }

        if let leftRaw = defaults.string(forKey: UserDefaultsKeys.tiltLeftAction),
           let left = HeadGestureAction(rawValue: leftRaw) {
            tiltLeftAction = left
        }
        if let rightRaw = defaults.string(forKey: UserDefaultsKeys.tiltRightAction),
           let right = HeadGestureAction(rawValue: rightRaw) {
            tiltRightAction = right
        }

        // Check if first launch
        if !defaults.bool(forKey: UserDefaultsKeys.hasLaunched) {
            defaults.set(true, forKey: UserDefaultsKeys.hasLaunched)
        }

        // Record if we should restore active state - let the app handle the actual restoration
        shouldRestoreActiveState = defaults.bool(forKey: UserDefaultsKeys.headTrackingEnabled)
    }
    
    private func setupPropertyObservers() {
        // Save settings when they change
        $scrollSensitivity
            .dropFirst() // Skip initial value
            .sink { UserDefaults.standard.set($0, forKey: UserDefaultsKeys.scrollSensitivity) }
            .store(in: &cancellables)

        $scrollThreshold
            .dropFirst()
            .sink { UserDefaults.standard.set($0, forKey: UserDefaultsKeys.scrollThreshold) }
            .store(in: &cancellables)

        $clickThreshold
            .dropFirst()
            .sink { UserDefaults.standard.set($0, forKey: UserDefaultsKeys.clickThreshold) }
            .store(in: &cancellables)

        $invertScroll
            .dropFirst()
            .sink { UserDefaults.standard.set($0, forKey: UserDefaultsKeys.invertScroll) }
            .store(in: &cancellables)

        $tiltLeftAction
            .dropFirst()
            .sink { UserDefaults.standard.set($0.rawValue, forKey: UserDefaultsKeys.tiltLeftAction) }
            .store(in: &cancellables)

        $tiltRightAction
            .dropFirst()
            .sink { UserDefaults.standard.set($0.rawValue, forKey: UserDefaultsKeys.tiltRightAction) }
            .store(in: &cancellables)

        $smoothingAlpha
            .dropFirst()
            .sink { UserDefaults.standard.set($0, forKey: UserDefaultsKeys.smoothingAlpha) }
            .store(in: &cancellables)

        $lookAwayPauseEnabled
            .dropFirst()
            .sink { UserDefaults.standard.set($0, forKey: UserDefaultsKeys.lookAwayPauseEnabled) }
            .store(in: &cancellables)

        // Note: isActive is saved in its didSet to avoid feedback loops
    }
    
    func startUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            return
        }

        // Reset visualizer immediately
        currentPitch = 0.0
        currentYaw = 0.0
        currentRoll = 0.0
        smoothedPitch = 0.0
        smoothedYaw = 0.0
        smoothedRoll = 0.0

        // Start countdown for centering
        startCenteringCountdown()

        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion, error == nil else { return }
            self.processMotion(motion)
        }
        isActive = true
    }

    private func startCenteringCountdown() {
        countdownTimer?.invalidate()
        countdownValue = 3

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            self.countdownValue -= 1

            if self.countdownValue <= 0 {
                timer.invalidate()
                self.countdownTimer = nil
                self.needsRecenter = true
            }
        }
    }
    
    func stopUpdates() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownValue = 0
        motionManager.stopDeviceMotionUpdates()
        isActive = false
        isReceivingData = false
    }
    
    func recenter(using motion: CMDeviceMotion? = nil) {
        guard let motion = motion ?? motionManager.deviceMotion else { return }
        referencePitch = motion.attitude.pitch
        referenceYaw = motion.attitude.yaw
        referenceRoll = motion.attitude.roll

        // Reset smoothed values to prevent sluggish response after recenter
        smoothedPitch = 0.0
        smoothedYaw = 0.0
        smoothedRoll = 0.0

        // Reset visualizer
        currentPitch = 0.0
        currentYaw = 0.0
        currentRoll = 0.0
    }
    
    /// Normalizes an angle difference to the range [-π, π] to handle wrap-around
    private func normalizeAngle(_ angle: Double) -> Double {
        var normalized = angle
        while normalized > .pi { normalized -= 2 * .pi }
        while normalized < -.pi { normalized += 2 * .pi }
        return normalized
    }

    /// Checks if user is looking away from screen and updates pause state
    private func checkLookAway() {
        guard lookAwayPauseEnabled else {
            if isLookingAway { isLookingAway = false }
            return
        }

        // Check if looking too far in any direction (using smoothed values in radians)
        let isAway = abs(smoothedPitch) > lookAwayThreshold ||
                     abs(smoothedYaw) > lookAwayThreshold

        if isAway != isLookingAway {
            isLookingAway = isAway
        }
    }

    private func processMotion(_ motion: CMDeviceMotion) {
        // Check for deferred recenter FIRST before any processing
        if needsRecenter {
            recenter(using: motion)
            needsRecenter = false
        }

        DispatchQueue.main.async {
            if !self.isReceivingData { self.isReceivingData = true }
        }

        // Sneeze Guard / Safety Check
        let userAcceleration = motion.userAcceleration
        let totalAcceleration = sqrt(pow(userAcceleration.x, 2) + pow(userAcceleration.y, 2) + pow(userAcceleration.z, 2))

        if totalAcceleration > 2.0 { // Threshold for sudden movement
            lastActionTime = Date() // Reset timer to block input
            return
        }

        if Date().timeIntervalSince(lastActionTime) < sneezeGuardDuration {
            return
        }

        // 1. Calibration & Smoothing with angle normalization to handle wrap-around
        let currentPitch = normalizeAngle(motion.attitude.pitch - referencePitch)
        let currentYaw = normalizeAngle(motion.attitude.yaw - referenceYaw)
        let currentRoll = normalizeAngle(motion.attitude.roll - referenceRoll)
        
        // Exponential Moving Average
        smoothedPitch = (currentPitch * smoothingAlpha) + (smoothedPitch * (1.0 - smoothingAlpha))
        smoothedYaw = (currentYaw * smoothingAlpha) + (smoothedYaw * (1.0 - smoothingAlpha))
        smoothedRoll = (currentRoll * smoothingAlpha) + (smoothedRoll * (1.0 - smoothingAlpha))
        
        // Update published values for visualizer (throttled to reduce CPU)
        let now = Date()
        if now.timeIntervalSince(lastUIUpdateTime) >= uiUpdateInterval {
            self.currentPitch = smoothedPitch * 180.0 / .pi // Convert to degrees
            self.currentYaw = smoothedYaw * 180.0 / .pi
            self.currentRoll = smoothedRoll * 180.0 / .pi
            lastUIUpdateTime = now
        }

        // Check look-away pause
        checkLookAway()
        if isLookingAway {
            return // Skip gesture detection when looking away
        }

        // 2. Gesture Detection

        // Check if enough time has passed since last scroll event (rate limiting)
        let timeSinceLastScroll = Date().timeIntervalSince(lastScrollTime)
        let canSendScrollEvent = timeSinceLastScroll >= scrollEventInterval

        // Calculate scroll speeds for both axes independently
        var scrollDeltaY: Int32 = 0
        var scrollDeltaX: Int32 = 0

        // Vertical Scroll (Pitch)
        if abs(smoothedPitch) > scrollThreshold {
            let rawSpeed = (abs(smoothedPitch) - scrollThreshold) * 10 * scrollSensitivity
            var direction: Int32 = smoothedPitch > 0 ? 1 : -1
            if invertScroll { direction *= -1 }
            scrollDeltaY = direction * Int32(rawSpeed)
        }

        // Horizontal Scroll (Yaw) - Looking left/right
        if abs(smoothedYaw) > scrollThreshold {
            let rawSpeed = (abs(smoothedYaw) - scrollThreshold) * 10 * scrollSensitivity
            var direction: Int32 = smoothedYaw > 0 ? -1 : 1
            if invertScroll { direction *= -1 }
            scrollDeltaX = direction * Int32(rawSpeed)
        }

        // Send combined scroll event if any scrolling detected
        if canSendScrollEvent && (scrollDeltaY != 0 || scrollDeltaX != 0) {
            inputSynthesizer.scroll(deltaY: scrollDeltaY, deltaX: scrollDeltaX)
            lastScrollTime = Date()
        }
        
        // Tilt Gestures (Roll) - Tilting ear to shoulder
        // Roll > 0 is usually Tilt Right
        // Roll < 0 is usually Tilt Left
        
        // Tilt Right
        if tiltRightAction != .none {
            if smoothedRoll > clickThreshold {
                if canTriggerRight {
                    perform(action: tiltRightAction)
                    canTriggerRight = false
                }
            } else if smoothedRoll < (clickThreshold * 0.5) {
                canTriggerRight = true
            }
        }

        // Tilt Left
        if tiltLeftAction != .none {
            if smoothedRoll < -clickThreshold {
                if canTriggerLeft {
                    perform(action: tiltLeftAction)
                    canTriggerLeft = false
                }
            } else if smoothedRoll > -(clickThreshold * 0.5) {
                canTriggerLeft = true
            }
        }
    }
    
    private func perform(action: HeadGestureAction) {
        switch action {
        case .click:
            inputSynthesizer.leftClick()
        case .rightClick:
            inputSynthesizer.rightClick()
        case .none:
            break
        }
    }
}

extension HeadphoneMotionManager: CMHeadphoneMotionManagerDelegate {
    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.needsRecenter = true
        }
    }
    
    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}
