import SwiftUI
import CaddyAICore

struct SwingReviewView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Screen {
            header
            if let report = state.lastSwingReport {
                rootCauses(report)
                drills(report)
                if report.source == "mock" {
                    Text("Coach running in offline mock mode — set OPENAI_API_KEY on the backend for richer advice.")
                        .font(Theme.Type.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .padding(.horizontal, Theme.Spacing.s)
                }
            }
            if let m = state.lastSwingMetrics {
                metricsGrid(m)
            }
        }
        .navigationTitle("Swing review")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    @ViewBuilder private var header: some View {
        if let report = state.lastSwingReport {
            HeroCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(spacing: Theme.Spacing.s) {
                        Image(systemName: "waveform.path.ecg").font(.system(size: 13, weight: .bold))
                        Text("COACH REPORT").font(Theme.Type.caption).tracking(1.0)
                    }
                    .foregroundStyle(.white.opacity(0.9))

                    Text(report.likelyBallFlight)
                        .font(Theme.Type.hero)
                        .foregroundStyle(.white)

                    Text(report.summary)
                        .font(Theme.Type.body)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        } else {
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Swing analyzed").font(Theme.Type.title2)
                    Text("Coach unavailable — raw metrics below.")
                        .font(Theme.Type.body)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
    }

    private func rootCauses(_ report: CoachingReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Root causes")
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ForEach(Array(report.rootCauses.enumerated()), id: \.offset) { _, cause in
                        HStack(alignment: .top, spacing: Theme.Spacing.m) {
                            ZStack {
                                Circle().fill(Theme.Palette.accent.opacity(0.2)).frame(width: 24, height: 24)
                                Image(systemName: "exclamationmark").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Theme.Palette.accent)
                            }
                            Text(cause).font(Theme.Type.body).foregroundStyle(Theme.Palette.textPrimary)
                        }
                    }
                }
            }
        }
    }

    private func drills(_ report: CoachingReport) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Drills")
            VStack(spacing: Theme.Spacing.m) {
                ForEach(Array(report.drills.enumerated()), id: \.offset) { i, drill in
                    Card {
                        HStack(alignment: .top, spacing: Theme.Spacing.m) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(Theme.Palette.primary.opacity(0.12))
                                Text("\(i + 1)").font(Theme.Type.bodyStrong)
                                    .foregroundStyle(Theme.Palette.primary)
                            }
                            .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(drill.name).font(Theme.Type.bodyStrong)
                                    .foregroundStyle(Theme.Palette.textPrimary)
                                Text(drill.description).font(Theme.Type.body)
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func metricsGrid(_ m: SwingMetrics) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Metrics", subtitle: sourceSubtitle(m))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.m),
                                GridItem(.flexible(), spacing: Theme.Spacing.m)],
                      spacing: Theme.Spacing.m) {
                MetricTile(label: "Tempo", value: String(format: "%.2f", m.tempoRatio), unit: ":1", icon: "metronome")
                MetricTile(label: "Shoulder turn", value: String(format: "%.0f", m.peakShoulderTurnDeg), unit: "°", icon: "arrow.triangle.2.circlepath")
                MetricTile(label: "Hip turn", value: String(format: "%.0f", m.peakHipTurnDeg), unit: "°", icon: "arrow.triangle.2.circlepath")
                MetricTile(label: "X-factor", value: String(format: "%.0f", m.xFactorDeg), unit: "°", icon: "bolt.fill")
                MetricTile(label: "Sway", value: String(format: "%.1f", m.lateralSwayCm), unit: "cm", icon: "arrow.left.and.right")
                MetricTile(label: "Head", value: String(format: "%.1f", m.headMovementCm), unit: "cm", icon: "figure.stand")
                MetricTile(label: "Plane", value: String(format: "%.0f", m.swingPlaneDeg), unit: "°", icon: "line.diagonal")
                MetricTile(label: "Lead weight", value: String(format: "%.0f", m.weightTransferPct), unit: "%", icon: "scale.3d")
                if let aa = m.attackAngleDeg {
                    MetricTile(label: "Attack", value: String(format: "%+.1f", aa), unit: "°", icon: "arrow.up.right")
                }
                if let seq = m.sequencingIndex {
                    MetricTile(label: "Sequencing", value: String(format: "%.0f", seq * 100), unit: "%", icon: "square.stack.3d.up.fill")
                }
                MetricTile(label: "Confidence", value: String(format: "%.0f", m.confidence * 100), unit: "%", icon: "checkmark.seal.fill")
            }
        }
    }

    private func sourceSubtitle(_ m: SwingMetrics) -> String? {
        guard let vp = m.viewpoint else { return nil }
        switch vp {
        case .faceOn: return "Face-on (2D)"
        case .downTheLine: return "Down-the-line (2D)"
        case .fused: return "Face-on + DTL fused"
        case .pose3D: return "3D pose"
        }
    }
}
