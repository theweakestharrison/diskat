---
title: How to see folder sizes in Windows File Explorer
description: File Explorer leaves the Size column empty for folders. Five ways to see how big a folder is on Windows 10 and 11, from Properties to PowerShell and a free tool.
slug: show-folder-size-windows
lang: en
updated: 2026-10-20
---
Open a folder in File Explorer, switch to the Details view, and the **Size** column shows a number for every file but stays empty for every folder. Windows has never shown folder sizes there. To know how big a folder is, Explorer would have to add up every file in every subfolder, and doing that for a whole list of folders would make browsing slow. Here are five ways to get the numbers anyway, from a quick check of one folder to a list of all of them, sorted by size.

## 1. Properties: the size of one folder

Right-click the folder and choose **Properties**, or select it and press Alt+Enter. The General tab shows:

- **Size**: the total size of all files inside, including every subfolder
- **Size on disk**: how much space those files really take on the drive
- **Contains**: how many files and folders it holds

For a big folder, the numbers count up for a few seconds while Windows adds everything up. You can select several folders and open Properties once to see their combined size.

This is fine for one or two folders. It doesn't tell you which of twenty folders is the big one without opening Properties twenty times.

## 2. Folder tips: the size when you hover

File Explorer can show a folder's size in the small tooltip that appears when you hover over it:

1. In File Explorer, open **Options**. In Windows 11, click the three dots (**See more**) on the toolbar, then **Options**. In Windows 10, it's on the **View** tab.
2. On the **View** tab of Folder Options, tick **Display file size information in folder tips**.
3. Click **OK**, then hover over a folder.

The tooltip includes the size for small and medium folders. For very large folders it may take a moment or leave the size out.

## 3. Storage settings: the big picture

**Settings > System > Storage** shows how the space on a drive is split between categories such as Apps, Documents, Pictures and Temporary files. Click a category for details or for cleanup options such as Temporary files.

It's a good overview of a full C drive, but it groups by category, not by folder, so it won't tell you that one particular project or game folder is 80 GB.

## 4. PowerShell or the command prompt

For an exact number without opening any windows, use PowerShell. This prints the size of your Videos folder in gigabytes:

`"{0:N2} GB" -f ((Get-ChildItem "$env:USERPROFILE\Videos" -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1GB)`

And this lists every folder in your user profile with its size, biggest first:

`Get-ChildItem "$env:USERPROFILE" -Directory -Force | ForEach-Object { [pscustomobject]@{ Folder = $_.Name; GB = [math]::Round((Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1GB, 2) } } | Sort-Object GB -Descending`

In the classic command prompt, `dir /s "C:\Users\YourName\Videos"` lists every file and ends with a total under **Total Files Listed**.

Both work, but they're slow on folders with many files, they skip folders you're not allowed to read without telling you much, and you have to run them again for every folder you want to look into.

## 5. A folder size tool: every folder at once

A disk space analyzer does what Explorer won't: it scans a drive or folder once and shows the size of every folder, sorted from biggest to smallest. [Diskat](/download) is a free, open-source one for Windows 10 and 11. It's a single .exe, so there's nothing to install.

1. Start Diskat and click a drive card, or **Choose folder…** to pick a folder.
2. The folder tree fills in while the scan runs. Every folder shows its size, a "% of parent" bar, its file and folder counts and when it was last changed, and the heaviest folders float to the top.
3. Expand a folder to see what's inside it, again sorted by size. The **Space map** tab beside the tree draws the same folders as rectangles sized by how much space they use.

To jump straight from Explorer to a folder's sizes, turn on **Show "Scan with Diskat" in Explorer** in Diskat's ⋯ menu. Then right-click any folder or drive and choose **Scan with Diskat**. In Windows 11 it's under **Show more options**.

If the goal is to free up space, the same window lets you act on what you find: the **Largest files** tab lists the biggest files, and deleting sends items to the Recycle Bin by default while system folders stay protected.

## Size or size on disk?

Properties shows two numbers, and they can differ a lot:

- **Size** is the sum of the file lengths. It's what most tools, including Diskat, show.
- **Size on disk** is the space the files occupy on the drive. It's usually a little larger, because space is handed out in small blocks. It can also be much smaller: compressed files take less, and OneDrive files that are online-only take almost nothing until you open them.

If a folder in your OneDrive looks huge but your drive isn't full, check the Size on disk. The files may live mostly in the cloud.

## FAQ

### Why doesn't File Explorer show folder sizes?

Because a folder's size is the total of every file in it and in all of its subfolders. Calculating that for every folder in a list would mean reading the whole tree each time you open a folder, which would make Explorer slow.

### How do I see the size of all folders at once?

Use a disk space analyzer such as Diskat. It scans once and shows every folder's size in a tree sorted by size. In PowerShell, the second command above lists the folders of one location with their sizes.

### Can I add a folder size column to File Explorer?

Not with Windows' own settings. Explorer's Size column only applies to files. Folder tips show the size when you hover, and a disk space analyzer shows sizes for all folders together.

### Which folders are usually the biggest?

On a typical PC: Downloads, Videos and Pictures in your user folder, game libraries, `AppData` for app data and caches, and `C:\Windows` with its update files. Our guides explain what's safe to clean in [AppData](/guides/appdata-folder-large), in [WinSxS](/guides/winsxs-folder) and on [a full C drive](/guides/c-drive-full).
