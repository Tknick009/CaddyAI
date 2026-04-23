#if canImport(Vision) && canImport(CoreML)
import Foundation
import CoreMedia
import UIKit
import CaddyAICore

/// Orchestrates per-frame club-head tracking during a swing capture.
///
/// Priority:
///   1. `ClubHeadMLDetector` — per-frame CoreML object detector, works
///      without user input but only if the model is bundled (see
///      `docs/CLUBHEAD_TRAINING.md`).
///   2. `ClubHeadVisionTracker` — `VNTrackObjectRequest` fallback,
///      seeded by a bounding box the user drew on frame 1.
///
/// Call `feed(frame:)` for every `CMSampleBuffer` from the capture
/// pipeline. When segmentation decides the swing is over, call
/// `finish(calibration:handedness:)` for a `ClubHeadMetrics` summary.
@available(iOS 14.0, *)
public final class ClubHeadSession {

    public enum Mode {
        case automatic
        case seeded(CGRect)
        case disabled
    }

    private let detector: ClubHeadMLDetector
    private let fallback = ClubHeadVisionTracker()
    private var mode: Mode
    private(set) public var track: [ClubHeadPoint] = []

    public init(bundle: Bundle = .main) {
        self.detector = ClubHeadMLDetector(bundle: bundle)
        self.mode = detector.isAvailable ? .automatic : .disabled
    }

    /// Switch to user-seeded tracking mode. Call this if the app
    /// decides the CoreML model isn't available or didn't acquire in
    /// the first few frames.
    public func seed(with box: CGRect) {
        fallback.seed(with: box)
        mode = .seeded(box)
    }

    public func reset() {
        track.removeAll()
        fallback.reset()
        mode = detector.isAvailable ? .automatic : .disabled
    }

    public func feed(frame: CMSampleBuffer) {
        switch mode {
        case .automatic:
            if let p = detector.detect(frame: frame) {
                track.append(p)
            }
        case .seeded:
            if let p = try? fallback.track(frame: frame) {
                track.append(p)
            }
        case .disabled:
            break
        }
    }

    /// Derive final metrics. Returns nil if the track is too short or
    /// the calibration input is missing — callers should fall back to
    /// pose-only metrics in that case.
    public func finish(
        calibration: CameraCalibration?,
        handedness: Handedness
    ) -> ClubHeadMetrics? {
        guard track.count >= 3, let calibration else { return nil }
        return try? ClubHeadAnalyzer.analyze(
            track,
            calibration: calibration,
            handedness: handedness
        )
    }
}
#endif
