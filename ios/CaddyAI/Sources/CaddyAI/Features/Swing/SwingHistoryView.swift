import SwiftUI
import CaddyAICore

/// Lists the player's recent analyzed swings — the user-visible half of
/// the persistent-history feature. Each row opens a detail sheet with
/// the full report and metrics. Data is fetched fresh from the backend
/// on appear; we don't maintain a local cache here because the server
/// is the source of truth (a user on a second device should see the
/// same history once device sync lands).
struct SwingHistoryView: View {
    @EnvironmentObject private var state: AppState
    @State private var entries: [SwingHistoryEntry] = []
    @State private var loading = false
    @State private var error: String?
    @State private var selected: SwingHistoryEntry?

    var body: some View {
        List {
            if loading && entries.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "No swings yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Record a swing and it'll show up here.")
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(entries) { entry in
                    Button { selected = entry } label: { row(entry) }
                        .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Swing history")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await reload() }
        .task { await reload() }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .sheet(item: $selected) { entry in
            NavigationStack { detail(entry) }
        }
    }

    private func row(_ e: SwingHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(e.ts, style: .date).font(.subheadline.bold())
                Text(e.ts, style: .time).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let k = e.metrics.clubKind {
                    Text(k.rawValue.capitalized)
                        .font(.caption.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            Text(e.report.likelyBallFlight).font(.headline)
            Text(e.report.summary).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private func detail(_ e: SwingHistoryEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(e.report.likelyBallFlight).font(.title2.bold())
                Text(e.report.summary).foregroundStyle(.secondary)
                if !e.report.rootCauses.isEmpty {
                    sectionHeader("Root causes")
                    ForEach(Array(e.report.rootCauses.enumerated()), id: \.offset) { _, c in
                        Text("• \(c)")
                    }
                }
                if !e.report.drills.isEmpty {
                    sectionHeader("Drills")
                    ForEach(Array(e.report.drills.enumerated()), id: \.offset) { _, d in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name).font(.headline)
                            Text(d.description).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(e.ts.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { selected = nil }
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text).font(.headline).padding(.top, 4)
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            let resp = try await state.api.swingHistory()
            entries = resp.entries
        } catch {
            self.error = error.localizedDescription
        }
    }
}
