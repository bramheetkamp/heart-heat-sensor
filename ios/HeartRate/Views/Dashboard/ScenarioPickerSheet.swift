import SwiftUI

/// Quick demo-scenario switcher presented as a sheet from the dashboard toolbar.
/// Applies the chosen scenario end-to-end via `AppEnvironment.applyDemoScenario`.
struct ScenarioPickerSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(DemoScenario.allCases) { scenario in
                Button {
                    Task {
                        await env.applyDemoScenario(scenario)
                        dismiss()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scenario.rawValue).font(.headline)
                        Text(scenario.description).font(.footnote).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Demo Scenario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
