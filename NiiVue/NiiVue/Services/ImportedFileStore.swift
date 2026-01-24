//
//  ImportedFileStore.swift
//  NiiVue
//
//  Task 10 stub: Provides URL lookup for imported files.
//  Task 12 will fully implement this with loading existing library entries.
//

import Foundation

/// Manages imported files and provides URL lookup by ID.
/// Uses actor isolation for thread-safe access.
actor ImportedFileStore {
    private let libraryDirectory: URL
    private var map: [String: URL]

    init(libraryDirectory: URL = ImportedFileStore.defaultLibraryDirectory()) {
        self.libraryDirectory = libraryDirectory
        self.map = Self.loadMap(libraryDirectory: libraryDirectory)
    }

    static func defaultLibraryDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("NiiVue/Library", isDirectory: true)
    }

    private static func loadMap(libraryDirectory: URL) -> [String: URL] {
        let fm = FileManager.default
        guard let entryDirs = try? fm.contentsOfDirectory(at: libraryDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return [:]
        }

        var map: [String: URL] = [:]
        for entryDir in entryDirs where entryDir.hasDirectoryPath {
            let id = entryDir.lastPathComponent
            if let fileURL = (try? fm.contentsOfDirectory(at: entryDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?.first {
                map[id] = fileURL
            }
        }
        return map
    }

    /// Register an imported file with the store
    func register(importedFile: FileImportService.ImportedFile) {
        map[importedFile.id] = importedFile.localURL
    }

    /// Get the file URL for a given ID
    func url(for id: String) -> URL? {
        map[id]
    }

    /// Get all registered file IDs
    func allIDs() -> [String] {
        Array(map.keys)
    }
}
