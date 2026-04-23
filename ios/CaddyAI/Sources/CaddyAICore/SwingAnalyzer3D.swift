import Foundation

// MARK: - 3D primitives

/// 3D joint position, in **meters, camera-space**. +x is right, +y is
/// up, +z points *out of* the screen toward the viewer (so the golfer
/// at address with the camera in front has z ≈ +1.8). This matches
/// Apple Vision's `VNHumanBodyPose3DObservation` world coordinates.
public struct Point3D: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Point3D(x: 0, y: 0, z: 0)

    public func distance(to other: Point3D) -> Double {
        let dx = x - other.x, dy = y - other.y, dz = z - other.z
        return (dx * dx + dy * dy + dz * dz).squareRoot()
    }

    public static func + (a: Point3D, b: Point3D) -> Point3D {
        Point3D(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)
    }

    public static func - (a: Point3D, b: Point3D) -> Point3D {
        Point3D(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z)
    }

    public static func * (a: Point3D, s: Double) -> Point3D {
        Point3D(x: a.x * s, y: a.y * s, z: a.z * s)
    }

    public var length: Double { distance(to: .zero) }

    public func normalized() -> Point3D {
        let l = length
        guard l > 1e-9 else { return .zero }
        return Point3D(x: x / l, y: y / l, z: z / l)
    }

    public func dot(_ other: Point3D) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    public func cross(_ other: Point3D) -> Point3D {
        Point3D(
            x: y * other.z - z * other.y,
            y: z * other.x - x * other.z,
            z: x * other.y - y * other.x
        )
    }
}

/// One frame of 3D body-pose joints. Unlike `PoseFrame`, positions are
/// in real meters — so distances, angles, and attack angle come out in
/// real units without body-scale normalization.
public struct Pose3DFrame: Hashable, Sendable {
    public let timestamp: TimeInterval
    public let joints: [Joint: Point3D]

    public init(timestamp: TimeInterval, joints: [Joint: Point3D]) {
        self.timestamp = timestamp
        self.joints = joints
    }
}

// MARK: - 3D analyzer

/// Produces `SwingMetrics` from a sequence of 3D body-pose frames.
///
/// The pipeline mirrors `SwingAnalyzer` (segment → metrics) but every
/// measurement uses real 3D geometry:
/// - **Shoulder/hip turn** are angles about the vertical (y) axis, so
///   they stay honest regardless of where the camera sits.
/// - **Swing plane** is the tilt of the best-fit plane of the lead-wrist
///   trajectory relative to horizontal.
/// - **Attack angle** is the pitch of the lead-wrist velocity vector at
///   impact. Negative = hitting down.
/// - **Pelvis slide / tilt** come directly from pelvis-center translation
///   and hip-line tilt, in centimeters / degrees.
/// - **Sequencing index** compares the timing of peak rotational
///   velocities of pelvis, torso, and hands. Good sequencing is
///   pelvis → torso → hands, with monotonically increasing peak speeds.
public struct SwingAnalyzer3D: Sendable {
    public init() {}

    public func analyze(
        frames: [Pose3DFrame],
        handedness: Handedness = .right,
        clubKind: ClubKind? = nil
    ) -> SwingMetrics? {
        let required: [Joint] = [
            .leftShoulder, .rightShoulder,
            .leftHip, .rightHip,
            .leftWrist, .rightWrist,
            .nose,
        ]
        let clean = frames.filter { f in required.allSatisfy { f.joints[$0] != nil } }
        guard clean.count >= 10 else { return nil }
        guard let segs = segment(frames: clean, handedness: handedness) else { return nil }
        return metrics(from: clean, segments: segs, handedness: handedness, clubKind: clubKind)
    }

    // MARK: Segmentation

    public func segment(frames: [Pose3DFrame], handedness: Handedness) -> SwingSegments? {
        let leadWrist: Joint = handedness == .right ? .leftWrist : .rightWrist
        guard frames.count >= 10 else { return nil }

        // Top = maximum wrist height (y is up in 3D world coords).
        var topIdx = 0
        var topY = -Double.infinity
        for (i, f) in frames.enumerated() {
            if let w = f.joints[leadWrist], w.y > topY {
                topY = w.y
                topIdx = i
            }
        }
        guard topIdx > 2 && topIdx < frames.count - 3 else { return nil }

        // Impact = highest **downward** wrist speed after top (vy most negative).
        var impactIdx = topIdx + 1
        var maxDownwardSpeed = 0.0
        for i in (topIdx + 1)..<frames.count {
            guard
                let w1 = frames[i - 1].joints[leadWrist],
                let w2 = frames[i].joints[leadWrist]
            else { continue }
            let dt = frames[i].timestamp - frames[i - 1].timestamp
            if dt <= 0 { continue }
            let vy = (w2.y - w1.y) / dt   // m/s, negative = moving down
            if -vy > maxDownwardSpeed {
                maxDownwardSpeed = -vy
                impactIdx = i
            }
        }
        guard impactIdx > topIdx && impactIdx < frames.count else { return nil }

        return SwingSegments(addressIndex: 0, topIndex: topIdx, impactIndex: impactIdx)
    }

