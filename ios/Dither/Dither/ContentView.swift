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
        ZStack(alignment: .top) {
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
                    .badge(state.pendingOpCount > 0 ? "\(state.pendingOpCount)" : nil)
            }
            .tint(Color.ditherGreen)

            // Offline banner — slides in from the top when disconnected
            if !state.isOnline {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                    Text(state.pendingOpCount > 0
                         ? "Offline — \(state.pendingOpCount) change\(state.pendingOpCount == 1 ? "" : "s") queued"
                         : "Offline — changes will sync when connected")
                        .font(.caption).fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.orange.opacity(0.95))
                .clipShape(Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.35), value: state.isOnline)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}
