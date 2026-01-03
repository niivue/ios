//
//  NiivueURLRouter.swift
//  NiiVue
//
//  Task 10: URL router for niivue:// custom scheme
//  Routes requests to appropriate handlers with path traversal protection.
//

import Foundation

struct NiivueURLRouter {
    enum Route {
        case dist(path: String)           // Bundle `dist/` (Vite output)
        case sample(path: String)         // Bundle `samples/`
        case importedFile(id: String)     // `files/<id>` (app sandbox)
    }

    /// Routes a niivue:// URL to the appropriate handler.
    /// Returns nil for invalid URLs or security violations.
    ///
    /// URL structure:
    /// - `niivue://app/` or `niivue://app/index.html` → dist/index.html
    /// - `niivue://app/assets/...` → dist/assets/...
    /// - `niivue://app/samples/filename.nii.gz` → samples/filename.nii.gz
    /// - `niivue://app/files/<id>` → Application Support/NiiVue/Library/<id>/
    func route(_ url: URL) -> Route? {
        // Validate scheme
        guard url.scheme == "niivue" else { return nil }

        // Validate host
        guard url.host == "app" else { return nil }

        // `URL.pathComponents` is percent-decoded; reject traversal after decoding.
        let components = url.pathComponents.filter { $0 != "/" }

        // Security check: reject path traversal attempts
        guard !components.contains(".."), !components.contains(".") else { return nil }

        // Route based on first path component
        if let first = components.first {
            switch first {
            case "files":
                // Need exactly 2 components: ["files", "<id>"]
                guard components.count == 2 else { return nil }
                let id = components[1]
                guard !id.isEmpty else { return nil }
                return .importedFile(id: id)

            case "samples":
                // samples/<path>
                let path = components.dropFirst().joined(separator: "/")
                guard !path.isEmpty else { return nil }
                return .sample(path: path)

            default:
                // Default: serve from dist/ (Vite output)
                let distPath = components.joined(separator: "/")
                return .dist(path: distPath)
            }
        }

        // Root URL → index.html
        return .dist(path: "index.html")
    }
}
