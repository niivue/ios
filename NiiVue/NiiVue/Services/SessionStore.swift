//
//  SessionStore.swift
//  NiiVue
//
//  Phase 2 Task 6: Session Save/Restore Pack
//  Persists thin session snapshots (file IDs + viewer state, NOT base64 image data).
//

import Foundation

enum SessionStoreError: Error, Equatable {
    case invalidID
}

/// Manages session snapshots and provides save/load functionality.
/// Uses actor isolation for thread-safe access.
actor SessionStore {
    private let sessionsDirectory: URL

    init(sessionsDirectory: URL = SessionStore.defaultSessionsDirectory()) {
        self.sessionsDirectory = sessionsDirectory
    }

    private func sessionFileURL(for id: String) throws -> URL {
        guard let uuid = UUID(uuidString: id) else {
            throw SessionStoreError.invalidID
        }
        return sessionsDirectory.appendingPathComponent("\(uuid.uuidString).json")
    }

    static func defaultSessionsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NiiVue/Sessions", isDirectory: true)
    }

    /// Saves a session JSON string and returns its ID.
    /// - Parameter json: The session JSON to save
    /// - Returns: The session ID (UUID string)
    func save(json: String) throws -> String {
        let id = UUID().uuidString
        let fm = FileManager.default

        // Ensure sessions directory exists
        try fm.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true, attributes: nil)

        // Write session file
        let sessionFile = sessionsDirectory.appendingPathComponent("\(id).json")
        try json.write(to: sessionFile, atomically: true, encoding: .utf8)

        return id
    }

    /// Loads a session JSON string by ID.
    /// - Parameter id: The session ID
    /// - Returns: The session JSON string
    func load(id: String) throws -> String {
        let sessionFile = try sessionFileURL(for: id)
        return try String(contentsOf: sessionFile, encoding: .utf8)
    }

    /// Lists all saved session IDs.
    /// - Returns: Array of session IDs (most recent first)
    func list() throws -> [String] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: sessionsDirectory.path) else {
            return []
        }

        let files = try fm.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])

        // Sort by modification date (most recent first)
        let sorted = files
            .filter { $0.pathExtension == "json" }
            .filter { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
            .sorted { (a, b) -> Bool in
                let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return aDate > bDate
            }

        return sorted.map { $0.deletingPathExtension().lastPathComponent }
    }

    /// Deletes a session by ID.
    /// - Parameter id: The session ID to delete
    func delete(id: String) throws {
        let sessionFile = try sessionFileURL(for: id)
        try FileManager.default.removeItem(at: sessionFile)
    }
}
