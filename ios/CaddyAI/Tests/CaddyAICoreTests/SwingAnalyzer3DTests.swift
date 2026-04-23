import XCTest
@testable import CaddyAICore

final class SwingAnalyzer3DTests: XCTestCase {
    /// Address pose, roughly a person facing +z (camera in front). Units
    /// are meters. Feet at y=0; head at y≈1.7.
    static let addressJoints: [Joint: Point3D] = [
        .nose:           Point3D(x: 0.00, y: 1.70, z: 0.00),
        .leftShoulder:   Point3D(x: -0.20, y: 1.45, z: 0.00),
        .rightShoulder:  Point3D(x: 0.20, y: 1.45, z: 0.00),
        .leftHip:        Point3D(x: -0.12, y: 1.00, z: 0.00),
        .rightHip:       Point3D(x: 0.12, y: 1.00, z: 0.00),
        .leftWrist:      Point3D(x: 0.05, y: 0.80, z: 0.30),
        .rightWrist:     Point3D(x: 0.10, y: 0.80, z: 0.30),
        .leftKnee:       Point3D(x: -0.12, y: 0.55, z: 0.05),
        .rightKnee:      Point3D(x: 0.12, y: 0.55, z: 0.05),
        .leftAnkle:      Point3D(x: -0.16, y: 0.05, z: 0.00),
        .rightAnkle:     Point3D(x: 0.16, y: 0.05, z: 0.00),
    ]

    /// Build a synthetic right-handed 3D swing:
    /// - Shoulders rotate from 0° (facing +z camera) to ~85° at top,
    ///   hips rotate to ~45°; both unwind back to neutral at impact.
    /// - The lead wrist arcs up-and-back during backswing, then cuts
    ///   down-and-through with a quadratic ease-in on the downswing so
    ///   peak velocity is near impact.
    /// - 120 fps capture.
    func makeSyntheticSwing() -> [Pose3DFrame] {
        let fps = 120.0
        let backswingFrames = 36
        let downswingFrames = 14
        let followThroughFrames = 18

        let shoulderTopDeg = 85.0
        let hipTopDeg = 45.0
        let topWristY = 1.80
        let topWristX = 0.60        // hands over trail shoulder
        let topWristZ = -0.25       // slightly behind the golfer
        let addressWrist = Self.addressJoints[.leftWrist]!

        var frames: [Pose3DFrame] = []

        func rotatedJoints(shoulderDeg: Double, hipDeg: Double) -> [Joint: Point3D] {
            var out = Self.addressJoints
            let sR = shoulderDeg * .pi / 180.0
            let hR = hipDeg * .pi / 180.0
            // Rotate shoulder endpoints about y axis around the spine center.
            let sc = (out[.leftShoulder]! + out[.rightShoulder]!) * 0.5
            for j in [Joint.leftShoulder, .rightShoulder] {
                let p = out[j]!
                let dx = p.x - sc.x
                let dz = p.z - sc.z
                out[j] = Point3D(
                    x: sc.x + dx * cos(sR) + dz * sin(sR),
                    y: p.y,
                    z: sc.z - dx * sin(sR) + dz * cos(sR)
                )
            }
            let hc = (out[.leftHip]! + out[.rightHip]!) * 0.5
            for j in [Joint.leftHip, .rightHip] {
                let p = out[j]!
                let dx = p.x - hc.x
                let dz = p.z - hc.z
                out[j] = Point3D(
                    x: hc.x + dx * cos(hR) + dz * sin(hR),
                    y: p.y,
                    z: hc.z - dx * sin(hR) + dz * cos(hR)
                )
            }
            return out
        }

        // Backswing.
        for i in 0..<backswingFrames {
            let t = Double(i) / Double(backswingFrames - 1)
            var j = rotatedJoints(shoulderDeg: shoulderTopDeg * t, hipDeg: hipTopDeg * t)
            j[.leftWrist] = Point3D(
                x: addressWrist.x + (topWristX - addressWrist.x) * t,
                y: addressWrist.y + (topWristY - addressWrist.y) * t,
                z: addressWrist.z + (topWristZ - addressWrist.z) * t
            )
            j[.rightWrist] = j[.leftWrist]
            frames.append(Pose3DFrame(timestamp: Double(frames.count) / fps, joints: j))
        }

        // Downswing.
        let impactWristY = 0.80
        let impactWristX = 0.10
        let impactWristZ = 0.30
        for i in 0..<downswingFrames {
            let t = Double(i + 1) / Double(downswingFrames)
            let eased = t * t
            // Hips start unwinding first (scale by 1.1 × t), shoulders follow (t²).
            let hipAngle = hipTopDeg * (1 - min(1, t * 1.1))
            let shoulderAngle = shoulderTopDeg * (1 - eased)
            var j = rotatedJoints(shoulderDeg: shoulderAngle, hipDeg: hipAngle)
            j[.leftWrist] = Point3D(
                x: topWristX + (impactWristX - topWristX) * eased,
                y: topWristY + (impactWristY - topWristY) * eased,
                z: topWristZ + (impactWristZ - topWristZ) * eased
            )
            j[.rightWrist] = j[.leftWrist]
            frames.append(Pose3DFrame(timestamp: Double(frames.count) / fps, joints: j))
        }

        // Follow-through.
        for i in 0..<followThroughFrames {
            let t = Double(i + 1) / Double(followThroughFrames)
            var j = rotatedJoints(shoulderDeg: -30 * t, hipDeg: -20 * t)
            j[.leftWrist] = Point3D(
                x: impactWristX - 0.5 * t,
                y: impactWristY + 0.7 * t,
                z: impactWristZ - 0.1 * t
            )
            j[.rightWrist] = j[.leftWrist]
            frames.append(Pose3DFrame(timestamp: Double(frames.count) / fps, joints: j))
        }
        return frames
    }

