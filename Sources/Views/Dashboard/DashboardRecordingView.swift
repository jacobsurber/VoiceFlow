import AVFoundation
import AppKit
import SwiftUI

internal struct DashboardRecordingView: View {
    @AppStorage("selectedMicrophone") private var selectedMicrophone = ""
    @AppStorage(AppDefaults.Keys.pressAndHoldEnabled) private var pressAndHoldEnabled =
        PressAndHoldConfiguration.defaults
        .enabled
    @AppStorage(AppDefaults.Keys.pressAndHoldKeyIdentifier) private var pressAndHoldKeyIdentifier =
        PressAndHoldConfiguration
        .defaults.key.rawValue
    @AppStorage(AppDefaults.Keys.pressAndHoldMode) private var pressAndHoldModeRaw = PressAndHoldConfiguration
        .defaults.mode
        .rawValue
    @AppStorage(AppDefaults.Keys.pressAndHoldFnWarningAcknowledged) private
        var pressAndHoldFnWarningAcknowledged = false
    @AppStorage(AppDefaults.Keys.pressAndHoldFnReadiness) private var pressAndHoldFnReadinessRaw =
        FnGlobeHotkeyReadiness
        .requiresAcknowledgement.rawValue
    @AppStorage(AppDefaults.Keys.pressAndHoldFnFailureMessage) private var pressAndHoldFnFailureMessage = ""

    @State private var availableMicrophones: [AVCaptureDevice] = []
    @State private var previousPressAndHoldKeyIdentifier = PressAndHoldConfiguration.defaults.key.rawValue
    @State private var showFnWarningConfirmation = false

    private let inputMonitoringPermissionManager = InputMonitoringPermissionManager()

