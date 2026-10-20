---
title: How to free up disk space on Windows 10 and 11
description: Free up disk space on Windows 10 and 11 step by step. See what is big, then clean temp files, updates, apps, hibernation and restore points safely.
slug: free-up-disk-space-windows
lang: en
updated: 2026-10-20
---
When your drive fills up, Windows gets slow, updates fail and apps can't save files. The fix is usually a mix of quick cleanups and a few bigger decisions. This guide starts with the safest steps and moves on to the ones that need more care. Work through it in order and check your free space after each step, so you stop when you have enough room.

## Step 1: See what is using the space

Before you delete anything, find out where the space went. Open **Settings > System > Storage**. Windows shows how much space is used and splits it into categories such as apps, temporary files, documents and system files. It's a good overview, but the categories are broad and don't tell you which folder is the problem.

A disk space analyzer gives you the exact answer. Diskat is a free, open-source analyzer that runs without installing. Click the C: drive card and it scans the drive, with the heaviest folders moving to the top as it goes. The "% of parent" bars and the space map make it obvious which folders matter. For more ways to do this, see [how to find large files](/guides/find-large-files-windows).

## Step 2: Empty the Recycle Bin

Files you delete in File Explorer go to the Recycle Bin and still take up space. Open the Recycle Bin, check that nothing in it is still needed, then right-click its icon and choose **Empty Recycle Bin**.

If the bin often grows large, you can cap its size. Right-click the Recycle Bin, choose **Properties**, select the drive and set a custom maximum size.

## Step 3: Remove temporary files in Settings

Go to **Settings > System > Storage** and click **Temporary files**. Windows scans the drive and lists what it can remove, for example:

- Temporary files left behind by apps
- Windows Update Cleanup (old update files)
- Delivery Optimization Files (update data shared with other PCs)
- Thumbnails
- Recycle Bin

Check the boxes you want and click **Remove files**. Be careful with the **Downloads** box: it deletes everything in your Downloads folder, not just old installers. Leave it unchecked unless you have already looked through that folder.

On Windows 11 the same page also shows **Cleanup recommendations**. It suggests large or unused files, files already synced to the cloud and apps you haven't used for a while. Review each suggestion before you accept it.

## Step 4: Turn on Storage Sense

Storage Sense cleans up automatically so the drive doesn't fill up again. Turn it on in **Settings > System > Storage > Storage Sense**. In its settings you choose how often it runs and what it removes: temporary files, Recycle Bin items older than a set number of days, Downloads files you haven't opened for a while, and OneDrive files that can go back to being online-only. If you keep important files in Downloads, set that option to **Never**.

## Step 5: Clean up system files with Disk Cleanup

The classic Disk Cleanup tool still works on Windows 10 and 11 and can reach system files. Type `cleanmgr` in the Start menu and open it, choose drive C:, then click **Clean up system files**. This needs administrator rights.

In the list, the most useful entries are usually **Windows Update Cleanup**, **Delivery Optimization Files**, **Temporary files** and, if present, **Previous Windows installation(s)**. Removing the previous installation deletes the `C:\Windows.old` folder, which can be large. After that you can no longer go back to your earlier version of Windows, so only do it once the current version works well.

## Step 6: Uninstall apps and games you don't use

Open **Settings > Apps > Installed apps** on Windows 11, or **Settings > Apps > Apps & features** on Windows 10. Sort the list by size. Games are often the biggest items. Uninstall what you no longer use. Many game launchers can also move a game to another drive instead of removing it.

## Step 7: Clear out Downloads and other personal folders

Your Downloads folder collects installers, ISO files and zip archives that you only needed once. Open it in File Explorer, switch to the Details view and click the **Size** column to sort. Old videos, phone backups and screen recordings in your Videos and Pictures folders are also common space hogs.

Delete to the Recycle Bin first. Empty the bin only after you are sure you don't need the files.

## Step 8: Bigger savings from system settings

These steps can free several gigabytes each, but they change how Windows behaves. Read each one before you act.

### Turn off hibernation

Windows keeps a hibernation file, `C:\hiberfil.sys`, that is often several gigabytes. If you never use Hibernate, open Terminal or Command Prompt as administrator and run `powercfg /hibernate off`. Windows deletes the file. This also turns off Fast Startup. Run `powercfg /hibernate on` to undo it. Don't do this on a laptop if you rely on hibernation to save your work when the battery runs low.

### Limit space for restore points

System Restore keeps restore points (shadow copies) on the drive. Press Win+R, run `SystemPropertiesProtection`, select drive C: and click **Configure**. Lower the **Max Usage** slider to cap the space. Restore points are a safety net, so keep some space for them rather than turning protection off.

### Shrink the component store

Old versions of Windows components pile up in `C:\Windows\WinSxS`. Run `DISM /Online /Cleanup-Image /StartComponentCleanup` from an administrator Terminal to remove the ones Windows no longer needs. Never delete files from that folder by hand. The [WinSxS guide](/guides/winsxs-folder) explains why.

## Step 9: Move files off the C: drive

If you have a second drive, move large personal files there. To move a whole library such as Documents, right-click it in File Explorer, choose **Properties**, open the **Location** tab and click **Move**. If you use OneDrive, right-click files or folders you rarely open and choose **Free up space**. They stay visible but only download when you open them.

## What not to delete

Some large items look tempting but should never be removed by hand:

- Anything inside `C:\Windows`, including WinSxS, Installer and System32
- `pagefile.sys` and `hiberfil.sys` (use the settings above instead)
- Folders under Program Files (uninstall the app instead)
- The AppData folder as a whole (see [why AppData gets big](/guides/appdata-folder-large))

A tool that blocks these mistakes helps. Diskat refuses to delete Windows, Program Files, ProgramData, user profile roots and similar folders. It moves items to the Recycle Bin by default and asks for confirmation every time. You can [download Diskat](/download) as a single portable file.

## FAQ

### How much free space should I keep on my C drive?

There is no fixed rule. A good target is at least 10 to 15 percent of the drive. Windows needs extra room to download and install feature updates, so keep more if updates keep failing.

### Is it safe to delete temporary files?

Yes. Temporary files listed in Settings or Disk Cleanup are safe to remove. You can also open `%TEMP%` from the Run box and delete its contents. Windows skips any file that is still in use.

### Why does my drive fill up again after I clean it?

Updates, browser and app caches, new downloads and restore points all grow over time. Turning on Storage Sense handles much of this automatically.

### Does Disk Cleanup still work on Windows 11?

Yes. `cleanmgr` is still included in Windows 11. Most of its options are also available in **Settings > System > Storage > Temporary files**.
