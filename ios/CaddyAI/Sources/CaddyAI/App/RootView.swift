import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            SwingCaptureView()
                .tabItem { Label("Swing", systemImage: "video.fill") }

            CaddyView()
                .tabItem { Label("Caddy", systemImage: "figure.golf") }

            BagView()
                .tabItem { Label("Bag", systemImage: "bag.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

#Preview {
    RootView().environmentObject(AppState())
}
