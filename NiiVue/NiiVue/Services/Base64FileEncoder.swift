//
//  Base64FileEncoder.swift
//  NiiVue
//
//  Swift 6 concurrency: keep heavy file IO off the MainActor.
//

import Foundation

enum Base64FileEncoder {
    static func encodeFileToBase64(url: URL, maxBytes: Int) -> String? {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize <= maxBytes else {
            print("Skipping base64 fallback: file too large or size unknown (\(url.lastPathComponent))")
            return nil
        }

        do {
            let fileData = try Data(contentsOf: url)
            return fileData.base64EncodedString()
        } catch {
            print("Error reading file for base64 encoding: \(error)")
            return nil
        }
    }
}

