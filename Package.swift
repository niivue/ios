// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Requires Swift 5.9+ for modern resource bundling and concurrency features.

import PackageDescription

let package = Package(
    name: "NiivueKit",

    // MARK: - Platform Support

    /// Minimum platform versions:
    /// - iOS 16.0: Required for WebGL 2.0 stability + WKWebView enhancements
    /// - macOS 13.0 (Catalyst): Enables iPad apps on Apple Silicon Macs
    /// - visionOS 1.0: Future WebXR compatibility for spatial computing
    platforms: [
        .iOS(.v16),
        .macCatalyst(.v16),
        .visionOS(.v1)
    ],

    // MARK: - Products

    /// Main library product that consumers will import
    products: [
        .library(
            name: "NiivueKit",
            targets: ["NiivueKit"]
        )
    ],

    // MARK: - Dependencies

    /// No external SPM dependencies - package is self-contained
    /// All functionality provided via bundled React app + WASM modules
    dependencies: [
        // Intentionally empty for maximum stability
    ],

    // MARK: - Targets

    targets: [
        // Main target containing all Swift code and bundled resources
        .target(
            name: "NiivueKit",
            dependencies: [],
            resources: [
                // React application build output (Vite dist/)
                // Contains: index.html, JS bundles, CSS, WASM modules, fonts
                // MUST use .copy() to preserve directory structure and hash-based filenames
                .copy("Resources/dist"),

                // Sample neuroimaging files for demos and testing
                // Contains: T1w_DEMO.nii.gz (demo brain scan)
                .copy("Resources/samples")
            ],
            swiftSettings: [
                // Enable strict concurrency checking for modern Swift concurrency
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),

        // Test target with minimal fixtures
        .testTarget(
            name: "NiivueKitTests",
            dependencies: ["NiivueKit"],
            resources: [
                // Test fixtures: minimal neuroimaging volumes for unit tests
                .copy("Resources/Fixtures")
            ]
        )
    ],

    // MARK: - Swift Language Version

    swiftLanguageVersions: [.v5]
)
