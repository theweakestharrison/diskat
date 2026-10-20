---
title: How to delete a file that's open in another program
description: Fix the Windows error that says a file is open in another program. Find the program that holds the file, close it, then delete the file safely.
slug: delete-file-in-use
lang: en
updated: 2026-10-20
---
You try to delete, move or rename a file and Windows shows a **File In Use** dialog: "The action can't be completed because the file is open in another program." Sometimes it names the program, sometimes it doesn't. Either way, the cause is the same. A running program has the file open, and Windows won't remove a file while it's in use. The fix is to find that program and close it. This guide shows how, from the quickest checks to tools that show exactly which process holds the file.

## Why Windows locks files

When a program opens a file, it can tell Windows that no one else may delete or change it until it's done. That protects the file from damage while it's being written. The lock is released when the program closes the file or exits.

The program holding the file isn't always one you opened yourself. Common hidden causes are:

- The File Explorer preview pane, which opens files to show a preview
- A program still running in the background after you closed its window
- Antivirus software scanning the file
- OneDrive or another sync or backup tool uploading it
- A Command Prompt or Terminal window whose current folder is the folder you're deleting

## Fix 1: Close the program Windows names

If the dialog names a program, for example "open in Microsoft Word", switch to that program, save your work and close the file or the whole program. Then click **Try Again** in the dialog.

If you don't see the program, check the system tray in the bottom right corner of the taskbar. Click the arrow to show hidden icons. Many apps keep running there after you close their window. Right-click the icon and choose the option to quit or exit.

## Fix 2: Turn off the preview pane

The preview pane in File Explorer opens a file to show its contents, which can lock it. Click an empty spot in the folder, press Alt+P to hide the preview pane, then try again. If another File Explorer window shows the same folder, close it too.

If you're deleting a folder, the message is slightly different: "The action can't be completed because the folder or a file in it is open in another program." Close any Command Prompt, PowerShell or Terminal window that is working inside that folder.

## Fix 3: Find the program with Resource Monitor

Resource Monitor is built into Windows and can show which process has a file open.

1. Press Win+R, type `resmon` and press Enter.
2. Open the **CPU** tab.
3. Expand the **Associated Handles** section.
4. Type the file name (or part of it) in the search box of that section.
5. Look at the **Image** column. It shows the name of each process that has the file open.

Once you know the program, close it normally if you can. That's the safest way. If it won't close, right-click it in Resource Monitor and choose **End Process**. Any unsaved work in that program is lost. Don't end processes you don't recognize, and never end Windows processes such as `System`, `csrss.exe` or `svchost.exe`.

If the process is `explorer.exe`, restart File Explorer instead. Press Ctrl+Shift+Esc to open Task Manager, find **Windows Explorer** in the list of processes, right-click it and choose **Restart**.

## Fix 4: Use a tool made for locked files

Two free Microsoft tools make this easier:

- **PowerToys File Locksmith.** Install Microsoft PowerToys and turn on File Locksmith. Right-click the file and use the File Locksmith entry in the menu (on Windows 11 it may be under **Show more options**). It lists the processes using the file and can end them.
- **Process Explorer** from Sysinternals. Open the **Find** menu, choose **Find Handle or DLL** and type the file name. It shows every process with a matching handle.

## Fix 5: Restart Windows, then delete

A restart closes every program, so the lock is gone. Delete the file right after Windows starts, before you open other apps.

If the file is locked again after a restart, a program that starts with Windows is opening it. In Task Manager, open **Startup apps** on Windows 11 or the **Startup** tab on Windows 10 and disable the program you suspect. As a last resort, start Windows in Safe Mode, where only essential drivers and services run, and delete the file there.

## Let the delete happen at the next startup

Windows can also delete a file during the next startup, before other programs load. That avoids the lock completely. Diskat, a free disk space analyzer, uses this from version 1.1. When a delete fails because another program has the file open, Diskat shows which program is holding it. It then offers to close that program and retry, or to delete the file the next time Windows starts (that option needs Diskat to run as administrator). Every delete still goes through a confirmation dialog, and by default files go to the Recycle Bin. You can [download Diskat](/download) as a single portable file.

## When you should not force it

A lock is sometimes a warning sign. Think twice in these cases:

- **Files inside `C:\Windows` or Program Files.** Windows or an installed app needs them. Uninstall the app instead of deleting its files.
- **`pagefile.sys` and `hiberfil.sys`.** Windows always has these open. Change them through system settings, as described in [what to do when your C drive is full](/guides/c-drive-full).
- **App data in AppData.** A database or cache that's open is in active use. Close the app first, and read [what's safe to delete in AppData](/guides/appdata-folder-large).
- **Files you don't recognize.** Find out what they are before you end processes to remove them.

## FAQ

### Why does Windows say the file is open when no program is open?

A program can hold a file without showing a window. Background apps in the system tray, the File Explorer preview pane, antivirus scans and OneDrive syncing are the usual causes. Resource Monitor shows which one it is.

### Is it safe to end a process in Task Manager to delete a file?

It's safe for programs you recognize, but any unsaved work in that program is lost. Don't end Windows system processes, because that can freeze or restart the PC.

### Does restarting the computer always unlock the file?

Usually, yes. If a program that starts with Windows opens the file again, disable that program at startup, or delete the file in Safe Mode.

### How do I delete a folder that is in use?

Use the same steps. Also close any File Explorer, Command Prompt or Terminal window that is open inside the folder, because those keep the folder busy.
