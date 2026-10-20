<p align="center">
  <img src="packaging/store/store-logo-300.png" width="96" alt="Diskat logo">
</p>

<h1 align="center">Diskat</h1>

<p align="center">
  Fast disk space analyzer for Windows: find the heaviest folders and clean them up safely.
</p>

![Diskat scanning a drive: folder tree on the left, space map on the right](packaging/store/screenshots/en/01-overview.png)

## Features

Everything in the current release (1.1.0). All of it is free.

### Scan
- **Fast parallel scan**: multi-threaded, no per-file allocations. About 2 million files in 12.5 seconds on an SSD.
- **Live results**: sizes update while scanning and the heaviest folders float to the top. Stop a scan at any time.
- **Any drive**: internal disks, USB drives and network shares, picked from drive cards that show used and free space, from a folder dialog, or by typing a path.
- **Run as Admin** to include protected system folders.
- **Rescan one folder** with `F5` instead of the whole drive.

### Explore
- **Folder tree** with size, "% of parent" bar, file and folder counts and modified date. Click a column header to sort; works fully from the keyboard.
- **Space map** (squarified treemap, two levels): click a tile to select it, double-click to drill in, ↑ to go back up.
- **Largest files**: the top 500 files of the whole scan in one list.
- **File types** tab: space and file count per extension.
- **File age** tab: space by last-modified date, from under a month to over 5 years.

### Find
- **Search every file** in the scan by name pattern (`*.log; *.tmp`, or any part of a name), minimum size and age, largest first.
- **Double-click** a file type or an age range to list all of its files.
- **Open** any item, **show it in Explorer** or **copy its path**.

### Clean up
- **Safe delete**: Recycle Bin by default (`Del`) or permanent (`Shift+Del`), always with a confirmation dialog that shows the full path and size.
- **Multi-select delete** from the Largest files list and search results.
- **Instant totals**: sizes update after a delete, no rescan needed.
- **Files in use**: when a delete fails because a program has the file or folder open, Diskat shows which program, closes it and retries (force-closing only after you confirm), or deletes it at the next Windows restart (as admin). System processes, services and File Explorer are never closed.

### Stay safe
- **Protected folders**: drive roots, Windows, Program Files, ProgramData, the Users folder, every user profile root and AppData can't be deleted, also when reached through a `subst` drive or a junction.
- **No double counting**: junctions and symlinks are listed but never followed.
- **Tricky names** ending in a dot or a space are refused, because Windows would act on a different item.
- **Honest numbers**: the delete dialog warns when a folder wasn't fully scanned.

### Reports and automation
- **PDF report**: summary, drive free space, space map, largest folders and files, file types and file age, in your interface language.
- **CSV export** of the folder tree and of the file list, ready for Excel.
- **Command line** for scripted reports (see below).
- **"Scan with Diskat"** in the Explorer right-click menu for folders and drives (optional, per user, no admin needed).

### Private and portable
- **One portable .exe**: no installer and no .NET to install. Windows 10 and 11, 64-bit. Also packaged as MSIX for the Microsoft Store.
- **11 languages**: English (default), Tiếng Việt, 简体中文, 日本語, 한국어, Español, Português, Deutsch, Français, Русский, Bahasa Indonesia.
- **Private**: no ads, no accounts, no telemetry. The only network access is the optional update check, which is off by default and verifies the download with SHA-256 (the Microsoft Store version never checks; the Store updates it).
- **Open source** under the MIT License.

| Largest files | Safe delete |
|---|---|
| ![Largest files tab](packaging/store/screenshots/en/02-largest-files.png) | ![Delete confirmation dialog](packaging/store/screenshots/en/04-safe-delete.png) |

## Download

