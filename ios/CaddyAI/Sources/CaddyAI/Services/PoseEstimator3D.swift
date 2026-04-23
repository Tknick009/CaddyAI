import Foundation
import Vision
import CoreMedia
import CaddyAICore

/// 3D body-pose estimator backed by `VNDetectHumanBodyPose3DRequest`
/// (iOS 17+, macOS 14+). On a LiDAR-equipped device this produces metric
/// depth; on other devices Vision falls back to monocular depth
/// estimation. Either way, the output is in meters, in world-space
/// coordinates centered on the root (hip) joint.
///
/// Older OS builds should instantiate `PoseEstimator` (2D) and use
/// `MultiAngleSwingAnalyzer.fuse(faceOn:downTheLine:)` to approximate 3D
/// measurements by recording both camera angles.
@available(iOS 17.0, macOS 14.0, *)
final class PoseEstimator3D {
    private let request = VNDetectHumanBodyPose3DRequest()

    func estimate(_ sampleBuffer: CMSampleBuffer, timestamp: TimeInterval) -> Pose3DFrame? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        return Self.toPose3DFrame(observation, timestamp: timestamp)
    }

    /// Subset of Vision's 3D joints we care about.
    private static let jointMapping: [VNHumanBodyPose3DObservation.JointName: Joint] = [
        .centerHead: .nose,
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .leftHip: .leftHip, .rightHip: .rightHip,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
    ]

    static func toPose3DFrame(_ obs: VNHumanBodyPose3DObservation, timestamp: TimeInterval) -> Pose3DFrame? {
        var joints: [Joint: Point3D] = [:]
        for (visionJoint, ourJoint) in jointMapping {
            guard let recognized = try? obs.recognizedPoint(visionJoint) else { continue }
            // `position` is a `simd_float4x4` in world-space metres; the
            // translation column gives the joint's xyz position.
            let m = recognized.position
            joints[ourJoint] = Point3D(
                x: Double(m.columns.3.x),
                y: Double(m.columns.3.y),
                z: Double(m.columns.3.z)
            )
        }
        guard joints.count >= 6 else { return nil }
        return Pose3DFrame(timestamp: timestamp, joints: joints)
    }
}
