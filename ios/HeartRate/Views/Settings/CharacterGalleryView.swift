import SwiftUI
import SwiftData

/// Character selection gallery. Shows all companion characters with unlock status
/// and lets users customize the AI summary tone.
struct CharacterGalleryView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Query private var allReadings: [Reading]

    @State private var profile: UserProfile?
    @State private var selectedTone: AISummaryTone = .encouraging

    private var uniqueRecordedDays: Int {
        let calendar = Calendar.current
        let days = Set(allReadings.map { calendar.startOfDay(for: $0.timestamp) })
        return days.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerCard
                characterGrid
                toneSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("My Companion")
        .navigationBarTitleDisplayMode(.large)
        .task {
            profile = try? env.dataStore.getOrCreateProfile()
            selectedTone = profile?.aiTone ?? .encouraging
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(spacing: 20) {
            MascotView(state: .cheering, character: env.selectedCharacter, size: 72)

            VStack(alignment: .leading, spacing: 5) {
                Text(env.selectedCharacter.displayName)
                    .font(.title2.bold())
                Text(env.selectedCharacter.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Voice preview — the character's cheering line
                Text("\u{201C}" + env.selectedCharacter.statusMessage(for: .cheering) + "\u{201D}")
                    .font(.footnote.italic())
                    .foregroundStyle(.orange.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: env.selectedCharacter)
            }
            Spacer()
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }

    // MARK: - Character Grid

    private var characterGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Your Companion")
                .font(.headline)
                .padding(.horizontal, 4)

            Text("Earn new companions by recording more health data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(MascotCharacter.allCases, id: \.rawValue) { character in
                    characterCard(for: character)
                }
            }
        }
    }

    @ViewBuilder
    private func characterCard(for character: MascotCharacter) -> some View {
        let isUnlocked = character.isUnlocked(recordedDays: uniqueRecordedDays)
        let isSelected = env.selectedCharacter == character

        Button {
            if isUnlocked { select(character: character) }
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    MascotView(state: .happy, character: character, size: 64)
                        .opacity(isUnlocked ? 1 : 0.35)
                        .blur(radius: isUnlocked ? 0 : 2.5)

                    if !isUnlocked {
                        lockBadge(for: character)
                    }
                }
                .frame(height: 84)

                VStack(spacing: 3) {
                    Text(character.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isUnlocked ? .primary : .secondary)
                    Text(isUnlocked ? character.tagline : character.unlockDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected
                          ? Color.orange.opacity(0.1)
                          : Color(.systemBackground).opacity(isUnlocked ? 1 : 0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
                    .padding(8)
            }
        }
    }

    private func lockBadge(for character: MascotCharacter) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "lock.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)

            let progress = min(
                Double(uniqueRecordedDays) / Double(max(character.unlockDays, 1)),
                1.0
            )
            ProgressView(value: progress)
                .tint(.orange)
                .frame(width: 52)

            Text("\(uniqueRecordedDays)/\(character.unlockDays) days")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - AI Tone Section

    private var toneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Summary Tone")
                    .font(.headline)
                    .padding(.horizontal, 4)
                Text("Choose how your companion speaks to you in AI-generated summaries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            VStack(spacing: 0) {
                ForEach(0..<AISummaryTone.allCases.count, id: \.self) { index in
                    let tone = AISummaryTone.allCases[index]
                    if index > 0 {
                        Divider().padding(.leading, 54)
                    }
                    toneRow(for: tone)
                }
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        }
    }

    private func toneRow(for tone: AISummaryTone) -> some View {
        let isSelected = selectedTone == tone

        return Button {
            selectTone(tone)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: tone.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? .orange : .secondary)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tone.displayName)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(tone.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func select(character: MascotCharacter) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            env.selectedCharacter = character
        }
        if let profile {
            profile.selectedCharacter = character
            try? env.dataStore.container.mainContext.save()
        }
    }

    private func selectTone(_ tone: AISummaryTone) {
        withAnimation { selectedTone = tone }
        if let profile {
            profile.aiTone = tone
            try? env.dataStore.container.mainContext.save()
        }
    }
}

#Preview {
    let env = AppEnvironment()
    return NavigationStack {
        CharacterGalleryView()
            .environmentObject(env)
    }
    .modelContainer(env.dataStore.container)
}
