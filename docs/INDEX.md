# NiivueKit Documentation Index

Complete documentation for the NiivueKit Swift Package Manager design.

## Overview

NiivueKit is a Swift SDK that wraps the Niivue neuroimaging visualization library (WebGL-based, runs in WKWebView). This documentation set defines the complete package structure, architecture, and migration process.

## Documentation Files

### 1. SPM_PACKAGE_DESIGN.md (Main Design Document)
**File:** `/Users/leandroalmeida/niivue-ios-foundation/docs/SPM_PACKAGE_DESIGN.md`

**Contents:**
- Complete Package.swift configuration with detailed comments
- Platform support rationale (iOS 16+, Mac Catalyst, visionOS)
- Resource bundling strategy (React dist/, WASM modules)
- Versioning strategy (semantic versioning with asset tracking)
- Target structure rationale (single target vs. modularization)
- Public API design patterns
- Testing strategy (unit tests vs. integration tests)
- Migration from Xcode project to SPM
- Distribution via GitHub + SPM
- Documentation generation with DocC
- Security considerations (CSP, sandboxing)
- Performance optimization strategies
- Build optimization for release
- Troubleshooting common issues
- Release checklist

**Recommended for:** Understanding the overall package design philosophy

---

### 2. DIRECTORY_STRUCTURE.md (File Organization)
**File:** `/Users/leandroalmeida/niivue-ios-foundation/docs/DIRECTORY_STRUCTURE.md`

**Contents:**
- Complete directory tree with explanations
- File organization strategy (Core, Networking, Services, etc.)
- Resource bundling details (dist/ and samples/ structure)
- Access patterns for Bundle.module resources
- Migration script from Xcode project
- Code changes required (Bundle.main → Bundle.module)
- File sizes and package contribution
- Build system integration (SPM build process)
- Common issues and solutions
- Future enhancement possibilities

**Recommended for:** Understanding where files go and how to organize code

---

### 3. MIGRATION_CHECKLIST.md (Step-by-Step Migration)
**File:** `/Users/leandroalmeida/niivue-ios-foundation/docs/MIGRATION_CHECKLIST.md`

**Contents:**
- Phase-by-phase migration plan (9 phases)
- Prerequisites checklist
- Detailed terminal commands for each step
- Verification steps after each phase
- Code modification examples (access control, Bundle access)
- Test migration procedures
- Documentation creation steps
- Example app setup
- Version control setup (Git tags, GitHub)
- CI/CD configuration (GitHub Actions)
- Final verification checklist
- Integration testing
- Troubleshooting guide
- Rollback plan

**Recommended for:** Actually performing the migration from Xcode to SPM

---

### 4. ARCHITECTURE_DIAGRAM.md (Visual Architecture)
**File:** `/Users/leandroalmeida/niivue-ios-foundation/docs/ARCHITECTURE_DIAGRAM.md`

**Contents:**
- High-level architecture diagram (ASCII art)
- Component layer architecture
- Data flow diagrams (loading a volume)
- Custom URL scheme routing visualization
- Service dependencies graph
- Testing architecture
- Platform support matrix
- WebView lifecycle diagram
- Resource loading flow
- Security boundaries visualization
- Async/await concurrency model
- Package distribution flow
- Diagram legend

**Recommended for:** Understanding how components interact and data flows through the system

---

### 5. Package.swift (SPM Manifest)
**File:** `/Users/leandroalmeida/niivue-ios-foundation/Package.swift`

**Contents:**
- Swift tools version: 5.9
- Platform declarations (iOS 16+, macOS Catalyst 16+, visionOS 1+)
- Library product definition
- Target configuration with resource copying
- Test target configuration
- Swift language version

**Recommended for:** Reference implementation of the package manifest

---

## Quick Navigation

### For Package Consumers (Using NiivueKit)

If you want to **use** NiivueKit in your app:
1. See Package.swift for dependency declaration
2. See SPM_PACKAGE_DESIGN.md → "Consumer Integration" section
3. See ARCHITECTURE_DIAGRAM.md → "High-Level Architecture"

### For Package Developers (Contributing to NiivueKit)

If you want to **develop** NiivueKit:
1. Read MIGRATION_CHECKLIST.md for initial setup
2. Read DIRECTORY_STRUCTURE.md for file organization
3. Read SPM_PACKAGE_DESIGN.md for design principles
4. Read ARCHITECTURE_DIAGRAM.md for system understanding

### For Migration (Converting Xcode Project to SPM)

If you're **migrating** the existing Xcode project:
1. Start with MIGRATION_CHECKLIST.md (follow phase by phase)
2. Reference DIRECTORY_STRUCTURE.md for file placement
3. Reference SPM_PACKAGE_DESIGN.md for design decisions
4. Reference Package.swift for manifest configuration

## Document Relationships

```
                    ┌─────────────────────┐
                    │  SPM_PACKAGE_       │
                    │  DESIGN.md          │
                    │  (Design Philosophy)│
                    └──────────┬──────────┘
                               │
                ┌──────────────┼──────────────┐
                │              │              │
                ▼              ▼              ▼
    ┌──────────────────┐ ┌─────────────┐ ┌──────────────────┐
    │ DIRECTORY_       │ │ Package.    │ │ ARCHITECTURE_    │
    │ STRUCTURE.md     │ │ swift       │ │ DIAGRAM.md       │
    │ (Organization)   │ │ (Manifest)  │ │ (Visual)         │
    └──────────────────┘ └─────────────┘ └──────────────────┘
                │              │              │
                └──────────────┼──────────────┘
                               │
                               ▼
                    ┌─────────────────────┐
                    │  MIGRATION_         │
                    │  CHECKLIST.md       │
                    │  (Step-by-Step)     │
                    └─────────────────────┘
```

