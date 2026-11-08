//
//  DebugSeed.swift
//  Journal-Whisper
//
//  Debug-only helpers for UI tests: seed sample data into an in-memory store.
//  Launch with `-uiTesting -seedActive N -seedDeleted N` (and optionally `-logToFile`).
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
        try? context.save()
    }
}
#endif
