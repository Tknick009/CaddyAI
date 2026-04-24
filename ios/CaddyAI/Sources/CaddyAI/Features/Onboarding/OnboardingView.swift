import SwiftUI
import AVFoundation
import CoreLocation
import CaddyAICore

/// First-run flow. Four pages: value prop → handedness → permissions → bag
/// preview. Once complete, sets the `hasOnboarded` flag in UserDefaults
/// and the root view switches to the main tab bar.
struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @Binding var hasOnboarded: Bool
    @State private var page = 0

    var body: some View {
        ZStack {
            Theme.Palette.heroGradient.ignoresSafeArea()

            VStack {
                TabView(selection: $page) {
                    WelcomePage().tag(0)
                    HandednessPage(handedness: $state.preferredHandedness).tag(1)
                    PermissionsPage().tag(2)
                    BagPage(bag: state.bag).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageIndicator
                    .padding(.top, Theme.Spacing.m)

                HStack(spacing: Theme.Spacing.m) {
                    if page > 0 {
                        Button("Back") {
                            withAnimation { page -= 1 }
                            Haptics.selection()
                        }
                        .buttonStyle(.secondaryPill(fullWidth: false))
                        .tint(.white)
                    }
                    Button(page < 3 ? "Continue" : "Start playing") {
                        Haptics.tap()
                        if page < 3 {
                            withAnimation { page += 1 }
                        } else {
                            state.persist()
                            Haptics.success()
                            hasOnboarded = true
                        }
                    }
                    .buttonStyle(.primaryPill(tint: Theme.Palette.accent, fullWidth: true))
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xl)
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<4) { i in
                Capsule()
                    .fill(i == page ? Color.white : Color.white.opacity(0.35))
                    .frame(width: i == page ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: page)
            }
        }
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: "figure.golf")
                .font(.system(size: 72, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, Theme.Spacing.m)
            Text("Your AI caddy.\nIn your pocket.")
                .font(Theme.Type.hero)
                .foregroundStyle(.white)
            Text("Record a swing, get a coach report. Line up a shot, get a club. Trained on your bag, your distances, your tendencies.")
                .font(Theme.Type.body)
                .foregroundStyle(.white.opacity(0.85))
            Spacer(); Spacer()
        }
        .padding(Theme.Spacing.xxl)
    }
}

private struct HandednessPage: View {
    @Binding var handedness: Handedness
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Spacer()
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Which hand?").font(Theme.Type.title).foregroundStyle(.white)
                Text("We use this to flip the skeleton overlay so the left side is always your lead side.")
                    .font(Theme.Type.body).foregroundStyle(.white.opacity(0.85))
            }
            HStack(spacing: Theme.Spacing.m) {
                handCard(.right, label: "Right-handed", icon: "hand.point.right.fill")
                handCard(.left, label: "Left-handed", icon: "hand.point.left.fill")
            }
            Spacer()
        }
        .padding(Theme.Spacing.xxl)
    }

    private func handCard(_ value: Handedness, label: String, icon: String) -> some View {
        let selected = handedness == value
        return Button {
            handedness = value
            Haptics.selection()
        } label: {
            VStack(spacing: Theme.Spacing.s) {
                Image(systemName: icon).font(.system(size: 38, weight: .semibold))
                Text(label).font(Theme.Type.bodyStrong)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
            .foregroundStyle(selected ? Theme.Palette.primary : .white)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(selected ? Color.white : Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .strokeBorder(.white.opacity(selected ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Retained wrapper around `CLLocationManager` so the manager outlives the
/// button tap and its delegate callback fires. Publishes an authorization
/// flag the view observes.
private final class LocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var granted: Bool = false
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        granted = Self.isGranted(manager.authorizationStatus)
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        granted = Self.isGranted(manager.authorizationStatus)
    }

    private static func isGranted(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }
}

private struct PermissionsPage: View {
    @State private var cameraGranted = false
    @StateObject private var location = LocationPermission()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Spacer()
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Two quick permissions").font(Theme.Type.title).foregroundStyle(.white)
                Text("The app works offline — these unlock the best features.")
                    .font(Theme.Type.body).foregroundStyle(.white.opacity(0.85))
            }

            VStack(spacing: Theme.Spacing.m) {
                permissionRow(
                    icon: "camera.fill",
                    title: "Camera",
                    subtitle: "Record and analyze your swing.",
                    granted: cameraGranted
                ) {
                    AVCaptureDevice.requestAccess(for: .video) { ok in
                        DispatchQueue.main.async {
                            cameraGranted = ok
                            Haptics.tap()
                        }
                    }
                }
                permissionRow(
                    icon: "location.fill",
                    title: "Location",
                    subtitle: "Wind, temperature, and elevation for club picks.",
                    granted: location.granted
                ) {
                    location.request()
                    Haptics.tap()
                }
            }
            Spacer()
        }
        .padding(Theme.Spacing.xxl)
        .onAppear {
            cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        }
    }

    private func permissionRow(icon: String, title: String, subtitle: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.15))
                Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Type.bodyStrong).foregroundStyle(.white)
                Text(subtitle).font(Theme.Type.caption).foregroundStyle(.white.opacity(0.75))
            }
            Spacer()
            Button(granted ? "Granted" : "Allow") { action() }
                .buttonStyle(.secondaryPill(fullWidth: false))
                .disabled(granted)
        }
        .padding(Theme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
    }
}

private struct BagPage: View {
    let bag: Bag
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Spacer()
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("You're set.").font(Theme.Type.title).foregroundStyle(.white)
                Text("We've pre-loaded a standard 14-club bag. You can add, remove, and save your personal distances once we're in.")
                    .font(Theme.Type.body).foregroundStyle(.white.opacity(0.85))
            }

            VStack(spacing: Theme.Spacing.xs) {
                ForEach(bag.clubs.prefix(6)) { club in
                    HStack {
                        Image(systemName: iconForKind(club.kind)).font(.system(size: 14, weight: .bold))
                        Text(club.name).font(Theme.Type.body)
                        Spacer()
                        if let loft = club.loftDeg {
                            Text("\(Int(loft))°").font(Theme.Type.caption).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.10))
                    )
                }
                if bag.clubs.count > 6 {
                    Text("+ \(bag.clubs.count - 6) more")
                        .font(Theme.Type.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.top, Theme.Spacing.xs)
                }
            }
            Spacer()
        }
        .padding(Theme.Spacing.xxl)
    }

    private func iconForKind(_ k: ClubKind) -> String {
        switch k {
        case .driver: return "d.circle.fill"
        case .wood: return "w.circle.fill"
        case .hybrid: return "h.circle.fill"
        case .iron: return "i.circle.fill"
        case .wedge: return "w.circle.fill"
        case .putter: return "p.circle.fill"
        }
    }
}
