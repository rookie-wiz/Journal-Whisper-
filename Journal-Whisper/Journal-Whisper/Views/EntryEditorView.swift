//
//  EntryEditorView.swift
//  Journal-Whisper
//

import SwiftUI
import SwiftData

/// A distraction-free editor. Changes save automatically through SwiftData.
struct EntryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.reflectionEngine) private var reflectionEngine
    @Bindable var entry: JournalEntry
    /// When true, the editor opens with the keyboard up (used by the Edit swipe action).
    var startEditing = false

    @FocusState private var focusedField: Field?
    private enum Field { case title, text }
    @State private var isPickingMood = false
    /// Created on appear, once the environment's engine is available.
    @State private var reflection: ReflectionCoordinator?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.createdAt, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    MoodChip(mood: entry.mood, source: entry.moodSource) {
                        focusedField = nil
                        isPickingMood = true
                    }
                    Spacer()
                    if let reflection, reflection.promptState != .support {
                        Button("Reflect", systemImage: "lightbulb") {
                            reflection.requestPrompts(for: entry)
                        }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(.borderless)
                        .disabled(reflection.promptState == .loading)
                        .accessibilityHint("Suggests questions to help you reflect")
                        .accessibilityIdentifier("reflectButton")
                    }
                }

                if let reflection {
                    ReflectionPromptCard(
                        state: reflection.promptState,
                        availability: ReflectionAvailability.current,
                        onUse: { prompt in
                            reflection.use(prompt, in: entry)
                            focusedField = .text
                        },
                        onRefresh: { reflection.requestPrompts(for: entry) },
                        onDismiss: { reflection.dismissPrompts() }
                    )
                    .animation(.default, value: reflection.promptState)
                }

                TextField("Title", text: $entry.title, axis: .vertical)
                    .font(.title.bold())
                    .focused($focusedField, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .text }

                TextField("What's on your mind?", text: $entry.text, axis: .vertical)
                    .font(.body)
                    .lineSpacing(4)
                    .focused($focusedField, equals: .text)
                    .accessibilityIdentifier("entryText")
                    .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $isPickingMood) {
            MoodPickerSheet(entry: entry)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if focusedField != nil {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { focusedField = nil }
                }
            }
        }
        .onAppear {
            if entry.isBlank || startEditing { focusedField = .text }
            if reflection == nil {
                reflection = ReflectionCoordinator(engine: reflectionEngine)
            }
            reflection?.entryDidAppear(entry)
        }
        .onChange(of: entry.title) { textDidChange() }
        .onChange(of: entry.text) { textDidChange() }
        .onDisappear {
            // Don't leave empty entries behind.
            if entry.isBlank {
                modelContext.delete(entry)
            } else {
                reflection?.entryWillClose(entry)
            }
        }
    }

    private func textDidChange() {
        entry.updatedAt = .now
        reflection?.entryDidChange(entry)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: JournalEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let entry = JournalEntry(title: "Sunday", text: "Slow day. Read a lot.")
    container.mainContext.insert(entry)
    return NavigationStack {
        EntryEditorView(entry: entry)
    }
    .environment(\.reflectionEngine, ReflectionEngineFactory.makeOffline())
    .modelContainer(container)
}
