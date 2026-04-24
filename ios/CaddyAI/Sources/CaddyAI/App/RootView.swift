import SwiftUI

struct RootView: View {
    @AppStorage(AppState.onboardedKey) private var hasOnboarded: Bool = false

    var body: some View {
        Group {
            if hasOnboarded {
                MainTabView()
                    .transition(.opacity)
            } else {
                OnboardingView(hasOnboarded: $hasOnboarded)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: hasOnboarded)
    }
}

struct MainTabView: View {
    @State private var selection = 0

    init() {
        // Hairline top border, tinted labels, subtle blur — matches the
        // palette so the tab bar doesn't break the rest of the chrome.
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().tintColor = UIColor(Theme.Palette.primary)
    }

    var body: some View {
        TabView(selection: $selection) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            SwingCaptureView()
                .tabItem { Label("Swing", systemImage: "figure.golf") }
                .tag(1)

            CaddyView()
                .tabItem { Label("Caddy", systemImage: "flag.fill") }
                .tag(2)

            BagView()
                .tabItem { Label("Bag", systemImage: "bag.fill") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(4)
        }
        .tint(Theme.Palette.primary)
    }
}

#Preview {
    RootView().environmentObject(AppState())
}
