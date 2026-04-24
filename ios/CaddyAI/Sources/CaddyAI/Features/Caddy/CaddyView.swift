import SwiftUI
import CaddyAICore

/// Club recommendation flow. Distance hero → context chips → big "Recommend"
/// CTA → result card with primary + alt club and plays-distance chips.
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
            Screen(title: "Caddy") {
                distanceHero
                contextGrid
                windControl
                recommendButton
                if let rec = recommendation {
                    RecommendationCard(rec: rec, bag: state.bag)
                }
                if let errorText {
                    Text(errorText)
                        .font(Theme.Type.caption)
                        .foregroundStyle(Theme.Palette.warning)
                        .padding(Theme.Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Theme.Palette.warning.opacity(0.12))
                        )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Sections

    private var distanceHero: some View {
        HeroCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "flag.fill").font(.system(size: 13, weight: .bold))
                    Text("Distance to pin").font(Theme.Type.caption).tracking(0.8)
                }
                .foregroundStyle(.white.opacity(0.9))

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(Int(target))")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("yd")
                        .font(Theme.Type.title2)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.top, -4)

                HStack(spacing: Theme.Spacing.s) {
                    Button { adjust(target: -5) } label: { stepGlyph("minus") }
                    Slider(value: $target, in: 20...350, step: 1)
                        .tint(.white)
                    Button { adjust(target: +5) } label: { stepGlyph("plus") }
                }
            }
        }
    }

    private func stepGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(.white.opacity(0.18)))
    }

    private func adjust(target delta: Double) {
        target = min(350, max(20, target + delta))
        Haptics.selection()
    }

    private var contextGrid: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Conditions")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.m),
                                GridItem(.flexible(), spacing: Theme.Spacing.m)],
                      spacing: Theme.Spacing.m) {
                numberTile(label: "Elevation", value: "\(Int(elevation))", unit: "ft", icon: "mountain.2.fill") { showElevationEditor = true }
                liePickerTile
            }
        }
        .confirmationDialog("Elevation change", isPresented: $showElevationEditor) {
            ForEach([-30, -15, -5, 0, 5, 15, 30], id: \.self) { v in
                Button("\(v) ft") { elevation = Double(v); Haptics.selection() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @State private var showElevationEditor = false

    private func numberTile(label: String, value: String, unit: String, icon: String, onTap: @escaping () -> Void) -> some View {
        Button(action: { Haptics.tap(); onTap() }) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.primary)
                    Text(label.uppercased())
                        .font(Theme.Type.micro).tracking(0.6)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value).font(Theme.Type.metricSmall).foregroundStyle(Theme.Palette.textPrimary)
                    Text(unit).font(Theme.Type.caption).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(Theme.Palette.surface)
            )
            .themeShadow()
        }
        .buttonStyle(.plain)
    }

    private var liePickerTile: some View {
        Menu {
            ForEach(Lie.allCases, id: \.self) { l in
                Button(l.rawValue.replacingOccurrences(of: "_", with: " ").capitalized) {
                    lie = l; Haptics.selection()
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.primary)
                    Text("LIE").font(Theme.Type.micro).tracking(0.6)
                        .foregroundStyle(Theme.Palette.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                Text(lie.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(Theme.Type.bodyStrong)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(Theme.Palette.surface)
            )
            .themeShadow()
        }
    }

    private var windControl: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "wind").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Palette.primary)
                        Text("WIND").font(Theme.Type.micro).tracking(0.6)
                            .foregroundStyle(Theme.Palette.textSecondary)
                    }
                    Spacer()
                    Text("\(Int(windSpeed)) mph · \(windLabel)")
                        .font(Theme.Type.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Slider(value: $windSpeed, in: 0...40, step: 1)
                    .tint(Theme.Palette.primary)
                HStack(spacing: Theme.Spacing.s) {
                    ForEach([(0, "Head"), (90, "R→L"), (180, "Tail"), (270, "L→R")], id: \.0) { pair in
                        let active = abs(windDirection - Double(pair.0)) < 1
                        Button {
                            windDirection = Double(pair.0); Haptics.selection()
                        } label: {
                            Text(pair.1).font(Theme.Type.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule().fill(active ? Theme.Palette.primary : Theme.Palette.surfaceMuted)
                                )
                                .foregroundStyle(active ? .white : Theme.Palette.textPrimary)
                        }
                    }
                }
            }
        }
    }

    private var recommendButton: some View {
        Button {
            Haptics.tap()
            Task { await recommend() }
        } label: {
            HStack {
                if loading { ProgressView().tint(.white).padding(.trailing, Theme.Spacing.s) }
                Image(systemName: "sparkles")
                Text(loading ? "Thinking…" : "Recommend a club")
            }
        }
        .buttonStyle(.primaryPill)
        .disabled(loading || state.bag.clubs.isEmpty)
    }

    // MARK: Wind label

    private var windLabel: String {
        switch windDirection {
        case 0..<22.5, 337.5...360: return "Headwind"
        case 22.5..<67.5: return "Quartering R→L"
        case 67.5..<112.5: return "Cross R→L"
        case 112.5..<157.5: return "Helping R→L"
        case 157.5..<202.5: return "Tailwind"
        case 202.5..<247.5: return "Helping L→R"
        case 247.5..<292.5: return "Cross L→R"
        case 292.5..<337.5: return "Quartering L→R"
        default: return ""
        }
    }

    // MARK: Networking

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
            recommendation = try await state.api.recommend(req)
            Haptics.success()
        } catch {
            if let local = CaddyEngine.recommend(ctx, bag: state.bag) {
                recommendation = local
                errorText = "Backend offline — using on-device caddy."
                Haptics.warning()
            } else {
                errorText = "Could not recommend: \(error.localizedDescription)"
                Haptics.error()
            }
        }
    }
}