    // MARK: Metrics

    public func metrics(
        from frames: [Pose3DFrame],
        segments: SwingSegments,
        handedness: Handedness = .right,
        clubKind: ClubKind? = nil
    ) -> SwingMetrics {
        let a = frames[segments.addressIndex]
        let t = frames[segments.topIndex]
        let i = frames[segments.impactIndex]

        let backswing = t.timestamp - a.timestamp
        let downswing = i.timestamp - t.timestamp
        let tempoRatio = downswing > 0 ? backswing / downswing : 0

        // Turn angles: project the shoulder/hip line onto the horizontal
        // (x-z) plane and measure rotation about vertical between address
        // and top. This is the "real" biomechanical number.
        let shoulderTurn = abs(horizontalTurnDeg(
            from: a, to: t,
            left: .leftShoulder, right: .rightShoulder
        ))
        let hipTurn = abs(horizontalTurnDeg(
            from: a, to: t,
            left: .leftHip, right: .rightHip
        ))
        let xFactor = shoulderTurn - hipTurn

        // Pelvis slide: horizontal (x,z) translation of pelvis center
        // from address to top. Positive only — direction isn't useful
        // for the metric itself.
        let pelvisA = pelvisCenter(a)
        let pelvisT = pelvisCenter(t)
        let slide = hypot(pelvisT.x - pelvisA.x, pelvisT.z - pelvisA.z) * 100.0 // → cm

        // Pelvis tilt at impact: angle of hip line from horizontal in
        // the frontal plane (y vs lateral).
        let tiltDeg: Double
        if let lh = i.joints[.leftHip], let rh = i.joints[.rightHip] {
            let lateral = hypot(rh.x - lh.x, rh.z - lh.z)
            let vertical = rh.y - lh.y
            tiltDeg = atan2(vertical, max(lateral, 1e-6)) * 180.0 / .pi
        } else {
            tiltDeg = 0
        }

        // Swing plane: tilt of the best-fit plane of the lead-wrist
        // trajectory between address and a few frames past impact.
        let leadWrist: Joint = handedness == .right ? .leftWrist : .rightWrist
        let traj = frames[segments.addressIndex...min(segments.impactIndex + 3, frames.count - 1)]
            .compactMap { $0.joints[leadWrist] }
        let plane = planeTiltDeg(points: traj)

        // Attack angle: pitch of the lead-wrist velocity vector in the
        // 3–5 frames around impact.
        let attack = attackAngleDeg(frames: frames, impact: segments.impactIndex, leadWrist: leadWrist)

        // Sway (lateral-only) and head movement, in real cm.
        let leadHip: Joint = handedness == .right ? .leftHip : .rightHip
        let sway: Double
        if let hipA = a.joints[leadHip], let hipT = t.joints[leadHip] {
            sway = abs(hipT.x - hipA.x) * 100.0
        } else { sway = 0 }

        let headMove: Double
        if let nA = a.joints[.nose], let nI = i.joints[.nose] {
            headMove = hypot(hypot(nI.x - nA.x, nI.z - nA.z), nI.y - nA.y) * 100.0
        } else { headMove = 0 }

        // Early extension = pelvis-center has moved toward the camera
        // (positive z) at impact relative to address.
        let earlyExt = abs(pelvisCenter(i).z - pelvisA.z) * 100.0

        // Weight transfer: x-projection of pelvis center between the two
        // ankles at impact. Handedness determines which ankle is "lead".
        let weight = weightTransferPct(frame: i, handedness: handedness)

        // Kinematic sequence: relative timing of pelvis / torso / hand
        // peak angular velocity during the downswing.
        let seq = sequencingIndex(
            frames: frames,
            top: segments.topIndex,
            impact: segments.impactIndex,
            handedness: handedness
        )

        let confidence = min(1.0, Double(frames.count) / 60.0)

        return SwingMetrics(
            tempoRatio: tempoRatio,
            backswingSec: backswing,
            downswingSec: downswing,
            peakShoulderTurnDeg: shoulderTurn,
            peakHipTurnDeg: hipTurn,
            xFactorDeg: xFactor,
            lateralSwayCm: sway,
            headMovementCm: headMove,
            earlyExtensionCm: earlyExt,
            swingPlaneDeg: plane,
            weightTransferPct: weight,
            confidence: confidence,
            handedness: handedness,
            clubKind: clubKind,
            viewpoint: .pose3D,
            attackAngleDeg: attack,
            pelvisSlideCm: slide,
            pelvisTiltDeg: tiltDeg,
            sequencingIndex: seq,
            clubPathDeg: nil
        )
    }

