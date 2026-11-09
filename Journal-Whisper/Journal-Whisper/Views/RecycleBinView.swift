//
//  RecycleBinView.swift
//  Journal-Whisper
//

import SwiftUI
import SwiftData

/// Lists entries moved to Recently Deleted. Entries are kept for
/// `JournalEntry.retentionDays` days; restoring is free, but permanently
/// deleting one entry or emptying the bin requires Face ID / passcode.
struct RecycleBinView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppLock.self) private var appLock
    @Query(
        filter: #Predicate<JournalEntry> { $0.deletedAt != nil },
        sort: \JournalEntry.deletedAt,
        order: .reverse
    ) private var deletedEntries: [JournalEntry]

    @State private var entryPendingDeletion: JournalEntry?
    @State private var isConfirmingEmpty = false
    @State private var authFailed = false

    var body: some View {
        List {
            if !deletedEntries.isEmpty {
                Section {
                    ForEach(deletedEntries) { entry in
                        DeletedEntryRow(entry: entry)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    entryPendingDeletion = entry
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button("Restore", systemImage: "arrow.uturn.backward") {
                                    restore(entry)
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button("Restore", systemImage: "arrow.uturn.backward") { restore(entry) }
                                Button("Delete Permanently", systemImage: "trash", role: .destructive) {
                                    entryPendingDeletion = entry
                                }
                            }
                    }
                } footer: {
                    Text("Entries are permanently deleted after \(JournalEntry.retentionDays) days.")
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .overlay {
            if deletedEntries.isEmpty {
                ContentUnavailableView(
                    "No Recently Deleted Entries",
                    systemImage: "trash",
                    description: Text("Deleted entries stay here for \(JournalEntry.retentionDays) days.")
                )
            }
        }
        .toolbar {
            if !deletedEntries.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Empty", role: .destructive) { isConfirmingEmpty = true }
                        .disabled(appLock.isAuthenticating)
                }
            }
        }
        // Confirm deleting a single entry.
        .confirmationDialog(
            "Delete this entry permanently?",
            isPresented: Binding(
                get: { entryPendingDeletion != nil },
                set: { if !$0 { entryPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: entryPendingDeletion
        ) { entry in
            Button("Delete Permanently", role: .destructive) {
                Task { await permanentlyDelete([entry], reason: "Permanently delete this entry") }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone.")
        }
        // Confirm emptying the whole bin.
        .confirmationDialog(
            "Delete all \(deletedEntries.count) entries permanently?",
            isPresented: $isConfirmingEmpty,
            titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) {
                Task { await permanentlyDelete(deletedEntries, reason: "Empty Recently Deleted") }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .alert("Authentication Failed", isPresented: $authFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was deleted.")
        }
        .task { JournalEntry.purgeExpired(in: modelContext) }
    }

    private func restore(_ entry: JournalEntry) {
        withAnimation { entry.deletedAt = nil }
        WeeklySummary.discard(weekContaining: entry.createdAt, in: modelContext)
    }

    private func permanentlyDelete(_ entries: [JournalEntry], reason: String) async {
        guard await appLock.authenticate(reason: reason) else {
            authFailed = true
            return
        }
        for entry in entries {
            WeeklySummary.discard(weekContaining: entry.createdAt, in: modelContext)
        }
        withAnimation {
            entries.forEach(modelContext.delete)
        }
        try? modelContext.save()
    }
}

private struct DeletedEntryRow: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayTitle)
                .font(.headline)
                .lineLimit(1)
            Text(entry.createdAt, format: .dateTime.weekday(.wide).day().month().year())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(daysLeftText)
                .font(.caption)
                .foregroundStyle(entry.daysUntilPurge <= 3 ? .red : .secondary)
        }
        .padding(.vertical, 2)
    }

    private var daysLeftText: String {
        switch entry.daysUntilPurge {
        case 0: "Deletes today"
        case 1: "1 day left"
        case let days: "\(days) days left"
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: JournalEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let old = JournalEntry(title: "Old thoughts", text: "Something I deleted.")
    old.deletedAt = Calendar.current.date(byAdding: .day, value: -28, to: .now)
    let recent = JournalEntry(text: "Deleted this morning.")
    recent.deletedAt = .now
    container.mainContext.insert(old)
    container.mainContext.insert(recent)
    return NavigationStack {
        RecycleBinView()
    }
    .environment(AppLock())
    .modelContainer(container)
}
