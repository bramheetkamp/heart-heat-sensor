import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var step: OnboardingStep = .welcome
    @State private var slideDirection: AnyTransition = .asymmetric(
        insertion: .move(edge: .trailing),
        removal: .move(edge: .leading)
    )
    @State private var email = ""
    @State private var password = ""
    @State private var isSigningUp = false
    @State private var signupError: String?
    @State private var isLoginMode = false

    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case whatItDoes = 1
        case bluetoothPrimer = 2
        case account = 3
        case pairing = 4
        case baselineExplainer = 5
    }

    var body: some View {
        ZStack {
            // Warm gradient background
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.92, blue: 0.80), Color(red: 1.0, green: 0.97, blue: 0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(OnboardingStep.allCases, id: \.self) { s in
                        Capsule()
                            .fill(s == step ? Color.orange : Color.orange.opacity(0.25))
                            .frame(width: s == step ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.4), value: step)
                    }
                }
                .padding(.top, 20)

                // Step content
                Group {
                    switch step {
                    case .welcome:       WelcomeStep()
                    case .whatItDoes:    WhatItDoesStep()
                    case .bluetoothPrimer: BluetoothPrimerStep()
                    case .account:       AccountStep(email: $email, password: $password, error: $signupError, isLoginMode: $isLoginMode)
                    case .pairing:       PairingStep()
                    case .baselineExplainer: BaselineExplainerStep()
                    }
                }
                .transition(slideDirection)
                .id(step)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Navigation buttons
                bottomButtons
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            Button(action: advance) {
                HStack {
                    if isSigningUp {
                        ProgressView().tint(.white)
                    }
                    Text(primaryButtonTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.orange, in: RoundedRectangle(cornerRadius: 16))
            }
            .disabled(isSigningUp)

            if let skip = skipTitle {
                Button(skip) { advanceSkipping() }
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome:        return "Let's go"
        case .whatItDoes:     return "Got it"
        case .bluetoothPrimer: return "Allow Bluetooth"
        case .account:        return email.isEmpty ? "Skip for now" : (isLoginMode ? "Log in" : "Create account")
        case .pairing:        return "Start scanning"
        case .baselineExplainer: return "Enter app"
        }
    }

    private var skipTitle: String? {
        switch step {
        case .pairing:  return "I don't have my device yet — use demo mode"
        case .account:  return "Continue without account"
        default:        return nil
        }
    }

    // MARK: - Navigation

    private func advance() {
        switch step {
        case .bluetoothPrimer:
            env.bleService.startScanning()
            nextStep()
        case .account:
            if !email.isEmpty && !password.isEmpty {
                Task { await authenticate(isLogin: isLoginMode) }
            } else {
                nextStep()
            }
        case .pairing:
            env.bleService.startScanning()
            nextStep()
        case .baselineExplainer:
            completeOnboarding()
        default:
            nextStep()
        }
    }

    private func advanceSkipping() {
        switch step {
        case .pairing:
            env.isDemoMode = true
            UserDefaults.standard.set(true, forKey: "isDemoMode")
            Task { try? await env.demoMode.seedReadings(scenario: .normalWeek, into: env.dataStore) }
            nextStep()
        case .account:
            nextStep()
        default:
            nextStep()
        }
    }

    private func nextStep() {
        slideDirection = .asymmetric(
            insertion: .move(edge: .trailing),
            removal: .move(edge: .leading)
        )
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            if let idx = OnboardingStep.allCases.firstIndex(of: step),
               idx + 1 < OnboardingStep.allCases.count {
                step = OnboardingStep.allCases[idx + 1]
            }
        }
    }

    /// Authenticate against the backend, either logging into an existing
    /// account or registering a new one, then persist the returned token.
    private func authenticate(isLogin: Bool) async {
        isSigningUp = true
        defer { isSigningUp = false }
        do {
            let token = isLogin
                ? try await env.syncService.login(email: email, password: password)
                : try await env.syncService.register(email: email, password: password)
            let profile = try env.dataStore.getOrCreateProfile()
            profile.email = email
            profile.backendToken = token
            try env.dataStore.container.mainContext.save()
            nextStep()
        } catch {
            signupError = authErrorMessage(error)
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        withAnimation(.spring()) {
            // RootView observes this key and switches to main app
            NotificationCenter.default.post(name: .onboardingComplete, object: nil)
        }
    }
}

