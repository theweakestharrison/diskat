---
title: Can you delete the WinSxS folder? (and how to shrink it safely)
description: The WinSxS folder looks huge, but deleting it breaks Windows. Learn what it is, how to check its real size, and how to shrink it safely with DISM.
slug: winsxs-folder
lang: en
updated: 2026-10-20
---
If you look at `C:\Windows\WinSxS` while hunting for disk space, it often looks like one of the biggest folders on the drive. The short answer to whether you can delete it is no. Not the folder, and not files inside it. But you can shrink it safely with tools built into Windows. This guide explains what WinSxS is, why it looks bigger than it really is, and how to clean it up the supported way.

## What the WinSxS folder is

WinSxS is the Windows component store. It holds the files Windows needs to install, update and repair itself, and to turn optional features on and off. When an update replaces a system component, Windows keeps the older version for a while so the update can be uninstalled if something goes wrong.

Windows also uses the component store to repair itself. When you run `sfc /scannow` or `DISM /Online /Cleanup-Image /RestoreHealth`, damaged system files are restored from it.

## Why it looks bigger than it really is

Many files in WinSxS are not separate copies. They are hard links: one file on the disk that appears in two places, for example in WinSxS and in `C:\Windows\System32`. File Explorer, and any tool that counts each link, adds the size once for each place the file appears. That makes WinSxS look much larger than the space it really uses on its own.

Diskat counts each hard link too, so in a scan of `C:\Windows` the shared files are included in both WinSxS and System32. Treat the WinSxS number in Explorer or Diskat as an upper limit, not as the space you could get back. To see the real figure, use DISM as shown in step 1.

## Why you should never delete it by hand

- The folder is owned by TrustedInstaller, the account Windows uses for updates. To delete its files you would have to take ownership, which is already a sign you're going around a safety check.
- Without the component store, Windows Update can fail, optional features can't be turned on, and repair tools have nothing to repair from. In bad cases Windows stops starting.
- Because so many files are hard links, deleting them from WinSxS often frees far less space than you expect.

Diskat blocks every delete inside `C:\Windows` for these reasons, so the folder can't be removed by accident from a scan.

## Step 1: Check the real size

Open Terminal or Command Prompt as administrator and run:

`Dism.exe /Online /Cleanup-Image /AnalyzeComponentStore`

After a minute or two, DISM shows a report. The important lines are:

- **Windows Explorer Reported Size of Component Store**: the size File Explorer shows, including hard links.
- **Actual Size of Component Store**: the space it really uses.
- **Shared with Windows**: files that are hard-linked into the rest of Windows. These would stay even without WinSxS.
- **Backups and Disabled Features**: older component versions and files for features that are turned off.
- **Cache and Temporary Data**: working files used by servicing.
- **Component Store Cleanup Recommended**: Yes or No.

If cleanup is recommended, go on to step 2.

## Step 2: Run component cleanup

In the same administrator window, run:

`DISM /Online /Cleanup-Image /StartComponentCleanup`

DISM removes older versions of components that have been replaced by updates. It can take several minutes and may look stuck at times. Let it finish and don't turn off the PC while it runs.

Windows runs a similar cleanup on its own through a scheduled task, but that task waits about 30 days after an update before removing the old versions. Running the command yourself removes them right away.

## Step 3 (optional): Reset the base

For a bit more space you can add `/ResetBase`:

`DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase`

This removes all superseded versions of every component. The catch: **after this, you can't uninstall any update that is currently installed.** Only do it when your PC has been running well on its current updates, and skip it if you might need to roll one back.

## Another option: Disk Cleanup

If you prefer not to use the command line, Disk Cleanup does a similar job. Type `cleanmgr` in the Start menu, choose drive C:, click **Clean up system files** and check **Windows Update Cleanup**. On Windows 10 and 11 the same item also appears in **Settings > System > Storage > Temporary files**.

## Leave the automatic cleanup task on

Windows keeps the component store in check with a scheduled task. In Task Scheduler you'll find it under **Task Scheduler Library > Microsoft > Windows > Servicing > StartComponentCleanup**. It runs when the PC is idle. Don't disable it.

## What to expect

How much you get back depends on how long it has been since the last cleanup and how many updates were installed since. It can be a few hundred megabytes or several gigabytes. Right after a big update, the store is often larger for a while. WinSxS will never be small, because Windows needs it to work.

If your drive is still full after cleanup, the space is most likely somewhere else. Start with [what to do when your C drive is full](/guides/c-drive-full) or the general guide to [freeing up disk space](/guides/free-up-disk-space-windows). A disk space analyzer shows which folders are really large, and you can [download Diskat](/download) for free.

## FAQ

### Can I delete the WinSxS folder?

No. Deleting the folder or files inside it can break Windows Update, optional features and system repair, and can stop Windows from starting. Use DISM or Disk Cleanup to shrink it instead.

### Is it safe to run DISM StartComponentCleanup?

Yes. It's a supported Microsoft command that only removes component versions Windows no longer needs. Run it from an administrator window and let it finish. Only the `/ResetBase` option has a real downside: you can no longer uninstall current updates.

### Why is WinSxS so big?

Partly because it holds older versions of updated components, and partly because many tools count its hard-linked files more than once. The DISM analysis shows the actual size and how much is shared with the rest of Windows.

### Does Disk Cleanup clean the WinSxS folder?

Yes. The **Windows Update Cleanup** option under **Clean up system files** removes superseded components from WinSxS, much like the DISM command.

### How big should the WinSxS folder be?

There's no single correct size. It depends on your Windows version, installed features and update history. Use `/AnalyzeComponentStore` and follow its recommendation rather than aiming for a number.
