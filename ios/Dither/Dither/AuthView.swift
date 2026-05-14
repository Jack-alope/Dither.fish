import SwiftUI

struct AuthView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedTab = 0
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Logo
                    VStack(spacing: 12) {
                        Image("DitherLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                        Text("dither.fish")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.ditherGreen)
                        Text("Gear tracking for the outdoors")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 48)

                    // Tab Switcher
                    Picker("Mode", selection: $selectedTab) {
                        Text("Login").tag(0)
                        Text("Register").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: selectedTab) {
                        errorMessage = nil
                        password = ""
                        confirmPassword = ""
                    }

                    // Form
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Username")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Username", text: $username)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField("Password", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }

                        if selectedTab == 1 {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Confirm Password")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                SecureField("Confirm Password", text: $confirmPassword)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        if let error = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: { Task { await submit() } }) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(selectedTab == 0 ? "Log In" : "Create Account")
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.ditherGreen)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isLoading || username.isEmpty || password.isEmpty)
                    }
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func submit() async {
        errorMessage = nil

        if selectedTab == 1 {
            guard password == confirmPassword else {
                errorMessage = "Passwords do not match"
                return
            }
            guard password.count >= 6 else {
                errorMessage = "Password must be at least 6 characters"
                return
            }
        }

        isLoading = true
        defer { isLoading = false }

        do {
            if selectedTab == 0 {
                try await state.login(username: username, password: password)
            } else {
                try await state.register(username: username, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AppState.shared)
}
