import SwiftUI

@main
struct DitherApp: App {
    @StateObject private var state = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .tint(Color.ditherGreen)
        }
    }
}
