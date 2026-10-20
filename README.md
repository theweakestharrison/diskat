<p align="center">
  <img src="packaging/store/store-logo-300.png" width="96" alt="Diskat logo">
</p>

<h1 align="center">Diskat</h1>

<p align="center">
  Fast disk space analyzer for Windows: find the heaviest folders and clean them up safely.
</p>

![Diskat scanning a drive: folder tree on the left, space map on the right](packaging/store/screenshots/en/01-overview.png)

## Features

- **Fast parallel scan**: multi-threaded, no per-file allocations. About 2 million files in 15 seconds on an SSD.
- **Live results**: sizes update while scanning and the heaviest folders float to the top.
- **Folder tree** with size, "% of parent" bar, file and folder counts, modified date. Click a column header to sort.
- **Space map** (squarified treemap): click a tile to select it, double-click to drill in, ↑ to go back up.
- **Largest files** across the whole scan (top 500), with multi-select delete.
- **Safe delete**: Recycle Bin by default (`Del`) or permanent (`Shift+Del`), always with a confirmation dialog.
  Drive roots, Windows, Program Files, ProgramData and user profile roots are protected.
- **No double counting**: junctions and symlinks are listed but never followed.
- **Run as Admin** to include protected system folders.
- **11 languages**: English (default), Tiếng Việt, 简体中文, 日本語, 한국어, Español, Português, Deutsch, Français, Русский, Bahasa Indonesia.
- Fully offline: no telemetry, no network access.

| Largest files | Safe delete |
|---|---|
| ![Largest files tab](packaging/store/screenshots/en/02-largest-files.png) | ![Delete confirmation dialog](packaging/store/screenshots/en/04-safe-delete.png) |

## Download

Get it from **[diskat.cc](https://diskat.cc)** or the [Releases](../../releases) page. It is a single self-contained file (Windows 10/11 x64), no .NET install needed.

> The exe is not code-signed yet, so Windows SmartScreen may show "Windows protected your PC" the first time.
> Click **More info** then **Run anyway**, or right-click the file > Properties > **Unblock**.

You can also pass a folder on the command line: `Diskat.exe "D:\Projects"`.

## Keyboard shortcuts

| Key | Action |
|---|---|
| `→` / `←` | Expand / collapse (or jump to parent) |
| `Enter` | Toggle folder |
| `Del` / `Shift+Del` | Move to Recycle Bin / delete permanently |
| `F5` | Rescan the selected folder |

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
| `Core/` | Parallel scanner, directory tree model, delete / Recycle Bin operations, localization (EN/VI strings) |
| `UI/` | Flattened tree rows, treemap control, confirmation dialog |
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

The landing page in `website/` is plain HTML/CSS/JS (no build step), served by a Cloudflare Worker with static assets.
Short links such as `/download` and `/github` are defined in `website/_redirects`.

```powershell
npx wrangler dev      # preview at http://localhost:8787
npx wrangler deploy   # publish to https://diskat.cc
```

## Contributing

Issues and pull requests are welcome.

**Translations.** App strings live in `Core/Lang/Strings.<code>.cs` (English is the source and the fallback for missing keys); website strings live in `website/assets/i18n/<code>.js`. To add a language, copy the English files, translate the values, register the language in `Core/Loc.cs` and `website/assets/app.js`, then run:

```powershell
node tools/check-i18n.js <code>
```

It checks that every key exists and that placeholders such as `{0}` and HTML tags are kept.

## License

Diskat is released under the [MIT License](LICENSE).
