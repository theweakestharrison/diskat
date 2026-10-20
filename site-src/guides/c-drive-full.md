---
title: C drive full? How to see what's taking up space and fix it
description: Is your C drive full? Find out what is using the space on Windows 10 or 11, from user files to system files, and fix each cause safely, step by step.
slug: c-drive-full
lang: en
updated: 2026-10-20
---
When the C: drive bar in This PC turns red, Windows starts to struggle. Updates fail, apps can't save, and the PC can feel slow. Guessing what to delete rarely works. The reliable approach is to measure first, then fix the specific things that are big. This guide shows how to do both on Windows 10 and 11.

## Step 1: Check the overview in Settings

Open **Settings > System > Storage**. Windows shows the used and free space on C: and splits the used space into categories such as apps, documents, temporary files and system files.

Click **Show more categories** if you don't see them all. One category that often surprises people is **System & reserved**. It includes Windows itself, the page file, the hibernation file and **reserved storage**. Reserved storage is space Windows keeps aside so updates can install even when the drive is nearly full. You can check its state with `DISM /Online /Get-ReservedStorageState` in an administrator Terminal. Leave it on: it exists to keep updates working.

## Step 2: Scan the drive to see folder sizes

Settings tells you the category, not the folder. For that you need a disk space analyzer. Diskat is a free, portable one: [download Diskat](/download), run it and click the C: drive card.

When the scan finishes, the top level of C: usually shows these items:

- `Users`, with your personal files and app data
- `Windows`, the operating system
- `Program Files` and `Program Files (x86)`, installed apps
- `ProgramData`, shared app data
- Files such as `hiberfil.sys`, `pagefile.sys` and `swapfile.sys`

Expand the biggest folder and keep going down until you find the folders that matter. If the status bar says some folders were blocked, click **Run as Admin** and scan again to include protected system folders.

Sometimes the scanned total is noticeably smaller than the used space Windows reports. The gap is often in `C:\System Volume Information`, where Windows stores restore points. That folder can stay unreadable even with administrator rights. Run `vssadmin list shadowstorage` in an administrator Terminal to see how much space restore points use.

## Step 3: Match what you find to a fix

Once you know what is big, use this table to pick the right fix.

| What is big | What it is | How to shrink it safely |
|---|---|---|
| `C:\Users\YourName\Downloads` | Installers, archives, ISO files | Delete what you no longer need |
| `C:\Users\YourName\AppData` | App caches and data | Clear caches from inside each app |
| `C:\Windows\WinSxS` | Windows component store | Run DISM component cleanup |
| `C:\Windows\SoftwareDistribution\Download` | Downloaded updates | Usually cleared by Windows, see below |
| `C:\Windows.old` | Previous Windows installation | Remove with Settings or Disk Cleanup |
| `C:\hiberfil.sys` | Hibernation file | Turn off hibernation |
| `C:\pagefile.sys` | Virtual memory | Leave it system managed |
| `C:\System Volume Information` | Restore points | Lower the System Restore limit |
| `C:\Program Files` | Installed apps and games | Uninstall or move apps |

For the AppData folder, see [what you can safely delete in AppData](/guides/appdata-folder-large). For WinSxS, see [how to shrink the WinSxS folder](/guides/winsxs-folder).

## Step 4: Quick fixes that take minutes

Start with these. They are safe and often enough on their own.

1. **Empty the Recycle Bin.** Deleted files still use space until you empty it.
2. **Remove temporary files.** Go to **Settings > System > Storage > Temporary files**, check the items you want and click **Remove files**. Leave the **Downloads** box unchecked unless you have already reviewed that folder, because it deletes everything in it.
3. **Clear out Downloads.** Sort the folder by size in File Explorer and remove old installers and archives.
4. **Uninstall unused apps.** Open **Settings > Apps > Installed apps** (Windows 11) or **Apps & features** (Windows 10), sort by size and remove what you don't use.

## Step 5: Bigger fixes that need more care

### Remove Windows.old

After a major Windows update, the previous version is kept in `C:\Windows.old` so you can go back. Windows deletes it automatically after about 10 days. To remove it sooner, open Disk Cleanup (`cleanmgr`), click **Clean up system files** and check **Previous Windows installation(s)**. You won't be able to roll back afterwards.

### Turn off hibernation

If you never use Hibernate, run `powercfg /hibernate off` in an administrator Terminal. Windows deletes `hiberfil.sys`, which is often several gigabytes. This also turns off Fast Startup. Don't do it on a laptop if you depend on hibernation.

### Reduce space for restore points

Press Win+R and run `SystemPropertiesProtection`. Select C:, click **Configure** and lower **Max Usage**. In Disk Cleanup, after you click **Clean up system files**, the **More Options** tab can also remove all but the most recent restore point. Keep at least one restore point as a safety net.

### Clean the Windows Update download cache

Windows normally clears `C:\Windows\SoftwareDistribution\Download` on its own. If it stays large, you can empty it by hand. Make sure no update is installing, then open an administrator Terminal and run `net stop wuauserv`. Delete the contents of the Download folder, not the folder itself, then run `net start wuauserv`. Windows downloads again whatever it still needs. Diskat blocks deletions anywhere inside `C:\Windows` on purpose, so do this step in File Explorer.

### Clean up the component store

Run `DISM /Online /Cleanup-Image /StartComponentCleanup` in an administrator Terminal. It removes old versions of Windows components that are no longer needed. Never delete WinSxS files by hand.

## Step 6: Keep it from filling up again

- Turn on **Storage Sense** in **Settings > System > Storage** so temporary files and old Recycle Bin items are removed automatically.
- Move large personal folders to another drive. Right-click Documents, Videos or Pictures, choose **Properties**, open the **Location** tab and click **Move**.
- If you use OneDrive, right-click folders you rarely open and choose **Free up space**. They stay visible but download only when needed.
- Install large games on a second drive. Most game launchers let you add a library folder on another drive.

## When the drive is simply too small

Some laptops ship with a small SSD. After Windows, updates and a few apps, there may be little room left no matter how much you clean. In that case a larger SSD, a second internal drive or an external drive for personal files is the lasting fix.

## FAQ

### Why is my C drive full when I haven't saved anything?

Windows and apps write data on their own: updates, update backups, restore points, browser caches, app data in AppData and the hibernation file. A disk space analyzer shows which of these is the main cause on your PC.

### What is "System & reserved" in Storage settings?

It's space used by Windows itself, the page file, the hibernation file, restore points and reserved storage for updates. You can shrink parts of it by turning off hibernation and limiting restore points, but don't try to delete these files by hand.

### Can I delete files in the Windows folder to free space?

Don't delete anything there by hand. Use Disk Cleanup, Settings and DISM, which know which files are safe to remove. Deleting the wrong file can stop Windows from updating or starting.

### Is it safe to delete Windows.old?

Yes, if your current Windows version works well. Once it's gone you can't go back to the previous version. Remove it with Disk Cleanup or Settings rather than deleting it in File Explorer.

### Why does my scan show less used space than Windows reports?

Some folders, such as System Volume Information, can't be read even with administrator rights. Restore points stored there count as used space but don't appear in the scan.
