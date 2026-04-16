import AppKit
import ApplicationServices
import Foundation
import os.log

internal enum FnGlobeHotkeyReadiness: String {
    case requiresAcknowledgement
    case requiresInputMonitoring
    case awaitingVerification
    case ready
    case unavailable

    var title: String {
        switch self {
        case .requiresAcknowledgement:
            return "Fn / Globe setup required"
        case .requiresInputMonitoring:
            return "Grant Input Monitoring"
        case .awaitingVerification:
            return "Verify Fn / Globe capture"
        case .ready:
            return "Fn / Globe ready"
        case .unavailable:
            return "Fn / Globe unavailable"
        }
    }

    var defaultMessage: String {
        switch self {
        case .requiresAcknowledgement:
            return "Enable Fn / Globe mode first so VoiceFlow can guide you through setup."
        case .requiresInputMonitoring:
            return
                "Grant Input Monitoring, then set Keyboard > Press Globe key to Do Nothing if macOS keeps taking over the key. If VoiceFlow still cannot see Fn after granting access, quit and reopen the app."
        case .awaitingVerification:
            return
                "Hold Fn / Globe until VoiceFlow starts recording. If nothing happens, refresh after adjusting Keyboard settings."
        case .ready:
            return
                "VoiceFlow has seen Fn / Globe successfully. You can keep using it as your microphone trigger."
        case .unavailable:
            return
                "VoiceFlow could not keep the Fn / Globe listener running. Refresh the setup after checking permissions and keyboard settings."
        }
    }

    var statusSymbolName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .unavailable:
            return "xmark.octagon.fill"
        default:
            return "exclamationmark.triangle.fill"
        }
    }
}

private enum FnGlobeHotkeyCopy {
    static let acknowledgementSetupMessage = "Enable Fn / Globe mode to finish setup."
    static let inputMonitoringSetupMessage =
        "Grant Input Monitoring, then set Keyboard > Press Globe key to Do Nothing. If VoiceFlow still cannot capture Fn after granting access, quit and reopen the app."
    static let verificationSetupMessage =
        "Hold Fn / Globe to verify capture. If macOS opens Emoji & Symbols or Dictation, set Keyboard > Press Globe key to Do Nothing and try again. If nothing changes after granting Input Monitoring, quit and reopen VoiceFlow."
    static let recoveredTapMessage =
        "Fn / Globe capture recovered after a system interruption. Try the key again if the last press was missed."
    static let startupUnavailableMessage = "VoiceFlow could not start Fn / Globe capture on this Mac."
    static let tapDisabledMessage =
        "Fn / Globe capture stopped responding. Reopen settings and refresh permissions."
}

internal enum FnGlobeHotkeyPreferenceStore {
    static func warningAcknowledged(using defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: AppDefaults.Keys.pressAndHoldFnWarningAcknowledged)
    }

    static func setWarningAcknowledged(_ acknowledged: Bool, using defaults: UserDefaults = .standard) {
        defaults.set(acknowledged, forKey: AppDefaults.Keys.pressAndHoldFnWarningAcknowledged)

        if !acknowledged {
            setReadiness(
                .requiresAcknowledgement,
                message: FnGlobeHotkeyCopy.acknowledgementSetupMessage,
                using: defaults
            )
        }

        defaults.synchronize()
    }

    static func readiness(using defaults: UserDefaults = .standard) -> FnGlobeHotkeyReadiness {
        let rawValue =
            defaults.string(forKey: AppDefaults.Keys.pressAndHoldFnReadiness)
            ?? FnGlobeHotkeyReadiness.requiresAcknowledgement.rawValue
        return FnGlobeHotkeyReadiness(rawValue: rawValue) ?? .requiresAcknowledgement
    }

    static func failureMessage(using defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: AppDefaults.Keys.pressAndHoldFnFailureMessage) ?? ""
    }

    static func setReadiness(
        _ readiness: FnGlobeHotkeyReadiness,
        message: String? = nil,
        using defaults: UserDefaults = .standard
    ) {
        defaults.set(readiness.rawValue, forKey: AppDefaults.Keys.pressAndHoldFnReadiness)
        defaults.set(message ?? "", forKey: AppDefaults.Keys.pressAndHoldFnFailureMessage)
        defaults.synchronize()
    }

    static func syncForConfiguration(
        _ configuration: PressAndHoldConfiguration,
        inputMonitoringGranted: Bool,
        using defaults: UserDefaults = .standard
    ) {
        guard configuration.isFnGlobeEnabled else { return }

        guard warningAcknowledged(using: defaults) else {
            setReadiness(
                .requiresAcknowledgement,
                message: FnGlobeHotkeyCopy.acknowledgementSetupMessage,
                using: defaults
            )
            return
        }

        guard inputMonitoringGranted else {
            setReadiness(
                .requiresInputMonitoring,
                message: FnGlobeHotkeyCopy.inputMonitoringSetupMessage,
                using: defaults
            )
            return
        }

        if readiness(using: defaults) != .ready {
            setReadiness(
                .awaitingVerification,
                message: FnGlobeHotkeyCopy.verificationSetupMessage,
                using: defaults
            )
        }
    }

    static func message(for readiness: FnGlobeHotkeyReadiness, failureMessage: String = "") -> String {
        if !failureMessage.isEmpty {
            return failureMessage
        }

        return readiness.defaultMessage
    }
}

