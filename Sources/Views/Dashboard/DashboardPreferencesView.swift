import ServiceManagement
import SwiftUI
import os.log

internal struct DashboardPreferencesView: View {
    @AppStorage(AppDefaults.Keys.startAtLogin) private var startAtLogin = true
    @AppStorage(AppDefaults.Keys.floatingMicrophoneDockEnabled) private var floatingMicrophoneDockEnabled =
        true
    @AppStorage("autoBoostMicrophoneVolume") private var autoBoostMicrophoneVolume = false
    @AppStorage(AppDefaults.Keys.enableSmartPaste) private var enableSmartPaste = true
    @AppStorage(AppDefaults.Keys.playCompletionSound) private var playCompletionSound = true
    @AppStorage(AppDefaults.Keys.maxModelStorageGB) private var maxModelStorageGB = 5.0

    @State private var loginItemError: String?

    private let storageOptions: [Double] = [1, 2, 5, 10, 20]

    var body: some View {
        Form {
            Section("General") {
                Toggle(isOn: $startAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start at Login")
                        Text("Launch VoiceFlow when you sign in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: startAtLogin) { _, newValue in
                    updateLoginItem(enabled: newValue)
                }

                Toggle(isOn: $floatingMicrophoneDockEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Floating Microphone Dock")
                        Text("Keep a non-activating mic dock visible across apps and Spaces.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $autoBoostMicrophoneVolume) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Boost Microphone")
                        Text("Temporarily maximize mic input while recording.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $enableSmartPaste) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Paste")
                        Text("Automatically paste finished transcripts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $playCompletionSound) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Completion Sound")
                        Text("Play a chime when transcription finishes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let loginItemError {
                    Text(loginItemError)
                        .foregroundStyle(Color(nsColor: .systemRed))
                }
            }

            Section("Storage") {
                Picker("Max Model Storage", selection: $maxModelStorageGB) {
                    ForEach(storageOptions, id: \.self) { option in
                        Text("\(Int(option)) GB").tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(VersionInfo.fullVersionInfo)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if VersionInfo.gitHash != "dev-build" && VersionInfo.gitHash != "unknown" {
                    LabeledContent("Git") {
                        Text(VersionInfo.gitHash)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if !VersionInfo.buildDate.isEmpty {
                    LabeledContent("Built") {
                        Text(VersionInfo.buildDate)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            Logger.settings.error("Failed to update login item: \(error.localizedDescription)")
            loginItemError = "Couldn't update login item: \(error.localizedDescription)"
        }
    }
}

#Preview {
    DashboardPreferencesView()
        .frame(width: 900, height: 700)
}
