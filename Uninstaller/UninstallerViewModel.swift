import AppKit
import Foundation
import SwiftUI
import WhispUninstallerCore

struct SelectableUninstallItem: Identifiable {
    let item: WhispUninstallItem
    var isSelected: Bool

    var id: String {
        item.id
    }
}

@MainActor
final class UninstallerViewModel: ObservableObject {
    @Published var items: [SelectableUninstallItem]
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var activityLog: [String] = []

    init(items: [WhispUninstallItem] = WhispInstallLayout.defaultItems()) {
        self.items = items.map { item in
            SelectableUninstallItem(item: item, isSelected: item.isSelectedByDefault)
        }
    }

    func setSelection(for id: String, isSelected: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        items[index].isSelected = isSelected
    }

    func confirmAndRun() {
        let selectedItems = items.filter(\.isSelected).map(\.item)
        guard !selectedItems.isEmpty else {
            successMessage = nil
            errorMessage = "Select at least one item to remove."
            return
        }

        let alert = NSAlert()
        alert.messageText = "Uninstall Whisp?"
        let selectedTitles = selectedItems.map(\.title).joined(separator: "\n• ")
        alert.informativeText = "This will remove:\n• \(selectedTitles)\n\nThis action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        isRunning = true
        errorMessage = nil
        successMessage = nil
        activityLog = []

        Task {
            await runUninstall(selectedItems)
        }
    }

    private func runUninstall(_ selectedItems: [WhispUninstallItem]) async {
        do {
            activityLog.append("Closing Whisp if it is running...")
            try await terminateRunningWhisp()

            activityLog.append("Removing selected files and settings...")
            let result = try await Task.detached(priority: .userInitiated) {
                try WhispUninstallerService().uninstall(items: selectedItems)
            }.value

            activityLog.append("Removed \(result.removedPaths.count) path(s).")
            if !result.skippedPaths.isEmpty {
                activityLog.append("Skipped \(result.skippedPaths.count) missing path(s).")
            }
            for warning in result.warnings {
                activityLog.append("Warning: \(warning)")
            }

            successMessage = "Whisp uninstall complete."
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }

    private func terminateRunningWhisp() async throws {
        let bundleIdentifier = WhispInstallLayout.appBundleIdentifier
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
            return
        }

        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
            _ = app.terminate()
        }

        try await waitForWhispToQuit()

        let remainingApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        if !remainingApps.isEmpty {
            for app in remainingApps {
                _ = app.forceTerminate()
            }
            try await waitForWhispToQuit()
        }

        if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
            throw NSError(
                domain: "WhispUninstaller",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Whisp is still running. Quit it manually and try again."
                ]
            )
        }
    }

    private func waitForWhispToQuit() async throws {
        let bundleIdentifier = WhispInstallLayout.appBundleIdentifier

        for _ in 0..<15 {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
                return
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }
}