internal final class InputMonitoringPermissionManager {
    private let preflight: () -> Bool
    private let requestAccess: () -> Bool
    private let eventTapProbe: () -> Bool

    init(
        preflight: @escaping () -> Bool = { CGPreflightListenEventAccess() },
        requestAccess: @escaping () -> Bool = {
            if AppEnvironment.isRunningTests {
                return false
            }
            return CGRequestListenEventAccess()
        },
        eventTapProbe: @escaping () -> Bool = InputMonitoringPermissionManager.defaultEventTapProbe
    ) {
        self.preflight = preflight
        self.requestAccess = requestAccess
        self.eventTapProbe = eventTapProbe
    }

    func checkPermission() -> Bool {
        preflight() || eventTapProbe()
    }

    @discardableResult
    func requestPermission() -> Bool {
        requestAccess()
    }

    func openSystemSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"),
            NSWorkspace.shared.open(url)
        {
            return
        }

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func defaultEventTapProbe() -> Bool {
        guard !AppEnvironment.isRunningTests else { return false }

        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, _, event, _ in
            Unmanaged.passUnretained(event)
        }

        guard
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: callback,
                userInfo: nil
            )
        else {
            return false
        }

        CFMachPortInvalidate(tap)
        return true
    }
}

internal final class FnGlobeMonitor {
    internal enum SemanticEvent {
        case functionKeyChanged(isPressed: Bool)
        case otherKeyPressed
        case tapDisabled
    }

    typealias ReadinessHandler = (FnGlobeHotkeyReadiness, String) -> Void

    private let keyDownHandler: () -> Void
    private let keyUpHandler: (() -> Void)?
    private let readinessHandler: ReadinessHandler
    private let inputMonitoringPermissionManager: InputMonitoringPermissionManager
    private let holdDelay: TimeInterval

    private static let eventMask =
        CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        | CGEventMask(1 << CGEventType.keyDown.rawValue)
        | CGEventMask(1 << CGEventType.tapDisabledByTimeout.rawValue)
        | CGEventMask(1 << CGEventType.tapDisabledByUserInput.rawValue)

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pendingActivationWorkItem: DispatchWorkItem?
    private var isFunctionKeyDown = false
    private var isCaptureActive = false
    private var isFunctionKeyPartOfCombination = false
    private var hasVerifiedCapture = false

    init(
        keyDownHandler: @escaping () -> Void,
        keyUpHandler: (() -> Void)? = nil,
        readinessHandler: @escaping ReadinessHandler,
        inputMonitoringPermissionManager: InputMonitoringPermissionManager =
            InputMonitoringPermissionManager(),
        holdDelay: TimeInterval = 0.12
    ) {
        self.keyDownHandler = keyDownHandler
        self.keyUpHandler = keyUpHandler
        self.readinessHandler = readinessHandler
        self.inputMonitoringPermissionManager = inputMonitoringPermissionManager
        self.holdDelay = holdDelay
    }

    @discardableResult
    func start() -> Bool {
        stop()

        guard inputMonitoringPermissionManager.checkPermission() else {
            readinessHandler(
                .requiresInputMonitoring,
                FnGlobeHotkeyCopy.inputMonitoringSetupMessage
            )
            return false
        }

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard
            let eventTap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: Self.eventMask,
                callback: Self.eventTapCallback,
                userInfo: userInfo
            )
        else {
            readinessHandler(
                .unavailable,
                FnGlobeHotkeyCopy.startupUnavailableMessage
            )
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)

