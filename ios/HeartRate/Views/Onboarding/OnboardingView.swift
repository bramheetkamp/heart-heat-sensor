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
    @State private var firstName = ""
    @State private var chosenCharacter: MascotCharacter = .blob

    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case chooseName = 1
        case whatItDoes = 2
        case bluetoothPrimer = 3
        case account = 4
        case pairing = 5
        case chooseMascot = 6
        case baselineExplainer = 7
    }

    var body: some View {
        ZStack {
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
                    case .welcome:          WelcomeStep()
                    case .chooseName:       ChooseNameStep(firstName: $firstName)
                    case .whatItDoes:       WhatItDoesStep()
                    case .bluetoothPrimer:  BluetoothPrimerStep()
                    case .account:          AccountStep(email: $email, password: $password, error: $signupError, isLoginMode: $isLoginMode)
                    case .pairing:          PairingStep()
                    case .chooseMascot:     ChooseMascotStep(chosen: $chosenCharacter)
                    case .baselineExplainer: BaselineExplainerStep(character: chosenCharacter, name: firstName)
                    }
                }
                .transition(slideDirection)
                .id(step)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
            .animation(.none, value: step)

            if let skip = skipTitle {
                Button(skip) { advanceSkipping() }
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome:          return "Let's go"
        case .chooseName:       return firstName.trimmingCharacters(in: .whitespaces).isEmpty ? "Skip" : "That's me"
        case .whatItDoes:       return "Got it"
        case .bluetoothPrimer:  return "Allow Bluetooth"
        case .account:          return email.isEmpty ? "Skip for now" : (isLoginMode ? "Log in" : "Create account")
        case .pairing:          return "Start scanning"
        case .chooseMascot:     return "Choose \(chosenCharacter.displayName)"
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
        case .chooseName:
            saveNameIfNeeded()
            nextStep()
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
        case .chooseMascot:
            applyChosenCharacter()
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

    private func saveNameIfNeeded() {
        let name = firstName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            if let profile = try? env.dataStore.getOrCreateProfile() {
                profile.displayName = name
                try? env.dataStore.container.mainContext.save()
            }
        }
    }

    private func applyChosenCharacter() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            env.selectedCharacter = chosenCharacter
        }
        Task {
            if let profile = try? env.dataStore.getOrCreateProfile() {
                profile.selectedCharacter = chosenCharacter
                try? env.dataStore.container.mainContext.save()
            }
        }
    }

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
            NotificationCenter.default.post(name: .onboardingComplete, object: nil)
        }
    }
}

extension Notification.Name {
    static let onboardingComplete = Notification.Name("onboardingComplete")
}

// MARK: - Welcome Step

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

// MARK: - Choose Name Step

struct ChooseNameStep: View {
    @Binding var firstName: String
    @FocusState private var focused: Bool
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            MascotView(state: .cheering, character: .blob, size: 100)
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: appeared)

            VStack(spacing: 12) {
                Text("What's your name?")
                    .font(.system(size: 28, weight: .bold))

                Text("We'll use it to greet you each day.\nCompletely optional — skip if you prefer.")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
            .animation(.easeOut(duration: 0.45).delay(0.2), value: appeared)

            TextField("First name", text: $firstName)
                .font(.system(size: 22, weight: .medium))
                .multilineTextAlignment(.center)
                .textContentType(.givenName)
                .autocapitalization(.words)
                .focused($focused)
                .padding(.vertical, 14)
                .padding(.horizontal, 20)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(focused ? Color.orange.opacity(0.6) : Color.clear, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)
                .animation(.easeOut(duration: 0.45).delay(0.35), value: appeared)

            if !firstName.isEmpty {
                Text("Nice to meet you, \(firstName.trimmingCharacters(in: .whitespaces))!")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .animation(.spring(response: 0.3), value: firstName.isEmpty)
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { focused = true }
        }
    }
}

// MARK: - What It Does Step

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

// MARK: - Bluetooth Primer Step

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

// MARK: - Account Step

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

// MARK: - Pairing Step

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
        .task {
            if !env.bleService.isConnected { env.bleService.startScanning() }
        }
        .onChange(of: env.bleService.isConnected) { connected in
            withAnimation { mascotState = connected ? .cheering : .scanning }
        }
    }
}

// MARK: - Choose Mascot Step

struct ChooseMascotStep: View {
    @Binding var chosen: MascotCharacter
    @State private var appeared = false

    private let alwaysAvailable: Set<MascotCharacter> = [.blob, .bear]

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 4)

            VStack(spacing: 8) {
                Text("Pick your companion")
                    .font(.system(size: 26, weight: .bold))
                Text("They'll cheer you on, warn you when something's off, and grow with you over time.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)

            // Active character preview
            VStack(spacing: 6) {
                MascotView(state: .cheering, character: chosen, size: 80)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: chosen)
                // Show the character's own voice so users know what they're picking
                Text(""\(chosen.statusMessage(for: .cheering))"")
                    .font(.footnote.italic())
                    .foregroundStyle(.orange.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 36)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: chosen)
            }
            .padding(.vertical, 4)

            // 2×2 character grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(MascotCharacter.allCases, id: \.rawValue) { character in
                    characterButton(for: character)
                }
            }
            .padding(.horizontal, 24)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)

            Spacer(minLength: 4)
        }
        .onAppear { appeared = true }
    }

    @ViewBuilder
    private func characterButton(for character: MascotCharacter) -> some View {
        let isAvailable = alwaysAvailable.contains(character)
        let isSelected = chosen == character

        Button {
            if isAvailable {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    chosen = character
                }
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    MascotView(state: isSelected ? .cheering : .happy, character: character, size: 54)
                        .opacity(isAvailable ? 1 : 0.4)
                        .blur(radius: isAvailable ? 0 : 1.5)

                    if !isAvailable {
                        VStack(spacing: 2) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                            Text("\(character.unlockDays)d")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .frame(height: 64)

                Text(character.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isAvailable ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected
                          ? Color.orange.opacity(0.12)
                          : Color(.systemBackground).opacity(isAvailable ? 0.9 : 0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Baseline Explainer Step

struct BaselineExplainerStep: View {
    var character: MascotCharacter = .blob
    var name: String = ""

    private var addressedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "" : ", \(trimmed)"
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            MascotView(state: .happy, character: character, size: 80)

            VStack(spacing: 12) {
                Text("Almost there\(addressedName)!")
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