    var body: some View {
        Form {
            Section {
                if availableMicrophones.isEmpty {
                    Text("No microphones detected. Plug in a microphone or check system permissions.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Input Device", selection: $selectedMicrophone) {
                        Text("System Default").tag("")
                        ForEach(availableMicrophones, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(device.uniqueID)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Microphone")
            }

            Section {
                Toggle(isOn: $pressAndHoldEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Press & Hold")
                        Text("Hold a modifier key to control recording.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: pressAndHoldEnabled) { _, _ in
                    publishPressAndHoldConfiguration()
                }

                if pressAndHoldEnabled {
                    Picker("Behavior", selection: $pressAndHoldModeRaw) {
                        ForEach(PressAndHoldMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: pressAndHoldModeRaw) { _, _ in
                        publishPressAndHoldConfiguration()
                    }

                    Picker("Key", selection: $pressAndHoldKeyIdentifier) {
                        ForEach(PressAndHoldKey.allCases, id: \.rawValue) { key in
                            Text(key.displayName).tag(key.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: pressAndHoldKeyIdentifier) { oldValue, newValue in
                        handlePressAndHoldKeyChange(from: oldValue, to: newValue)
                    }

                    if isFnGlobeSelected {
                        fnGlobeSetupSection
                    }
                }
            } header: {
                Text("Press & Hold")
            } footer: {
                Text(
                    "Hotkeys are optional. The floating dock can start dictation with microphone access only. Command, Option, and Control require Accessibility permission to work in other apps. Fn / Globe uses Input Monitoring, may require Keyboard > Press Globe key to Do Nothing, and may need a Whisp restart after permission changes."
                )
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadMicrophones()
            syncPressAndHoldConfiguration()
        }
        .alert("Enable Fn / Globe Mode?", isPresented: $showFnWarningConfirmation) {
            Button("Cancel", role: .cancel) {
                pressAndHoldKeyIdentifier = previousPressAndHoldKeyIdentifier
            }

            Button("Enable Fn / Globe") {
                FnGlobeHotkeyPreferenceStore.setWarningAcknowledged(true)
                _ = inputMonitoringPermissionManager.requestPermission()
                previousPressAndHoldKeyIdentifier = PressAndHoldKey.globe.rawValue
                publishPressAndHoldConfiguration()
            }
        } message: {
            Text(
                "Whisp can use standalone Fn / Globe, but this mode needs explicit setup. Grant Input Monitoring, then set Keyboard > Press Globe key to Do Nothing if macOS keeps opening Emoji & Symbols or Dictation instead of starting Whisp. If macOS still blocks Fn after you grant access, quit and reopen Whisp before refreshing status."
            )
        }
    }

    @ViewBuilder
    private var fnGlobeSetupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(fnGlobeStatusTitle, systemImage: fnGlobeStatusIcon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(fnGlobeStatusColor)

            Text(fnGlobeStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if fnGlobeReadiness == .requiresAcknowledgement {
                    Button("Enable Fn / Globe Mode") {
                        showFnWarningConfirmation = true
                    }
                }

                if fnGlobeReadiness == .requiresInputMonitoring {
                    Button("Request Access") {
                        _ = inputMonitoringPermissionManager.requestPermission()
                        refreshFnGlobeSetup()
                    }
                }

                if showsFnGlobeSettingsActions {
                    Button("Open Settings") {
                        inputMonitoringPermissionManager.openSystemSettings()
                    }

                    Button("Refresh Status") {
                        refreshFnGlobeSetup()
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var selectedPressAndHoldKey: PressAndHoldKey {
        PressAndHoldKey(rawValue: pressAndHoldKeyIdentifier) ?? PressAndHoldConfiguration.defaults.key
    }

    private var selectedPressAndHoldMode: PressAndHoldMode {
        PressAndHoldMode(rawValue: pressAndHoldModeRaw) ?? PressAndHoldConfiguration.defaults.mode
    }

    private var currentPressAndHoldConfiguration: PressAndHoldConfiguration {
        PressAndHoldConfiguration(
            enabled: pressAndHoldEnabled,
            key: selectedPressAndHoldKey,
            mode: selectedPressAndHoldMode
        )
    }

    private var isFnGlobeSelected: Bool {
        currentPressAndHoldConfiguration.isFnGlobeEnabled
    }

    private var fnGlobeReadiness: FnGlobeHotkeyReadiness {
        FnGlobeHotkeyReadiness(rawValue: pressAndHoldFnReadinessRaw) ?? .requiresAcknowledgement
    }

    private var fnGlobeStatusTitle: String {
        fnGlobeReadiness.title
    }

    private var fnGlobeStatusIcon: String {
        fnGlobeReadiness.statusSymbolName
    }

    private var fnGlobeStatusColor: Color {
        switch fnGlobeReadiness {
        case .ready:
            return Color(nsColor: .systemGreen)
        case .unavailable:
            return Color(nsColor: .systemRed)
        default:
            return Color(nsColor: .systemOrange)
        }
    }

    private var fnGlobeStatusMessage: String {
        FnGlobeHotkeyPreferenceStore.message(
            for: fnGlobeReadiness,
            failureMessage: pressAndHoldFnFailureMessage
        )
    }

    private var showsFnGlobeSettingsActions: Bool {
        switch fnGlobeReadiness {
        case .requiresInputMonitoring, .awaitingVerification, .unavailable:
            return true
        default:
            return false
        }
    }

    private func loadMicrophones() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        availableMicrophones = discoverySession.devices
    }

    private func publishPressAndHoldConfiguration() {
        let configuration = currentPressAndHoldConfiguration

        PressAndHoldSettings.update(configuration)
        refreshFnGlobeSetup(for: configuration, notify: false)
        syncPressAndHoldConfiguration(configuration)
    }

    private func handlePressAndHoldKeyChange(from oldValue: String, to newValue: String) {
        if newValue == PressAndHoldKey.globe.rawValue && !pressAndHoldFnWarningAcknowledged {
            previousPressAndHoldKeyIdentifier = oldValue
            showFnWarningConfirmation = true
            return
        }

        previousPressAndHoldKeyIdentifier = newValue
        publishPressAndHoldConfiguration()
    }

    private func refreshFnGlobeSetup(
        for configuration: PressAndHoldConfiguration? = nil,
        notify: Bool = true
    ) {
        let configuration = configuration ?? currentPressAndHoldConfiguration

        guard configuration.isFnGlobeEnabled else { return }

        FnGlobeHotkeyPreferenceStore.syncForConfiguration(
            configuration,
            inputMonitoringGranted: inputMonitoringPermissionManager.checkPermission()
        )

        if notify {
            NotificationCenter.default.post(name: .pressAndHoldSettingsChanged, object: configuration)
        }
    }

    private func syncPressAndHoldConfiguration() {
        syncPressAndHoldConfiguration(PressAndHoldSettings.configuration())
    }

    private func syncPressAndHoldConfiguration(_ configuration: PressAndHoldConfiguration) {

        if pressAndHoldEnabled != configuration.enabled {
            pressAndHoldEnabled = configuration.enabled
        }

        if pressAndHoldKeyIdentifier != configuration.key.rawValue {
            pressAndHoldKeyIdentifier = configuration.key.rawValue
        }

        previousPressAndHoldKeyIdentifier = configuration.key.rawValue

        if pressAndHoldModeRaw != configuration.mode.rawValue {
            pressAndHoldModeRaw = configuration.mode.rawValue
        }
    }

}

#Preview {
    DashboardRecordingView()
        .frame(width: 900, height: 700)
}
