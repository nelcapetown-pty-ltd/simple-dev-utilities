# NelCapeTown Simple Dev Utilities — Architecture Overview

## Vision

A collection of small, focused developer productivity utilities for Windows, each independently deployable, all living together in a single repository and Visual Studio solution. The repo grows one utility at a time; adding a new one should never require touching an existing one.

---

## Repository Layout

```
NelCapeTown.SimpleDevUtilities.slnx   ← solution file (lists all utility projects)
│
├── ExplorerOrchestrator/             ← Utility 1 (self-contained)
│   ├── NelCapeTown.ExplorerOrchestrator.App.csproj
│   ├── App.xaml / App.xaml.cs
│   ├── MainWindow.xaml / MainWindow.xaml.cs
│   ├── FolderEntry.cs
│   ├── OpenFoldersTabbedExplorer.ahk ← automation script (copied to output on build)
│   ├── folders.json                  ← runtime persistence (auto-created, not in source)
│   ├── theme.txt                     ← runtime preference (auto-created, not in source)
│   └── docs/                         ← utility-specific documentation
│
├── <NextUtility>/                    ← Utility 2 (future — same pattern)
│   ├── NelCapeTown.<NextUtility>.App.csproj
│   └── ...
│
└── docs/                             ← repo-wide documentation
    ├── architecture/
    │   └── overview.md               ← this file
    └── how-to/
        └── automating-explorer-tabs-with-ahk.md
```

---

## The "One Folder per Utility" Rule

Each utility is a **self-contained folder** at the repository root. This decision drives several downstream choices:

### Why one folder per utility

| Concern | Decision |
|---|---|
| **Independent deployment** | Each utility can be copied or published from its own `bin/` without touching any other utility. |
| **Configuration isolation** | `folders.json`, `theme.txt`, and any other runtime files live beside the executable in `AppContext.BaseDirectory` — always inside the utility's own output folder. One utility's settings can never collide with another's. |
| **No shared runtime** | There is no shared WPF shell or plugin host. Each utility is its own `.exe`. This avoids version-lock between utilities and keeps each one runnable without the others being present. |
| **Build independence** | Each `.csproj` builds and publishes independently. The solution file is a convenience for opening everything in Visual Studio or VS Code at once; it is not required to build any individual utility. |

### What is shared

Nothing at runtime. At the repository level, only the solution file and the top-level `docs/` folder are shared. All code, assets, and scripts belong to exactly one utility folder.

---

## Utility: Explorer Orchestrator

### Purpose

Open a user-defined list of folders, each in its own tab inside a single Windows 11 File Explorer window, with a single button click.

### Files

| File | Role |
|---|---|
| `MainWindow.xaml` | WPF UI — folder card grid, toolbar with Add / Save / Theme / Open All buttons |
| `MainWindow.xaml.cs` | All application logic (load, save, launch, theme) |
| `FolderEntry.cs` | Simple model: `Path` (stored) + `Name` (derived from last path segment) |
| `App.xaml / App.xaml.cs` | WPF application entry point |
| `OpenFoldersTabbedExplorer.ahk` | AutoHotkey v2 script that orchestrates the Explorer tabs (see below) |
| `folders.json` | Persisted folder list — created at `AppContext.BaseDirectory` on first save |
| `theme.txt` | Dark/light preference — created at `AppContext.BaseDirectory` on first save |

### Persistence model

Both runtime files are written beside the executable:

```csharp
private static readonly string SettingsPath = Path.Combine(
    AppContext.BaseDirectory, "folders.json");

private static readonly string ThemePath = Path.Combine(
    AppContext.BaseDirectory, "theme.txt");
```

`AppContext.BaseDirectory` resolves to the output folder of the specific utility being run. This means:

- Debug runs write to `ExplorerOrchestrator/bin/Debug/net10.0-windows/`
- A published deployment writes to whatever folder the user extracts the utility into
- There is no user-profile or `%APPDATA%` dependency — the utility is fully portable

### The AHK script

`OpenFoldersTabbedExplorer.ahk` is an AutoHotkey v2 script that does the tab orchestration work Explorer's own API does not expose directly. It is declared as a `Content` file in the `.csproj`:

```xml
<Content Include="OpenFoldersTabbedExplorer.ahk">
  <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
</Content>
```

The WPF app resolves the script path the same way it resolves `folders.json` — via `AppContext.BaseDirectory` — so the script is always beside the executable regardless of where the utility is deployed.

The script is invoked by passing the folder list as command-line arguments:

```csharp
var quotedPaths = string.Join(" ", _folders.Select(f => $"\"{f.Path}\""));
Process.Start(new ProcessStartInfo
{
    FileName = ahkExe,
    Arguments = $"\"{AhkScriptPath}\" {quotedPaths}",
    UseShellExecute = false
});
```

The script uses `Shell.Application` COM automation to navigate each tab directly rather than injecting keyboard input — see [automating-explorer-tabs-with-ahk.md](../how-to/automating-explorer-tabs-with-ahk.md) for the full design rationale.

---

## Adding a New Utility

1. Create a new folder at the repository root: `<UtilityName>/`
2. Add a new WPF (or console/WinForms) project inside it with the naming convention `NelCapeTown.<UtilityName>.App.csproj`
3. Add the project to `NelCapeTown.SimpleDevUtilities.slnx`
4. Store all runtime files (JSON, preferences, helper scripts) beside the executable using `AppContext.BaseDirectory`
5. Add a `docs/` subfolder inside the utility folder for utility-specific documentation
6. No changes to any existing utility are required

The solution file after adding a second utility would look like:

```xml
<Solution>
  <Project Path="ExplorerOrchestrator/NelCapeTown.ExplorerOrchestrator.App.csproj" />
  <Project Path="NextUtility/NelCapeTown.NextUtility.App.csproj" />
</Solution>
```

---

## Technology Choices

| Choice | Reason |
|---|---|
| **.NET 10 / WPF** | Modern Windows-native UI with full access to Win32 APIs; no browser runtime dependency |
| **AutoHotkey v2** | Lightweight Windows automation for tasks that require shell-level interaction (window management, Explorer tab control) that are impractical to do purely from managed code |
| **COM (`Shell.Application`)** | The stable, Microsoft-supported way to query and drive Explorer windows — preferred over hwnd tracking or keyboard injection, both of which are fragile on Windows 11 |
| **Flat JSON persistence** | Simple, human-readable, no database dependency; appropriate for the small data sets these utilities manage |
| **No shared runtime / plugin model** | Keeps each utility independently deployable and avoids cross-utility version coupling |