// MARK: - Result card

private struct RecommendationCard: View {
    let rec: CaddyRecommendation
    let bag: Bag

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Recommendation")
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PLAY").font(Theme.Type.micro).tracking(0.8)
                                .foregroundStyle(Theme.Palette.textSecondary)
                            Text(clubName(rec.primaryClubId))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.Palette.textPrimary)
                        }
                        Spacer()
                        if let altId = rec.altClubId, altId != rec.primaryClubId {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("ALT").font(Theme.Type.micro).tracking(0.8)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                                Text(clubName(altId))
                                    .font(Theme.Type.title2)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                        }
                    }

                    Text(rec.commentary)
                        .font(Theme.Type.body)
                        .foregroundStyle(Theme.Palette.textSecondary)

                    FlowChips(chips: adjustmentChips)
                }
            }
        }
    }

    private func clubName(_ id: String) -> String {
        bag.clubs.first(where: { $0.id == id })?.name ?? id
    }

    private var adjustmentChips: [(String, String)] {
        var xs: [(String, String)] = []
        xs.append(("target", "Plays \(Int(rec.effectiveDistanceYards)) yd"))
        if rec.windAdjustmentYards != 0 { xs.append(("wind", "Wind \(signed(rec.windAdjustmentYards)) yd")) }
        if rec.elevationAdjustmentYards != 0 { xs.append(("mountain.2.fill", "Elev \(signed(rec.elevationAdjustmentYards)) yd")) }
        if rec.lieAdjustmentYards != 0 { xs.append(("leaf.fill", "Lie \(signed(rec.lieAdjustmentYards)) yd")) }
        return xs
    }

    private func signed(_ d: Double) -> String {
        let v = Int(d.rounded())
        return v >= 0 ? "+\(v)" : "\(v)"
    }
}

/// Simple wrap-around chip stack (SwiftUI doesn't have `FlowLayout` pre-iOS 16
/// but we're on iOS 16+, so a `FlowView` via Layout would work — keeping this
/// lightweight HStack with wrap-proxy to avoid extra complexity).
private struct FlowChips: View {
    let chips: [(String, String)]
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(chips.indices, id: \.self) { i in
                let (symbol, text) = chips[i]
                Chip(text: text, systemImage: sf(symbol), tint: Theme.Palette.primary)
            }
        }
    }

    private func sf(_ k: String) -> String? {
        switch k {
        case "target": return "scope"
        case "wind": return "wind"
        default: return k
        }
    }
}

/// Very small flow layout — lays children left-to-right, wrapping when the row fills.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, totalW: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxWidth { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height); totalW = max(totalW, x)
        }
        return CGSize(width: min(maxWidth, totalW), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