    func testAnalyze3DProducesHonestMetrics() throws {
        let metrics = try XCTUnwrap(SwingAnalyzer3D().analyze(frames: makeSyntheticSwing()))
        XCTAssertEqual(metrics.viewpoint, .pose3D)
        XCTAssertEqual(metrics.tempoRatio, 3.0, accuracy: 0.6)
        // 3D shoulder turn should recover close to the 85° we injected.
        XCTAssertEqual(metrics.peakShoulderTurnDeg, 85, accuracy: 15)
        XCTAssertEqual(metrics.peakHipTurnDeg, 45, accuracy: 15)
        XCTAssertGreaterThan(metrics.xFactorDeg, 20)
        // Attack angle should be negative (hitting down on an iron).
        let attack = try XCTUnwrap(metrics.attackAngleDeg)
        XCTAssertLessThan(attack, 0)
        XCTAssertGreaterThan(attack, -80)
        // Sequencing: hips started unwinding before shoulders, so score
        // should be ≥ 0.33 (pelvis→torso pair correct at minimum).
        let seq = try XCTUnwrap(metrics.sequencingIndex)
        XCTAssertGreaterThanOrEqual(seq, 0.33)
        // Pelvis slide was injected as ~0 (we only rotated, didn't slide),
        // so should be below a few cm.
        let slide = try XCTUnwrap(metrics.pelvisSlideCm)
        XCTAssertLessThan(slide, 10)
    }

    func testSegment3DFindsTopBeforeImpact() throws {
        let frames = makeSyntheticSwing()
        let segs = try XCTUnwrap(SwingAnalyzer3D().segment(frames: frames, handedness: .right))
        XCTAssertEqual(segs.addressIndex, 0)
        XCTAssertGreaterThan(segs.topIndex, 10)
        XCTAssertLessThan(segs.topIndex, frames.count - 3)
        XCTAssertGreaterThan(segs.impactIndex, segs.topIndex)
    }

    func testAnalyze3DRejectsTooFewFrames() {
        let short = Array(makeSyntheticSwing().prefix(5))
        XCTAssertNil(SwingAnalyzer3D().analyze(frames: short))
    }

    func testSwingMetricsRoundTripWithNew3DFields() throws {
        let m = SwingMetrics(
            tempoRatio: 3.0, backswingSec: 0.9, downswingSec: 0.3,
            peakShoulderTurnDeg: 85, peakHipTurnDeg: 45, xFactorDeg: 40,
            lateralSwayCm: 2, headMovementCm: 3, earlyExtensionCm: 1,
            swingPlaneDeg: 58, weightTransferPct: 80, confidence: 0.9,
            handedness: .right, clubKind: .iron,
            viewpoint: .pose3D,
            attackAngleDeg: -4.5,
            pelvisSlideCm: 5.0,
            pelvisTiltDeg: 8.0,
            sequencingIndex: 0.85,
            clubPathDeg: nil
        )
        let data = try CaddyAIJSON.encoder.encode(m)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("attack_angle_deg"))
        XCTAssertTrue(json.contains("\"pose3d\""))
        XCTAssertTrue(json.contains("sequencing_index"))
        let decoded = try CaddyAIJSON.decoder.decode(SwingMetrics.self, from: data)
        XCTAssertEqual(decoded, m)
    }
}
