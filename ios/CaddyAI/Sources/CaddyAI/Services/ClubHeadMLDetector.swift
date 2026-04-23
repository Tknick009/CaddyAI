#if canImport(Vision) && canImport(CoreML)
import Foundation
import Vision
import CoreML
import CoreMedia
import CaddyAICore

/// Per-frame club-head detector backed by an optional bundled CoreML
/// model (`ClubHeadDetector.mlmodelc`).
///
/// The model isn't committed to this repo — see
/// `docs/CLUBHEAD_TRAINING.md` for the pipeline that trains it. This
/// class silently returns `nil` from `detect(frame:)` when the model
/// isn't available, so the app can always fall back to
/// `ClubHeadVisionTracker` and still run.
///
/// Expected model contract: a Vision-compatible object detector (YOLOv8
/// exported as CoreML, for example) with a single class `"clubhead"`.
/// `VNRecognizedObjectObservation.labels[0].identifier == "clubhead"`.
@available(iOS 14.0, *)
public final class ClubHeadMLDetector {

    public static let modelBundleName = "ClubHeadDetector"

    private let visionModel: VNCoreMLModel?

    public init(bundle: Bundle = .main) {
        self.visionModel = ClubHeadMLDetector.loadModel(from: bundle)
    }

    public var isAvailable: Bool { visionModel != nil }

    private static func loadModel(from bundle: Bundle) -> VNCoreMLModel? {
        guard let url = bundle.url(
            forResource: modelBundleName,
            withExtension: "mlmodelc"
        ) else { return nil }
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let ml = try MLModel(contentsOf: url, configuration: config)
            return try VNCoreMLModel(for: ml)
        } catch {
            return nil
        }
    }

    /// Returns the highest-confidence club-head detection in the frame,
    /// or `nil` if the model isn't bundled / no detection met threshold.
    public func detect(
        frame: CMSampleBuffer,
        confidenceThreshold: Float = 0.35
    ) -> ClubHeadPoint? {
        guard let visionModel,
              let pixelBuffer = CMSampleBufferGetImageBuffer(frame) else {
            return nil
        }
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            return nil
        }
        let best = results
            .filter { $0.labels.first?.identifier == "clubhead" }
            .max { $0.confidence < $1.confidence }
        guard let best, best.confidence >= confidenceThreshold else { return nil }

        let box = best.boundingBox
        let cx = box.midX
        let cy = 1.0 - box.midY   // flip Vision bottom-left → top-left
        let ts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(frame))
        return ClubHeadPoint(
            timestamp: ts.isFinite ? ts : 0,
            position: Point2D(x: Double(cx), y: Double(cy)),
            confidence: Double(best.confidence)
        )
    }
}
#endif
