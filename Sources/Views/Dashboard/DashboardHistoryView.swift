import SwiftUI

internal struct DashboardHistoryView: View {
    @State private var records: [TranscriptionRecord] = []
    @State private var isLoading = true

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
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No transcriptions yet")
                .font(.headline)
            Text("Your transcription history will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
}
