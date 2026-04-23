#if canImport(Vision)
import Foundation
import Vision
import CoreGraphics
import CoreMedia
import CaddyAICore

/// Tracks the club-head across a sequence of frames using Apple Vision's
/// generic object tracker. Seed is a bounding box the user drew on the
/// very first frame (usually over the club-head while the player is at
/// address); Vision then predicts the box in each subsequent frame and
/// we record its centre as a `ClubHeadPoint`.
///
/// This is the *fallback* path. The preferred detector is the CoreML
/// model in `ClubHeadMLDetector`, which runs per-frame without an
/// initial user seed. If that model isn't bundled yet (common during
/// beta), the app falls back to this tracker after asking the user to
/// tap the club-head on the first frame.
@available(iOS 13.0, *)
public final class ClubHeadVisionTracker {

    public enum Error: Swift.Error {
        case sequenceHandlerFailed(Swift.Error)
        case observationLost
    }

    private let handler = VNSequenceRequestHandler()
    private var lastObservation: VNDetectedObjectObservation?

    public init() {}

    /// Seed the tracker with a bounding box (Vision coordinates:
    /// origin bottom-left, normalized 0..1) on the first frame.
    public func seed(with box: CGRect) {
        lastObservation = VNDetectedObjectObservation(boundingBox: box)
    }

    /// Track the next frame. Returns the detected centre (Vision
    /// coords, 0..1) and confidence, or nil if the observation was lost.
    public func track(frame: CMSampleBuffer) throws -> ClubHeadPoint? {
        guard let previous = lastObservation else { return nil }
        let request = VNTrackObjectRequest(detectedObjectObservation: previous)
        request.trackingLevel = .accurate

        do {
            try handler.perform([request], on: frame)
        } catch {
            throw Error.sequenceHandlerFailed(error)
        }

        guard let observation = request.results?.first as? VNDetectedObjectObservation,
              observation.confidence > 0.2 else {
            return nil
        }

        lastObservation = observation
        let box = observation.boundingBox
        let cx = box.midX
        let cy = 1.0 - box.midY   // flip to CaddyAICore's top-left origin
        let ts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(frame))
        return ClubHeadPoint(
            timestamp: ts.isFinite ? ts : 0,
            position: Point2D(x: Double(cx), y: Double(cy)),
            confidence: Double(observation.confidence)
        )
    }

    public func reset() {
        lastObservation = nil
    }
}
#endif
