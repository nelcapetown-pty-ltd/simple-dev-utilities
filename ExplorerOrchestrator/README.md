# Explorer Orchestrator

A Windows utility that manages a curated set of folders and opens them all as tabs in a single Windows Explorer window — in one click.

Built with WPF on .NET 10 and AutoHotkey v2.

![Logo](docs/assets/RecursiveKnotLogo_Trademarked.svg)

---

## What it does

Explorer Orchestrator keeps a persistent list of folders you care about and gives you two ways to get into them:

- **Click a card** — opens that folder in a new Explorer window immediately.
- **Open All in Explorer** — launches AutoHotkey to open every folder in your list as a tab inside a *single* Explorer window.

Folders are saved to a `folders.json` file next to the executable, so your list survives restarts.

---

## Features

| Feature | Detail |
| --- | --- |
| Folder card grid | Scrollable, wrap-layout grid of folder cards |
| Add folders | Multi-select folder browser dialog |
| Persistent storage | Saved to `folders.json` (JSON, human-readable) |
| Dark / Light theme | Full two-tone theming; preference saved to `theme.txt` |
| Single-click open | Opens any folder directly in Explorer |
| Batch tabbed open | Opens all folders as tabs in one Explorer window via AutoHotkey |
| Robust tab scripting | Polls for a stable window handle — works around Windows 11's Explorer window recreation behaviour |
| Diagnostic logging | AutoHotkey script writes a timestamped log (`OpenFoldersTabbedExplorer.log`) |

---

## Requirements

| Requirement | Version |
| --- | --- |
| Windows | 10 / 11 |
| .NET Runtime | 10.0 (Windows) |
| AutoHotkey | v2 (optional — required only for "Open All in Explorer") |

AutoHotkey v2 is detected automatically at the four most common install paths. If it is not found, single-folder opening still works; only the batch-tab feature is unavailable.

---

## Getting started

### Build from source

```powershell
git clone <repo-url>
cd ExplorerOrchestrator
dotnet build -c Release
```

The build copies `OpenFoldersTabbedExplorer.ahk` next to the executable automatically.

### Run

```powershell
dotnet run
# or launch the built exe directly:
.\bin\Release\net10.0-windows\NelCapeTown.ExplorerOrchestrator.App.exe
```

On first launch the app seeds a default folder list. Edit it with **+ Add Folder** and hit **Save**.

---

## Usage

### Toolbar

| Button | Action |
| --- | --- |
| **+ Add Folder** | Open a multi-select folder browser and add new entries |
| **Save** | Write the current list to `folders.json` |
| **Light / Dark Theme** | Toggle theme; persisted across sessions |
| **Open All in Explorer** | Open every folder as a tab in one Explorer window |

### Folder cards

- **Click the card** — opens the folder in a new Explorer window.
- **× button** — removes the folder from the list (remember to Save).

---

## How "Open All in Explorer" works

The feature is implemented in `OpenFoldersTabbedExplorer.ahk` (AutoHotkey v2):

1. The WPF app passes all folder paths as command-line arguments to the script.
2. The script opens the **first** path in a new Explorer window and waits for it to appear.
3. It polls for a stable window handle — checking whether the same `hwnd` appears in two consecutive 500 ms scans — to handle the window recreation that Windows 11 Explorer performs on startup.
4. For each additional path it sends `Ctrl+T` (new tab), then `Ctrl+L` → path → `Enter` to navigate.
5. Finally it switches back to the first tab with `Ctrl+1`.

All steps are logged with timestamps to `OpenFoldersTabbedExplorer.log`.

---

## Project structure

```text
ExplorerOrchestrator/
├── App.xaml                            Application resources (theme brushes)
├── App.xaml.cs                         Application entry point
├── MainWindow.xaml                     Main UI layout
├── MainWindow.xaml.cs                  UI logic, folder management, AHK launch
├── FolderEntry.cs                      Folder data model
├── AssemblyInfo.cs                     WPF theme assembly attribute
├── OpenFoldersTabbedExplorer.ahk       AutoHotkey v2 — batch tabbed open script
├── StartupExplorer.ahk                 AutoHotkey v2 — hotkey-triggered variant
├── NelCapeTown.ExplorerOrchestrator.App.csproj
└── docs/
    └── assets/
        └── RecursiveKnotLogo_Trademarked.svg
```

The solution file (`NelCapeTown.SimpleDevUtilities.slnx`) lives at the repository root and covers all utilities.

### Runtime files (not committed)

| File | Purpose |
| --- | --- |
| `folders.json` | Saved folder list |
| `theme.txt` | Saved theme preference (`dark` or `light`) |
| `OpenFoldersTabbedExplorer.log` | AutoHotkey diagnostic log |

---

## AutoHotkey scripts

Two AHK scripts ship with the project:

### `OpenFoldersTabbedExplorer.ahk`

The primary script, called by the WPF app. Accepts folder paths as command-line arguments. Copied to the output directory at build time.

### `StartupExplorer.ahk`

A standalone variant bound to `Ctrl+Shift+Win+E`. Opens a hardcoded set of paths and also wakes WSL (`wsl.exe -d Ubuntu-24.04`) before launching Explorer. Useful as a system-startup script independent of the WPF app.

---

## License

MIT — Copyright 2026 [NelCapeTown (Pty) Ltd](https://nelcapetown.com)
