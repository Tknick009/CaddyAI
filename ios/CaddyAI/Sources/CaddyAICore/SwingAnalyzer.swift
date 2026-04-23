import Foundation

/// A 2D point in normalized image coordinates (0...1 in both axes).
/// We deliberately don't use `CGPoint` here because `Foundation.CGPoint`
/// on Linux isn't `Hashable`/`Sendable`, which breaks our cross-platform
/// test build. Callers on iOS can convert to/from `CGPoint` trivially.
public struct Point2D: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    public static let zero = Point2D(x: 0, y: 0)
}

/// A single frame of extracted body-pose joints, in normalized image
/// coordinates (0...1 in both axes). `nil` means the joint was not
/// detected with sufficient confidence and the frame should be skipped.
public struct PoseFrame: Hashable, Sendable {
    public let timestamp: TimeInterval
    public let joints: [Joint: Point2D]

    public init(timestamp: TimeInterval, joints: [Joint: Point2D]) {
        self.timestamp = timestamp
        self.joints = joints
    }
}

/// The subset of Apple Vision's `VNHumanBodyPoseObservation.JointName`s
/// that the swing analyzer actually uses. Keeping this as its own enum
/// means `CaddyAICore` stays Foundation-only and Linux-buildable.
public enum Joint: String, Hashable, Sendable {
    case nose
    case leftShoulder, rightShoulder
    case leftHip, rightHip
    case leftWrist, rightWrist
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
}

/// Output of the swing segmenter.
public struct SwingSegments: Hashable, Sendable {
    public let addressIndex: Int
    public let topIndex: Int
    public let impactIndex: Int
}

public struct SwingAnalyzer: Sendable {
    public init() {}

    /// Run the full pipeline: segment the swing, then compute metrics.
    ///
    /// Returns `nil` if the frames don't look like a swing — e.g. fewer
    /// than 10 usable frames or we can't find a plausible top-of-swing.
    public func analyze(frames: [PoseFrame], handedness: Handedness = .right, clubKind: ClubKind? = nil) -> SwingMetrics? {
        let clean = frames.filter { frame in
            // Require the core joints for segmentation.
            let required: [Joint] = [.leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftWrist, .rightWrist, .nose]
            return required.allSatisfy { frame.joints[$0] != nil }
        }
        guard clean.count >= 10 else { return nil }
        guard let segments = segment(frames: clean, handedness: handedness) else { return nil }
        return metrics(from: clean, segments: segments, handedness: handedness, clubKind: clubKind)
    }

    // MARK: - Segmentation

    /// Find address, top-of-swing, and impact frames.
    ///
    /// Strategy:
    /// - address = first frame
    /// - top     = frame with the smallest lead-wrist Y (highest in image coords)
    /// - impact  = frame with the largest lead-wrist *downward* velocity after top
    public func segment(frames: [PoseFrame], handedness: Handedness) -> SwingSegments? {
        let leadWrist: Joint = handedness == .right ? .leftWrist : .rightWrist
        guard frames.count >= 10 else { return nil }

        let addressIdx = 0

        // Top of swing: minimum Y of lead wrist (image Y grows downward).
        var topIdx = 0
        var topY = Double.infinity
        for (i, f) in frames.enumerated() {
            if let w = f.joints[leadWrist] {
                if Double(w.y) < topY {
                    topY = Double(w.y)
                    topIdx = i
                }
            }
        }
        guard topIdx > 2 && topIdx < frames.count - 3 else { return nil }

        // Impact: highest downward velocity of lead wrist after top.
        var impactIdx = topIdx + 1
        var maxDownVel = -Double.infinity
        for i in (topIdx + 1)..<frames.count {
            guard
                let w1 = frames[i - 1].joints[leadWrist],
                let w2 = frames[i].joints[leadWrist]
            else { continue }
            let dt = frames[i].timestamp - frames[i - 1].timestamp
            if dt <= 0 { continue }
            let vy = Double(w2.y - w1.y) / dt  // positive = moving down the image
            if vy > maxDownVel {
                maxDownVel = vy
                impactIdx = i
            }
        }
        // Impact frame must be after top and before the last frame.
        guard impactIdx > topIdx && impactIdx < frames.count else { return nil }

        return SwingSegments(addressIndex: addressIdx, topIndex: topIdx, impactIndex: impactIdx)
    }

    // MARK: - Metrics

