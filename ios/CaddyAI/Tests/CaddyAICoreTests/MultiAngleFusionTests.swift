import XCTest
@testable import CaddyAICore

final class MultiAngleFusionTests: XCTestCase {
    private func faceOnMetrics() -> SwingMetrics {
        SwingMetrics(
            tempoRatio: 3.1, backswingSec: 0.93, downswingSec: 0.30,
            peakShoulderTurnDeg: 88, peakHipTurnDeg: 48, xFactorDeg: 40,
            lateralSwayCm: 4, headMovementCm: 5, earlyExtensionCm: 999,  // garbage FO
            swingPlaneDeg: 999,                                          // garbage FO
            weightTransferPct: 82, confidence: 0.9,
            handedness: .right, clubKind: .iron, viewpoint: .faceOn
        )
    }

    private func dtlMetrics() -> SwingMetrics {
        SwingMetrics(
            tempoRatio: 2.9, backswingSec: 0.87, downswingSec: 0.30,
            peakShoulderTurnDeg: 999,                                    // garbage DTL
            peakHipTurnDeg: 999, xFactorDeg: 999,
            lateralSwayCm: 999, headMovementCm: 999,                     // garbage DTL
            earlyExtensionCm: 2,
            swingPlaneDeg: 57,
            weightTransferPct: 999,                                      // garbage DTL
            confidence: 0.85,
            handedness: .right, clubKind: .iron, viewpoint: .downTheLine,
            attackAngleDeg: -4.5
        )
    }

    func testFuseUsesFaceOnForTurnMetrics() throws {
        let fused = try XCTUnwrap(MultiAngleSwingAnalyzer.fuse(faceOn: faceOnMetrics(), downTheLine: dtlMetrics()))
        XCTAssertEqual(fused.viewpoint, .fused)
        XCTAssertEqual(fused.peakShoulderTurnDeg, 88)
        XCTAssertEqual(fused.peakHipTurnDeg, 48)
        XCTAssertEqual(fused.xFactorDeg, 40)
        XCTAssertEqual(fused.lateralSwayCm, 4)
        XCTAssertEqual(fused.headMovementCm, 5)
        XCTAssertEqual(fused.weightTransferPct, 82)
    }

    func testFuseUsesDTLForPlaneAttackAndEarlyExtension() throws {
        let fused = try XCTUnwrap(MultiAngleSwingAnalyzer.fuse(faceOn: faceOnMetrics(), downTheLine: dtlMetrics()))
        XCTAssertEqual(fused.earlyExtensionCm, 2)
        XCTAssertEqual(fused.swingPlaneDeg, 57)
        XCTAssertEqual(fused.attackAngleDeg, -4.5)
    }

    func testFusedConfidenceExceedsWorstInput() throws {
        let fused = try XCTUnwrap(MultiAngleSwingAnalyzer.fuse(faceOn: faceOnMetrics(), downTheLine: dtlMetrics()))
        XCTAssertGreaterThan(fused.confidence, min(faceOnMetrics().confidence, dtlMetrics().confidence))
        XCTAssertLessThanOrEqual(fused.confidence, 1.0)
    }

    func testFuseWithSingleSourceReturnsTaggedInput() throws {
        let fo = faceOnMetrics()
        let onlyFO = try XCTUnwrap(MultiAngleSwingAnalyzer.fuse(faceOn: fo, downTheLine: nil))
        XCTAssertEqual(onlyFO.viewpoint, .faceOn)
        XCTAssertEqual(onlyFO.peakShoulderTurnDeg, fo.peakShoulderTurnDeg)

        let dtl = dtlMetrics()
        let onlyDTL = try XCTUnwrap(MultiAngleSwingAnalyzer.fuse(faceOn: nil, downTheLine: dtl))
        XCTAssertEqual(onlyDTL.viewpoint, .downTheLine)
        XCTAssertEqual(onlyDTL.swingPlaneDeg, dtl.swingPlaneDeg)
    }

    func testFuseReturnsNilWhenBothMissing() {
        XCTAssertNil(MultiAngleSwingAnalyzer.fuse(faceOn: nil, downTheLine: nil))
    }
}