    // MARK: - Geometry helpers

    private func pelvisCenter(_ f: Pose3DFrame) -> Point3D {
        guard let l = f.joints[.leftHip], let r = f.joints[.rightHip] else { return .zero }
        return (l + r) * 0.5
    }

    /// Rotation about the vertical axis (y) between the angle of the
    /// `left`→`right` vector at two frames. Returned in degrees.
    private func horizontalTurnDeg(
        from a: Pose3DFrame,
        to b: Pose3DFrame,
        left: Joint,
        right: Joint
    ) -> Double {
        func angle(_ f: Pose3DFrame) -> Double? {
            guard let l = f.joints[left], let r = f.joints[right] else { return nil }
            return atan2(r.z - l.z, r.x - l.x)
        }
        guard let ang1 = angle(a), let ang2 = angle(b) else { return 0 }
        var delta = (ang2 - ang1) * 180.0 / .pi
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        return delta
    }

    /// Fit a plane to the trajectory and return its tilt from horizontal.
    /// We use a simple covariance-eigen trick: the plane's normal is the
    /// eigenvector of the point-cloud covariance with the smallest
    /// eigenvalue. Power-iteration is fine for 3×3.
    private func planeTiltDeg(points: [Point3D]) -> Double {
        guard points.count >= 3 else { return 0 }
        let mean = points.reduce(Point3D.zero, +) * (1.0 / Double(points.count))
        var cov = [[Double]](repeating: [0, 0, 0], count: 3)
        for p in points {
            let d = p - mean
            let v = [d.x, d.y, d.z]
            for i in 0..<3 {
                for j in 0..<3 {
                    cov[i][j] += v[i] * v[j]
                }
            }
        }
        // Invert cov (or skip if singular) and power-iterate to get the
        // smallest-eigenvalue vector. For a rank-3 positive-definite
        // matrix, `inv^k v` converges to that eigenvector.
        guard let inv = invert3x3(cov) else { return 0 }
        var v = [1.0, 0.0, 0.0]
        for _ in 0..<32 {
            v = mul3x3Vec(inv, v)
            let n = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).squareRoot()
            if n < 1e-12 { break }
            v = [v[0] / n, v[1] / n, v[2] / n]
        }
        // Tilt = angle of the plane's normal to vertical → plane angle
        // from horizontal = 90° − that. Equivalently: the plane's
        // steepness is the angle of its normal *away from* vertical.
        let dotY = abs(v[1])
        let normalFromY = acos(min(1, max(-1, dotY))) * 180.0 / .pi
        return 90.0 - normalFromY
    }

    private func attackAngleDeg(frames: [Pose3DFrame], impact: Int, leadWrist: Joint) -> Double {
        // Use a 3-frame window centered on impact (or clamped to edges).
        let lo = max(0, impact - 1)
        let hi = min(frames.count - 1, impact + 1)
        guard lo < hi else { return 0 }
        guard
            let w1 = frames[lo].joints[leadWrist],
            let w2 = frames[hi].joints[leadWrist]
        else { return 0 }
        let dt = frames[hi].timestamp - frames[lo].timestamp
        if dt <= 0 { return 0 }
        let dy = w2.y - w1.y
        let dh = hypot(w2.x - w1.x, w2.z - w1.z)
        // Negative when descending (y decreasing).
        return atan2(dy, max(dh, 1e-6)) * 180.0 / .pi
    }

    private func weightTransferPct(frame f: Pose3DFrame, handedness: Handedness) -> Double {
        let leadAnkle: Joint = handedness == .right ? .leftAnkle : .rightAnkle
        let trailAnkle: Joint = handedness == .right ? .rightAnkle : .leftAnkle
        guard
            let la = f.joints[leadAnkle],
            let ta = f.joints[trailAnkle],
            let lh = f.joints[.leftHip],
            let rh = f.joints[.rightHip]
        else { return 50 }
        let hipX = (lh.x + rh.x) / 2
        let laX = la.x, taX = ta.x
        let lo = min(laX, taX), hi = max(laX, taX)
        guard hi - lo > 1e-6 else { return 50 }
        let t = max(0, min(1, (hipX - lo) / (hi - lo)))
        // How close is mid-hip to the lead ankle (0..1)?
        let leadIsLowX = laX < taX
        let leadFraction = leadIsLowX ? (1 - t) : t
        return leadFraction * 100.0
    }

    /// Sequencing index ∈ 0…1.
    ///
    /// Good sequence: pelvis peak angular velocity fires first, then
    /// torso, then hands, all during the downswing (top → impact). We
    /// score the *order* by checking pairwise correctness and return
    /// the fraction of pairs in the right order (3 pairs → 0, 0.33,
    /// 0.66, 1.0). If any segment is missing data we fall back to 0.5.
    private func sequencingIndex(
        frames: [Pose3DFrame],
        top: Int,
        impact: Int,
        handedness: Handedness
    ) -> Double {
        guard impact - top >= 3 else { return 0.5 }
        let leadWrist: Joint = handedness == .right ? .leftWrist : .rightWrist

        func peakAngleChangeFrame(segment: (Pose3DFrame) -> Double?) -> Int? {
            var best = -Double.infinity
            var bestIdx: Int?
            for i in (top + 1)...impact {
                guard
                    let a1 = segment(frames[i - 1]),
                    let a2 = segment(frames[i])
                else { continue }
                let dt = frames[i].timestamp - frames[i - 1].timestamp
                if dt <= 0 { continue }
                var d = abs(a2 - a1)
                if d > 180 { d = 360 - d }
                let w = d / dt
                if w > best {
                    best = w
                    bestIdx = i
                }
            }
            return bestIdx
        }

        let hipsPeak = peakAngleChangeFrame { f in
            guard let l = f.joints[.leftHip], let r = f.joints[.rightHip] else { return nil }
            return atan2(r.z - l.z, r.x - l.x) * 180.0 / .pi
        }
        let shouldersPeak = peakAngleChangeFrame { f in
            guard let l = f.joints[.leftShoulder], let r = f.joints[.rightShoulder] else { return nil }
            return atan2(r.z - l.z, r.x - l.x) * 180.0 / .pi
        }
        // Hand "angle" proxy: horizontal angle of lead wrist relative to
        // pelvis center. Sharpest change late in the downswing → good.
        let handsPeak = peakAngleChangeFrame { f in
            guard let w = f.joints[leadWrist] else { return nil }
            let lh = f.joints[.leftHip] ?? .zero
            let rh = f.joints[.rightHip] ?? .zero
            let pc = (lh + rh) * 0.5
            return atan2(w.z - pc.z, w.x - pc.x) * 180.0 / .pi
        }

        guard let h = hipsPeak, let s = shouldersPeak, let n = handsPeak else { return 0.5 }
        var correct = 0
        var total = 0
        for (a, b) in [(h, s), (s, n), (h, n)] {
            total += 1
            if a <= b { correct += 1 }
        }
        return Double(correct) / Double(total)
    }
}

// MARK: - Tiny 3×3 matrix helpers (Linux-friendly, no Accelerate)

private func invert3x3(_ m: [[Double]]) -> [[Double]]? {
    let a = m[0][0], b = m[0][1], c = m[0][2]
    let d = m[1][0], e = m[1][1], f = m[1][2]
    let g = m[2][0], h = m[2][1], i = m[2][2]
    let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    guard abs(det) > 1e-12 else { return nil }
    let inv = 1.0 / det
    return [
        [(e * i - f * h) * inv, (c * h - b * i) * inv, (b * f - c * e) * inv],
        [(f * g - d * i) * inv, (a * i - c * g) * inv, (c * d - a * f) * inv],
        [(d * h - e * g) * inv, (b * g - a * h) * inv, (a * e - b * d) * inv],
    ]
}

private func mul3x3Vec(_ m: [[Double]], _ v: [Double]) -> [Double] {
    [
        m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
        m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
        m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2],
    ]
}
