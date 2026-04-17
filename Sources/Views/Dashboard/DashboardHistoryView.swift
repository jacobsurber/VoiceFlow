import SwiftUI

internal struct DashboardHistoryView: View {
    @State private var records: [TranscriptionRecord] = []
    @State private var isLoading = true
    @State private var showClearConfirmation = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if records.isEmpty {
                emptyState
            } else {
                recordsList
            }
        }
        .task {
            await loadRecords()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if !records.isEmpty {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label("Clear History", systemImage: "trash")
                    }
                }
            }
        }
        .alert("Clear all history?", isPresented: $showClearConfirmation) {
            Button("Clear", role: .destructive) {
                Task { await clearHistory() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all transcription records.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundStyle(.quaternary)
            Text("No transcriptions yet")
                .font(.system(size: 15, weight: .medium, design: .serif))
            Text("Record something to see it here.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordsList: some View {
        List(records, id: \.id) { record in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(record.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let provider = record.transcriptionProvider {
                        Text(provider.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                Text(record.text)
                    .font(.body)
                    .lineLimit(4)
                    .textSelection(.enabled)

                HStack(spacing: 12) {
                    if record.wordCount > 0 {
                        Label("\(record.wordCount) words", systemImage: "textformat.size")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let duration = record.formattedDuration {
                        Label(duration, systemImage: "timer")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let appName = record.sourceAppName {
                        Label(appName, systemImage: "app")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listStyle(.inset)
    }

    private func loadRecords() async {
        isLoading = true
        records = await DataManager.shared.fetchAllRecordsQuietly()
        isLoading = false
    }

    private func clearHistory() async {
        try? await DataManager.shared.deleteAllRecords()
        records = []
    }
}
