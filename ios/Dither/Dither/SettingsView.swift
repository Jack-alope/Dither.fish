import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var showLogoutConfirm = false

    // Change username
    @State private var newUsername = ""
    @State private var usernameMsg: (text: String, isError: Bool)? = nil
    @State private var savingUsername = false

    // Change email
    @State private var newEmail = ""
    @State private var emailMsg: (text: String, isError: Bool)? = nil
    @State private var savingEmail = false

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
                            if !state.email.isEmpty {
                                Text(state.email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
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

                // ── Change username ────────────────────────────────────────
                Section(header: Text("Change Username").ditherSectionHeader()) {
                    HStack(spacing: 8) {
                        TextField("New username", text: $newUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: newUsername) { usernameMsg = nil }
                        Button(savingUsername ? "Saving…" : "Save") {
                            Task { await doChangeUsername() }
                        }
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(savingUsername || newUsername.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let msg = usernameMsg {
                        Text(msg.text)
                            .font(.caption)
                            .foregroundColor(msg.isError ? .red : .ditherGreen)
                    }
                }

                // ── Change email ───────────────────────────────────────────
                Section(header: Text("Change Email").ditherSectionHeader()) {
                    HStack(spacing: 8) {
                        TextField("New email", text: $newEmail)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .onChange(of: newEmail) { emailMsg = nil }
                        Button(savingEmail ? "Saving…" : "Save") {
                            Task { await doChangeEmail() }
                        }
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(savingEmail || newEmail.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let msg = emailMsg {
                        Text(msg.text)
                            .font(.caption)
                            .foregroundColor(msg.isError ? .red : .ditherGreen)
                    }
                }

                // ── Sync ───────────────────────────────────────────────────
                Section(header: Text("Sync").ditherSectionHeader()) {
                    LabeledContent("Status") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(state.isOnline ? Color.ditherGreen : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(state.isOnline ? "Online" : "Offline")
                                .foregroundColor(.secondary)
                        }
                    }

                    if state.pendingOpCount > 0 {
                        HStack {
                            Label("\(state.pendingOpCount) change\(state.pendingOpCount == 1 ? "" : "s") waiting to sync",
                                  systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            if state.isOnline {
                                Button("Sync Now") {
                                    Task { await state.syncPendingOps() }
                                }
                                .font(.subheadline)
                                .tint(.ditherGreen)
                            }
                        }
                    }
                }

                // ── Support ────────────────────────────────────────────────
                Section(header: Text("Support").ditherSectionHeader()) {
                    Link(destination: URL(string: "https://buymeacoffee.com/mrph")!) {
                        HStack(spacing: 14) {
                            Text("☕")
                                .font(.title2)
                                .frame(width: 36, height: 36)
                                .background(Color(red: 1.0, green: 0.95, blue: 0.87))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Buy me a coffee")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text("Help keep Dither.fish running")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    Link(destination: URL(string: "https://github.com/Jack-alope/Dither.fish")!) {
                        HStack(spacing: 14) {
                            Image(systemName: "curlybraces")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(Color(.label))
                                .frame(width: 36, height: 36)
                                .background(Color(.systemGray5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Open source")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text("View the code on GitHub")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
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
            .task { await state.refreshMe() }
            .confirmationDialog("Log Out", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("Log Out", role: .destructive) { state.logout() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will need to sign in again to access your gear and trips.")
            }
        }
    }

    private static let usernameRegex = /^[a-z0-9_-]{3,30}$/

    private func doChangeUsername() async {
        let trimmed = newUsername.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let lower = trimmed.lowercased()
        guard (try? Self.usernameRegex.wholeMatch(in: lower)) != nil else {
            usernameMsg = ("Username must be 3–30 characters: letters, numbers, hyphens and underscores only", true)
            return
        }
        savingUsername = true
        defer { savingUsername = false }
        do {
            try await state.changeUsername(to: trimmed)
            newUsername = ""
            usernameMsg = ("Username updated to "\(state.username)"", false)
        } catch {
            usernameMsg = (error.localizedDescription, true)
        }
    }

    private func doChangeEmail() async {
        let trimmed = newEmail.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        savingEmail = true
        defer { savingEmail = false }
        do {
            try await state.changeEmail(to: trimmed)
            newEmail = ""
            emailMsg = ("Email updated", false)
        } catch {
            emailMsg = (error.localizedDescription, true)
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
