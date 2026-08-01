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

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        // Report what routing actually delivered. For this milestone that IS the
        // product: it proves which type matched and that the sandbox handed over a
        // readable file, which is exactly what the exit gate asks for.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? "unknown"
        label.text = """
            NiiVue Quick Look
            \(url.lastPathComponent)
            type: \(type)
            \(size >= 0 ? ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) : "unreadable")
            """
        // Milestone 1 does no asynchronous work, so the request completes here.
        // From Milestone 3 this must move behind the single completion gate.
        handler(nil)
    }
}
