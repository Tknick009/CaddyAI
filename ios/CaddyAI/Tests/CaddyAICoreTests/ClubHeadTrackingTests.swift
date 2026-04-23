import XCTest
@testable import CaddyAICore

final class ClubHeadTrackingTests: XCTestCase {

    /// Convenience: a synthetic right-handed swing recorded from face-on.
    /// At impact the club-head is moving left-to-right across the frame
    /// (in our axis convention: +x) at a known pace, slightly downward
    /// (+y ≈ small positive). Frame rate 120 fps.
    ///
    /// Calibration: the frame is 3 yards wide at the ball's distance
    /// from the camera. With the club covering 0.40 of the frame in
    /// the 5 frames surrounding impact (~42 ms), the horizontal speed
    /// is (0.40 × 3 y) / 0.042 s ≈ 28.8 y/s ≈ 58.8 mph.
    private func syntheticTrack() -> [ClubHeadPoint] {
        var out: [ClubHeadPoint] = []
        let fps: Double = 120
        let n = 31
        for i in 0..<n {
            let t = Double(i) / fps
            // x ramps up through impact; y dips slightly at impact.
            let tImpact = Double(n / 2) / fps
            let dt = t - tImpact
            let x = 0.5 + dt * 9.6            // 9.6 normalized-units/s ≈ 28.8 y/s
            let y = 0.55 + 0.02 * dt          // mild descent
            out.append(ClubHeadPoint(timestamp: t, position: Point2D(x: x, y: y)))
        }
        return out
    }

    func testAnalyzeRejectsShortTracks() {
        XCTAssertThrowsError(try ClubHeadAnalyzer.analyze(
            [],
            calibration: CameraCalibration(yardsPerNormalizedUnit: 3)
        ))
        XCTAssertThrowsError(try ClubHeadAnalyzer.analyze(
            [ClubHeadPoint(timestamp: 0, position: Point2D(x: 0, y: 0))],
            calibration: CameraCalibration(yardsPerNormalizedUnit: 3)
        ))
    }

    func testImpactIsNearTheMiddleOfAPeakyTrack() {
        // Build a track whose instantaneous speed peaks at frame 15.
        var pts: [ClubHeadPoint] = []
        for i in 0..<31 {
            let t = Double(i) / 120.0
            let peakiness = 1.0 / (1.0 + pow(Double(i - 15), 2.0) / 8.0)
            let x = 0.5 + 0.1 * peakiness * (i < 15 ? -1 : 1)
            pts.append(ClubHeadPoint(timestamp: t, position: Point2D(x: x, y: 0.5)))
        }
        let idx = ClubHeadAnalyzer.impactIndex(pts)
        XCTAssert((13...17).contains(idx), "impact should land near the peak, got \(idx)")
    }

    func testAnalyzeRecoversSpeedWithinTolerance() throws {
        let track = syntheticTrack()
        let m = try ClubHeadAnalyzer.analyze(
            track,
            calibration: CameraCalibration(yardsPerNormalizedUnit: 3)
        )
        // Expected ≈ 9.6 * 3 y/s = 28.8 y/s ≈ 58.8 mph. Allow 5%.
        XCTAssert(55.0 < m.speedMph && m.speedMph < 63.0, "got \(m.speedMph) mph")
    }

    func testRightHandedPlayerGetsNonInvertedPath() throws {
        let m = try ClubHeadAnalyzer.analyze(
            syntheticTrack(),
            calibration: CameraCalibration(yardsPerNormalizedUnit: 3),
            handedness: .right
        )
        // Track moves left-to-right (+x) with mild downward (+y) drift.
        // Forward component is +x. Lateral component (-dy) is slightly
        // negative → path should be a small negative angle. Not a big
        // out-to-in swing, but definitely on that side of zero.
        XCTAssert(m.pathDeg > -5.0 && m.pathDeg < 1.0, "got \(m.pathDeg)°")
    }

    func testLeftHandedMirrorsPathSign() throws {
        let track = syntheticTrack()
        let rh = try ClubHeadAnalyzer.analyze(
            track,
            calibration: CameraCalibration(yardsPerNormalizedUnit: 3),
            handedness: .right
        )
        let lh = try ClubHeadAnalyzer.analyze(
            track,
            calibration: CameraCalibration(yardsPerNormalizedUnit: 3),
            handedness: .left
        )
        // Left-hander on the same frame data should report the mirrored path.
        XCTAssertEqual(rh.pathDeg, -lh.pathDeg, accuracy: 1e-6)
    }

    func testAttackAngleNegativeWhenDescending() throws {
        // Build a track where the club moves +x quickly and +y (downward)
        // — negative attack angle in our convention.
        var pts: [ClubHeadPoint] = []
        for i in 0..<21 {
            let t = Double(i) / 120.0
            pts.append(ClubHeadPoint(
                timestamp: t,
                position: Point2D(x: 0.3 + Double(i) * 0.02, y: 0.4 + Double(i) * 0.004)
            ))
        }
        let m = try ClubHeadAnalyzer.analyze(
            pts,
            calibration: CameraCalibration(yardsPerNormalizedUnit: 3)
        )
        XCTAssertLessThan(m.attackAngleDeg, 0)
    }

    func testCalibrationScalesSpeedLinearly() throws {
        let t = syntheticTrack()
        let a = try ClubHeadAnalyzer.analyze(
            t, calibration: CameraCalibration(yardsPerNormalizedUnit: 3)
        )
        let b = try ClubHeadAnalyzer.analyze(
            t, calibration: CameraCalibration(yardsPerNormalizedUnit: 6)
        )
        XCTAssertEqual(b.speedMph, 2 * a.speedMph, accuracy: 0.5)
    }
}
