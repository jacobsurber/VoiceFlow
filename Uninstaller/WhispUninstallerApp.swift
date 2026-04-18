import AppKit
import SwiftUI

@main
struct WhispUninstallerApp: App {
    @StateObject private var viewModel = UninstallerViewModel()

    var body: some Scene {
        WindowGroup {
            UninstallerView(viewModel: viewModel)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}