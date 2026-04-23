import SwiftUI
import CaddyAICore

struct CaddyView: View {
    @EnvironmentObject private var state: AppState

    @State private var target: Double = 150
    @State private var elevation: Double = 0
    @State private var windSpeed: Double = 0
    @State private var windDirection: Double = 0
    @State private var lie: Lie = .fairway
    @State private var recommendation: CaddyRecommendation?
    @State private var errorText: String?
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Shot") {
                    Stepper(value: $target, in: 20...350, step: 5) {
                        HStack { Text("Distance"); Spacer(); Text("\(Int(target)) yd") }
                    }
                    Stepper(value: $elevation, in: -100...100, step: 5) {
                        HStack { Text("Elevation"); Spacer(); Text("\(Int(elevation)) ft") }
                    }
                    Picker("Lie", selection: $lie) {
                        ForEach(Lie.allCases, id: \.self) { l in
                            Text(l.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag(l)
                        }
                    }
                }
                Section("Wind") {
                    Stepper(value: $windSpeed, in: 0...40, step: 1) {
                        HStack { Text("Speed"); Spacer(); Text("\(Int(windSpeed)) mph") }
                    }
                    Stepper(value: $windDirection, in: 0...360, step: 15) {
                        HStack {
                            Text("Direction")
                            Spacer()
                            Text("\(Int(windDirection))°")
                            Text(windLabel).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Button {
                        Task { await recommend() }
                    } label: {
                        if loading { ProgressView() } else { Text("Recommend club") }
                    }
                    .disabled(loading || state.bag.clubs.isEmpty)
                }
                if let rec = recommendation {
                    Section("Recommendation") {
                        RecommendationCard(rec: rec, bag: state.bag)
                    }
                }
                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Caddy")
        }
    }

    private var windLabel: String {
        switch windDirection {
        case 0..<22.5, 337.5...360: return "Headwind"
        case 22.5..<67.5: return "Quartering (R→L)"
        case 67.5..<112.5: return "Crosswind R→L"
        case 112.5..<157.5: return "Helping (R→L)"
        case 157.5..<202.5: return "Tailwind"
        case 202.5..<247.5: return "Helping (L→R)"
        case 247.5..<292.5: return "Crosswind L→R"
        case 292.5..<337.5: return "Quartering (L→R)"
        default: return ""
        }
    }

    private func recommend() async {
        errorText = nil
        loading = true
        defer { loading = false }
        let ctx = ShotContext(
            targetDistanceYards: target,
            elevationChangeFt: elevation,
            windSpeedMph: windSpeed,
            windDirectionDeg: windDirection,
            lie: lie
        )
        do {
            let req = CaddyRecommendRequest(context: ctx, bag: state.bag)
            let rec = try await state.api.recommend(req)
            recommendation = rec
        } catch {
            // Fall back to the local engine so the caddy works off-grid.
            if let local = CaddyEngine.recommend(ctx, bag: state.bag) {
                recommendation = local
                errorText = "Backend offline — used on-device caddy."
            } else {
                errorText = "Could not recommend: \(error.localizedDescription)"
            }
        }
    }
}

private struct RecommendationCard: View {
    let rec: CaddyRecommendation
    let bag: Bag

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(clubName(rec.primaryClubId))
                    .font(.largeTitle.bold())
                Spacer()
                if let altId = rec.altClubId, altId != rec.primaryClubId {
                    VStack(alignment: .trailing) {
                        Text("Alt")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(clubName(altId))
                            .font(.title3.weight(.semibold))
                    }
                }
            }
            Text(rec.commentary).foregroundStyle(.secondary)

            HStack(spacing: 8) {
                chip("Plays \(Int(rec.effectiveDistanceYards)) yd")
                if rec.windAdjustmentYards != 0 {
                    chip("Wind \(signed(rec.windAdjustmentYards)) yd")
                }
                if rec.elevationAdjustmentYards != 0 {
                    chip("Elev \(signed(rec.elevationAdjustmentYards)) yd")
                }
                if rec.lieAdjustmentYards != 0 {
                    chip("Lie \(signed(rec.lieAdjustmentYards)) yd")
                }
            }
            .lineLimit(1)
        }
    }

    private func clubName(_ id: String) -> String {
        bag.clubs.first(where: { $0.id == id })?.name ?? id
    }

    private func chip(_ s: String) -> some View {
        Text(s)
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(.thinMaterial))
    }

    private func signed(_ d: Double) -> String {
        let v = Int(d.rounded())
        return v >= 0 ? "+\(v)" : "\(v)"
    }
}
