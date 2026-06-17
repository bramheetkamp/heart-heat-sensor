import SwiftUI
import SwiftData

// Supporting screens and rows presented from `SettingsView`. Pulled out of the
// main file to keep `SettingsView` focused on its section list.

// MARK: - Export Data View

struct ExportDataView: View {
    @Query(sort: \Reading.timestamp, order: .reverse)
    private var readings: [Reading]
    @Environment(\.dismiss) private var dismiss
    @State private var csvURL: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.orange)
                    Text("\(readings.count) readings ready")
                        .font(.title2.bold())
                    Text("Export your full health history as a comma-separated file you can open in any spreadsheet app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(.horizontal, 24)

                if let url = csvURL {
                    ShareLink(
                        item: url,
                        preview: SharePreview("pulse_health_data.csv", image: Image(systemName: "waveform.path.ecg"))
                    ) {
                        Label("Share CSV File", systemImage: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal, 24)
                } else {
                    ProgressView("Generating export…")
                        .tint(.orange)
                }

                Spacer()
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .task { csvURL = generateCSV() }
    }

    private func generateCSV() -> URL? {
        let header = "timestamp,heart_rate_bpm,core_temp_c,skin_temp_c,hrv_rmssd_ms,eda_us,activity\n"
        let iso = ISO8601DateFormatter()
        let rows = readings.map { r -> String in
            let ts   = iso.string(from: r.timestamp)
            let hr   = r.heartRate.map(String.init) ?? ""
            let core = r.tempCore.map  { String(format: "%.2f", $0) } ?? ""
            let skin = r.tempSkin.map  { String(format: "%.2f", $0) } ?? ""
            let hrv  = r.rmssd.map    { String(format: "%.1f",  $0) } ?? ""
            let eda  = r.eda.map      { String(format: "%.2f", $0) } ?? ""
            return "\(ts),\(hr),\(core),\(skin),\(hrv),\(eda),\(r.activity.rawValue)"
        }.joined(separator: "\n")

        let csv = header + rows
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pulse_health_data.csv")
        guard (try? csv.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return url
    }
}

// MARK: - Threshold Row

struct ThresholdRow: View {
    let label: String
    @Binding var value: Double
    let unit: String
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 14))
                Spacer()
                Text("\(String(format: format, value)) \(unit)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
                .tint(.orange)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Scenario Picker (Settings)

struct ScenarioPicker: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(DemoScenario.allCases) { scenario in
            Button {
                env.demoMode.activeScenario = scenario
                Task { try? await env.demoMode.seedReadings(scenario: scenario, into: env.dataStore) }
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(scenario.rawValue).font(.headline).foregroundColor(.primary)
                        Text(scenario.description).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    if env.demoMode.activeScenario == scenario {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.orange)
                    }
                }
            }
        }
        .navigationTitle("Choose Scenario")
    }
}

// MARK: - Account Setup View

struct AccountSetupView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $email).keyboardType(.emailAddress).autocapitalization(.none)
                SecureField("Password", text: $password)
            }
            if let error { Text(error).foregroundColor(.red).font(.caption) }
            Section {
                Button("Create Account") { Task { await register() } }.disabled(isLoading)
                Button("Sign In") { Task { await login() } }.disabled(isLoading)
            }
        }
        .navigationTitle("Account")
        .overlay(isLoading ? ProgressView() : nil)
    }

    private func register() async {
        isLoading = true; defer { isLoading = false }
        do {
            let token = try await env.syncService.register(email: email, password: password)
            let profile = try env.dataStore.getOrCreateProfile()
            profile.email = email; profile.backendToken = token
            try env.dataStore.container.mainContext.save()
            dismiss()
        } catch { self.error = authErrorMessage(error) }
    }

    private func login() async {
        isLoading = true; defer { isLoading = false }
        do {
            let token = try await env.syncService.login(email: email, password: password)
            let profile = try env.dataStore.getOrCreateProfile()
            profile.email = email; profile.backendToken = token
            try env.dataStore.container.mainContext.save()
            dismiss()
        } catch { self.error = authErrorMessage(error) }
    }
}
