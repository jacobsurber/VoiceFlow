import AVFoundation
import AppKit
import Observation

internal enum PermissionState {
    case unknown
    case notRequested
    case requesting
    case granted
    case denied
    case restricted

    var needsRequest: Bool {
        switch self {
        case .unknown, .notRequested:
            return true
        default:
            return false
        }
    }

    var canRetry: Bool {
        switch self {
        case .denied:
            return true
        default:
            return false
        }
    }
}

@MainActor
@Observable
internal class PermissionManager {
    var microphonePermissionState: PermissionState = .unknown
    var accessibilityPermissionState: PermissionState = .unknown
    var showEducationalModal = false
    var showRecoveryModal = false
    private let isTestEnvironment: Bool
    private let accessibilityManager = AccessibilityPermissionManager()

    private var needsAccessibility: Bool {
        let enableSmartPaste = UserDefaults.standard.bool(forKey: AppDefaults.Keys.enableSmartPaste)
        let pressAndHoldEnabled = PressAndHoldSettings.configuration().enabled
        return enableSmartPaste || pressAndHoldEnabled
    }

    var allPermissionsGranted: Bool {
        if needsAccessibility {
            return microphonePermissionState == .granted && accessibilityPermissionState == .granted
        } else {
            return microphonePermissionState == .granted
        }
    }

    init() {
        // Detect if running in tests
        isTestEnvironment = NSClassFromString("XCTestCase") != nil
    }

    func checkPermissionState() {
        checkMicrophonePermission()

        // Check Accessibility if SmartPaste or Press & Hold is enabled
        if needsAccessibility {
            checkAccessibilityPermission()
        } else {
            // Reset accessibility state if not needed
            accessibilityPermissionState = .granted
        }
    }

    private func checkMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            self.microphonePermissionState = .granted
        case .denied:
            self.microphonePermissionState = .denied
        case .restricted:
            self.microphonePermissionState = .restricted
        case .notDetermined:
            self.microphonePermissionState = .notRequested
        @unknown default:
            self.microphonePermissionState = .unknown
        }
    }

    private func checkAccessibilityPermission() {
        // Use dedicated AccessibilityPermissionManager for consistent checking
        let trusted = accessibilityManager.checkPermission()

        self.accessibilityPermissionState = trusted ? .granted : .notRequested
    }

    func requestPermissionWithEducation() {
        let needsMicrophone = microphonePermissionState.needsRequest
        let needsAccessibilityNow = needsAccessibility && accessibilityPermissionState.needsRequest

        let canRetryMicrophone = microphonePermissionState.canRetry
        let canRetryAccessibilityNow = needsAccessibility && accessibilityPermissionState.canRetry

        if needsMicrophone || needsAccessibilityNow {
            showEducationalModal = true
        } else if canRetryMicrophone || canRetryAccessibilityNow {
            showRecoveryModal = true
        }
    }

    func proceedWithPermissionRequest() {
        if isTestEnvironment {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                self.microphonePermissionState = .denied
                if needsAccessibility {
                    self.accessibilityPermissionState = .denied
                }
                self.showRecoveryModal = true
            }
        } else {
            requestMicrophonePermission()

            if needsAccessibility {
                requestAccessibilityPermission()
            }
        }
    }

    private func requestMicrophonePermission() {
        if microphonePermissionState.needsRequest {
            microphonePermissionState = .requesting
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor [weak self] in
                    self?.microphonePermissionState = granted ? .granted : .denied
                    self?.checkIfAllPermissionsHandled()
                }
            }
        }
    }

    private func requestAccessibilityPermission() {
        if accessibilityPermissionState.needsRequest {
            accessibilityPermissionState = .requesting

            // Use dedicated AccessibilityPermissionManager for proper explanation and handling
            accessibilityManager.requestPermissionWithExplanation { [weak self] granted in
                Task { @MainActor [weak self] in
                    self?.accessibilityPermissionState = granted ? .granted : .denied
                    self?.checkIfAllPermissionsHandled()
                }
            }
        }
    }

    private func checkIfAllPermissionsHandled() {
        let hasFailures = microphonePermissionState == .denied || accessibilityPermissionState == .denied
        if hasFailures && !showRecoveryModal {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self.showRecoveryModal = true
            }
        }
    }

    func openSystemSettings() {
        // Skip actual system settings in test environment
        if isTestEnvironment {
            return
        }

        // Open the main Privacy & Security preferences
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
