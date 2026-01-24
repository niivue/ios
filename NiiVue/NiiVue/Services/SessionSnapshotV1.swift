//
//  SessionSnapshotV1.swift
//  NiiVue
//
//  Phase 2 Task 6: Session Save/Restore Pack
//  Stores volume sources + thin viewer state (no encoded image blobs).
//

import Foundation

enum SessionSnapshotError: Error, Equatable {
    case invalidJSON
    case invalidViewerState
}

/// Persisted session payload (v1).
///
/// - `volumeSources`: Sources to reload the volume stack (e.g., `niivue://app/files/<id>` and `niivue://app/samples/...`).
/// - `viewerState`: Thin per-volume state (colormap/opacity/frame).
struct SessionSnapshotV1: Codable, Equatable {
    struct VolumeSource: Codable, Equatable {
        let url: String
        let name: String
    }

    struct ViewerStateVolume: Codable, Equatable {
        var colormap: String?
        var opacity: Double?
        var frame4D: Int?
    }

    struct ViewerStateSnapshot: Codable, Equatable {
        var volumes: [ViewerStateVolume]
    }

    let version: Int
    let volumeSources: [VolumeSource]
    let viewerState: ViewerStateSnapshot

    static func make(volumeSources: [VolumeSource], viewerStateJSON: String) throws -> SessionSnapshotV1 {
        guard let data = viewerStateJSON.data(using: .utf8) else {
            throw SessionSnapshotError.invalidViewerState
        }

        let decoder = JSONDecoder()
        let viewerState = try decoder.decode(ViewerStateSnapshot.self, from: data)

        return SessionSnapshotV1(
            version: 1,
            volumeSources: volumeSources,
            viewerState: viewerState
        )
    }

    func viewerStateJSONString() throws -> String {
        let data = try JSONEncoder().encode(viewerState)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SessionSnapshotError.invalidJSON
        }
        return json
    }
}

