import SwiftUI

/// Dashboard view showing transcription history and statistics.
struct HistoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    let onDismiss: () -> Void

    @State private var records: [HistoryStore.Record] = []
    @State private var stats: HistoryStore.Stats = .init(totalSessions: 0, last7DaysSessions: 0, failureRate: 0, avgDuration: 0)

    private var dark: Bool { colorScheme == .dark }
    private var bg: Color { dark ? Color(red: 0.08, green: 0.12, blue: 0.13) : Color(red: 0.96, green: 0.96, blue: 0.95) }
    private var surface: Color { dark ? Color(red: 0.12, green: 0.18, blue: 0.18) : Color(red: 0.92, green: 0.93, blue: 0.92) }
    private var textColor: Color { dark ? Color(red: 0.95, green: 0.94, blue: 0.89) : Color(red: 0.12, green: 0.13, blue: 0.15) }
    private var muted: Color { dark ? Color(red: 0.67, green: 0.73, blue: 0.70) : Color(red: 0.42, green: 0.45, blue: 0.43) }
    private let accent = Color(red: 0.90, green: 0.58, blue: 0.31)

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("History")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor)
                Spacer()
                Button("Export CSV") { exportCSV() }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .buttonStyle(.bordered)
                    .tint(accent)
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(muted)
                        .frame(width: 24, height: 24)
                        .background((dark ? Color.white : Color.black).opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Stats cards
            HStack(spacing: 12) {
                statCard("Total", value: "\(stats.totalSessions)")
                statCard("7 Days", value: "\(stats.last7DaysSessions)")
                statCard("Avg Duration", value: String(format: "%.1fs", stats.avgDuration))
                statCard("Failure Rate", value: String(format: "%.0f%%", stats.failureRate * 100))
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            // Records list
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    ForEach(records) { record in
                        recordRow(record)
                    }
                    if records.isEmpty {
                        Text("No sessions recorded yet.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(muted)
                            .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg)
        .onAppear { refresh() }
    }

    private func refresh() {
        records = HistoryStore.shared.recentRecords(limit: 50)
        stats = HistoryStore.shared.stats()
    }

    private func statCard(_ title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(textColor)
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func recordRow(_ r: HistoryStore.Record) -> some View {
        HStack(spacing: 10) {
            Image(systemName: r.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(r.success ? Color.green.opacity(0.75) : Color.red.opacity(0.75))

            VStack(alignment: .leading, spacing: 2) {
                Text(r.timestamp, style: .date)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(textColor)
                Text("\(r.mode) · \(r.textLength) chars · \(String(format: "%.1fs", r.durationSec))\(r.polished ? " · polished" : "")")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(muted)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func exportCSV() {
        let csv = HistoryStore.shared.exportCSV()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "murmur-history.csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
