# Changelog

All notable changes to Diskat are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-20

First public release.

### Download
- Windows 10/11, 64-bit: [Diskat.exe](https://diskat.cc/download/v1.0.0/Diskat.exe) (60.7 MB, portable). SHA-256: `5f24ff3a3a53255f97fcd8c9b3e870d15db72cedb973c09fe2b1be11004e2590`

### Added
- **Parallel scanner**: multi-threaded directory enumeration with no per-file allocations; about 2 million files in 15 seconds on an SSD.
- **Live results** while scanning: sizes update every 200 ms and the heaviest folders are re-sorted to the top every second.
- **Folder tree** with size, "% of parent" bar, file and folder counts and modified date; sortable by any column.
- **Space map** (squarified treemap, two levels deep): click to select, double-click to drill in, ↑ to go back up.
- **Largest files** tab listing the top 500 files of the scan, with multi-select delete.
- **Delete** to the Recycle Bin (`Del`) or permanently (`Shift+Del`), always behind a confirmation dialog that shows the full path and size.
- **Rescan** a single folder with `F5` without rescanning the whole drive.
- **Run as Admin** button to include protected system folders.
- **11 interface languages**: English (default), Vietnamese, Simplified Chinese, Japanese, Korean, Spanish, Portuguese, German, French, Russian and Indonesian, picked from a menu and remembered between runs.
- Drive cards with used / free space for every ready drive.
- Command-line argument to scan a folder on startup: `Diskat.exe "D:\Projects"`.
- Single self-contained `Diskat.exe` (no .NET install needed) and an MSIX package for the Microsoft Store.

### Safety
- Junctions and symbolic links are shown but never followed, so nothing is counted twice and scans can't loop.
- Protected from deletion: drive roots, `Windows` (and everything inside it), `Program Files`, `Program Files (x86)`, `ProgramData`, `ProgramData\Microsoft`, the `Users` folder, every user profile root, `AppData\Roaming` and `AppData\Local`. Checks are applied to the real path too, so a `subst` drive or a junction can't be used to get around them.
- Permanent delete clears read-only attributes only inside the folder being deleted and never walks through junctions or symlinks.
- Names ending in a dot or a space (which Windows APIs silently rewrite, e.g. `foo.` becomes `foo`) are skipped by the scanner and refused for deletion, so the wrong item can never be deleted.
- The confirmation dialog warns when a folder wasn't fully scanned (scan stopped or access denied), because its real size may be larger than shown.
- Only one delete or rescan runs at a time; keyboard shortcuts are blocked while it runs.

[1.0.0]: ../../releases/tag/v1.0.0
