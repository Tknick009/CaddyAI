import SwiftUI
import CaddyAICore

struct SwingReviewView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let report = state.lastSwingReport {
                    headerCard(report.likelyBallFlight, subtitle: report.summary)
                    sectionCard(title: "Root causes") {
                        ForEach(Array(report.rootCauses.enumerated()), id: \.offset) { _, cause in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 6)
                                Text(cause)
                            }
                        }
                    }
                    sectionCard(title: "Drills") {
                        ForEach(Array(report.drills.enumerated()), id: \.offset) { _, drill in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(drill.name).font(.headline)
                                Text(drill.description).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    }
                    if report.source == "mock" {
                        Text("Coach running in offline mock mode — set OPENAI_API_KEY on the backend for richer advice.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    headerCard("Swing analyzed", subtitle: "Coach unavailable — see raw metrics below.")
                }
                if let m = state.lastSwingMetrics {
                    sectionCard(title: "Metrics") {
                        if let vp = m.viewpoint {
                            MetricRow("Source", value: sourceLabel(for: vp))
                        }
                        MetricRow("Tempo", value: String(format: "%.2f:1", m.tempoRatio))
                        MetricRow("Backswing", value: String(format: "%.2fs", m.backswingSec))
                        MetricRow("Downswing", value: String(format: "%.2fs", m.downswingSec))
                        MetricRow("Shoulder turn", value: String(format: "%.0f°", m.peakShoulderTurnDeg))
                        MetricRow("Hip turn", value: String(format: "%.0f°", m.peakHipTurnDeg))
                        MetricRow("X-factor", value: String(format: "%.0f°", m.xFactorDeg))
                        MetricRow("Sway", value: String(format: "%.1f cm", m.lateralSwayCm))
                        MetricRow("Head movement", value: String(format: "%.1f cm", m.headMovementCm))
                        MetricRow("Swing plane", value: String(format: "%.0f°", m.swingPlaneDeg))
                        MetricRow("Weight on lead foot", value: String(format: "%.0f%%", m.weightTransferPct))
                        if let aa = m.attackAngleDeg {
                            MetricRow("Attack angle", value: String(format: "%+.1f°", aa))
                        }
                        if let ps = m.pelvisSlideCm {
                            MetricRow("Pelvis slide", value: String(format: "%.1f cm", ps))
                        }
                        if let pt = m.pelvisTiltDeg {
                            MetricRow("Pelvis tilt", value: String(format: "%+.1f°", pt))
                        }
                        if let seq = m.sequencingIndex {
                            MetricRow("Sequencing", value: String(format: "%.0f%%", seq * 100))
                        }
                        MetricRow("Confidence", value: String(format: "%.0f%%", m.confidence * 100))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Swing review")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func headerCard(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.thinMaterial))
    }

    private func sourceLabel(for vp: SwingViewpoint) -> String {
        switch vp {
        case .faceOn: return "Face-on (2D)"
        case .downTheLine: return "Down-the-line (2D)"
        case .fused: return "Face-on + DTL fused"
        case .pose3D: return "3D pose"
        }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.thinMaterial))
    }
}

private struct MetricRow: View {
    let label: String
    let value: String
    init(_ label: String, value: String) {
        self.label = label
        self.value = value
    }
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