    public func metrics(
        from frames: [PoseFrame],
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

        let shoulderTurn = shoulderLineDeg(at: t) - shoulderLineDeg(at: a)
        let hipTurn = hipLineDeg(at: t) - hipLineDeg(at: a)
        let xFactor = abs(shoulderTurn) - abs(hipTurn)

        // Lateral sway: how far the lead hip has moved laterally from address
        // to top, in the plane of the image, normalized to body scale.
        let bodyScale = shoulderWidthPx(a)
        let leadHip: Joint = handedness == .right ? .leftHip : .rightHip
        let sway: Double
        if
            let hipAddr = a.joints[leadHip],
            let hipTop = t.joints[leadHip]
        {
            let dxPx = Double(hipTop.x - hipAddr.x)
            // body scale ~ shoulder width ≈ 40 cm for most adults
            sway = abs(dxPx / max(bodyScale, 0.0001)) * 40.0
        } else {
            sway = 0
        }

        // Head movement (total nose displacement from address to impact).
        let headMove: Double
        if let n1 = a.joints[.nose], let n2 = i.joints[.nose] {
            let dx = Double(n2.x - n1.x)
            let dy = Double(n2.y - n1.y)
            let dist = (dx * dx + dy * dy).squareRoot()
            // Nose -> pelvis vertical span ≈ 60 cm for most adults.
            let bodyHeightPx = hipToNoseHeightPx(a)
            headMove = dist / max(bodyHeightPx, 0.0001) * 60.0
        } else {
            headMove = 0
        }

        // Early extension: forward movement of pelvis mid-point at impact
        // relative to address. In a 2D image this is approximated by the
        // Y-shift of the mid-hip relative to the shoulders.
        let earlyExt = earlyExtensionCm(address: a, impact: i)

        // Swing plane: angle of the line from trail shoulder to lead wrist
        // at the top of the swing.
        let trailShoulder: Joint = handedness == .right ? .rightShoulder : .leftShoulder
        let leadWrist: Joint = handedness == .right ? .leftWrist : .rightWrist
        let plane: Double
        if let sh = t.joints[trailShoulder], let wr = t.joints[leadWrist] {
            let dx = Double(wr.x - sh.x)
            let dy = Double(wr.y - sh.y)
            plane = abs(atan2(dy, dx) * 180.0 / .pi)
        } else {
            plane = 0
        }

        // Weight transfer (very approximate from 2D): horizontal position
        // of the mid-hip between the ankles at impact.
        let weight = weightTransferPct(at: i, handedness: handedness)

        // Confidence: how many frames were usable of how many expected.
        let confidence = min(1.0, Double(frames.count) / 60.0)

        return SwingMetrics(
            tempoRatio: tempoRatio,
            backswingSec: backswing,
            downswingSec: downswing,
            peakShoulderTurnDeg: abs(shoulderTurn),
            peakHipTurnDeg: abs(hipTurn),
            xFactorDeg: xFactor,
            lateralSwayCm: sway,
            headMovementCm: headMove,
            earlyExtensionCm: earlyExt,
            swingPlaneDeg: plane,
            weightTransferPct: weight,
            confidence: confidence,
            handedness: handedness,
            clubKind: clubKind
        )
    }

    // MARK: - Geometry helpers

    private func shoulderLineDeg(at f: PoseFrame) -> Double {
        guard let l = f.joints[.leftShoulder], let r = f.joints[.rightShoulder] else { return 0 }
        return atan2(Double(r.y - l.y), Double(r.x - l.x)) * 180.0 / .pi
    }

    private func hipLineDeg(at f: PoseFrame) -> Double {
        guard let l = f.joints[.leftHip], let r = f.joints[.rightHip] else { return 0 }
        return atan2(Double(r.y - l.y), Double(r.x - l.x)) * 180.0 / .pi
    }

    private func shoulderWidthPx(_ f: PoseFrame) -> Double {
        guard let l = f.joints[.leftShoulder], let r = f.joints[.rightShoulder] else { return 1 }
        let dx = Double(r.x - l.x)
        let dy = Double(r.y - l.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    private func hipToNoseHeightPx(_ f: PoseFrame) -> Double {
        guard
            let nose = f.joints[.nose],
            let lHip = f.joints[.leftHip],
            let rHip = f.joints[.rightHip]
        else { return 1 }
        let midHipY = Double(lHip.y + rHip.y) / 2
        return abs(midHipY - Double(nose.y))
    }

    private func earlyExtensionCm(address: PoseFrame, impact: PoseFrame) -> Double {
        guard
            let lhA = address.joints[.leftHip],
            let rhA = address.joints[.rightHip],
            let lsA = address.joints[.leftShoulder],
            let rsA = address.joints[.rightShoulder],
            let lhI = impact.joints[.leftHip],
            let rhI = impact.joints[.rightHip],
            let lsI = impact.joints[.leftShoulder],
            let rsI = impact.joints[.rightShoulder]
        else { return 0 }
        let hipY_A = Double(lhA.y + rhA.y) / 2
        let shY_A = Double(lsA.y + rsA.y) / 2
        let hipY_I = Double(lhI.y + rhI.y) / 2
        let shY_I = Double(lsI.y + rsI.y) / 2
        // Pelvis-to-shoulder distance as our ruler (≈ 50 cm average).
        let scaleA = abs(hipY_A - shY_A)
        // How much the shoulder has risen relative to the pelvis at impact.
        // Positive = pelvis pushed toward ball = early extension.
        let extPx = (shY_I - hipY_I) - (shY_A - hipY_A)
        return abs(extPx) / max(scaleA, 0.0001) * 50.0
    }

    private func weightTransferPct(at f: PoseFrame, handedness: Handedness) -> Double {
        let leadAnkle: Joint = handedness == .right ? .leftAnkle : .rightAnkle
        let trailAnkle: Joint = handedness == .right ? .rightAnkle : .leftAnkle
        guard
            let la = f.joints[leadAnkle],
            let ta = f.joints[trailAnkle],
            let lh = f.joints[.leftHip],
            let rh = f.joints[.rightHip]
        else { return 50 }
        let midHipX = Double(lh.x + rh.x) / 2
        let leftX = Double(min(la.x, ta.x))
        let rightX = Double(max(la.x, ta.x))
        let span = max(rightX - leftX, 0.0001)
        // How far between the two ankles the mid-hip is, normalized to 0..1.
        var t = (midHipX - leftX) / span
        t = max(0, min(1, t))
        // For a right-handed swing the lead foot is the left one (smaller X in
        // a face-on view from the camera's perspective — but this depends on
        // camera orientation). We'll assume the camera is facing the golfer
        // and the lead foot is on the "target" side. Return % on lead foot.
        if handedness == .right {
            // Lead (left) foot tends to be at smaller X in a mirrored view.
            return (1 - t) * 100
        } else {
            return t * 100
        }
    }
}