Download it from **[diskat.cc](https://diskat.cc/download)**. It is a single self-contained file (Windows 10/11 x64), no .NET install needed.

> The exe is not code-signed yet, so Windows SmartScreen may show "Windows protected your PC" the first time.
> Click **More info** then **Run anyway**, or right-click the file > Properties > **Unblock**.

### Command line

```powershell
# Scan a folder on startup
Diskat.exe "D:\Projects"

# Scripted report: scan, write the files, then exit (exit code 1 if an export failed)
Diskat.exe "D:\Projects" --pdf report.pdf --csv folders.csv --files-csv files.csv --quit

# Other options
Diskat.exe --lang vi                  # interface language for this run only
Diskat.exe --shell-menu on --quit     # add or remove "Scan with Diskat" in Explorer (on|off)
```

## Keyboard shortcuts

| Key | Action |
|---|---|
| `→` / `←` | Expand / collapse (or jump to parent) |
| `Enter` | Toggle folder |
| `Del` / `Shift+Del` | Move to Recycle Bin / delete permanently |
| `F5` | Rescan the selected folder |
| `Enter` in the search box | Search files on the Largest files tab |

## Building from source

Requires the [.NET 9 SDK](https://dotnet.microsoft.com/download/dotnet/9.0) on Windows.

```powershell
# Run in debug
dotnet run

# Single self-contained exe in .\dist
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true -p:PublishReadyToRun=true -p:DebugType=none -o dist
```

### Project layout

| Path | Contents |
|---|---|
| `Core/` | Parallel scanner (with file type and age totals), directory tree model, delete / Recycle Bin operations, locked-file finder (Restart Manager), file search, updater, Explorer menu entry, command line, localization (`Core/Lang`, 11 languages) |
| `UI/` | Flattened tree rows, treemap control, confirmation, locked-file and update dialogs, PDF report (PDFsharp) |
| `site-src/guides/` | Markdown sources of the website guides, built into `website/guides/` by `node tools/build-pages.js` |
| `Themes/` | Styles and the vector logo (`Logo.xaml`, also used to generate `app.ico` and Store tiles) |
| `MainWindow.*` | Main window: scanning, tree, map and actions |
| `packaging/` | Microsoft Store (MSIX) packaging scripts, tiles, listing text and screenshots |
| `website/` | Landing page for [diskat.cc](https://diskat.cc), deployed to Cloudflare (`wrangler.jsonc`) |

### Microsoft Store package (MSIX)

```powershell
powershell -ExecutionPolicy Bypass -File packaging\build-msix.ps1 -IdentityName "<Package/Identity/Name>" -Publisher "CN=<...>" -PublisherDisplayName "<...>"
```

The identity values come from Partner Center > Product identity. On first run the script downloads Microsoft's packaging tools (`Microsoft.Windows.SDK.BuildTools`: makeappx, makepri) from nuget.org into `packaging\.tools` and checks their signature. Output: `packaging\out\Diskat_<version>_x64.msix`.
Store tiles are generated from the logo with `powershell -STA -File packaging\make-assets.ps1`.

### Website (diskat.cc)

The landing page in `website/` is plain HTML/CSS/JS, served by a Cloudflare Worker with static assets (`wrangler.jsonc`).
`/download` is handled by `worker/index.js`, which streams `Diskat.exe` from the R2 bucket `diskat-downloads`.
`/changelog` and `/license` are generated from `CHANGELOG.md` and `LICENSE` by `node tools/build-pages.js`.

```powershell
npx wrangler dev      # preview at http://localhost:8787
npx wrangler deploy   # publish to https://diskat.cc
```

Publishing a new version:

```powershell
npx wrangler r2 object put diskat-downloads/releases/v1.1.0/Diskat.exe --file dist\Diskat.exe --remote
# then set LATEST_VERSION in wrangler.jsonc, update CHANGELOG.md, and run:
node tools/build-pages.js
npx wrangler deploy
```

## Contributing

Issues and pull requests are welcome. For questions or support, email fat@diskat.cc.

**Translations.** App strings live in `Core/Lang/Strings.<code>.cs` (English is the source and the fallback for missing keys); website strings live in `website/assets/i18n/<code>.js`. To add a language, copy the English files, translate the values, register the language in `Core/Loc.cs` and `website/assets/app.js`, then run:

```powershell
node tools/check-i18n.js <code>
```

It checks that every key exists and that placeholders such as `{0}` and HTML tags are kept.

## License

Diskat is released under the [MIT License](LICENSE).
