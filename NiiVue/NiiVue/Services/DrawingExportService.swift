//
//  DrawingExportService.swift
//  NiiVue
//
//  Task 5: Service for exporting drawings to NIfTI files
//

import Foundation

/// Service for decoding and writing drawing data to NIfTI files.
struct DrawingExportService {
    enum ExportError: Error, Equatable {
        case invalidBase64
        case writeFailed(String)
    }

    /// Decodes a base64-encoded NIfTI drawing and writes it to disk.
    /// - Parameters:
    ///   - base64: Base64-encoded NIfTI data
    ///   - preferredFileName: Desired filename for the output
    ///   - directory: Directory to write the file to
    /// - Returns: URL of the written file
    /// - Throws: `ExportError` if decoding or writing fails
    func writeNiftiGz(base64: String, preferredFileName: String, directory: URL) throws -> URL {
        guard let data = Data(base64Encoded: base64) else {
            throw ExportError.invalidBase64
        }

        let url = directory.appendingPathComponent(preferredFileName)

        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }

        return url
    }
}
