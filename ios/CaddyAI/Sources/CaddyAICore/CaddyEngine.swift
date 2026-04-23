import Foundation

/// A pure-Swift mirror of `backend/app/services/caddy.py` so the iOS app
/// can produce recommendations offline (e.g. mid-round, no cellular).
/// The backend remains the source of truth when a network is available.
public enum CaddyEngine {
    /// Amateur averages in yards, used when we don't have a learned
    /// personal distance for a club yet.
    public static let defaultDistances: [ClubKind: [(Double, Double)]] = [
        .driver: [(10.5, 230)],
        .wood: [(15, 210), (18, 200), (21, 190)],
        .hybrid: [(19, 195), (22, 180), (25, 170)],
        .iron: [
            (18, 190), (21, 180), (24, 170),
            (27, 160), (30, 150), (34, 140),
            (38, 130), (42, 120), (46, 110),
        ],
        .wedge: [(50, 100), (54, 85), (58, 65), (60, 55)],
        .putter: [(3, 0)],
    ]

    public static func distance(for club: Club, personal: [String: PersonalDistance]) -> Double {
        if let pd = personal[club.id] { return pd.typicalYards }
        let table = defaultDistances[club.kind] ?? []
        guard !table.isEmpty else { return 100 }
        if let loft = club.loftDeg {
            let closest = table.min(by: { abs($0.0 - loft) < abs($1.0 - loft) })!
            return closest.1
        }
        return table.map(\.1).reduce(0, +) / Double(table.count)
    }

    public static func lieAdjustmentYards(lie: Lie, target: Double) -> Double {
        switch lie {
        case .tee, .fairway:   return 0
        case .rough:           return target * 0.03
        case .deepRough:       return target * 0.07
        case .bunker:          return target * 0.08
        case .recovery:        return target * 0.10
        }
    }

    public static func windAdjustmentYards(_ ctx: ShotContext) -> Double {
        let theta = ctx.windDirectionDeg * .pi / 180
        let headComponent = ctx.windSpeedMph * cos(theta)
        return ctx.targetDistanceYards * (headComponent / 100.0)
    }

    public static func elevationAdjustmentYards(_ ctx: ShotContext) -> Double {
        ctx.elevationChangeFt / 3.0
    }

    public static func recommend(_ ctx: ShotContext, bag: Bag) -> CaddyRecommendation? {
        guard !bag.clubs.isEmpty else { return nil }

        let wind = windAdjustmentYards(ctx)
        let elev = elevationAdjustmentYards(ctx)
        let lieAdj = lieAdjustmentYards(lie: ctx.lie, target: ctx.targetDistanceYards)

        var effective = ctx.targetDistanceYards + wind + elev + lieAdj
        if let carry = ctx.mustCarryYards {
            effective = max(effective, carry + 5)
        }

        let personal = Dictionary(uniqueKeysWithValues: bag.personalDistances.map { ($0.clubId, $0) })

        let scored: [(club: Club, dist: Double, residual: Double)] =
            bag.clubs
            .filter { $0.kind != .putter }
            .map { club in
                let d = distance(for: club, personal: personal)
                return (club, d, abs(d - effective))
            }
            .sorted { $0.residual < $1.residual }

        guard let best = scored.first else { return nil }

        let alt = scored.dropFirst().first {
            ($0.dist - effective) * (best.dist - effective) <= 0
        } ?? scored.dropFirst().first

        var parts = ["Plays \(Int(effective.rounded()))y effective (\(Int(ctx.targetDistanceYards))y target"]
        if wind != 0 { parts.append("\(Int(wind.rounded().magnitude))y \(wind > 0 ? "headwind" : "tailwind")") }
        if elev != 0 { parts.append("\(Int(elev.rounded().magnitude))y \(elev > 0 ? "up" : "down")") }
        if lieAdj != 0 { parts.append("\(Int(lieAdj.rounded()))y lie") }
        let header = parts.joined(separator: ", ") + ")."

        let delta = best.dist - effective
        let swingNote: String
        if abs(delta) < 3 {
            swingNote = "Stock \(best.club.name)."
        } else if delta > 0 {
            swingNote = "Smooth \(best.club.name) — a touch too much, ease off."
        } else {
            swingNote = "Full \(best.club.name) — you'll need every bit of it."
        }
        var commentary = "\(header) \(swingNote)"
        if let alt, alt.club.id != best.club.id {
            commentary += " Alt: \(alt.club.name)."
        }

        return CaddyRecommendation(
            primaryClubId: best.club.id,
            altClubId: alt?.club.id,
            effectiveDistanceYards: (effective * 10).rounded() / 10,
            windAdjustmentYards: (wind * 10).rounded() / 10,
            elevationAdjustmentYards: (elev * 10).rounded() / 10,
            lieAdjustmentYards: (lieAdj * 10).rounded() / 10,
            commentary: commentary
        )
    }
}
