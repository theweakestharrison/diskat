---
title: Diskat vs SpaceSniffer
description: Diskat vs SpaceSniffer: both are free and portable. SpaceSniffer is built around its treemap, Diskat adds a size-sorted tree, duplicates, reports and safe deletion.
slug: spacesniffer-alternative
lang: en
updated: 2026-10-20
---
SpaceSniffer is a small, portable disk space analyzer from Uderzo Software. It is freeware (donations are welcome) and it is built entirely around a treemap: every folder and file is a box sized by how much space it uses, and you zoom in by clicking. Diskat is a free, open-source disk space analyzer with a treemap too, but its main view is a folder tree sorted by size, with tools for finding and deleting files safely. This page compares them honestly, including when SpaceSniffer is the better choice.

The facts about SpaceSniffer on this page come from its official website, checked in October 2026. Software changes, so check the current version before you decide.

## At a glance

| Feature | Diskat | SpaceSniffer |
|---|---|---|
| Made by | Open-source project | Uderzo Software |
| Price | Free | Free (donations welcome) |
| License | MIT (open source) | Freeware, source code not published |
| Installation | None, a single portable .exe | None, portable |
| Main view | Folder tree sorted by size, plus a space map | Zoomable treemap |
| Filters | File types and file age tabs, search by name, size and age | Filter box for type, size, date and tags |
| Duplicate files | Duplicates tab (Diskat 1.2) | Not listed among its features |
| Reports | PDF report and CSV export (Diskat 1.1) | Customizable text reports |
| Shows which program locks a file | Yes (Diskat 1.1) | Not listed among its features |

## Two ways to look at a drive

SpaceSniffer opens straight into a treemap. Bigger boxes are bigger folders and files. Click a box to see what is inside it, double-click to zoom it to the full window, and keep following the biggest boxes until you find what filled the drive. You can open several views of the same disk with different filters, and SpaceSniffer only scans once. It also watches the file system, so boxes blink and update when files change.

Diskat starts with a folder tree sorted by size. Each folder shows its size, a "% of parent" bar, how many files and folders it holds, and when it was last changed, so the heaviest folders sit at the top of every level. The **Space map** tab next to it is a two-level treemap of the folder you selected: click a tile to select it in the tree, double-click to drill in.

Which one feels faster to use is mostly a matter of taste. If you think in pictures, SpaceSniffer's treemap is very direct. If you want exact numbers and a list you can sort, Diskat's tree gives you that and the map on the side.

## Filters and finding files

SpaceSniffer has a filter box. Type `*.jpg` to see only JPEG files, `>1mb` for files over a megabyte, `>2years` for old files, or combine them, for example `*.jpg;>1mb;<3months`. You can also tag files in four colors and filter on the tags.

Diskat spreads the same ideas over a few tabs:

- **Largest files** lists the 500 biggest files in the scan. The search box above it finds every file by name pattern such as `*.log; *.tmp`, minimum size and age, largest first.
- **File types** totals space and file count per extension. Double-click a type to list all of its files.
- **File age** groups space by last-modified date, from under a month to over five years. Double-click a row to list the files older than that.
- From Diskat 1.2, **Duplicates** finds files with identical content and sorts them by wasted space.

## Deleting safely

Finding a big folder is half the job. The other half is removing the right thing. Diskat is built around that second half:

- Del moves items to the Recycle Bin and Shift+Del deletes permanently. Both always ask first and show the full path and size.
- Diskat refuses to delete drive roots, `C:\Windows` and everything in it, Program Files, ProgramData, `C:\Users` and every user profile root, and the `AppData\Roaming` and `AppData\Local` folders.
- Junctions and symbolic links are never followed, so nothing is counted twice and nothing outside the folder is touched.
- If a file is open in another program, Diskat shows which program holds it and can ask it to close, retry, or delete the file at the next Windows startup.

SpaceSniffer's website focuses on viewing, filtering and reporting, so check how it handles deletion in the version you use.

## Reports

SpaceSniffer has an export module that writes a text report, and you can customize its layout.

From Diskat 1.1 you can save a PDF report of a scan, with a summary, the drive's free space, the space map, the largest folders and files, and the file type and file age breakdowns. You can also export the folder tree or a file list as CSV for Excel. From the command line, `Diskat.exe "D:\Data" --pdf report.pdf --quit` writes a report without opening anything by hand.

## Diskat's limitations

- It shows logical file sizes, not size on disk. OneDrive files that are online-only and compressed files can look larger than the space they really use.
- In the folder tree, files with hard links are counted once per link, so `C:\Windows` looks larger than its real footprint.
- It has no tags and no free-form filter language like SpaceSniffer's.
- The .exe isn't code-signed yet, so Windows SmartScreen may warn the first time you run it.

## When to choose Diskat

- You want a folder tree with exact sizes, sorted so the biggest folders come first.
- You want duplicate files, file types, file age, PDF reports and CSV export in one free tool.
- You need to use it at work and want a clear open-source license (MIT).
- You want strong protection against deleting the wrong folder, and help when a file is in use.
- You want the interface in your language: Diskat comes in 11.

## When to choose SpaceSniffer

- You like to explore a drive visually and want the treemap to be the whole interface.
- You want several filtered views of one disk at the same time.
- You use its color tags to keep track of files you've already checked.
- You need to see NTFS alternate data streams, which SpaceSniffer can scan.

Both are portable, so you can try them side by side on the same drive in a few minutes. [Download Diskat](/download), and if you're comparing more tools, see [the best free disk space analyzers for Windows](/guides/best-disk-space-analyzer).

## FAQ

### Is SpaceSniffer free?

Yes. According to its website, SpaceSniffer is freeware and donations are welcome. Its source code is not published.

### Does Diskat have a treemap like SpaceSniffer?

Yes. Diskat's Space map tab is a two-level treemap of the selected folder. Click a tile to select it, double-click to drill in. The main view is a folder tree sorted by size.

### Can SpaceSniffer find duplicate files?

Duplicate detection isn't listed among SpaceSniffer's features. Diskat finds files with identical content in its Duplicates tab, from Diskat 1.2.

### Do I need to install either one?

No. Both are portable. Diskat is a single .exe for Windows 10 and 11 that you can run from any folder or a USB stick.