extension Notification.Name {
    static let onboardingComplete = Notification.Name("onboardingComplete")
}

// MARK: - Step Views

struct WelcomeStep: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            MascotView(state: .cheering, size: 120)
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: appeared)

            VStack(spacing: 12) {
                Text("Meet Pulse")
                    .font(.system(size: 36, weight: .black))
                    .foregroundColor(.orange)

                Text("Your personal health companion.\nWe watch the signals — you live your life.")
                    .font(.system(size: 17))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(.easeOut(duration: 0.5).delay(0.3), value: appeared)

            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear { appeared = true }
    }
}

struct WhatItDoesStep: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text("What we track")
                .font(.system(size: 28, weight: .bold))

            VStack(spacing: 16) {
                FeatureRow(icon: "heart.fill", color: .red,
                           title: "Heart rate + HRV",
                           detail: "Continuous beats per minute and heart rate variability — a window into your nervous system.")
                FeatureRow(icon: "thermometer.medium", color: .orange,
                           title: "Core body temperature",
                           detail: "Your internal temperature from two body sites, not just skin.")
                FeatureRow(icon: "chart.line.uptrend.xyaxis", color: .purple,
                           title: "Your personal baseline",
                           detail: "We learn your normal over ~2 weeks so we can spot when something's off.")
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

struct BluetoothPrimerStep: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundColor(.blue)
                .symbolEffect(.pulse)

            VStack(spacing: 12) {
                Text("Before we ask…")
                    .font(.system(size: 28, weight: .bold))

                Text("We need Bluetooth to connect to your device. We only use it to receive health data — we never scan for other devices or track your location.")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

struct AccountStep: View {
    @Binding var email: String
    @Binding var password: String
    @Binding var error: String?
    @Binding var isLoginMode: Bool

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(.orange)

            VStack(spacing: 10) {
                Text(isLoginMode ? "Log in" : "Create an account")
                    .font(.system(size: 26, weight: .bold))
                Text(isLoginMode
                     ? "Sign in to sync your existing data across devices."
                     : "Sync across devices and keep your data safe. Totally optional — the app works great without one.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textContentType(.emailAddress)
                    .padding()
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))

                SecureField("Password", text: $password)
                    .padding()
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))

                if let err = error {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Button {
                withAnimation { isLoginMode.toggle() }
                error = nil
            } label: {
                Text(isLoginMode ? "Don't have an account? Create one" : "Already have an account? Log in")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.orange)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

struct PairingStep: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var mascotState: MascotState = .scanning

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            MascotView(state: mascotState, size: 100)

            VStack(spacing: 10) {
                Text("Find your device")
                    .font(.system(size: 26, weight: .bold))
                Text("Make sure your device is powered on and nearby. It should appear in a few seconds.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            ConnectionStatusBadge(state: env.bleService.connectionState)

            Spacer()
        }
        .padding(.horizontal, 32)
        .onChange(of: env.bleService.isConnected) { connected in
            withAnimation { mascotState = connected ? .cheering : .scanning }
        }
    }
}

struct BaselineExplainerStep: View {
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 60))
                .foregroundStyle(.orange, .orange.opacity(0.3))

            VStack(spacing: 12) {
                Text("Learning your normal")
                    .font(.system(size: 26, weight: .bold))

                Text("Over the next ~2 weeks, we build a personal baseline for your resting heart rate and temperature.\n\nOnce we have it, we can tell you when something's actually off — not just above some generic threshold.")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            HStack(spacing: 0) {
                Label("Trend-based", systemImage: "chart.line.uptrend.xyaxis")
                Spacer()
                Label("Private", systemImage: "lock.fill")
                Spacer()
                Label("Yours", systemImage: "person.fill")
            }
            .font(.footnote.weight(.medium))
            .foregroundColor(.orange)
            .padding()
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))

            Spacer()
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - Shared Sub-components

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.footnote).foregroundColor(.secondary).lineSpacing(3)
            }
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppEnvironment())
}
