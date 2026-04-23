import Foundation

// MARK: - Clubs & bag

public enum ClubKind: String, Codable, Hashable, CaseIterable, Sendable {
    case driver, wood, hybrid, iron, wedge, putter
}

public struct Club: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var kind: ClubKind
    public var name: String
    public var loftDeg: Double?

    public init(id: String, kind: ClubKind, name: String, loftDeg: Double? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.loftDeg = loftDeg
    }
}

public struct PersonalDistance: Codable, Hashable, Sendable {
    public var clubId: String
    public var typicalYards: Double
    public var stddevYards: Double
    public var sampleSize: Int

    public init(clubId: String, typicalYards: Double, stddevYards: Double = 0, sampleSize: Int = 0) {
        self.clubId = clubId
        self.typicalYards = typicalYards
        self.stddevYards = stddevYards
        self.sampleSize = sampleSize
    }
}

public struct Bag: Codable, Hashable, Sendable {
    public var clubs: [Club]
    public var personalDistances: [PersonalDistance]

    public init(clubs: [Club] = [], personalDistances: [PersonalDistance] = []) {
        self.clubs = clubs
        self.personalDistances = personalDistances
    }

    public static let standard14 = Bag(clubs: [
        Club(id: "drv", kind: .driver, name: "Driver", loftDeg: 10.5),
        Club(id: "3w", kind: .wood, name: "3 Wood", loftDeg: 15),
        Club(id: "4h", kind: .hybrid, name: "4 Hybrid", loftDeg: 22),
        Club(id: "5i", kind: .iron, name: "5 Iron", loftDeg: 24),
        Club(id: "6i", kind: .iron, name: "6 Iron", loftDeg: 27),
        Club(id: "7i", kind: .iron, name: "7 Iron", loftDeg: 30),
        Club(id: "8i", kind: .iron, name: "8 Iron", loftDeg: 34),
        Club(id: "9i", kind: .iron, name: "9 Iron", loftDeg: 38),
        Club(id: "pw", kind: .wedge, name: "PW", loftDeg: 46),
        Club(id: "gw", kind: .wedge, name: "GW", loftDeg: 50),
        Club(id: "sw", kind: .wedge, name: "SW", loftDeg: 54),
        Club(id: "lw", kind: .wedge, name: "LW", loftDeg: 58),
        Club(id: "put", kind: .putter, name: "Putter"),
    ])
}

// MARK: - Shots & rounds

public enum ShotSource: String, Codable, Sendable {
    case manual
    case garminWatch = "garmin_watch"
    case launchMonitorR10 = "launch_monitor_r10"
    case launchMonitorMevo = "launch_monitor_mevo"
    case launchMonitorSkyTrak = "launch_monitor_skytrak"
    case launchMonitorRapsodo = "launch_monitor_rapsodo"
}

public enum ShotResult: String, Codable, Sendable {
    case fairway, rough, green, bunker, hazard, ob, unknown
}

public struct Shot: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var clubId: String
    public var distanceYards: Double
    public var carryYards: Double?
    public var ballSpeedMph: Double?
    public var clubSpeedMph: Double?
    public var launchAngleDeg: Double?
    public var spinRpm: Double?
    public var sideYards: Double?
    public var result: ShotResult
    public var ts: Date
    public var source: ShotSource
    public var note: String?

    public init(
        id: String = UUID().uuidString,
        clubId: String,
        distanceYards: Double,
        carryYards: Double? = nil,
        ballSpeedMph: Double? = nil,
        clubSpeedMph: Double? = nil,
        launchAngleDeg: Double? = nil,
        spinRpm: Double? = nil,
        sideYards: Double? = nil,
        result: ShotResult = .unknown,
        ts: Date = Date(),
        source: ShotSource = .manual,
        note: String? = nil
    ) {
        self.id = id
        self.clubId = clubId
        self.distanceYards = distanceYards
        self.carryYards = carryYards
        self.ballSpeedMph = ballSpeedMph
        self.clubSpeedMph = clubSpeedMph
        self.launchAngleDeg = launchAngleDeg
        self.spinRpm = spinRpm
        self.sideYards = sideYards
        self.result = result
        self.ts = ts
        self.source = source
        self.note = note
    }
}

public struct Round: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public var course: String?
    public var date: Date
    public var shots: [Shot]

    public init(id: String = UUID().uuidString, course: String? = nil, date: Date = Date(), shots: [Shot] = []) {
        self.id = id
        self.course = course
        self.date = date
        self.shots = shots
    }
}

// MARK: - Swing metrics

public enum Handedness: String, Codable, Sendable {
    case right, left
}

