//
//  PreviewViewController.swift
//  NiiVue Quick Look preview extension
//
//  Milestone 1 scope: the target exists, is discoverable, and completes a
//  request. The NiiVue rendering shell is Milestone 2 and the scoped file
//  transport is Milestone 3 — deliberately not prototyped here, so that a
//  routing failure in this milestone cannot be confused with a rendering one.
//

import UIKit
import QuickLook

class PreviewViewController: UIViewController, QLPreviewingController {

    private let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.textColor = .white
        label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
        ])
    }

    /// Types we render on sight. Anything arriving as plain gzip has to earn it by
    /// content — see `shouldRender(_:)`.
    private static let gzipType = "org.gnu.gnu-zip-archive"

    /// Decide whether this file is ours to draw.
    ///
    /// We claim `org.gnu.gnu-zip-archive` because that is the only way `.nii.gz`
    /// can reach us at all, which makes us the previewer for *every* `.gz` on the
    /// machine. That is a responsibility, not a licence: a gzip whose payload is
    /// not a NIfTI must fall back to plain archive metadata and never render.
    private func shouldRender(_ url: URL, type: String) -> Bool {
        guard type == Self.gzipType else { return true }
        guard let header = GzipPeek.inflatePrefix(ofFileAt: url) else { return false }
        return VolumeSniff.isNIfTI(header)
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        // Report what routing actually delivered. For this milestone that IS the
        // product: it proves which type matched and that the sandbox handed over a
        // readable file, which is exactly what the exit gate asks for.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? "unknown"
        let sizeText = size >= 0
            ? ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            : "unreadable"

        if shouldRender(url, type: type) {
            label.text = """
                NiiVue Quick Look
                \(url.lastPathComponent)
                type: \(type)
                \(sizeText)
                """
        } else {
            // Somebody else's gzip. Say only what is true of any archive.
            label.text = """
                \(url.lastPathComponent)
                Gzip archive · \(sizeText)
                """
        }
        // Milestone 1 does no asynchronous work, so the request completes here.
        // From Milestone 3 this must move behind the single completion gate.
        handler(nil)
    }
}
