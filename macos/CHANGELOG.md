# Changelog (macOS)

Changes to the macOS version of Diskat. It is versioned separately from the Windows app
(see the main [CHANGELOG](../CHANGELOG.md)); version numbers follow the Windows release whose features it matches.

## [1.1.0] - Unreleased

Brings the features of Diskat 1.1 for Windows to the Mac.

### Added
- **File types** tab: space and file count per extension. Double-click a type to list every file of that type.
- **File age** tab: space by last-modified date, from under a month to over 5 years. Double-click a row to list files older than that.
- **Find files** on the Largest files tab: search the whole scan by name pattern (`*.log; *.tmp`), minimum size and age, largest first, then delete from the results.
- **Duplicates** tab: finds files with identical content (same size, then the first 64 KB, then the whole file, SHA-256). Files stored only in iCloud are skipped so nothing is downloaded, hard links count as one file, and APFS clones are marked because deleting one frees little space. `/System`, `/Library`, `/Applications`, `~/Library` and the inside of apps and other packages are skipped by default. **Select all but newest**, then delete through the usual flow; Diskat never lets you select every copy of a group and checks again just before deleting that nothing changed.
- **Compare with an earlier scan**: after each finished scan Diskat saves a compact copy of the folder tree on this Mac (folder names, sizes and counts only), keeping the latest 10 scans of each folder. Pick one from the ⋯ menu to add a **Change** column, mark new folders and show how much the whole folder grew. Saving can be turned off and all saved scans deleted from the same menu.
- **PDF report** of a scan (summary, volume free space, space map, largest folders and files, file types, file age, and the change when comparing), in the interface language.
- **CSV export** of the folder tree and of the file list, UTF-8 with the separator Excel expects in your region.
- **Theme**: follow macOS, or always light or dark (⋯ > Theme, or View > Theme). The space map uses softer colors on dark backgrounds.
- **Check for updates** (off by default): downloads the new DMG to Downloads, checks its SHA-256 and opens it.
- **"Scan with Diskat"** in the Finder right-click menu (Services / Quick Actions) for folders.
- **Command line**: `Diskat.app/Contents/MacOS/Diskat ~/Data --pdf report.pdf --csv folders.csv --files-csv files.csv --compare --lang vi --quit` for scripted reports.

## [1.0.0] - 2026-10-20

First macOS release: parallel `getattrlistbulk` scanner, live folder tree, space map, largest files, Trash /
permanent delete with protected macOS folders, rescan, Full Disk Access prompt, volume cards, 11 languages.
