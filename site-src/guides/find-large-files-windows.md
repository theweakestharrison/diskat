---
title: How to find large files on Windows
description: Find the large files filling your Windows 10 or 11 PC using File Explorer search, Storage settings or a disk space analyzer, then delete them safely.
slug: find-large-files-windows
lang: en
updated: 2026-10-20
---
A few large files often take up more space than thousands of small ones. An old video export, a forgotten ISO file or a virtual machine disk can each use tens of gigabytes. The hard part is finding them, because Windows doesn't show folder sizes in File Explorer. This guide covers four ways to track them down, from built-in tools to a dedicated analyzer, and what to check before you delete anything.

## Method 1: Search by size in File Explorer

File Explorer can filter search results by size. It's built in and works well for a single drive or folder.

1. Open File Explorer and go to the drive or folder you want to search, for example This PC or `C:\Users\YourName`.
2. Click the search box in the top right corner.
3. Type `size:>1GB` and press Enter. You can use other values too, such as `size:>500MB`.
4. Switch to the **Details** view and click the **Size** column to sort the results, largest first.

This search includes subfolders, so it can take a while on a full drive, especially in locations that Windows doesn't index. It also has limits. It only shows files, not folder totals, and it skips hidden and system files unless you turn on hidden items. On Windows 11 that option is under **View > Show > Hidden items**. On Windows 10 it's the **Hidden items** checkbox on the **View** tab.

## Method 2: Check folder sizes one at a time

In the Details view, File Explorer sorts files in a folder by size, but folders show no size at all. To see how big a folder is, right-click it and choose **Properties**. Windows counts the contents and shows the total.

This works when you already suspect a folder. It's slow when you don't know where to look, because you have to check folders one by one and drill down by hand.

## Method 3: Use Storage settings

Open **Settings > System > Storage**. Windows shows how your drive is used, split into categories such as apps, temporary files and documents. Click a category to see more detail.

On Windows 11, **Cleanup recommendations** on the same page includes a list of large or unused files. It's a quick way to catch obvious candidates, but it only shows a selection, not everything on the drive.

## Method 4: Use a disk space analyzer

A disk space analyzer scans a whole drive and sorts every folder and file by size. You see the answer in one view instead of searching by hand.

Diskat is a free, open-source analyzer for Windows 10 and 11. It's a single portable file, so there's nothing to install. Here is how to find large files with it:

1. [Download Diskat](/download) and run it.
2. Click the card for the drive you want to check, or click **Choose folder** to scan one folder.
3. Watch the folder tree. Sizes update while the scan runs and the heaviest folders move to the top.
4. Open the **Largest files** tab. It lists the 500 biggest files in the scan, with the folder each one is in.
5. Right-click a file and choose **Show in Explorer** to see it in context, or select several files and press Del to move them to the Recycle Bin.
6. Use the **Space map** tab to spot big blocks visually. Double-click a tile to drill into a folder.

If the status bar says some folders were blocked, click **Run as Admin** to include protected system folders in the scan.

## Where large files usually hide

The same locations show up on most PCs. This table lists them and what to do about each one.

| Location | What it usually is | What to do |
|---|---|---|
| `C:\Users\YourName\Downloads` | Installers, ISO files, zip archives | Delete what you no longer need |
| `Videos`, `Pictures`, `Desktop` | Recordings, phone imports, exports | Your data: move or back up before deleting |
| `C:\Users\YourName\AppData` | App caches, chat media, virtual disks | Depends on the app, check first |
| `C:\hiberfil.sys` | Hibernation file | Use `powercfg /hibernate off`, never delete it directly |
| `C:\pagefile.sys` | Virtual memory | Leave it, or change it in system settings |
| `C:\Windows\MEMORY.DMP` | Crash dump from a past system error | Remove with Disk Cleanup |
| `C:\Windows.old` | Previous Windows installation | Remove with Disk Cleanup or Settings |
| Game library folders | Installed games | Uninstall or move with the game launcher |

For more on the AppData folder, see [why AppData gets so big](/guides/appdata-folder-large). If your C: drive is the one that's full, the [C drive full guide](/guides/c-drive-full) goes through each system item in more detail.

## Common types of large files

Some file types are large by nature. When you sort by size, these are the usual suspects:

- Video files such as `.mp4`, `.mkv` and `.mov`, especially screen and game recordings
- Disk images such as `.iso` and `.img`
- Virtual machine disks such as `.vhdx` and `.vmdk`
- Archives such as `.zip`, `.7z` and `.rar`
- Installers such as `.exe` and `.msi` left in Downloads
- Mail data files such as `.pst` and `.ost`
- Phone and app backups

## Before you delete a large file

A file being big doesn't mean it's useless. Check these points first:

- **Know what it is.** Look at the name, the extension, the folder and the date. Search the name online if you don't recognize it.
- **Don't delete program files.** If a large file is inside Program Files or a game folder, uninstall the app instead.
- **Be careful with virtual disks and mail files.** A `.vhdx` file may hold an entire virtual machine, and a `.pst` file may hold years of email.
- **Use the Recycle Bin first.** Move files there, use your PC for a day or two, then empty it.
- **Back up personal files.** If it's a video or photo archive you care about, copy it to an external drive or cloud storage before you remove it.

## A note on file sizes

Analyzers can show different totals than File Explorer. Diskat shows the logical size of each file, the number you see as "Size" in the Properties window, not the "Size on disk". For most files these are close. They can differ a lot for OneDrive files that are online-only and for NTFS-compressed files, which use less real space than their size suggests. Files with several hard links are counted once for each link.

## FAQ

### What is the fastest way to find large files on Windows?

A disk space analyzer is the fastest way, because it scans the whole drive once and sorts everything by size. File Explorer search with `size:>1GB` works too, but it's slower and doesn't show folder totals.

### Why can't I find some large files with File Explorer search?

File Explorer hides hidden and system files by default, and it can't search folders you don't have permission to open. Turn on hidden items, or use a tool that can scan with administrator rights.

### Is it safe to delete large files I don't recognize?

Not without checking. Look at where the file is and search its name first. Files in Windows, Program Files or ProgramData usually belong to the system or an app and should not be deleted by hand.

### Can I find large files on an external or USB drive?

Yes. All four methods work on external drives. In an analyzer, pick the external drive instead of C: and scan it the same way.