/// Where the metrics came from. Some measurements are only honest from
/// certain camera angles (e.g. swing plane from DTL, hip turn from FO),
/// so downstream consumers — including the coach — can weight the
/// numbers based on the viewpoint they were captured from.
public enum SwingViewpoint: String, Codable, Sendable {
    /// Face-on (golfer faces the camera). Good for hip/shoulder turn,
    /// sway, weight transfer, lateral head movement.
    case faceOn = "face_on"
    /// Down-the-line (camera behind trail shoulder). Good for swing
    /// plane, attack angle, early extension.
    case downTheLine = "down_the_line"
    /// Output of `MultiAngleSwingAnalyzer.fuse(...)` — each metric was
    /// sourced from whichever viewpoint measures it most honestly.
    case fused = "fused"
    /// 3D joints (iOS 17+ `VNDetectHumanBodyPose3DRequest` or a similar
    /// depth-aware estimator). These metrics are honest from any angle.
    case pose3D = "pose3d"
}

public struct SwingMetrics: Codable, Hashable, Sendable {
    public var tempoRatio: Double
    public var backswingSec: Double
    public var downswingSec: Double
    public var peakShoulderTurnDeg: Double
    public var peakHipTurnDeg: Double
    public var xFactorDeg: Double
    public var lateralSwayCm: Double
    public var headMovementCm: Double
    public var earlyExtensionCm: Double
    public var swingPlaneDeg: Double
    public var weightTransferPct: Double
    public var confidence: Double
    public var handedness: Handedness
    public var clubKind: ClubKind?

    // 3D-only (optional). Populated by `SwingAnalyzer3D` or by fusing
    // DTL + face-on 2D captures. Old clients that only speak the 2D
    // schema simply ignore these.
    public var viewpoint: SwingViewpoint?
    /// Club-head descent angle at impact (°), negative = hitting down.
    /// Requires 3D pose or club-head tracking to be honest.
    public var attackAngleDeg: Double?
    /// Lateral pelvis translation from address to top (cm), real units.
    public var pelvisSlideCm: Double?
    /// Pelvis side-bend at impact (°), positive = trail-side down.
    public var pelvisTiltDeg: Double?
    /// Kinematic sequence quality: 0..1 where 1 = pelvis→torso→arm→hand
    /// peak rotational velocities fire in order with reasonable spacing.
    public var sequencingIndex: Double?
    /// Club path at impact (°), requires club-head tracking. Not
    /// populated in this release — scaffolding only.
    public var clubPathDeg: Double?

    public init(
        tempoRatio: Double,
        backswingSec: Double,
        downswingSec: Double,
        peakShoulderTurnDeg: Double,
        peakHipTurnDeg: Double,
        xFactorDeg: Double,
        lateralSwayCm: Double,
        headMovementCm: Double,
        earlyExtensionCm: Double,
        swingPlaneDeg: Double,
        weightTransferPct: Double,
        confidence: Double,
        handedness: Handedness = .right,
        clubKind: ClubKind? = nil,
        viewpoint: SwingViewpoint? = nil,
        attackAngleDeg: Double? = nil,
        pelvisSlideCm: Double? = nil,
        pelvisTiltDeg: Double? = nil,
        sequencingIndex: Double? = nil,
        clubPathDeg: Double? = nil
    ) {
        self.tempoRatio = tempoRatio
        self.backswingSec = backswingSec
        self.downswingSec = downswingSec
        self.peakShoulderTurnDeg = peakShoulderTurnDeg
        self.peakHipTurnDeg = peakHipTurnDeg
        self.xFactorDeg = xFactorDeg
        self.lateralSwayCm = lateralSwayCm
        self.headMovementCm = headMovementCm
        self.earlyExtensionCm = earlyExtensionCm
        self.swingPlaneDeg = swingPlaneDeg
        self.weightTransferPct = weightTransferPct
        self.confidence = confidence
        self.handedness = handedness
        self.clubKind = clubKind
        self.viewpoint = viewpoint
        self.attackAngleDeg = attackAngleDeg
        self.pelvisSlideCm = pelvisSlideCm
        self.pelvisTiltDeg = pelvisTiltDeg
        self.sequencingIndex = sequencingIndex
        self.clubPathDeg = clubPathDeg
    }
}

public struct Drill: Codable, Hashable, Sendable {
    public let name: String
    public let description: String
}

public struct CoachingReport: Codable, Hashable, Sendable {
    public let summary: String
    public let likelyBallFlight: String
    public let rootCauses: [String]
    public let drills: [Drill]
    public let source: String  // "openai" | "openai-vision" | "mock"
}

/// A still frame captured at one of the four canonical swing positions.
/// `jpegBase64` is the image data encoded as a base64 string so the whole
/// payload can ride in the same JSON request as the metrics.
public struct SwingKeyframe: Codable, Hashable, Sendable {
    public enum Position: String, Codable, Sendable {
        case address, top, impact, finish
    }

    public let position: Position
    public let jpegBase64: String

    public init(position: Position, jpegBase64: String) {
        self.position = position
        self.jpegBase64 = jpegBase64
    }
}

