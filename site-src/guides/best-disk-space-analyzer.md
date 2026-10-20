---
title: The best free disk space analyzers for Windows (2026)
description: Diskat, WizTree, WinDirStat, TreeSize Free and SpaceSniffer compared: price, use at work, open source, treemap, duplicates and what each one does best.
slug: best-disk-space-analyzer
lang: en
updated: 2026-10-20
---
A disk space analyzer scans a drive and shows which folders and files take up the space, so you can delete the right things instead of guessing. Windows doesn't include one: File Explorer won't even show folder sizes in its list view. Luckily there are several good free tools. This page compares five of them on what matters when you choose: the price at home and at work, the license, how they show your data and what they help you do next.

Diskat is our own app, so we've tried to be fair and to say clearly where another tool is the better pick. The facts about the other tools come from their official websites, checked in October 2026. Prices and features change, so check the current terms before you decide.

## Quick comparison

| | Diskat | WizTree | WinDirStat | TreeSize Free | SpaceSniffer |
|---|---|---|---|---|---|
| Price at home | Free | Free | Free | Free | Free (donations) |
| Use at work | Free | Paid license | Free | Paid editions only | Not stated on its website |
| Open source | Yes (MIT) | No | Yes (GPL-3.0) | No | No |
| Main view | Size-sorted folder tree | Tree and file list | Tree, file types, treemap | Explorer-style tree | Treemap |
| Treemap | Yes | Yes | Yes | Yes | Yes |
| Duplicate files | Yes (Diskat 1.2) | Yes | Yes | Paid editions | Not listed |
| Export | PDF and CSV | CSV | CSV and JSON | PDF | Text report |
| How you get it | One portable .exe | Installer or portable | Installer, portable or Microsoft Store | Installer or portable | Portable |

## Diskat

Diskat is a free, open-source disk space analyzer for Windows 10 and 11, released under the MIT license. It scans many folders in parallel: in our test, a 476 GB laptop SSD with 1.95 million files took about 12.5 seconds, without administrator rights. Results appear while it scans and the heaviest folders float to the top.

Its main view is a folder tree sorted by size, with a two-level space map beside it. Tabs show the 500 largest files, space by file type and by file age, and from Diskat 1.2, duplicate files sorted by wasted space. You can search every file by name, size and age, and save a PDF report or CSV files for Excel.

Where Diskat stands out is deleting safely. Everything goes to the Recycle Bin by default, system folders and user profile roots can't be deleted, junctions are never followed, and when a file is open in another program Diskat shows which program holds it.

**Best for:** home users and small businesses who want one free tool that finds what's big and removes it safely, with a license that allows use at work.

## WizTree

WizTree, from Antibody Software, is famous for speed. On NTFS drives it reads the Master File Table directly instead of opening folders one by one, which makes full-drive scans very fast. It counts hard links once, so its totals match what Windows reports. It can also find duplicate files and export file lists to CSV, and it's now available for macOS too.

WizTree is free for personal use. Using it commercially needs a paid supporter code, priced by the size of your organization.

**Best for:** scanning big NTFS drives as fast as possible at home.

## WinDirStat

WinDirStat is the classic open-source disk analyzer, released under the GPL. Recent versions have grown into a toolbox for power users: treemaps, sunbursts and flame graphs, file types, logical and physical sizes, duplicate search by content hash, permissions, saved scan snapshots, CSV and JSON export, cleanup tools and even recovery of deleted files. It scans faster on local NTFS drives when you run it as administrator.

**Best for:** power users and admins who want many analysis tools in one free, open-source app.

## TreeSize Free

TreeSize Free comes from JAM Software, a commercial vendor that also sells paid editions. The free edition shows an Explorer-like tree with sizes, a treemap chart, and PDF reports. It's for private, non-commercial use only. Duplicate search, comparing usage over time and more come with TreeSize Personal, from €20.40 per user per year, and TreeSize Professional, from €41 per user per year.

**Best for:** people who want software from an established vendor, or companies that already license a paid TreeSize edition.

## SpaceSniffer

SpaceSniffer, from Uderzo Software, is a portable freeware tool built entirely around a zoomable treemap. Click a box to see inside it, double-click to zoom in, and use the filter box to show only certain types, sizes or dates, such as `*.jpg;>1mb`. You can tag files with colors and open several filtered views of one scan. It also produces text reports.

**Best for:** people who like to explore a drive visually and don't need duplicate detection or a size-sorted list.

## How to choose

- **You want it free at work too:** Diskat or WinDirStat. Both are open source. WizTree and TreeSize need a paid license for business use.
- **You scan huge NTFS drives often:** WizTree is the fastest because it reads the Master File Table.
- **You want the most tools:** WinDirStat, especially for permissions, snapshots and file recovery.
- **You want to clean up safely without learning much:** Diskat, with its size-sorted tree, Recycle Bin by default and protected system folders.
- **You think visually:** SpaceSniffer, or the space map in Diskat and the treemaps in the others.

Whichever you pick, scan first and delete second. Our guides explain what is safe to remove on [a full C drive](/guides/c-drive-full), in [the AppData folder](/guides/appdata-folder-large) and in [the WinSxS folder](/guides/winsxs-folder). For a closer look at one tool, see Diskat compared with [TreeSize](/guides/treesize-alternative), [WinDirStat](/guides/windirstat-alternative), [WizTree](/guides/wiztree-alternative) and [SpaceSniffer](/guides/spacesniffer-alternative), or [download Diskat](/download) and try it on your own drive.

## FAQ

### What is the best free disk space analyzer for Windows?

It depends on what you need. WizTree is the fastest on NTFS drives, WinDirStat has the most tools, and Diskat focuses on finding big files and deleting them safely. Diskat and WinDirStat are also free at work, because they're open source.

### Is there a disk space analyzer built into Windows?

Not really. Settings > System > Storage shows space by broad category, and a folder's Properties window shows its size, but File Explorer doesn't list folder sizes side by side. A disk space analyzer does that for every folder at once.

### Which disk analyzers are free for business use?

Diskat (MIT license) and WinDirStat (GPL) are free at work. WizTree needs a paid license for commercial use, and TreeSize Free is for private use only. SpaceSniffer's website doesn't state terms for business use.

### Are disk space analyzers safe?

Scanning only reads folder information, so it's safe. The risk is in deleting. Prefer a tool that moves files to the Recycle Bin and protects system folders, and don't delete anything in `C:\Windows`, Program Files or ProgramData by hand.
