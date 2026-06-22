import Foundation

/// Tracks the active generation Task so the UI can cancel it.
///
/// The orchestrator does *not* own this — the UI layer hands the Task to this tracker after
/// spawning it. Cancellation propagates through `Task.cancel()`; the orchestrator's streaming
/// loop calls `Task.checkCancellation()` between tokens.
public actor ActiveGenerationTracker {
    private var runningTask: Task<Void, Never>?

    public init() {}

    /// Register a generation task, replacing (and cancelling) any previous in-flight task.
    public func register(_ task: Task<Void, Never>) {
        runningTask?.cancel()
        runningTask = task
    }

    /// Cancel the current generation if one is in flight.
    public func cancel() {
        runningTask?.cancel()
        runningTask = nil
    }

    /// Clear once the generation has completed (success or failure).
    public func clear() {
        runningTask = nil
    }

    public var hasActiveTask: Bool {
        runningTask != nil
    }
}