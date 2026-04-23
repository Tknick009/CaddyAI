import Foundation
import CaddyAICore

/// One-call adapter the UI uses to run whichever analyzer a capture
/// needs. Keeps `SwingCaptureView` free of `PoseFrame` vs `Pose3DFrame`
/// branching and keeps the multi-angle fusion entry-point in one place.
enum SwingAnalyzerFacade {

    /// Analyze a single capture.
    ///
    /// `.face2D` and `.dtl2D` are tagged on the output so that the
    /// server-side coach knows which measurements to trust. They can
    /// still be fused with a second capture via `fuse(faceOn:downTheLine:)`.
    static func analyze(
        _ capture: SwingCaptureResult,
        handedness: Handedness,
        clubKind: ClubKind?
    ) -> SwingMetrics? {
        switch capture {
        case let .twoD(mode, frames):
            guard var m = SwingAnalyzer().analyze(
                frames: frames, handedness: handedness, clubKind: clubKind
            ) else { return nil }
            m.viewpoint = mode == .dtl2D ? .downTheLine : .faceOn
            return m
        case let .threeD(frames):
            return SwingAnalyzer3D().analyze(
                frames: frames, handedness: handedness, clubKind: clubKind
            )
        }
    }

    /// Fuse a face-on and a down-the-line 2D capture into a single
    /// "best of both" report. Either side may be `nil`.
    static func fuse(
        faceOn: SwingCaptureResult?,
        downTheLine: SwingCaptureResult?,
        handedness: Handedness,
        clubKind: ClubKind?
    ) -> SwingMetrics? {
        let fo = faceOn.flatMap { analyze($0, handedness: handedness, clubKind: clubKind) }
        let dtl = downTheLine.flatMap { analyze($0, handedness: handedness, clubKind: clubKind) }
        return MultiAngleSwingAnalyzer.fuse(faceOn: fo, downTheLine: dtl)
    }
}