        if !hasVerifiedCapture {
            readinessHandler(
                .awaitingVerification,
                FnGlobeHotkeyCopy.verificationSetupMessage
            )
        }

        return true
    }

    func stop() {
        resetPendingState()
        endCaptureIfNeeded()
        removeEventTap()
    }

    deinit {
        stop()
    }

    func processSemanticEvent(_ event: SemanticEvent) {
        switch event {
        case .functionKeyChanged(let isPressed):
            if isPressed {
                guard !isFunctionKeyDown else { return }
                isFunctionKeyDown = true
                isFunctionKeyPartOfCombination = false
                scheduleActivation()
            } else {
                guard isFunctionKeyDown || isCaptureActive else { return }
                resetPendingState()
                endCaptureIfNeeded()
            }

        case .otherKeyPressed:
            guard isFunctionKeyDown, !isCaptureActive else { return }
            isFunctionKeyPartOfCombination = true
            cancelPendingActivation()

        case .tapDisabled:
            resetPendingState()
            endCaptureIfNeeded()

            readinessHandler(
                .unavailable,
                FnGlobeHotkeyCopy.tapDisabledMessage
            )
        }
    }

    func activateFnIfEligible() {
        guard isFunctionKeyDown, !isFunctionKeyPartOfCombination, !isCaptureActive else { return }
        isCaptureActive = true

        if !hasVerifiedCapture {
            hasVerifiedCapture = true
            readinessHandler(.ready, "Fn / Globe is ready.")
        }

        notifyKeyDown()
    }

    func handleFlagsChanged(keyCode: Int64, flags: CGEventFlags) {
        let isFunctionEvent =
            keyCode == Int64(PressAndHoldKey.globe.keyCode)
            || flags.contains(.maskSecondaryFn)

        if isFunctionEvent {
            let isPressed = flags.contains(.maskSecondaryFn)
            processSemanticEvent(.functionKeyChanged(isPressed: isPressed))

            if isPressed, hasAdditionalModifierFlags(flags) {
                processSemanticEvent(.otherKeyPressed)
            }
            return
        }

        if isFunctionKeyDown, hasAdditionalModifierFlags(flags) {
            processSemanticEvent(.otherKeyPressed)
        }
    }

    private func scheduleActivation() {
        cancelPendingActivation()

        let workItem = DispatchWorkItem { [weak self] in
            self?.activateFnIfEligible()
        }

        pendingActivationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay, execute: workItem)
    }

    private func cancelPendingActivation() {
        pendingActivationWorkItem?.cancel()
        pendingActivationWorkItem = nil
    }

    private func resetPendingState() {
        cancelPendingActivation()
        isFunctionKeyDown = false
        isFunctionKeyPartOfCombination = false
    }

    private func endCaptureIfNeeded() {
        guard isCaptureActive else { return }

        isCaptureActive = false

        guard let keyUpHandler else { return }
        Task { @MainActor in
            keyUpHandler()
        }
    }

    private func notifyKeyDown() {
        Task { @MainActor [keyDownHandler] in
            keyDownHandler()
        }
    }

    private func removeEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            handleTapDisabled()

        case .flagsChanged:
            handleFlagsChanged(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                flags: event.flags
            )

        case .keyDown:
            handleKeyDown(keyCode: event.getIntegerValueField(.keyboardEventKeycode))

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func hasAdditionalModifierFlags(_ flags: CGEventFlags) -> Bool {
        let combinationMask: CGEventFlags = [
            .maskShift,
            .maskControl,
            .maskAlternate,
            .maskCommand,
            .maskAlphaShift,
        ]

        return !flags.intersection(combinationMask).isEmpty
    }

    func handleKeyDown(keyCode: Int64) {
        guard isFunctionKeyDown else { return }

        if keyCode == Int64(PressAndHoldKey.globe.keyCode) {
            return
        }

        processSemanticEvent(.otherKeyPressed)
    }

    private func handleTapDisabled() {
        resetPendingState()
        endCaptureIfNeeded()

        guard let eventTap else {
            readinessHandler(
                .unavailable,
                FnGlobeHotkeyCopy.tapDisabledMessage
            )
            return
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)

        readinessHandler(
            hasVerifiedCapture ? .ready : .awaitingVerification,
            hasVerifiedCapture
                ? FnGlobeHotkeyCopy.recoveredTapMessage : FnGlobeHotkeyCopy.verificationSetupMessage
        )
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<FnGlobeMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        return monitor.handleEvent(type: type, event: event)
    }
}
