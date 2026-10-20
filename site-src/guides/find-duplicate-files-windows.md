---
title: How to find and delete duplicate files on Windows
description: Find duplicate files on Windows 10 and 11 by their content, not their names, and remove the extra copies safely. With a free tool or with PowerShell.
slug: find-duplicate-files-windows
lang: en
updated: 2026-10-20
---
Duplicate files pile up without anyone noticing: the same photos imported from your phone twice, a download you saved again, a backup copied into a second folder "just in case", a video sitting both in Downloads and in Videos. Each copy uses the full space again. This guide shows how to find real duplicates on Windows 10 and 11, decide which copy to keep, and remove the rest without losing anything.

## What counts as a duplicate

Two files are duplicates when their content is identical, byte for byte. Names don't tell you much:

- `IMG_2041.jpg` and `IMG_2041 (1).jpg` are often the same photo, but not always.
- Two files called `report.docx` in different folders may be completely different documents.
- A file renamed to `holiday.mp4` can be an exact copy of `VID_0815.mp4`.

So a good duplicate finder compares content. It first groups files by size, since files of different sizes can't be identical, and then compares the content of files that have the same size, usually with a hash: a short fingerprint calculated from the file's bytes.

## Before you start: what not to touch

Some duplicates are there on purpose. Deleting them frees a little space and can break things:

- **Windows, Program Files and ProgramData.** Programs often ship identical copies of the same file in several folders. Leave these folders alone.
- **AppData.** Apps keep their data, caches and sometimes whole installations here.
- **OneDrive and other sync folders.** Deleting a file in a synced folder deletes it in the cloud and on your other devices too. Also, files that are "online-only" have to be downloaded before a tool can read them.
- **Photo and music libraries managed by an app.** Apps such as Lightroom or iTunes keep a catalog that points to files by path. Remove duplicates from inside the app instead.
- **Hard links.** Two names for the same data on the disk aren't two copies. Deleting one of them frees nothing.

The safest targets are your own folders: Downloads, Desktop, Documents, Pictures, Videos and backup folders on an external drive.

## Find duplicates with Diskat

From Diskat 1.2, the free [Diskat](/download) disk space analyzer has a **Duplicates** tab. It compares content, skips the risky places listed above by default, and never lets you delete every copy of a file.

1. Start Diskat and scan the folder or drive you want to clean, for example `C:\Users\YourName` or an external backup drive.
2. Open the **Duplicates** tab on the right.
3. Pick the minimum size. The default of 1 MB skips the thousands of tiny files whose duplicates free almost nothing. Choose 100 MB to look only for big videos and disk images.
4. Leave **Skip Windows and program folders** ticked. It leaves out Windows, Program Files, ProgramData, every AppData folder and system files.
5. Click **Find duplicates**. Diskat only reads files that have the same size as another file: first their first 64 KB, then the whole file. A progress bar shows how far it is, and you can stop at any time.
6. The results are groups of identical files, sorted by how much space each group wastes. Expand a group to see every copy with its folder and its last-modified date.
7. Tick the copies you want to remove, or click **Select all but newest** to tick every copy except the most recently changed one in each group.
8. Click **Delete selected**. The copies go to the Recycle Bin, so you can restore them if you change your mind. Shift+Del deletes permanently.

A few safety rules are built in. You can't tick the last copy of a group. Online-only OneDrive files are skipped and never downloaded. Hard links count as one file and can't be ticked. Just before deleting, Diskat checks again that the copy you keep is still there and that nothing changed since the search.

## Find duplicates with PowerShell

If you'd rather not install anything, PowerShell can find exact duplicates. This command looks in your Pictures folder for files over 1 MB, groups them by size, hashes only the files that share a size, and lists the copies:

`Get-ChildItem "$env:USERPROFILE\Pictures" -Recurse -File | Where-Object Length -gt 1MB | Group-Object Length | Where-Object Count -gt 1 | ForEach-Object { $_.Group | Get-FileHash -Algorithm SHA256 } | Group-Object Hash | Where-Object Count -gt 1 | ForEach-Object { $_.Group.Path; "" }`

Each block of paths is one set of identical files. Open them in Explorer and delete the extras by hand, so they go to the Recycle Bin.

Keep in mind:

- Hashing reads every candidate file completely, so it can take a while on a large folder.
- If the folder is inside OneDrive, hashing an online-only file downloads it first.
- The command doesn't know about hard links, so two names of the same file show up as duplicates.

## Which copy to keep

When two copies are identical, the content doesn't care which one survives, but you do. Some rules of thumb:

- Keep the copy in the folder where you'd look for it: Pictures rather than Downloads, the organized backup rather than the "New folder (3)" copy.
- Keep the newest copy if you're not sure. It's the one most likely to be the "current" file. That's what **Select all but newest** does.
- Before you delete a whole batch, sort the results by wasted space and start with the biggest groups. A handful of duplicate videos often frees more than thousands of photos.

## FAQ

### Is it safe to delete duplicate files?

Yes, if they're really identical and they're your own files. Compare content rather than names, keep one copy of each, use the Recycle Bin, and stay out of Windows, Program Files, ProgramData and AppData.

### Does Windows have a built-in duplicate file finder?

No. File Explorer can sort by name and size, which helps spot obvious copies, but it can't compare content. You need a tool or a PowerShell command like the one above.

### Why do two files with the same name show up as different?

Because their content differs. A duplicate finder that compares content will only group files whose bytes are identical, whatever they're called.

### Will a duplicate finder download my OneDrive files?

Many will, because they have to read a file to compare it. Diskat skips online-only OneDrive files and opens files in a way that doesn't trigger a download.

### How much space can I get back?

It depends on your habits. Photo and video folders that were copied or imported more than once are the usual winners. Diskat shows the wasted space for each group and in total before you delete anything. Once duplicates are gone, [find the largest files](/guides/find-large-files-windows) or follow the [full guide to freeing disk space](/guides/free-up-disk-space-windows).
