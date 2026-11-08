//
//  MoodPickerSheet.swift
//  Journal-Whisper
//
//  Lets the user pick or correct an entry's mood. This works without AI and
//  always overrides a suggested mood.
//

import SwiftUI
import SwiftData

struct MoodPickerSheet: View {
    @Bindable var entry: JournalEntry
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(Mood.allCases) { mood in
                            MoodOption(mood: mood, isSelected: entry.mood == mood) {
                                entry.setUserMood(mood, intensity: entry.moodIntensity ?? Mood.defaultIntensity)
                            }
                        }
                    }

                    if entry.mood != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How strongly?")
                                .font(.headline)
                            Picker("Intensity", selection: intensityBinding) {
                                ForEach(Mood.intensityRange, id: \.self) { value in
                                    Text("\(value)").tag(value)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("moodIntensity")
                            HStack {
                                Text("A little")
                                Spacer()
                                Text("A lot")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("How are you feeling?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if entry.mood != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Clear", role: .destructive) { entry.clearMood() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Changing the intensity also confirms the mood as the user's own.
    private var intensityBinding: Binding<Int> {
        Binding(
            get: { entry.moodIntensity ?? Mood.defaultIntensity },
            set: { newValue in
                if let mood = entry.mood { entry.setUserMood(mood, intensity: newValue) }
            }
        )
    }
}

private struct MoodOption: View {
    let mood: Mood
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(mood.emoji)
                    .font(.largeTitle)
                Text(mood.label)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                mood.color.opacity(isSelected ? 0.3 : 0.08),
                in: .rect(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? mood.color : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mood.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("mood.\(mood.rawValue)")
    }
}

#Preview {
    let container = try! ModelContainer(
        for: JournalEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let entry = JournalEntry(text: "Long walk after class.")
    container.mainContext.insert(entry)
    return Color.clear
        .sheet(isPresented: .constant(true)) { MoodPickerSheet(entry: entry) }
        .modelContainer(container)
}
