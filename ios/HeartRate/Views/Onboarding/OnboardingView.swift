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

#Preview {
    OnboardingView()
        .environmentObject(AppEnvironment())
}
