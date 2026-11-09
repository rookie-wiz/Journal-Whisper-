//
//  JournalListView.swift
//  Journal-Whisper
//

import SwiftUI
import SwiftData

struct JournalListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppLock.self) private var appLock
    @Query(
        filter: #Predicate<JournalEntry> { $0.deletedAt == nil },
        sort: \JournalEntry.createdAt,
        order: .reverse
    ) private var entries: [JournalEntry]

    /// Everything pushed onto the journal's navigation stack.
    private enum Route: Hashable {
        case entry(JournalEntry)
        case recycleBin
        case insights
    }

    @State private var path: [Route] = []
    @State private var searchText = ""
    @State private var entryPendingDeletion: JournalEntry?
    /// Entry opened via the Edit swipe action; its editor opens with the keyboard up.
    @State private var entryToEdit: PersistentIdentifier?

    private var filteredEntries: [JournalEntry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedStandardContains(query) || $0.text.localizedStandardContains(query)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(filteredEntries) { entry in
                    NavigationLink(value: Route.entry(entry)) {
                        EntryRow(entry: entry)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button("Edit", systemImage: "pencil") {
                            edit(entry)
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            entryPendingDeletion = entry
                        }
                    }
                }
            }
            .navigationTitle("Journal")
            // One typed destination for the whole stack. Mixing this with
            // navigationDestination(isPresented:) made the bin re-render in a loop.
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .entry(let entry):
                    EntryEditorView(
                        entry: entry,
                        startEditing: entry.persistentModelID == entryToEdit
                    )
                case .recycleBin:
                    RecycleBinView()
                case .insights:
                    InsightsView()
                }
            }
            .confirmationDialog(
                "Delete this entry?",
                isPresented: Binding(
                    get: { entryPendingDeletion != nil },
                    set: { if !$0 { entryPendingDeletion = nil } }
                ),
                titleVisibility: .visible,
                presenting: entryPendingDeletion
            ) { entry in
                Button("Move to Recently Deleted", role: .destructive) {
                    moveToRecycleBin(entry)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("You can restore it from Recently Deleted for \(JournalEntry.retentionDays) days.")
            }
            .task { JournalEntry.purgeExpired(in: modelContext) }
            .onChange(of: path) { _, newPath in
                // Back on the list: a normal tap shouldn't auto-open the keyboard.
                if newPath.isEmpty { entryToEdit = nil }
            }
            .searchable(text: $searchText, prompt: "Search entries")
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No Entries Yet", systemImage: "book")
                    } description: {
                        Text("Tap the pencil to write your first entry.")
                    } actions: {
                        Button("New Entry", action: addEntry)
                            .buttonStyle(.borderedProminent)
                    }
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Lock", systemImage: "lock") {
                        appLock.lock()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Insights", systemImage: "chart.bar.xaxis") {
                        path.append(.insights)
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Recently Deleted", systemImage: "trash") {
                        path.append(.recycleBin)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Entry", systemImage: "square.and.pencil", action: addEntry)
                }
            }
        }
    }

    private func addEntry() {
        let entry = JournalEntry()
        modelContext.insert(entry)
        path.append(.entry(entry))
    }

    /// Opens the entry in the editor with the cursor ready in the text.
    private func edit(_ entry: JournalEntry) {
        entryToEdit = entry.persistentModelID
        path.append(.entry(entry))
    }

    /// Soft-deletes the entry; it's purged after `JournalEntry.retentionDays` days.
    private func moveToRecycleBin(_ entry: JournalEntry) {
        withAnimation {
            entry.deletedAt = .now
        }
        // The week's summary may describe this entry.
        WeeklySummary.discard(weekContaining: entry.createdAt, in: modelContext)
    }
}

private struct EntryRow: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let mood = entry.mood {
                    Text(mood.emoji)
                        .accessibilityLabel(String(localized: "Mood: \(mood.label)"))
                }
                Text(entry.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
            }
            Text(entry.createdAt, format: .dateTime.weekday(.wide).day().month().year())
                .font(.caption)
                .foregroundStyle(.secondary)
            if !entry.preview.isEmpty && !entry.title.isEmpty {
                Text(entry.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: JournalEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(JournalEntry(title: "A calm morning", text: "Walked to the lake and watched the fog lift."))
    container.mainContext.insert(JournalEntry(text: "Exams next week.\nFeeling a bit nervous but prepared."))
    return JournalListView()
        .environment(AppLock())
        .modelContainer(container)
}
