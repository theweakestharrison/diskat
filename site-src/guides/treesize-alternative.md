---
title: Diskat vs TreeSize Free
description: Diskat vs TreeSize Free compared. Both map what fills your drive, but only Diskat is open source and free to use at work. Here is where each one fits best.
slug: treesize-alternative
lang: en
updated: 2026-10-20
---
TreeSize Free is a disk space analyzer from JAM Software, a commercial software company that also sells paid editions. Diskat is a free, open-source disk space analyzer released under the MIT license. Both show which folders are using your space and let you clean them up. The biggest differences are licensing and which features you get without paying. This page compares them honestly, including when TreeSize is the better choice.

The facts about TreeSize on this page come from JAM Software's official website, checked in October 2026. Prices and editions change, so check the current terms before you decide.

## At a glance

| Feature | Diskat | TreeSize Free |
|---|---|---|
| Made by | Open-source project | JAM Software |
| Price for home use | Free | Free |
| Use at work | Free (MIT license) | Free edition is for private, non-commercial use only |
| Paid editions | None | From €20.40 per user per year |
| Treemap | Two-level space map | Yes |
| PDF report | Yes (Diskat 1.1) | Yes, PDF export and printing |
| File type and file age statistics | Yes (Diskat 1.1) | In the paid editions |
| Excel or CSV export | CSV (Diskat 1.1) | In the paid editions |
| Shows which program locks a file | Yes (Diskat 1.1) | Not advertised |
| Platform | Windows 10 and 11, 64-bit | Windows |

## Licensing: the biggest difference

TreeSize Free is free for private, non-commercial use. If you want to use TreeSize at work, you need one of the paid editions, which start at €20.40 per user per year.

Diskat is released under the MIT license. It's free for everyone, at home and at work, and there is no paid edition. The source code is public, so you or your IT team can check exactly what it does. For a small business, a school or an IT person who helps others with their PCs, that removes the licensing question entirely.

## Treemap and reports

A treemap draws every folder as a rectangle sized by how much space it uses, so the biggest folders stand out at a glance. In Diskat this is the **Space map** tab. It shows two levels at once. Click a tile to select it, double-click to drill into a folder, and go back up with the arrow button or the Up key.

TreeSize Free has a treemap too, and it can export a scan to PDF or print it. So for a quick look at a drive at home, both tools give you the picture.

The difference shows up in the details. From Diskat 1.1, the free app also has **File types** and **File age** tabs, a search for every file by name, size or age, and CSV export of folders and files for Excel. Its PDF report includes the space map, the biggest folders and files, and the file type and file age breakdowns. In TreeSize, file type and file age statistics and Excel or CSV exports are part of the paid editions.

## Scanning

Diskat scans many folders in parallel on several threads. In our test, it scanned a 476 GB laptop SSD with 1.95 million files in about 12.5 seconds, without administrator rights. Sizes update while the scan runs and the heaviest folders move to the top. After you delete something, F5 rescans only that folder.

We haven't compared scan speed with TreeSize Free under identical conditions. If speed matters to you, try both on the same drive.

## Finding and deleting files

Diskat's main views are a folder tree sorted by size, with a "% of parent" bar for each folder, and a **Largest files** tab with the 500 biggest files in the scan. You can select several files there and delete them in one go.

Deleting is built to be safe:

- Del moves items to the Recycle Bin and Shift+Del deletes permanently. Both always ask for confirmation and show the full path and size.
- Diskat refuses to delete drive roots, `C:\Windows` and everything in it, Program Files, ProgramData, `C:\Users` and every user profile root, and the `AppData\Roaming` and `AppData\Local` folders.
- Junctions and symbolic links are never followed, so nothing is counted twice.
- From Diskat 1.1, if a file is open in another program, Diskat shows which program holds it and offers to close it and retry, or to delete the file at the next Windows startup.

## Diskat's limitations

- It runs on 64-bit Windows 10 and 11 only.
- It shows logical file sizes, not size on disk. OneDrive files that are online-only and compressed files can look larger than the space they really use.
- Files with hard links are counted once per link, so folders such as `C:\Windows` look larger than their real footprint.
- There's no paid edition and no paid support contract. Support comes from the project itself.
- The .exe isn't code-signed yet, so Windows SmartScreen may warn the first time you run it.

## When to choose Diskat

- You need a disk space analyzer at work and don't want to buy a license.
- You want file type and file age statistics and CSV export without paying for them.
- You prefer open-source software you can inspect.
- You want strong protection against deleting the wrong folder.
- You want a single portable .exe you can run without installing anything.

## When to choose TreeSize

- You want a product from a commercial vendor, with paid editions you can buy and license per user.
- Your company already licenses a paid TreeSize edition.
- You need a feature in TreeSize's paid editions that Diskat doesn't have. Check JAM Software's feature list for your use case.
- You only use it at home, the free edition covers what you need, and you're happy with it.

If you want to see the difference yourself, [download Diskat](/download) and scan the same drive with both tools. Once you know what is big, the guides on [freeing up disk space](/guides/free-up-disk-space-windows) and [the AppData folder](/guides/appdata-folder-large) explain what is safe to remove.

## FAQ

### Is TreeSize Free free for business use?

No. According to JAM Software's website, TreeSize Free is for private, non-commercial use. For business use you need a paid edition, which starts at €20.40 per user per year.

### Does Diskat have a treemap like TreeSize?

Yes. Diskat's Space map is a two-level treemap, and TreeSize Free has a treemap as well. Diskat adds File types and File age views for free.

### Can Diskat export a report?

Yes, from Diskat 1.1. It exports a PDF report with a summary, the space map, the biggest folders and files, and breakdowns by file type and file age. It can also export folders and files as CSV.

### Is Diskat really free?

Yes. Diskat is open source under the MIT license, with no paid edition. You can use it at home and at work, and it sends no telemetry.
