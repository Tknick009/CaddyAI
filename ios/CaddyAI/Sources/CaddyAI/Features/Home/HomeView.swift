import SwiftUI
import CaddyAICore

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var garminStatus: GarminStatus?
    @State private var backendReachable = false

    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    NavigationLink {
                        SwingCaptureView()
                    } label: {
                        Label("Record a swing", systemImage: "video.fill")
                    }
                    NavigationLink {
                        CaddyView()
                    } label: {
                        Label("Pick a club", systemImage: "figure.golf")
                    }
                    NavigationLink {
                        LaunchMonitorImportView()
                    } label: {
                        Label("Import launch monitor data", systemImage: "tray.and.arrow.down.fill")
                    }
                    NavigationLink {
                        SwingHistoryView()
                    } label: {
                        Label("Swing history", systemImage: "clock.arrow.circlepath")
                    }
                }

                Section("Status") {
                    HStack {
                        Label("Backend", systemImage: "server.rack")
                        Spacer()
                        Text(backendReachable ? "Online" : "Offline")
                            .foregroundStyle(backendReachable ? .green : .orange)
                    }
                    HStack {
                        Label("Garmin integration", systemImage: "applewatch.watchface")
                        Spacer()
                        Text(garminStatus?.configured == true ? "Configured" : "Not configured")
                            .foregroundStyle(garminStatus?.configured == true ? .green : .secondary)
                    }
                    HStack {
                        Label("Clubs in bag", systemImage: "bag.fill")
                        Spacer()
                        Text("\(state.bag.clubs.count)").foregroundStyle(.secondary)
                    }
                }

                if let metrics = state.lastSwingMetrics {
                    Section("Last swing") {
                        Text(state.lastSwingReport?.summary ?? "Tempo \(String(format: "%.2f", metrics.tempoRatio)):1")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("CaddyAI")
            .task {
                await refreshStatus()
            }
            .refreshable {
                await refreshStatus()
            }
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
