//
//  DebugSeed.swift
//  Journal-Whisper
//
//  Debug-only helpers for UI tests: seed sample data into an in-memory store.
//  Launch with `-uiTesting -seedActive N -seedDeleted N` (and optionally `-logToFile`).
//  `-seedWeek` adds a fixed run of mood-tagged entries for the Insights screen.
//

#if DEBUG
import Foundation
import SwiftData

enum DebugSeed {
    private static func intArgument(_ name: String) -> Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return 0 }
        return Int(args[i + 1]) ?? 0
    }

    static func redirectLogIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-logToFile") else { return }
        let url = URL.documentsDirectory.appending(path: "debug.log")
        freopen(url.path, "w", stdout)
        setvbuf(stdout, nil, _IOLBF, 0)
    }

    @MainActor
    static func apply(to container: ModelContainer) {
        guard ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        let context = container.mainContext
        let body = String(repeating: "A long paragraph of journal text that goes on for a while.\n", count: 40)
        for i in 0..<intArgument("-seedActive") {
            context.insert(JournalEntry(
                createdAt: .now.addingTimeInterval(Double(-i) * 3600),
                title: "Entry \(i)", text: body))
        }
        for i in 0..<intArgument("-seedDeleted") {
            let entry = JournalEntry(
                createdAt: .now.addingTimeInterval(Double(-i) * 7200),
                title: i.isMultiple(of: 3) ? "" : "Deleted \(i)", text: body)
            entry.deletedAt = .now.addingTimeInterval(Double(-(i % 29)) * 86_400)
            context.insert(entry)
        }
        if ProcessInfo.processInfo.arguments.contains("-seedWeek") {
            seedWeek(into: context)
        }
        try? context.save()
    }

    /// Entries written today and the two days before (current streak 3), a gap,
    /// then five consecutive days (longest streak 5). Today has two entries, one
    /// without a mood.
    static let seededWeek: [(daysAgo: Int, mood: Mood?)] = [
        (0, .calm), (0, nil), (1, .anxious), (2, .joyful),
        (4, .sad), (5, .content), (6, .calm), (7, .frustrated), (8, .overwhelmed),
    ]

    private static func seedWeek(into context: ModelContext) {
        let calendar = Calendar.current
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now
        for (index, item) in seededWeek.enumerated() {
            // Today's entries go in the morning so they're never in the future.
            let day = calendar.date(byAdding: .day, value: -item.daysAgo, to: noon) ?? noon
            let date = item.daysAgo == 0 ? calendar.startOfDay(for: .now).addingTimeInterval(Double(index + 1) * 60) : day
            let entry = JournalEntry(createdAt: date, title: "Day \(item.daysAgo)", text: "Seeded entry \(index).")
            if let mood = item.mood { entry.setUserMood(mood) }
            context.insert(entry)
        }
    }
}
#endif