## Key Concepts Summary

### Swift Package Manager Structure
- Single library target: `NiivueKit`
- Single test target: `NiivueKitTests`
- No external dependencies (self-contained)
- Resources bundled via `.copy()` directive

### Platform Support
- iOS 16.0+ (primary)
- macOS 13.0+ via Mac Catalyst
- visionOS 1.0+ (future WebXR)

### Resource Bundling
- `Resources/dist/` - React app build (3.9MB)
- `Resources/samples/` - Demo neuroimaging files (4.2MB)
- Accessed via `Bundle.module` (not `Bundle.main`)

### Versioning
- Semantic versioning (MAJOR.MINOR.PATCH)
- Git tags (v1.0.0, v1.1.0, etc.)
- Asset updates tracked in CHANGELOG.md
- Breaking change deprecation cycle

### Architecture
- **Core Layer:** WebViewManager, JavaScript bridge
- **Networking Layer:** Custom URL scheme (niivue://)
- **Services Layer:** File import, DICOM, sessions
- **Resource Layer:** Bundled React app + WASM

### Testing
- Unit tests with MockJavaScriptEvaluator
- Integration tests with real WKWebView
- Test fixtures (minimal neuroimaging volumes)
- 80%+ code coverage target

## Code Organization

```
NiivueKit/
├── Package.swift              # SPM manifest
├── Sources/NiivueKit/
│   ├── Core/                  # WebView management
│   ├── Networking/            # URL scheme handling
│   ├── Services/              # Business logic
│   ├── Extensions/            # Swift extensions
│   ├── Models/                # Data models
│   └── Resources/             # Bundled assets
│       ├── dist/              # React app
│       └── samples/           # Demo files
└── Tests/NiivueKitTests/
    ├── Core/                  # Core tests
    ├── Networking/            # URL routing tests
    ├── Services/              # Service tests
    ├── Commands/              # Feature tests
    ├── Mocks/                 # Test utilities
    └── Resources/Fixtures/    # Test data
```

## Migration Phases

1. **Package Structure Setup** - Create directories, Package.swift
2. **Copy Source Files** - Swift sources, resources, tests
3. **Code Modifications** - Bundle.module, access control
4. **Build and Test** - Fix errors, run tests, coverage
5. **Documentation** - DocC comments, README, CHANGELOG
6. **Example App** - Demo integration
7. **Version Control** - Git, tags, GitHub
8. **CI/CD Setup** - GitHub Actions
9. **Final Verification** - Integration test

## File Sizes Reference

| Component | Size | Notes |
|-----------|------|-------|
| Swift sources | ~500KB | Compiled code |
| dist/ resources | 3.9MB | React app + WASM |
| samples/ resources | 4.2MB | Demo brain scan |
| **Total package** | **~8.6MB** | Bundled in framework |

## Platform Requirements

| Platform | Minimum Version | Rationale |
|----------|----------------|-----------|
| iOS | 16.0 | WebGL 2.0 + Swift Concurrency |
| macOS (Catalyst) | 13.0 | Aligned with iOS 16 |
| visionOS | 1.0 | Future WebXR support |
| Xcode | 15.0+ | Swift 5.9+ support |
| Swift | 5.9+ | Modern concurrency features |

## Build Commands Reference

```bash
# Build package
swift build

# Run tests
swift test

# Run tests with coverage
swift test --enable-code-coverage

# Generate documentation
swift package generate-documentation --target NiivueKit

# Preview documentation
swift package --disable-sandbox preview-documentation --target NiivueKit

# Describe package
swift package describe

# Update dependencies (none for NiivueKit)
swift package update

# Clean build
rm -rf .build
```

## Important Links

- **Swift Package Manager Guide:** https://swift.org/package-manager/
- **DocC Documentation:** https://www.swift.org/documentation/docc/
- **Niivue.js:** https://github.com/niivue/niivue
- **WebGL 2.0 Spec:** https://www.khronos.org/webgl/

## Version History

| Version | Date | Description |
|---------|------|-------------|
| 1.0.0 | 2026-01-15 | Initial design documentation |

## Contributing to Documentation

To update these documentation files:

1. Edit the relevant `.md` file in `docs/`
2. Ensure diagrams remain aligned (use monospace font)
3. Update this INDEX.md if adding new files
4. Test all code examples
5. Update version history

## Document Maintenance

**Review schedule:** Quarterly or before major releases

**Owner:** NiivueKit maintainers

**Last updated:** 2026-01-04

---

## Next Steps

After reading this documentation:

1. **To use NiivueKit:** Add to your project via SPM
2. **To develop NiivueKit:** Follow MIGRATION_CHECKLIST.md
3. **To understand architecture:** Read ARCHITECTURE_DIAGRAM.md
4. **To organize files:** Reference DIRECTORY_STRUCTURE.md
5. **To make design decisions:** Consult SPM_PACKAGE_DESIGN.md

For questions or issues, refer to the specific documentation file relevant to your task.
