import SwiftUI

/// Lets users drag-to-reorder and show/hide dashboard sections.
/// The companion status card is always pinned at the top and cannot be moved or hidden.
struct CustomizeDashboardView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Fixed pin — always shown, not movable
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "person.fill.checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Companion Status")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Always shown at the top")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Pinned")
            }

            // Reorderable sections
            Section {
                ForEach(env.dashboardLayout.sections) { section in
                    HStack(spacing: 14) {
                        Image(systemName: section.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(env.dashboardLayout.hiddenSections.contains(section.rawValue) ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                            .frame(width: 30)

                        Text(section.title)
                            .font(.system(size: 15))
                            .foregroundStyle(env.dashboardLayout.hiddenSections.contains(section.rawValue) ? .secondary : .primary)

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { !env.dashboardLayout.hiddenSections.contains(section.rawValue) },
                            set: { _ in env.dashboardLayout.toggleVisibility(of: section) }
                        ))
                        .tint(.orange)
                        .labelsHidden()
                    }
                    .padding(.vertical, 2)
                }
                .onMove { source, destination in
                    env.dashboardLayout.move(from: source, to: destination)
                }
            } header: {
                Text("Sections — drag to reorder")
            } footer: {
                Text("Toggle a section off to hide it. Drag the handle on the right to change the order.")
            }
        }
        .navigationTitle("Customize Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CustomizeDashboardView()
            .environmentObject(AppEnvironment())
    }
}
