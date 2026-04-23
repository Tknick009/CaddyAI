import SwiftUI
import CaddyAICore

struct BagView: View {
    @EnvironmentObject private var state: AppState
    @State private var showAdd = false
    @State private var syncStatus: String?

    var body: some View {
        NavigationStack {
            List {
                if state.bag.clubs.isEmpty {
                    ContentUnavailableView(
                        "No clubs",
                        systemImage: "bag",
                        description: Text("Add the clubs you're carrying so the caddy knows what to pick from.")
                    )
                } else {
                    ForEach(state.bag.clubs) { club in
                        ClubRow(club: club, distance: distance(for: club))
                    }
                    .onDelete { indices in
                        state.bag.clubs.remove(atOffsets: indices)
                        state.persist()
                    }
                }

                Section {
                    Button("Restore standard 14") {
                        state.bag = .standard14
                        state.persist()
                    }
                    Button("Sync to backend") {
                        Task { await sync() }
                    }
                    if let syncStatus { Text(syncStatus).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Bag")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddClubSheet { newClub in
                    if !state.bag.clubs.contains(where: { $0.id == newClub.id }) {
                        state.bag.clubs.append(newClub)
                        state.persist()
                    }
                    showAdd = false
                }
            }
        }
    }

    private func distance(for club: Club) -> Double? {
        state.bag.personalDistances.first(where: { $0.clubId == club.id })?.typicalYards
    }

    private func sync() async {
        syncStatus = "Syncing…"
        do {
            _ = try await state.api.putBag(state.bag)
            syncStatus = "Synced."
        } catch {
            syncStatus = "Backend offline — kept locally."
        }
    }
}

private struct ClubRow: View {
    let club: Club
    let distance: Double?

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(club.name).font(.body)
                HStack(spacing: 6) {
                    Text(club.kind.rawValue.capitalized)
                    if let loft = club.loftDeg {
                        Text("\(Int(loft))°")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let distance {
                Text("\(Int(distance)) yd")
                    .font(.headline)
                    .monospacedDigit()
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
    }
}

private struct AddClubSheet: View {
    let onAdd: (Club) -> Void
    @State private var name: String = ""
    @State private var kind: ClubKind = .iron
    @State private var loft: Double = 30

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. 7 Iron)", text: $name)
                Picker("Kind", selection: $kind) {
                    ForEach(ClubKind.allCases, id: \.self) { k in
                        Text(k.rawValue.capitalized).tag(k)
                    }
                }
                Stepper(value: $loft, in: 3...70, step: 0.5) {
                    HStack { Text("Loft"); Spacer(); Text("\(loft, specifier: "%.1f")°") }
                }
            }
            .navigationTitle("Add club")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let id = UUID().uuidString.prefix(8).lowercased()
                        onAdd(Club(id: String(id), kind: kind, name: name.isEmpty ? "\(kind.rawValue.capitalized)" : name, loftDeg: loft))
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
