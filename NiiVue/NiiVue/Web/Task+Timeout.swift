//
//  Task+Timeout.swift
//  NiiVue
//
//  Async helpers used by long-running operations (e.g. DICOM conversion).
//

import Foundation

extension Task where Failure == Error {
    /// Runs `work` with a timeout; throws `NiivueError.operationTimeout` on deadline.
    static func withTimeout<T>(
        seconds: TimeInterval,
        operation: String,
        priority: TaskPriority? = nil,
        work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let timeoutSeconds = max(0.0, seconds)
        let timeoutNanoseconds = UInt64(timeoutSeconds * 1_000_000_000)

        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(priority: priority) {
                try await work()
            }

            group.addTask(priority: .utility) {
                try await Task<Never, Never>.sleep(nanoseconds: timeoutNanoseconds)
                throw NiivueError.operationTimeout(operation: operation, timeoutSeconds: timeoutSeconds)
            }

            guard let result = try await group.next() else {
                throw NiivueError.operationTimeout(operation: operation, timeoutSeconds: timeoutSeconds)
            }

            group.cancelAll()
            return result
        }
    }
}
