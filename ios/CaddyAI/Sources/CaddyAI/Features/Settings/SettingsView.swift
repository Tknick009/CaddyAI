import SwiftUI
import CaddyAICore

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(AppState.onboardedKey) private var hasOnboarded: Bool = true
    @State private var backendText: String = ""
    @State private var saveStatus: Status = .idle

    enum Status: Equatable {
        case idle, ok, err(String)
    }

    var body: some View {
        NavigationStack {
            Screen(title: "Profile") {
                profileCard
                backendCard
                preferencesCard
                aboutCard
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { backendText = state.backendBaseURL.absoluteString }
        }
    }

    // MARK: Sections

    private var profileCard: some View {
        Card {
            HStack(spacing: Theme.Spacing.l) {
                ZStack {
                    Circle().fill(Theme.Palette.heroGradient).frame(width: 56, height: 56)
                    Image(systemName: "person.fill").foregroundStyle(.white)
                        .font(.system(size: 22, weight: .bold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Player").font(Theme.Type.bodyStrong)
                    Text("Device · \(String(state.deviceId.prefix(6))).swing")
                        .font(Theme.Type.caption).foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                Text(state.preferredHandedness == .right ? "Right" : "Left")
                    .font(Theme.Type.caption)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.Palette.surfaceMuted))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
        }
    }

    private var backendCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Backend", subtitle: "The server your phone talks to.")
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Base URL").font(Theme.Type.caption).foregroundStyle(Theme.Palette.textSecondary)
                    TextField("http://192.168.1.42:8000", text: $backendText)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(Theme.Spacing.m)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.Palette.surfaceMuted))
                    Button("Save") { save() }
                        .buttonStyle(.primaryPill)
                    switch saveStatus {
                    case .idle: EmptyView()
                    case .ok: StatusPill(text: "Saved", level: .ok)
                    case .err(let msg): StatusPill(text: msg, level: .err)
                    }
                }
            }
        }
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Preferences")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    LabeledRow(title: "Handedness", icon: "hand.raised.fill") {
                        Picker("", selection: $state.preferredHandedness) {
                            Text("Right").tag(Handedness.right)
                            Text("Left").tag(Handedness.left)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                    HairlineDivider()
                    LabeledRow(title: "Replay onboarding", icon: "arrow.counterclockwise") {
                        Button("Restart") {
                            hasOnboarded = false
                            Haptics.tap()
                        }
                        .font(Theme.Type.caption)
                        .foregroundStyle(Theme.Palette.primary)
                    }
                }
            }
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "About")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    LabeledRow(title: "Version", icon: "info.circle.fill") {
                        Text("0.1.0").font(Theme.Type.caption).foregroundStyle(Theme.Palette.textSecondary)
                    }
                    HairlineDivider()
                    LabeledRow(title: "Source", icon: "chevron.left.forwardslash.chevron.right") {
                        Link("GitHub", destination: URL(string: "https://github.com/Tknick009/CaddyAI")!)
                            .font(Theme.Type.caption)
                            .foregroundStyle(Theme.Palette.primary)
                    }
                }
            }
        }
    }

    private func save() {
        guard let url = URL(string: backendText), url.scheme != nil else {
            saveStatus = .err("Invalid URL")
            Haptics.error()
            return
        }
        state.backendBaseURL = url
        state.persist()
        saveStatus = .ok
        Haptics.success()
    }
}
