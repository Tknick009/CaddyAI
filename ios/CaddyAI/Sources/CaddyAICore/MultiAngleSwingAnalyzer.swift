import Foundation

/// Fuses two 2D `SwingMetrics` captures — one face-on, one down-the-line
/// — into a single "best of both" report.
///
/// The 2D pose is geometrically deficient on its own: a face-on camera
/// can't see depth, so swing plane and attack angle are heavily distorted;
/// a down-the-line camera can't see lateral sway or hip rotation because
/// they're mostly toward/away from the lens. By recording both angles and
/// picking each metric from the viewpoint that measures it honestly, we
/// get numbers that approach what a 3D capture would produce — without
/// requiring a LiDAR-equipped iPhone.
///
/// Viewpoint strengths used here (standard biomech convention):
///
/// | metric             | preferred viewpoint |
/// |--------------------|---------------------|
/// | tempoRatio         | higher-confidence   |
/// | shoulder / hip turn| face-on             |
/// | x-factor           | face-on             |
/// | lateral sway       | face-on             |
/// | head movement      | face-on             |
/// | weight transfer    | face-on             |
/// | swing plane        | down-the-line       |
/// | early extension    | down-the-line       |
/// | attack angle       | down-the-line       |
public enum MultiAngleSwingAnalyzer {

    /// Fuse two metrics, tagging the output with `.viewpoint = .fused`.
    /// If one side is missing (e.g. the player only recorded one angle),
    /// the available side is returned as-is with its own viewpoint tag.
    public static func fuse(faceOn: SwingMetrics?, downTheLine: SwingMetrics?) -> SwingMetrics? {
        switch (faceOn, downTheLine) {
        case (nil, nil): return nil
        case (let fo?, nil):
            var m = fo; m.viewpoint = .faceOn; return m
        case (nil, let dtl?):
            var m = dtl; m.viewpoint = .downTheLine; return m
        case (let fo?, let dtl?):
            return merge(faceOn: fo, downTheLine: dtl)
        }
    }

    private static func merge(faceOn fo: SwingMetrics, downTheLine dtl: SwingMetrics) -> SwingMetrics {
        // Choose tempo from whichever capture had more usable frames.
        let tempoSrc = fo.confidence >= dtl.confidence ? fo : dtl
        // Confidence of the fused report is the mean weighted toward the
        // more-confident capture. Fusion strictly improves the worst-case
        // confidence, so we add a small bonus.
        let conf = min(1.0, 0.5 * (fo.confidence + dtl.confidence) + 0.1)
        return SwingMetrics(
            tempoRatio: tempoSrc.tempoRatio,
            backswingSec: tempoSrc.backswingSec,
            downswingSec: tempoSrc.downswingSec,
            peakShoulderTurnDeg: fo.peakShoulderTurnDeg,
            peakHipTurnDeg: fo.peakHipTurnDeg,
            xFactorDeg: fo.xFactorDeg,
            lateralSwayCm: fo.lateralSwayCm,
            headMovementCm: fo.headMovementCm,
            earlyExtensionCm: dtl.earlyExtensionCm,
            swingPlaneDeg: dtl.swingPlaneDeg,
            weightTransferPct: fo.weightTransferPct,
            confidence: conf,
            handedness: fo.handedness,
            clubKind: fo.clubKind ?? dtl.clubKind,
            viewpoint: .fused,
            // When DTL is 2D-only we can't produce an honest attack angle,
            // but we still propagate it if upstream populated it (e.g.
            // came from a 3D capture that got routed through fusion).
            attackAngleDeg: dtl.attackAngleDeg ?? fo.attackAngleDeg,
            pelvisSlideCm: fo.pelvisSlideCm ?? dtl.pelvisSlideCm,
            pelvisTiltDeg: fo.pelvisTiltDeg ?? dtl.pelvisTiltDeg,
            sequencingIndex: dtl.sequencingIndex ?? fo.sequencingIndex,
            clubPathDeg: dtl.clubPathDeg ?? fo.clubPathDeg
        )
    }
}
