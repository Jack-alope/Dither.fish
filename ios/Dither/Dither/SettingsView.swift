import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                // ── Account ────────────────────────────────────────────────
                Section(header: Text("Account").ditherSectionHeader()) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.ditherGreen.opacity(0.15))
                                .frame(width: 48, height: 48)
                            Text(state.username.prefix(1).uppercased())
                                .font(.title2).fontWeight(.semibold)
                                .foregroundColor(.ditherGreen)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(state.username)
                                .font(.headline)
                            if state.isAdmin {
                                Label("Admin", systemImage: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundColor(.ditherGreen)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                // ── App ────────────────────────────────────────────────────
                Section(header: Text("App").ditherSectionHeader()) {
                    LabeledContent("Version") {
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                }

                // ── Danger zone ────────────────────────────────────────────
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .confirmationDialog("Log Out", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("Log Out", role: .destructive) { state.logout() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will need to sign in again to access your gear and trips.")
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
