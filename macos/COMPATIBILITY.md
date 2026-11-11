# macOS compatibility

Diskat targets macOS 11.0 (Big Sur) and later on Intel and Apple Silicon. Building,
packaging, and running the XCTest suite requires Swift 5.7+ (Xcode 14.1+).
The Windows project and the download endpoints are unchanged.

## Shared implementation

- The scanner, file operations, reports, and models are shared across supported
  macOS versions. `LockedState` owns its lock and protected state and does not
  depend on the macOS 13-only `OSAllocatedUnfairLock` API.
- Models use Combine's `ObservableObject`. Duplicate files forward changes to
  their group, groups to the duplicates model, and that model to the app model.
  This keeps counts, checked copies, menus, and delete availability in sync.
- Small availability adapters live in `Sources/Diskat/Support/Compatibility`.
  macOS 13+ retains SwiftUI tables and selection context menus. macOS 14+ retains
  the SwiftUI duplicates list when built with Xcode 15+. Older systems use AppKit
  tables with multi-selection, row context menus, double-click, and keyboard
  actions. Native prominent button styles are used on macOS 12+.
- `WindowGroup` supplies the main scene on all supported systems; Diskat replaces
  the New Window command and uses the same shared application model.
- On older kernels without APFS clone reference counts, shared-block flags keep
  reclaimable-space estimates conservative. Shared data may have clones outside
  the scanned folder, so Diskat does not promise that deleting it frees space.
- Update downloads still require HTTPS on the trusted host and a matching
  SHA-256. Callback-based URLSession APIs support the Big Sur runtime.

## Build and verify

```bash
swift test --package-path macos -c release

# App integration checks using disposable files (also exercises the debug build)
DISKAT_SELFTEST=1 swift run --package-path macos Diskat

# Default distribution: Intel + Apple Silicon, macOS 11+
macos/scripts/build-app.sh

# Separate architecture-specific packages
ARCH=x86_64 OUT=dist/intel macos/scripts/build-app.sh
ARCH=arm64 OUT=dist/apple-silicon macos/scripts/build-app.sh

# Verify an existing bundle
ARCH=x86_64 macos/scripts/verify-app.sh macos/dist/intel/Diskat.app
```

`build-app.sh` reads the runtime minimum from `Resources/Info.plist`, embeds the
back-deployed Swift concurrency runtime, and adds the bundle's Frameworks search
path. It signs nested libraries before the app. `SIGN_ID` and `NOTARY_PROFILE`
retain their existing Developer ID and notarization behavior.

`verify-app.sh` checks the requested architectures, each executable slice's
minimum macOS version against Info.plist, the embedded concurrency runtime and
its search path, and the bundle's nested signatures. SwiftPM's platform minimum
in `Package.swift` must match Info.plist; verification fails if they diverge.

The macOS GitHub Actions workflow runs the core tests, builds the debug app, packages a universal app,
verifies the DMG, and uploads it as a workflow artifact. This is a build check;
it does not exercise old macOS runtimes.

## Runtime validation

Before advertising a release as verified on all supported systems, run the app
on Big Sur, Monterey, and a current macOS release, including Intel and Apple
Silicon hardware. Exercise folder and volume selection, scan cancellation,
folder tree and map selection, file search, duplicates (including keeping one
copy), context menus and keyboard shortcuts, scan comparison, light/dark theme,
language changes, and PDF/CSV export. Use disposable files for deletion checks.

A binary's deployment target and successful compilation are not a substitute
for running on those systems. Notarization likewise requires a real Developer ID
and Apple notarization credentials; ad-hoc signing only verifies bundle integrity.
