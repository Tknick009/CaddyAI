import Foundation

/// A single detection of the club-head in one video frame.
///
/// `position` is in *normalized image coordinates* (0..1, origin top-left),
/// matching what Apple Vision returns. `confidence` is the detector's
/// own confidence in [0, 1]. We keep the types here pure-Swift so the
/// whole analyzer is unit-testable on Linux without the Vision framework.
public struct ClubHeadPoint: Hashable, Sendable {
    public let timestamp: TimeInterval
    public let position: Point2D
    public let confidence: Double

    public init(timestamp: TimeInterval, position: Point2D, confidence: Double = 1.0) {
        self.timestamp = timestamp
        self.position = position
        self.confidence = confidence
    }
}

/// Camera calibration required to convert pixel motion into real-world
/// speed. Real trajectory math would want full intrinsics + a ground
/// plane; we deliberately take the cheap road: the user marks a known
/// physical reference (the golfer's shoulder-to-hip distance, or a
/// visible yard stick). `yardsPerNormalizedUnit` is how many yards of
/// physical distance one full width of the captured frame corresponds
/// to *at the ball's distance from the camera*. For a phone on a
/// tripod 3 yards behind the player with a 60° horizontal FOV, this is
/// roughly `2 * 3 * tan(30°) ≈ 3.46` yards per image width.
public struct CameraCalibration: Hashable, Sendable {
    public let yardsPerNormalizedUnit: Double
    public let frameRate: Double

    public init(yardsPerNormalizedUnit: Double, frameRate: Double = 120) {
        self.yardsPerNormalizedUnit = yardsPerNormalizedUnit
        self.frameRate = frameRate
    }
}

/// Metrics derived from a club-head track at impact.
public struct ClubHeadMetrics: Hashable, Sendable {
    /// Club-head speed in mph at impact (or nil if we can't estimate it).
    public let speedMph: Double
    /// Club path angle at impact (°). 0 = straight at target.
    /// Positive = in-to-out for a right-handed player, negative = out-to-in.
    public let pathDeg: Double
    /// Attack angle (°). Negative = hitting down on the ball.
    public let attackAngleDeg: Double
    /// Frame index in the track we judged to be "impact".
    public let impactIndex: Int

    public init(speedMph: Double, pathDeg: Double, attackAngleDeg: Double, impactIndex: Int) {
        self.speedMph = speedMph
        self.pathDeg = pathDeg
        self.attackAngleDeg = attackAngleDeg
        self.impactIndex = impactIndex
    }
}

/// Compute club-head metrics from a sequence of tracked points.
///
/// Two stable things we can get from a pixel track + a yardage scale:
/// 1. **Impact** — the frame where the club-head is at its fastest
///    (peak pixel velocity). In a real swing this coincides with ball
///    contact to within 1-2 frames at 120 fps.
/// 2. **Direction** — the instantaneous velocity vector at impact,
///    decomposed into along-target (horizontal) and vertical
///    components.
///
/// We smooth the track with a 3-frame moving average first to kill
/// detector jitter, then differentiate with a central difference.
public enum ClubHeadAnalyzer {

    public enum Error: Swift.Error, Equatable {
        case notEnoughPoints
        case zeroDuration
    }

    /// Smoothed (x, y) velocity magnitude in normalized-units-per-second,
    /// centered-difference at each interior frame.
    public static func velocities(_ track: [ClubHeadPoint]) -> [Point2D] {
        guard track.count >= 2 else { return [] }
        var out: [Point2D] = []
        for i in 0..<track.count {
            let j0 = max(0, i - 1)
            let j1 = min(track.count - 1, i + 1)
            let dt = track[j1].timestamp - track[j0].timestamp
            if dt <= 0 {
                out.append(Point2D(x: 0, y: 0))
                continue
            }
            out.append(Point2D(
                x: (track[j1].position.x - track[j0].position.x) / dt,
                y: (track[j1].position.y - track[j0].position.y) / dt
            ))
        }
        return out
    }

    /// Index of the frame with maximum 2-D speed. Defaults to the last
    /// frame's delta if the track is too short to differentiate.
    public static func impactIndex(_ track: [ClubHeadPoint]) -> Int {
        let vels = velocities(track)
        var best = 0
        var bestMag = -1.0
        for (i, v) in vels.enumerated() {
            let m = v.x * v.x + v.y * v.y
            if m > bestMag {
                bestMag = m
                best = i
            }
        }
        return best
    }

    /// Full metrics block for a track. Coordinate conventions:
    /// - Image origin is top-left, so *positive y-velocity means moving
    ///   down*, which at impact is the downswing — hence the sign flip
    ///   when reporting attack angle (negative = hitting down on ball).
    /// - Target line is assumed to be horizontal in the image (face-on
    ///   or down-the-line capture). Club path is measured against that.
    public static func analyze(
        _ track: [ClubHeadPoint],
        calibration: CameraCalibration,
        handedness: Handedness = .right
    ) throws -> ClubHeadMetrics {
        guard track.count >= 3 else { throw Error.notEnoughPoints }
        let impact = impactIndex(track)
        let vels = velocities(track)
        guard impact < vels.count else { throw Error.notEnoughPoints }
        let v = vels[impact]

        // Convert normalized-units-per-second to yards-per-second, then to mph.
        let ypsX = v.x * calibration.yardsPerNormalizedUnit
        let ypsY = v.y * calibration.yardsPerNormalizedUnit
        let speedYps = (ypsX * ypsX + ypsY * ypsY).squareRoot()
        let mph = speedYps * 3600.0 / 1760.0   // 1 mile = 1760 yards

        // Use a 5-frame window centred on impact to estimate direction
        // (less sensitive to detector jitter than the central velocity
        // sample alone).
        let windowStart = max(0, impact - 2)
        let windowEnd = min(track.count - 1, impact + 2)
        let dx = track[windowEnd].position.x - track[windowStart].position.x
        let dy = track[windowEnd].position.y - track[windowStart].position.y
        let forwardMag = abs(dx)
        // Path: lateral deviation (-dy) vs forward motion (|dx|). With a
        // single camera we conflate lateral miss and vertical pitch;
        // the ball-flight model in `coach` handles the residual
        // uncertainty. Zero forward motion → path undefined; return 0.
        let rhPath = forwardMag == 0 ? 0 : atan2(-dy, forwardMag) * 180.0 / .pi
        // Left-handed mirrors: camera sees the player from the other
        // side, so an identical pixel trajectory is the opposite path.
        let pathDegOut = handedness == .right ? rhPath : -rhPath
        // Attack angle: vertical pitch of the velocity vector. Image-y
        // grows *downward*, so negative y-velocity = club moving up at
        // impact. Flip the sign so "negative = hitting down on the ball"
        // matches the launch-monitor convention.
        let attackDeg = atan2(-v.y, forwardMag) * 180.0 / .pi

        return ClubHeadMetrics(
            speedMph: mph,
            pathDeg: pathDegOut,
            attackAngleDeg: attackDeg,
            impactIndex: impact
        )
    }
}
