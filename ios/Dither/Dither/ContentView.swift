import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if state.token == nil {
                AuthView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.token == nil)
    }
}

struct MainTabView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView {
            GearLockerView()
                .tabItem {
                    Label("Gear", systemImage: "briefcase")
                }

            TripsView()
                .tabItem {
                    Label("Trips", systemImage: "map")
                }

            CatalogView()
                .tabItem {
                    Label("Catalog", systemImage: "books.vertical")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(Color.ditherGreen)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
