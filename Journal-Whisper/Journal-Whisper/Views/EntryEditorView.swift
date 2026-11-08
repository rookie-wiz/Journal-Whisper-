//
//  EntryEditorView.swift
//  Journal-Whisper
//

import SwiftUI
import SwiftData

/// A distraction-free editor. Changes save automatically through SwiftData.
struct EntryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var entry: JournalEntry
    /// When true, the editor opens with the keyboard up (used by the Edit swipe action).
    var startEditing = false

    @FocusState private var focusedField: Field?
    private enum Field { case title, text }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.createdAt, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Title", text: $entry.title, axis: .vertical)
                    .font(.title.bold())
                    .focused($focusedField, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .text }

                TextField("What's on your mind?", text: $entry.text, axis: .vertical)
                    .font(.body)
                    .lineSpacing(4)
                    .focused($focusedField, equals: .text)
                    .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
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
        }
        .onChange(of: entry.title) { entry.updatedAt = .now }
        .onChange(of: entry.text) { entry.updatedAt = .now }
        .onDisappear {
            // Don't leave empty entries behind.
            if entry.isBlank {
                modelContext.delete(entry)
            }
        }
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
    .modelContainer(container)
}
