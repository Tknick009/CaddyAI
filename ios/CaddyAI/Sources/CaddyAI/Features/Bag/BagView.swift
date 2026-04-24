import SwiftUI
import CaddyAICore

struct BagView: View {
    @EnvironmentObject private var state: AppState
    @State private var showAdd = false
    @State private var syncStatus: SyncStatus = .idle
    @State private var editingDistance: Club?

    enum SyncStatus: Equatable {
        case idle, syncing, synced, offline

        var pill: (text: String, level: StatusPill.Level)? {
            switch self {
            case .idle: return nil
            case .syncing: return ("Syncing…", .neutral)
            case .synced: return ("Synced", .ok)
            case .offline: return ("Offline — saved locally", .warn)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Screen {
                header
                if state.bag.clubs.isEmpty {
                    emptyState
                } else {
                    clubsCard
                }
                actions
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showAdd) {
                AddClubSheet { newClub in
                    if !state.bag.clubs.contains(where: { $0.id == newClub.id }) {
                        state.bag.clubs.append(newClub)
                        state.persist()
                        Haptics.success()
                    }
                    showAdd = false
                }
            }
            .sheet(item: $editingDistance) { club in
                DistanceEditor(club: club, currentDistance: distance(for: club)) { yards in
                    updateDistance(for: club, yards: yards)
                    editingDistance = nil
                }
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bag").font(Theme.Type.title).foregroundStyle(Theme.Palette.textPrimary)
                Text("\(state.bag.clubs.count) clubs · \(bagsWithDistance) with personal distance")
                    .font(Theme.Type.caption).foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            Button { showAdd = true; Haptics.tap() } label: {
                ZStack {
                    Circle().fill(Theme.Palette.primary).frame(width: 40, height: 40)
                    Image(systemName: "plus").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.top, Theme.Spacing.s)
    }

    private var emptyState: some View {
        Card {
            VStack(spacing: Theme.Spacing.m) {
                Image(systemName: "bag.badge.plus")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.Palette.primary)
                Text("No clubs yet").font(Theme.Type.bodyStrong)
                Text("Add the clubs you're carrying so the caddy has something to pick from.")
                    .font(Theme.Type.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Add first club") { showAdd = true }
                    .buttonStyle(.primaryPill(fullWidth: false))
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var clubsCard: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(state.bag.clubs.enumerated()), id: \.element.id) { idx, club in
                    ClubRow(club: club, distance: distance(for: club)) {
                        editingDistance = club; Haptics.tap()
                    } onDelete: {
                        state.bag.clubs.removeAll { $0.id == club.id }
                        state.bag.personalDistances.removeAll { $0.clubId == club.id }
                        state.persist()
                        Haptics.selection()
                    }
                    if idx < state.bag.clubs.count - 1 {
                        HairlineDivider().padding(.horizontal, Theme.Spacing.l)
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.s) {
            Button("Sync to backend") {
                Task { await sync() }
            }
            .buttonStyle(.primaryPill)
            .disabled(syncStatus == .syncing)

            Button("Restore standard bag") {
                state.bag = .standard14
                state.persist()
                Haptics.selection()
            }
            .buttonStyle(.secondaryPill)

            if let pill = syncStatus.pill {
                StatusPill(text: pill.text, level: pill.level)
                    .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    // MARK: Helpers

    private var bagsWithDistance: Int {
        state.bag.personalDistances.count
    }

    private func distance(for club: Club) -> Double? {
        state.bag.personalDistances.first { $0.clubId == club.id }?.typicalYards
    }

    private func updateDistance(for club: Club, yards: Double?) {
        state.bag.personalDistances.removeAll { $0.clubId == club.id }
        if let yards {
            state.bag.personalDistances.append(PersonalDistance(clubId: club.id, typicalYards: yards))
        }
        state.persist()
        Haptics.success()
    }

    private func sync() async {
        syncStatus = .syncing
        do {
            _ = try await state.api.putBag(state.bag)
            syncStatus = .synced
            Haptics.success()
        } catch {
            syncStatus = .offline
            Haptics.warning()
        }
    }
}

// MARK: - Club row

private struct ClubRow: View {
    let club: Club
    let distance: Double?
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.Palette.primary.opacity(0.12))
                Text(kindAbbreviation)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Palette.primary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(club.name).font(Theme.Type.bodyStrong).foregroundStyle(Theme.Palette.textPrimary)
                HStack(spacing: 6) {
                    Text(club.kind.rawValue.capitalized)
                    if let loft = club.loftDeg {
                        Text("· \(Int(loft))°")
                    }
                }
                .font(Theme.Type.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            Button(action: onEdit) {
                HStack(spacing: 4) {
                    if let distance {
                        Text("\(Int(distance))")
                            .font(Theme.Type.metricSmall)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text("yd")
                            .font(Theme.Type.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    } else {
                        Text("Add yds")
                            .font(Theme.Type.caption)
                            .foregroundStyle(Theme.Palette.primary)
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Theme.Palette.surfaceMuted)
                )
            }
            .buttonStyle(.plain)

            Button { showDeleteConfirm = true } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(club.name)")
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .confirmationDialog(
            "Remove \(club.name)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var kindAbbreviation: String {
        switch club.kind {
        case .driver: return "DR"
        case .wood: return "W"
        case .hybrid: return "H"
        case .iron: return "I"
        case .wedge: return "WG"
        case .putter: return "P"
        }
    }
}

// MARK: - Distance editor

private struct DistanceEditor: View {
    let club: Club
    let onSave: (Double?) -> Void
    @State private var yards: Double
    @Environment(\.dismiss) private var dismiss

    init(club: Club, currentDistance: Double?, onSave: @escaping (Double?) -> Void) {
        self.club = club
        self.onSave = onSave
        _yards = State(initialValue: currentDistance ?? 150)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(club.name).font(Theme.Type.title)
                        Text("Set your typical carry distance.").font(Theme.Type.caption).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(Int(yards))").font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("yd").font(Theme.Type.title2).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Slider(value: $yards, in: 40...330, step: 1)
                        .tint(Theme.Palette.primary)
                    Button("Save") {
                        onSave(yards)
                    }
                    .buttonStyle(.primaryPill)
                    Button("Clear") {
                        onSave(nil)
                    }
                    .buttonStyle(.secondaryPill)
                    Spacer()
                }
                .padding(Theme.Spacing.xl)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Add club

private struct AddClubSheet: View {
    let onAdd: (Club) -> Void
    @State private var name: String = ""
    @State private var kind: ClubKind = .iron
    @State private var loft: Double = 30
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Palette.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Name").font(Theme.Type.caption).foregroundStyle(Theme.Palette.textSecondary)
                        TextField("7 Iron", text: $name)
                            .padding(Theme.Spacing.m)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.Palette.surface))
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Kind").font(Theme.Type.caption).foregroundStyle(Theme.Palette.textSecondary)
                        Picker("Kind", selection: $kind) {
                            ForEach(ClubKind.allCases, id: \.self) { k in
                                Text(k.rawValue.capitalized).tag(k)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            HStack {
                                Text("Loft").font(Theme.Type.caption).foregroundStyle(Theme.Palette.textSecondary)
                                Spacer()
                                Text("\(loft, specifier: "%.1f")°").font(Theme.Type.bodyStrong).monospacedDigit()
                            }
                            Slider(value: $loft, in: 3...70, step: 0.5)
                                .tint(Theme.Palette.primary)
                        }
                    }

                    Button("Add to bag") {
                        let id = UUID().uuidString.prefix(8).lowercased()
                        let displayName = name.isEmpty ? kind.rawValue.capitalized : name
                        onAdd(Club(id: String(id), kind: kind, name: displayName, loftDeg: loft))
                    }
                    .buttonStyle(.primaryPill)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                }
                .padding(Theme.Spacing.xl)
            }
            .navigationTitle("Add club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
