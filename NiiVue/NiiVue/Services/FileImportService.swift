//
//  FileImportService.swift
//  NiiVue
//
//  Task 9: File import service for copying picker results into Application Support.
//  Uses asCopy: true workflow - the picker already creates a temp copy, so we just move it.
//

import Foundation

struct FileImportService {
    struct ImportedFile: Sendable {
        let id: String
        let originalFileName: String
        let localURL: URL
    }

    /// Import a file that was picked with `asCopy: true`.
    /// The `tempURL` is already a local copy in the app's tmp directory.
    ///
    /// - Parameters:
    ///   - tempURL: The temporary URL from the document picker (asCopy: true)
    ///   - destinationDirectory: The library directory to move the file into
    /// - Returns: An ImportedFile with the new location and metadata
    func importDocument(at tempURL: URL, destinationDirectory: URL) async throws -> ImportedFile {
        try await Task.detached(priority: .userInitiated) {
            let fileName = tempURL.lastPathComponent
            let id = UUID().uuidString

            // Create entry directory: Library/<id>/
            let entryDir = destinationDirectory.appendingPathComponent(id, isDirectory: true)
            let destURL = entryDir.appendingPathComponent(fileName)

            try FileManager.default.createDirectory(at: entryDir, withIntermediateDirectories: true)

            // Move (not copy) since tempURL is already a copy from asCopy: true
            try FileManager.default.moveItem(at: tempURL, to: destURL)

            return ImportedFile(id: id, originalFileName: fileName, localURL: destURL)
        }.value
    }

    /// Get the default library directory for imported files
    static func defaultLibraryDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("NiiVue/Library", isDirectory: true)
    }

    /// Ensure the library directory exists
    static func ensureLibraryDirectoryExists() throws {
        let dir = defaultLibraryDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
