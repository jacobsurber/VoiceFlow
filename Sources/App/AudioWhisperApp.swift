import AppKit
import SwiftData
import SwiftUI

@main
internal struct WhispApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // This is a menu bar app, so we just need to define menu commands
        // All windows are created programmatically
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .onAppear {
                    // Hide the empty window immediately
                    NSApplication.shared.windows.first?.orderOut(nil)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    DashboardWindowManager.shared.showDashboardWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    /// Creates a fallback container if DataManager initialization fails
    private func createFallbackContainer() -> ModelContainer? {
        do {
            let schema = Schema([TranscriptionRecord.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Critical error but don't crash - transcription history will be disabled
            NSLog("❌ CRITICAL: Failed to create fallback ModelContainer: \(error.localizedDescription)")

            // Show alert to user
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Database Initialization Failed"
                alert.informativeText = "Whisp couldn't initialize its database. Transcription history will be disabled this session.\n\nError: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Continue")
                alert.runModal()
            }

            return nil
        }
    }
}