/// v2 envelope for `POST /coach/swing`. Keeps the API shape stable as
/// features (keyframes, device memory) are added. v1 clients that send
/// a bare `SwingMetrics` still work — the backend accepts either shape.
public struct CoachRequest: Codable, Hashable, Sendable {
    public let metrics: SwingMetrics
    public let keyframes: [SwingKeyframe]
    public let deviceId: String?

    public init(metrics: SwingMetrics, keyframes: [SwingKeyframe] = [], deviceId: String? = nil) {
        self.metrics = metrics
        self.keyframes = keyframes
        self.deviceId = deviceId
    }
}

/// One row returned by `GET /coach/swing/history`.
public struct SwingHistoryEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String { swingId }
    public let swingId: String
    public let ts: Date
    public let metrics: SwingMetrics
    public let report: CoachingReport
}

public struct SwingHistoryResponse: Codable, Hashable, Sendable {
    public let deviceId: String
    public let entries: [SwingHistoryEntry]
}

// MARK: - On-course caddy

public enum Lie: String, Codable, CaseIterable, Sendable {
    case tee, fairway, rough
    case deepRough = "deep_rough"
    case bunker, recovery
}

public enum PinPosition: String, Codable, CaseIterable, Sendable {
    case front, middle, back
}

public enum ShotShape: String, Codable, CaseIterable, Sendable {
    case straight, draw, fade
}

public struct ShotContext: Codable, Hashable, Sendable {
    public var targetDistanceYards: Double
    public var elevationChangeFt: Double
    public var windSpeedMph: Double
    public var windDirectionDeg: Double
    public var lie: Lie
    public var pinPosition: PinPosition?
    public var shotShapePreference: ShotShape?
    public var avoidLeft: Bool
    public var avoidRight: Bool
    public var mustCarryYards: Double?

    // v2 — environment enrichment. The server also fills these when
    // `latitude`/`longitude` are set and a weather API key is configured.
    public var latitude: Double?
    public var longitude: Double?
    public var altitudeFt: Double?
    public var temperatureC: Double?
    public var pressureHpa: Double?
    public var humidityPct: Double?

    // v2 — hazards for the strokes-gained caddy.
    public var hazardLeftYards: Double?
    public var hazardRightYards: Double?

    public init(
        targetDistanceYards: Double,
        elevationChangeFt: Double = 0,
        windSpeedMph: Double = 0,
        windDirectionDeg: Double = 0,
        lie: Lie = .fairway,
        pinPosition: PinPosition? = nil,
        shotShapePreference: ShotShape? = nil,
        avoidLeft: Bool = false,
        avoidRight: Bool = false,
        mustCarryYards: Double? = nil
    ) {
        self.targetDistanceYards = targetDistanceYards
        self.elevationChangeFt = elevationChangeFt
        self.windSpeedMph = windSpeedMph
        self.windDirectionDeg = windDirectionDeg
        self.lie = lie
        self.pinPosition = pinPosition
        self.shotShapePreference = shotShapePreference
        self.avoidLeft = avoidLeft
        self.avoidRight = avoidRight
        self.mustCarryYards = mustCarryYards
    }
}

/// One candidate club with its strokes-gained score for the current shot.
public struct ClubChoice: Codable, Hashable, Sendable, Identifiable {
    public var id: String { clubId }
    public let clubId: String
    public let typicalPlayYards: Double
    public let expectedStrokes: Double
    public let lateralStddevYards: Double
    public let longStddevYards: Double
}

public struct CaddyRecommendation: Codable, Hashable, Sendable {
    public let primaryClubId: String
    public let altClubId: String?
    public let effectiveDistanceYards: Double
    public let windAdjustmentYards: Double
    public let elevationAdjustmentYards: Double
    public let lieAdjustmentYards: Double
    // v2 — all optional for forward compat with v1 servers.
    public let airDensityAdjustmentYards: Double?
    public let expectedStrokes: Double?
    public let candidates: [ClubChoice]?
    public let weatherSource: String?   // "none" | "request" | "openweather"
    public let commentary: String

    public init(
        primaryClubId: String,
        altClubId: String? = nil,
        effectiveDistanceYards: Double,
        windAdjustmentYards: Double,
        elevationAdjustmentYards: Double,
        lieAdjustmentYards: Double,
        airDensityAdjustmentYards: Double? = nil,
        expectedStrokes: Double? = nil,
        candidates: [ClubChoice]? = nil,
        weatherSource: String? = nil,
        commentary: String
    ) {
        self.primaryClubId = primaryClubId
        self.altClubId = altClubId
        self.effectiveDistanceYards = effectiveDistanceYards
        self.windAdjustmentYards = windAdjustmentYards
        self.elevationAdjustmentYards = elevationAdjustmentYards
        self.lieAdjustmentYards = lieAdjustmentYards
        self.airDensityAdjustmentYards = airDensityAdjustmentYards
        self.expectedStrokes = expectedStrokes
        self.candidates = candidates
        self.weatherSource = weatherSource
        self.commentary = commentary
    }
}

// MARK: - JSON coding helpers

public enum CaddyAIJSON {
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
