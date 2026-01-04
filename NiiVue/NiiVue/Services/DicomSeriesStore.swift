//
//  DicomSeriesStore.swift
//  NiiVue
//
//  Phase 2 Task 8: Actor-based store for DICOM series registration and manifest generation.
//  Supports the niivue:// custom scheme for serving DICOM files to the web view.
//

import Foundation

/// Actor-based store that manages DICOM series for the custom URL scheme.
/// Each series is registered with a unique ID and can generate a manifest for Niivue.
actor DicomSeriesStore {
    /// Storage for registered series: seriesId -> [fileName: localURL]
    private var series: [String: [String: URL]] = [:]

    /// Register a collection of DICOM files as a series.
    /// - Parameter files: Array of local file URLs to register
    /// - Returns: A unique series identifier
    func register(files: [URL]) -> String {
        let seriesId = UUID().uuidString

        var fileMap: [String: URL] = [:]
        for file in files {
            let fileName = file.lastPathComponent
            fileMap[fileName] = file
        }

        series[seriesId] = fileMap
        return seriesId
    }

    /// Generate manifest text for a series.
    /// The manifest contains one filename per line, sorted alphabetically.
    /// IMPORTANT: No trailing newline (Niivue doesn't ignore empty lines).
    /// - Parameter seriesId: The series identifier
    /// - Returns: Manifest text with one filename per line
    func manifestText(for seriesId: String) -> String {
        guard let fileMap = series[seriesId] else {
            return ""
        }

        // Sort filenames alphabetically for deterministic manifest
        let sortedFileNames = fileMap.keys.sorted()

        // Join with newline but NO trailing newline
        return sortedFileNames.joined(separator: "\n")
    }

    /// Resolve a file URL for a given series and filename.
    /// - Parameters:
    ///   - seriesId: The series identifier
    ///   - fileName: The filename to resolve
    /// - Returns: The local file URL, or nil if not found
    func url(for seriesId: String, fileName: String) -> URL? {
        return series[seriesId]?[fileName]
    }

    /// Check if a series exists.
    /// - Parameter seriesId: The series identifier
    /// - Returns: True if the series is registered
    func contains(seriesId: String) -> Bool {
        return series[seriesId] != nil
    }

    /// Remove a series from the store.
    /// - Parameter seriesId: The series identifier to remove
    func remove(seriesId: String) {
        series.removeValue(forKey: seriesId)
    }
}
