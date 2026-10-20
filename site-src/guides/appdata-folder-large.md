---
title: Why is the AppData folder so big, and what can you safely delete?
description: Learn why the AppData folder grows so large on Windows, which caches and temp files are safe to delete, and which app data you should leave alone.
slug: appdata-folder-large
lang: en
updated: 2026-10-20
---
AppData is a hidden folder in your user profile where apps keep their settings, caches and working data. On a PC that has been in use for a few years, it's common for it to reach tens of gigabytes. Some of that space is safe to reclaim, and some of it is data you would really miss. This guide explains what is inside AppData, why it grows, and how to clean it up without breaking your apps.

## What the AppData folder is

Every Windows user account has its own AppData folder at `C:\Users\YourName\AppData`. It's hidden by default, so you won't see it in File Explorer unless you show hidden items. The quickest way in is to press Win+R and type `%LOCALAPPDATA%` or `%APPDATA%`, then press Enter.

AppData has three subfolders:

| Folder | What it holds | Notes |
|---|---|---|
| `Local` | Caches, temporary files, large app data, Microsoft Store app data | Stays on this PC, usually the largest |
| `LocalLow` | Data for apps that run with restricted rights, such as some games | Usually small |
| `Roaming` | Settings and profiles, such as browser profiles, mail and chat data, game saves | Can follow you to other PCs on some work networks |

`%LOCALAPPDATA%` opens the Local folder and `%APPDATA%` opens the Roaming folder.

## Why AppData gets so big

AppData grows because apps write to it constantly and rarely clean up after themselves. The usual causes are:

- **Browser caches.** Chrome, Edge and Firefox store copies of web pages, images and videos.
- **Chat and meeting apps.** Teams, Discord, Slack and similar apps cache images, videos and files from your conversations.
- **Temporary files.** `AppData\Local\Temp` (the folder `%TEMP%` points to) collects leftovers from installers and apps.
- **Microsoft Store apps.** Their data lives in `AppData\Local\Packages`.
- **Developer tools.** Package managers such as npm and pip keep download caches.
- **Virtual disks.** WSL Linux distributions and Docker Desktop store large disk images here.
- **Phone backups.** iTunes for Windows saves iPhone backups under `AppData\Roaming\Apple Computer\MobileSync\Backup`.
- **Leftovers.** Many uninstallers leave their AppData folder behind.

## Find out what is big

File Explorer can't show folder sizes, so start with a disk space analyzer. In Diskat, type `C:\Users\YourName\AppData` into the path box and press Enter. Diskat includes hidden folders in the scan, so AppData shows up in full. Expand `Local` and `Roaming` and look at the top three or four folders. The space map shows at a glance whether one app is responsible or the space is spread out. For a wider search, see [how to find large files](/guides/find-large-files-windows).

## What you can usually delete safely

These are caches and temporary data. Apps rebuild them when needed, though the first start afterwards may be a little slower.

- **Contents of the Temp folder.** Close your apps, open `%TEMP%`, select everything and delete it. Skip any file Windows says is in use. Delete the contents, not the Temp folder itself.
- **Browser caches.** Use the browser's own cleanup. Press Ctrl+Shift+Delete in Chrome, Edge or Firefox and select only cached images and files. This keeps your passwords, bookmarks and history.
- **App cache folders.** Folders named `Cache`, `Code Cache` or `GPUCache` inside an app's folder can be removed while the app is closed. For example, Discord keeps one in `AppData\Roaming\discord\Cache`. If the app has its own "clear cache" option, as Spotify does, use that instead.
- **Crash dumps.** `AppData\Local\CrashDumps` holds crash reports. You only need them if you're sending them to a developer.
- **Graphics shader caches.** For example `AppData\Local\NVIDIA\DXCache`. The driver rebuilds them, though games may stutter briefly the first time.
- **Developer caches.** Use the tool's own command, such as `npm cache clean --force` or `pip cache purge`.
- **Leftover folders.** If an app is gone from your installed apps list, its old AppData folder can go too.

## What you should not delete

- **AppData, Local or Roaming themselves.** Deleting them resets or breaks every app on your account.
- **Browser profile folders.** `User Data` for Chrome and Edge, and the Firefox `Profiles` folder, hold your bookmarks, saved passwords, extensions and history.
- **Outlook data files.** `AppData\Local\Microsoft\Outlook` can contain `.pst` files, which may be your only copy of some email. `.ost` files are offline copies of a mail account and can usually be rebuilt, but that means downloading all your mail again.
- **Store app folders in Packages.** Uninstall the app, or reset it in **Settings > Apps > Installed apps** (Windows 11) or **Apps & features** (Windows 10) under **Advanced options**.
- **Virtual disk files.** A `.vhdx` file from WSL or Docker contains a whole Linux system or your containers. Remove those through the tool itself, and only if you no longer need the data.
- **Phone backups.** Manage them from the app that made them, so you don't delete your only backup.
- **Game saves and password vaults.** Some games and password managers keep their only copy of your data in Roaming or LocalLow.

## A safe cleanup routine

1. Close the apps whose data you want to clean.
2. Scan AppData and note the largest folders.
3. For each one, check which app it belongs to. Search the folder name online if it's unclear.
4. Use the app's own cleanup option first, if it has one.
5. Delete cache folders to the Recycle Bin, not permanently.
6. Open the app and check that it works and that your data is still there.
7. Empty the Recycle Bin after a day or two.

Diskat helps with steps 2 and 5. It refuses to delete the `AppData\Local` and `AppData\Roaming` folders themselves, and every delete shows a confirmation with the full path and size. You can [download Diskat](/download) as a single portable file. If space is still short afterwards, the [C drive full guide](/guides/c-drive-full) covers system files and other large items.

## FAQ

### Can I delete the whole AppData folder?

No. It holds the settings and data of every app on your account. Deleting it would reset or break those apps and could lose data such as bookmarks, saved passwords, email and game saves.

### Is it safe to delete the Temp folder in AppData?

It's safe to delete the contents of `AppData\Local\Temp`, but not the folder itself. Close your apps first. Windows skips files that are still in use, and you can ignore those.

### Why does AppData keep growing back?

Caches refill as you use your apps. That's normal. Turning on Storage Sense and clearing large app caches now and then keeps it under control.

### Can I move AppData to another drive?

Moving the whole AppData folder is not a supported setup and can break apps and Windows updates. Instead, check whether the app that uses the most space lets you choose where it stores its cache or downloads.
