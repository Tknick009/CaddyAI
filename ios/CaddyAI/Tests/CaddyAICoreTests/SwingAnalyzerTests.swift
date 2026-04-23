import XCTest
@testable import CaddyAICore

final class SwingAnalyzerTests: XCTestCase {
    /// Build a synthetic right-handed swing with a realistic-ish profile:
    /// linear backswing, quadratically-accelerating downswing, and a
    /// decelerating follow-through where the lead wrist rises back up on
    /// the target side. This gives the analyzer enough of a real velocity
    /// curve to pick a plausible impact frame.
    func makeSyntheticSwing() -> [PoseFrame] {
        let fps = 120.0
        var frames: [PoseFrame] = []

        let addressJoints: [Joint: Point2D] = [
            .nose:         Point2D(x: 0.50, y: 0.20),
            .leftShoulder: Point2D(x: 0.45, y: 0.30),
            .rightShoulder:Point2D(x: 0.55, y: 0.30),
            .leftHip:      Point2D(x: 0.47, y: 0.55),
            .rightHip:     Point2D(x: 0.53, y: 0.55),
            .leftWrist:    Point2D(x: 0.50, y: 0.70),
            .rightWrist:   Point2D(x: 0.52, y: 0.70),
            .leftKnee:     Point2D(x: 0.47, y: 0.75),
            .rightKnee:    Point2D(x: 0.53, y: 0.75),
            .leftAnkle:    Point2D(x: 0.45, y: 0.92),
            .rightAnkle:   Point2D(x: 0.55, y: 0.92),
        ]

        let addressY = 0.70
        let topY = 0.15
        let backswingFrames = 36           // ~0.30 s
        let downswingFrames = 12           // ~0.10 s — tempo 3:1
        let followThroughFrames = 20       // ~0.17 s

        // Backswing: linear climb.
        for i in 0..<backswingFrames {
            let tSeg = Double(i) / Double(backswingFrames - 1)
            var joints = addressJoints
            let wristY = addressY - (addressY - topY) * tSeg
            joints[.leftWrist]  = Point2D(x: 0.50 + 0.20 * tSeg, y: wristY)
            joints[.rightWrist] = Point2D(x: 0.52 + 0.20 * tSeg, y: wristY)
            joints[.leftShoulder]  = Point2D(x: 0.45 + 0.08 * tSeg, y: 0.30 - 0.01 * tSeg)
            joints[.rightShoulder] = Point2D(x: 0.55 - 0.02 * tSeg, y: 0.30 + 0.05 * tSeg)
            joints[.leftHip]  = Point2D(x: 0.47 + 0.03 * tSeg, y: 0.55)
            joints[.rightHip] = Point2D(x: 0.53 - 0.01 * tSeg, y: 0.55 + 0.02 * tSeg)
            frames.append(PoseFrame(timestamp: Double(frames.count) / fps, joints: joints))
        }

        // Downswing: quadratic ease-in so velocity peaks near impact.
        for i in 0..<downswingFrames {
            let tSeg = Double(i + 1) / Double(downswingFrames)
            let eased = tSeg * tSeg
            var joints = addressJoints
            let wristY = topY + (addressY + 0.02 - topY) * eased
            joints[.leftWrist]  = Point2D(x: 0.70 - 0.20 * tSeg, y: wristY)
            joints[.rightWrist] = Point2D(x: 0.70 - 0.18 * tSeg, y: wristY)
            joints[.leftShoulder]  = Point2D(x: 0.53 - 0.10 * tSeg, y: 0.29)
            joints[.rightShoulder] = Point2D(x: 0.53 + 0.02 * tSeg, y: 0.35 - 0.05 * tSeg)
            joints[.leftHip]  = Point2D(x: 0.50 - 0.05 * tSeg, y: 0.55)
            joints[.rightHip] = Point2D(x: 0.52 - 0.01 * tSeg, y: 0.57 - 0.02 * tSeg)
            frames.append(PoseFrame(timestamp: Double(frames.count) / fps, joints: joints))
        }

        // Follow-through: wrist swings UP on the target side (lead).
        let impactY = addressY + 0.02
        for i in 0..<followThroughFrames {
            let tSeg = Double(i + 1) / Double(followThroughFrames)
            var joints = addressJoints
            let wristY = impactY - (impactY - 0.30) * tSeg
            joints[.leftWrist]  = Point2D(x: 0.50 - 0.20 * tSeg, y: wristY)
            joints[.rightWrist] = Point2D(x: 0.52 - 0.18 * tSeg, y: wristY)
            joints[.leftShoulder]  = Point2D(x: 0.43 - 0.02 * tSeg, y: 0.29)
            joints[.rightShoulder] = Point2D(x: 0.55 - 0.06 * tSeg, y: 0.29)
            joints[.leftHip]  = Point2D(x: 0.45, y: 0.55)
            joints[.rightHip] = Point2D(x: 0.51, y: 0.55)
            frames.append(PoseFrame(timestamp: Double(frames.count) / fps, joints: joints))
        }

        return frames
    }

    func testAnalyzeProducesPlausibleMetrics() throws {
        let analyzer = SwingAnalyzer()
        let metrics = try XCTUnwrap(analyzer.analyze(frames: makeSyntheticSwing()))
        // 36 frames backswing / ~12 downswing → ratio ≈ 3.0
        XCTAssertEqual(metrics.tempoRatio, 3.0, accuracy: 0.3)
        XCTAssertGreaterThan(metrics.backswingSec, 0)
        XCTAssertGreaterThan(metrics.downswingSec, 0)
        XCTAssertGreaterThan(metrics.swingPlaneDeg, 0)
        // Confidence maxes out at 60 frames; we have exactly 60.
        XCTAssertEqual(metrics.confidence, 1.0, accuracy: 0.01)
    }

    func testSegmentationFindsTopAfterStart() throws {
        let analyzer = SwingAnalyzer()
        let frames = makeSyntheticSwing()
        let segs = try XCTUnwrap(analyzer.segment(frames: frames, handedness: .right))
        XCTAssertEqual(segs.addressIndex, 0)
        XCTAssertGreaterThan(segs.topIndex, 10)
        XCTAssertLessThan(segs.topIndex, frames.count - 3)
        XCTAssertGreaterThan(segs.impactIndex, segs.topIndex)
    }

    func testAnalyzeRejectsTooFewFrames() {
        let analyzer = SwingAnalyzer()
        let frames = Array(makeSyntheticSwing().prefix(5))
        XCTAssertNil(analyzer.analyze(frames: frames))
    }

    func testModelsRoundTripJson() throws {
        let metrics = SwingMetrics(
            tempoRatio: 3.0, backswingSec: 0.9, downswingSec: 0.3,
            peakShoulderTurnDeg: 90, peakHipTurnDeg: 50, xFactorDeg: 40,
            lateralSwayCm: 3, headMovementCm: 4, earlyExtensionCm: 1,
            swingPlaneDeg: 58, weightTransferPct: 80, confidence: 0.9,
            handedness: .right, clubKind: .iron
        )
        let data = try CaddyAIJSON.encoder.encode(metrics)
        let s = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("tempo_ratio"), "expected snake_case in wire format: \(s)")
        XCTAssertTrue(s.contains("club_kind"))
        let decoded = try CaddyAIJSON.decoder.decode(SwingMetrics.self, from: data)
        XCTAssertEqual(decoded, metrics)
    }
}
