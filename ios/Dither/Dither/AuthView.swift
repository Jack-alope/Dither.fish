import SwiftUI

struct AuthView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedTab = 0      // 0 = sign in, 1 = create account
    @State private var username    = ""   // register only
    @State private var email       = ""   // register only
    @State private var loginId     = ""   // login: username or email
    @State private var code        = ""
    @State private var maskedEmail = ""
    @State private var step        = 1      // 1 = username+email, 2 = OTP code
    @State private var errorMessage: String?
    @State private var isLoading   = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {

                    // ── Logo ──────────────────────────────────────────
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

                    // ── Tab switcher (only visible on step 1) ─────────
                    if step == 1 {
                        Picker("Mode", selection: $selectedTab) {
                            Text("Sign In").tag(0)
                            Text("Create Account").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .onChange(of: selectedTab) {
                            errorMessage = nil
                            code = ""
                            loginId = ""
                            username = ""
                            email = ""
                            withAnimation { step = 1 }
                        }
                    }

                    // ── Form ──────────────────────────────────────────
                    VStack(spacing: 16) {
                        if step == 1 {
                            // Step 1: login = username/email; register = both fields
                            if selectedTab == 0 {
                                // Login — single identifier field
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Username or email")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("Username or email", text: $loginId)
                                        .textFieldStyle(.roundedBorder)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .keyboardType(.emailAddress)
                                }
                            } else {
                                // Register — username + email
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
                                    Text("Email")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    TextField("you@example.com", text: $email)
                                        .textFieldStyle(.roundedBorder)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .keyboardType(.emailAddress)
                                }
                            }

                            if let error = errorMessage {
                                errorBanner(error)
                            }

                            Button(action: { Task { await sendCode() } }) {
                                loadingLabel("Send Code", loading: isLoading)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(isLoading || (selectedTab == 0 ? loginId.isEmpty : username.isEmpty || email.isEmpty))

                        } else {
                            // Step 2: OTP code
                            VStack(spacing: 6) {
                                Text("Check your email")
                                    .font(.headline)
                                Text("We sent a 6-digit code to **\(maskedEmail)**")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.bottom, 4)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("6-digit code")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("000000", text: $code)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.numberPad)
                                    .textContentType(.oneTimeCode)
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                                    .onChange(of: code) {
                                        code = String(code.filter(\.isNumber).prefix(6))
                                    }
                            }

                            if let error = errorMessage {
                                errorBanner(error)
                            }

                            Button(action: { Task { await verify() } }) {
                                loadingLabel(selectedTab == 0 ? "Sign In" : "Create Account",
                                             loading: isLoading)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(isLoading || code.count < 6)

                            Button("← Use a different email") {
                                withAnimation {
                                    step = 1
                                    code = ""
                                    errorMessage = nil
                                }
                            }
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: - Actions

    private static let usernameRegex = /^[a-z0-9_-]{3,30}$/

    private func usernameError(_ value: String) -> String? {
        let lower = value.trimmingCharacters(in: .whitespaces).lowercased()
        guard (try? Self.usernameRegex.wholeMatch(in: lower)) != nil else {
            return "Username must be 3–30 characters: letters, numbers, hyphens and underscores only"
        }
        return nil
    }

    private func sendCode() async {
        errorMessage = nil
        if selectedTab == 1, let err = usernameError(username) {
            errorMessage = err
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result: (maskedEmail: String, resolvedUsername: String)
            if selectedTab == 0 {
                result = try await state.requestOTPLogin(identifier: loginId.trimmingCharacters(in: .whitespaces))
            } else {
                result = try await state.requestOTPRegister(
                    username: username.trimmingCharacters(in: .whitespaces),
                    email: email.trimmingCharacters(in: .whitespaces)
                )
            }
            maskedEmail = result.maskedEmail
            username = result.resolvedUsername   // always use server-resolved username for verify
            withAnimation { step = 2 }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verify() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await state.verifyOTP(username: username.trimmingCharacters(in: .whitespaces),
                                      code: code.trimmingCharacters(in: .whitespaces))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func loadingLabel(_ title: String, loading: Bool) -> some View {
        HStack {
            if loading {
                ProgressView().tint(.white)
            } else {
                Text(title).fontWeight(.semibold)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Button Style

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .background(Color.ditherGreen.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundColor(.white)
            .cornerRadius(12)
    }
}

#Preview {
    AuthView()
        .environmentObject(AppState.shared)
}
