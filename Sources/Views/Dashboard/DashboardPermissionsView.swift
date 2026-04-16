import AVFoundation
import AppKit
import ApplicationServices
import SwiftUI

internal struct DashboardPermissionsView: View {
    @State private var microphoneStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(
        for: .audio)
    @State private var isAccessibilityTrusted: Bool = AXIsProcessTrusted()
    @State private var isInputMonitoringGranted = InputMonitoringPermissionManager().checkPermission()
    @AppStorage(AppDefaults.Keys.enableSmartPaste) private var enableSmartPaste = true
    @AppStorage(AppDefaults.Keys.pressAndHoldEnabled) private var pressAndHoldEnabled = true
    @AppStorage(AppDefaults.Keys.pressAndHoldKeyIdentifier) private var pressAndHoldKeyIdentifier =
        PressAndHoldConfiguration
        .defaults.key.rawValue
    @AppStorage(AppDefaults.Keys.pressAndHoldFnReadiness) private var pressAndHoldFnReadinessRaw =
        FnGlobeHotkeyReadiness
        .requiresAcknowledgement.rawValue
    @AppStorage(AppDefaults.Keys.pressAndHoldFnFailureMessage) private var pressAndHoldFnFailureMessage = ""

    private let inputMonitoringPermissionManager = InputMonitoringPermissionManager()

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    permissionLabel(
                        isGranted: microphoneStatus == .authorized,
                        grantedText: "Granted",
                        requiredText: microphoneStatus == .denied ? "Denied" : "Required"
                    )
                }

                HStack(spacing: 10) {
                    Button("Request Access") {
                        requestMicrophonePermission()
                    }
                    .disabled(microphoneStatus == .authorized)

                    Button("Open Settings") {
                        openSystemSettings(path: "Privacy_Microphone")
                    }
                }
            } header: {
                Text("Microphone")
            } footer: {
                Text(
                    "Microphone access is the only permission required to start dictating. Accessibility and Input Monitoring are optional for Smart Paste and background hotkeys."
                )
            }

            if needsAccessibility {
                Section {
                    LabeledContent("Status") {
                        permissionLabel(
                            isGranted: isAccessibilityTrusted,
                            grantedText: "Granted",
                            requiredText: "Required"
                        )
                    }

                    HStack(spacing: 10) {
                        Button("Open Settings") {
                            openSystemSettings(path: "Privacy_Accessibility")
                        }

                        Button("Refresh") {
                            refreshStatuses()
                        }
                    }
                } header: {
                    Text("Accessibility")
                } footer: {
                    Text(accessibilityFooterText)
                }
            }

            if needsInputMonitoring {
                Section {
                    LabeledContent("Status") {
                        permissionLabel(
                            isGranted: isInputMonitoringGranted,
                            grantedText: "Granted",
                            requiredText: "Required"
                        )
                    }

                    if let inputMonitoringStatusMessage {
                        Text(inputMonitoringStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Button("Request Access") {
                            refreshFnGlobePermission(requestAccess: true)
                        }

                        Button("Open Settings") {
                            inputMonitoringPermissionManager.openSystemSettings()
                        }

                        Button("Refresh") {
                            refreshFnGlobePermission()
                        }
                    }
                } header: {
                    Text("Input Monitoring")
                } footer: {
                    Text(
                        "Required for standalone Fn / Globe capture. VoiceFlow keeps Fn selected even if setup fails, so use Refresh after changing permissions or keyboard settings. If the status still does not update after granting access, quit and reopen VoiceFlow."
                    )
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshStatuses)
        .onChange(of: enableSmartPaste) { _, _ in
            refreshStatuses()
        }
        .onChange(of: pressAndHoldEnabled) { _, _ in
            refreshStatuses()
        }
        .onChange(of: pressAndHoldKeyIdentifier) { _, _ in
            refreshStatuses()
        }
    }

    private var currentPressAndHoldConfiguration: PressAndHoldConfiguration {
        PressAndHoldSettings.configuration()
    }

    private var selectedPressAndHoldKey: PressAndHoldKey {
        currentPressAndHoldConfiguration.key
    }

    private var needsAccessibility: Bool {
        enableSmartPaste || currentPressAndHoldConfiguration.requiresAccessibilityPermission
    }

    private var needsInputMonitoring: Bool {
        currentPressAndHoldConfiguration.isFnGlobeEnabled
    }

    private var fnGlobeReadiness: FnGlobeHotkeyReadiness {
        FnGlobeHotkeyReadiness(rawValue: pressAndHoldFnReadinessRaw) ?? .requiresAcknowledgement
    }

    private var inputMonitoringStatusMessage: String? {
        if !pressAndHoldFnFailureMessage.isEmpty {
            return pressAndHoldFnFailureMessage
        }

        if fnGlobeReadiness == .awaitingVerification {
            return
                "Hold Fn / Globe until VoiceFlow starts recording. If macOS opens Emoji & Symbols or Dictation, set Keyboard > Press Globe key to Do Nothing and refresh this page."
        }

        return nil
    }

    private var accessibilityFooterText: String {
        if pressAndHoldEnabled && selectedPressAndHoldKey != .globe && enableSmartPaste {
            return "Required for Press & Hold key detection and Smart Paste."
        }

        if pressAndHoldEnabled && selectedPressAndHoldKey != .globe {
            return "Required for Command, Option, or Control press-and-hold detection."
        }

        return "Optional. Required only for Smart Paste to type into other apps."
    }

    private func permissionLabel(isGranted: Bool, grantedText: String, requiredText: String) -> some View {
        Label(
            isGranted ? grantedText : requiredText,
            systemImage: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .foregroundStyle(isGranted ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
    }

    private func refreshStatuses() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        isAccessibilityTrusted = AXIsProcessTrusted()
        isInputMonitoringGranted = inputMonitoringPermissionManager.checkPermission()
    }

    private func refreshFnGlobePermission(requestAccess: Bool = false) {
        if requestAccess {
            _ = inputMonitoringPermissionManager.requestPermission()
        }

        refreshStatuses()
        NotificationCenter.default.post(name: .pressAndHoldSettingsChanged, object: nil)
    }

    private func requestMicrophonePermission() {
        guard !AppEnvironment.isRunningTests else { return }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                microphoneStatus = granted ? .authorized : .denied
            }
        }
    }

    private func openSystemSettings(path: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(path)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    DashboardPermissionsView()
        .frame(width: 900, height: 700)
}
