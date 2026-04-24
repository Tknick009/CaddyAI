import SwiftUI
import CaddyAICore

/// Dashboard. Hero card with a primary CTA, quick-action cards, the most
/// recent swing recap, and a compact system-status strip.
struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var garminStatus: GarminStatus?
    @State private var backendReachable = false
    @State private var goToSwing = false
    @State private var goToCaddy = false
    @State private var goToHistory = false
    @State private var goToImport = false

    var body: some View {
        NavigationStack {
            Screen {
                header
                hero
                quickActions
                lastSwingSection
                statusSection
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $goToSwing) { SwingCaptureView() }
            .navigationDestination(isPresented: $goToCaddy) { CaddyView() }
            .navigationDestination(isPresented: $goToHistory) { SwingHistoryView() }
            .navigationDestination(isPresented: $goToImport) { LaunchMonitorImportView() }
            .task { await refreshStatus() }
            .refreshable { await refreshStatus() }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(Theme.Type.caption).foregroundStyle(Theme.Palette.textSecondary)
                Text("CaddyAI").font(Theme.Type.title).foregroundStyle(Theme.Palette.textPrimary)
            }
            Spacer()
            StatusPill(
                text: backendReachable ? "Online" : "Offline",
                level: backendReachable ? .ok : .warn
            )
        }
        .padding(.top, Theme.Spacing.s)
    }

    private var hero: some View {
        HeroCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "sparkles").font(.system(size: 15, weight: .bold))
                    Text("Today's range session").font(Theme.Type.caption).tracking(0.8)
                }
                .foregroundStyle(.white.opacity(0.9))

                Text("Record your next swing.")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Pose estimation + coach report in about 8 seconds.")
                    .font(Theme.Type.body)
                    .foregroundStyle(.white.opacity(0.85))

                Button {
                    Haptics.tap(); goToSwing = true
                } label: {
                    HStack {
                        Image(systemName: "video.fill")
                        Text("Start recording")
                    }
                }
                .buttonStyle(.primaryPill(tint: Theme.Palette.accent, fullWidth: false))
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Quick actions", subtitle: "Tap to jump in")
            Button { Haptics.tap(); goToCaddy = true } label: {
                ActionRow(
                    systemImage: "flag.fill",
                    title: "Get a club",
                    subtitle: "Strokes-gained pick from your bag with wind + elevation."
                )
            }.buttonStyle(.plain)

            Button { Haptics.tap(); goToHistory = true } label: {
                ActionRow(
                    systemImage: "clock.arrow.circlepath",
                    title: "Swing history",
                    subtitle: "Review past swings and coach trends."
                )
            }.buttonStyle(.plain)

            Button { Haptics.tap(); goToImport = true } label: {
                ActionRow(
                    systemImage: "tray.and.arrow.down.fill",
                    title: "Import launch monitor",
                    subtitle: "TrackMan / SkyTrak / FlightScope CSV."
                )
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var lastSwingSection: some View {
        if let metrics = state.lastSwingMetrics {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "Last swing")
                Card(padding: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        if let report = state.lastSwingReport {
                            Text(report.likelyBallFlight)
                                .font(Theme.Type.title2)
                                .foregroundStyle(Theme.Palette.textPrimary)
                            Text(report.summary)
                                .font(Theme.Type.body)
                                .foregroundStyle(Theme.Palette.textSecondary)
                                .lineLimit(3)
                        }
                        HStack(spacing: Theme.Spacing.s) {
                            tinyMetric("Tempo", String(format: "%.2f:1", metrics.tempoRatio))
                            tinyMetric("Turn", String(format: "%.0f°", metrics.peakShoulderTurnDeg))
                            tinyMetric("X-factor", String(format: "%.0f°", metrics.xFactorDeg))
                        }
                    }
                }
            }
        }
    }

    private func tinyMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(Theme.Type.micro).tracking(0.6)
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(value).font(Theme.Type.bodyStrong).foregroundStyle(Theme.Palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Theme.Palette.surfaceMuted)
        )
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Connections")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    LabeledRow(title: "Backend", subtitle: state.backendBaseURL.host ?? "—", icon: "server.rack") {
                        StatusPill(
                            text: backendReachable ? "Online" : "Offline",
                            level: backendReachable ? .ok : .warn
                        )
                    }
                    HairlineDivider()
                    LabeledRow(title: "Garmin", subtitle: garminStatus?.configured == true ? "Watch paired" : "Not configured", icon: "applewatch.watchface") {
                        StatusPill(
                            text: garminStatus?.configured == true ? "Ready" : "Off",
                            level: garminStatus?.configured == true ? .ok : .neutral
                        )
                    }
                    HairlineDivider()
                    LabeledRow(title: "Clubs in bag", subtitle: "\(state.bag.clubs.count) configured", icon: "bag.fill") {
                        Text("\(state.bag.clubs.count)").font(Theme.Type.bodyStrong).foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private func refreshStatus() async {
        do {
            garminStatus = try await state.api.garminStatus()
            backendReachable = true
        } catch {
            backendReachable = false
        }
    }
}
