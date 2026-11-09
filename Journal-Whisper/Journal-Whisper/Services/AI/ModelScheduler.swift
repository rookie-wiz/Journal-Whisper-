//
//  ModelScheduler.swift
//  Journal-Whisper
//
//  Runs on-device model requests one at a time. Mood analysis, reflection
//  prompts and (later) weekly summaries can otherwise overlap and fail as
//  "busy", or compete for the same model and battery.
//
//  - A waiting user request (prompts) goes ahead of waiting background work (mood).
//  - A user request also interrupts background work that's already running. The
//    background work is cancelled, not failed, so its caller simply tries again
//    later (mood analysis re-runs on the next pause or when the editor closes).
//

import Foundation

actor ModelScheduler {
    static let shared = ModelScheduler()

    enum Priority: Int, Comparable, Sendable {
        case background
        case userInitiated
        static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
    }

    private struct Holder {
        let priority: Priority
        var cancel: (@Sendable () -> Void)?
        /// Set if a user request arrived before `cancel` was registered.
        var preemptRequested = false
    }

    private struct Waiter {
        let id: UUID
        let priority: Priority
        let continuation: CheckedContinuation<Void, any Error>
    }

    private var holder: Holder?
    private var waiters: [Waiter] = []

    /// Runs `body` when the model is free, holding it until `body` finishes.
    func run<T: Sendable>(
        priority: Priority,
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await acquire(priority)
        defer { release() }

        let task = Task { try await body() }
        holder?.cancel = { task.cancel() }
        if holder?.preemptRequested == true { task.cancel() }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - Slot management

    private func acquire(_ priority: Priority) async throws {
        guard let current = holder else {
            holder = Holder(priority: priority)
            return
        }
        if priority > current.priority {
            holder?.preemptRequested = true
            current.cancel?()
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await enqueue(id: id, priority: priority)
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// Suspends until `release()` hands this waiter the model.
    private func enqueue(id: UUID, priority: Priority) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            // Cancelled before queueing: the cancel handler found nothing to remove.
            if Task.isCancelled {
                continuation.resume(throwing: CancellationError())
            } else {
                waiters.append(Waiter(id: id, priority: priority, continuation: continuation))
            }
        }
    }

    private func release() {
        // Highest priority first; first come, first served within a priority.
        guard let index = waiters.indices.max(by: { waiters[$0].priority < waiters[$1].priority || (waiters[$0].priority == waiters[$1].priority && $0 > $1) }) else {
            holder = nil
            return
        }
        let next = waiters.remove(at: index)
        holder = Holder(priority: next.priority)
        next.continuation.resume()
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
