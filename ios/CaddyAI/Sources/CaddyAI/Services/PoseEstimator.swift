import Foundation
import Vision
import CoreMedia
import CaddyAICore

/// Wraps Apple Vision's `VNDetectHumanBodyPoseRequest` and converts its
/// output into `PoseFrame`s the cross-platform `SwingAnalyzer` understands.
final class PoseEstimator {
    private let request = VNDetectHumanBodyPoseRequest()

    init() {
        request.revision = VNDetectHumanBodyPoseRequestRevision1
    }

    /// Runs pose estimation on a single CMSampleBuffer (e.g. from an
    /// AVCaptureVideoDataOutputSampleBufferDelegate callback).
    /// Returns `nil` if no person is detected with sufficient confidence.
    func estimate(_ sampleBuffer: CMSampleBuffer, timestamp: TimeInterval) -> PoseFrame? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        return Self.toPoseFrame(observation, timestamp: timestamp)
    }

    /// Minimum confidence below which we ignore a joint.
    static let jointConfidenceThreshold: Float = 0.3

    /// Map from Vision joints to our cross-platform `Joint` enum.
    static let jointMapping: [VNHumanBodyPoseObservation.JointName: Joint] = [
        .nose: .nose,
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .leftHip: .leftHip, .rightHip: .rightHip,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
    ]

    static func toPoseFrame(_ obs: VNHumanBodyPoseObservation, timestamp: TimeInterval) -> PoseFrame? {
        var joints: [Joint: Point2D] = [:]
        for (visionJoint, ourJoint) in jointMapping {
            guard let point = try? obs.recognizedPoint(visionJoint) else { continue }
            guard point.confidence >= jointConfidenceThreshold else { continue }
            // Vision returns normalized points with y origin at the bottom.
            // We flip to match the "y grows downward" convention the swing
            // analyzer uses.
            joints[ourJoint] = Point2D(x: Double(point.location.x), y: Double(1.0 - point.location.y))
        }
        guard joints.count >= 6 else { return nil }
        return PoseFrame(timestamp: timestamp, joints: joints)
    }
}
