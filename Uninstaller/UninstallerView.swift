import AppKit
import SwiftUI

struct UninstallerView: View {
    @ObservedObject var viewModel: UninstallerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Uninstall Whisp")
                .font(.system(size: 28, weight: .semibold))

            Text("Remove the installed app and the data you choose below. The legacy transcription history database is optional because older builds stored it in a generic SwiftData location.")
                .font(.body)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(viewModel.items) { selection in
                        Toggle(isOn: binding(for: selection.id)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(selection.item.title)
                                    .font(.headline)

                                Text(selection.item.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                ForEach(selection.item.paths, id: \.path) { path in
                                    Text(path.path)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }

                                if selection.item.requiresExplicitSelection {
                                    Text("Optional. Only select this if you want to purge the older generic SwiftData history store.")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)

                        Divider()
                    }
                }
            }

            if let successMessage = viewModel.successMessage {
                Text(successMessage)
                    .foregroundStyle(.green)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            if !viewModel.activityLog.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(viewModel.activityLog.enumerated()), id: \.offset) { entry in
                            Text(entry.element)
                                .font(.caption.monospaced())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 120)
                .padding(10)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()

                Button("Close") {
                    NSApp.terminate(nil)
                }
                .disabled(viewModel.isRunning)

                Button(viewModel.isRunning ? "Uninstalling..." : "Uninstall Whisp") {
                    viewModel.confirmAndRun()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isRunning)
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 560)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: {
                viewModel.items.first(where: { $0.id == id })?.isSelected ?? false
            },
            set: { isSelected in
                viewModel.setSelection(for: id, isSelected: isSelected)
            }
        )
    }
}