# Automating Windows 11 Explorer Tabs with AutoHotkey v2 — A Case Study

## The Goal

Open a saved list of folders, each in its own tab inside a single Windows 11 File Explorer window, at the click of a button from a WPF utility app.

Simple enough idea. What followed was a masterclass in why Windows 11 Explorer is not a well-behaved automation target.

---

## The Stack

| Layer | Technology |
|---|---|
| UI host | C# WPF (.NET 10) |
| Tab orchestration | AutoHotkey v2 script |
| Folder list | JSON persisted alongside the app |

The WPF app passes the folder paths as command-line arguments to the AHK script. The script does all the window and tab management.

---

## Attempt 1 — Fixed Sleeps

The obvious first cut: open Explorer, send `Ctrl+T` for each extra folder, then use `Ctrl+L` to focus the address bar, type the path, press `Enter`.

```ahk
Send("^t")
Sleep 800          ; wait for new tab

Send("^l")
Sleep 600          ; wait for address bar

SendText path
Sleep 300
Send("{Enter}")
Sleep 1800         ; wait for navigation
```

**What went wrong:** Three out of five tabs stayed on the default Home folder. The fixed sleeps were not long enough on a slower machine or for network paths (WSL UNC paths in particular). Explorer sometimes took 1–3 seconds longer than the hard-coded delay.

---

## Attempt 2 — Track the Window Handle (hwnd)

The next idea: capture the Explorer window's hwnd after launch, use it for all operations, and poll until the title changes rather than sleeping blind.

```ahk
; Confirm hwnd survives two consecutive 500ms polls (Windows 11 instability)
if candidate && candidate = prevCandidate {
    explorerHwnd := candidate
    break
}
```

**What went wrong:** Explorer on Windows 11 silently recreates its window handle when the first tab is added via `Ctrl+T`. The window transitions from a single-pane mode to a tabbed mode and gets a brand-new hwnd in the process. Our captured hwnd became stale, and every `WinActivate("ahk_hwnd " . explorerHwnd)` threw:

```
Error: Target window not found.
Specifically: ahk_hwnd 12784730
```

Adding hwnd re-detection after each `Ctrl+T` helped but did not fully solve it — the race between `WinExist` returning `true` and the window being destroyed in the gap before `WinActivate` persisted.

---

## Attempt 3 — Title-Delta Detection

Drop the hwnd for ongoing operations entirely. Use `ahk_class CabinetWClass` (the active Explorer window) for all `WinActivate` calls, and replace fixed sleeps with condition polling based on window title changes.

The key insight: Windows 11 Explorer uses a compound window title when multiple tabs are open:

```
"Portfolio Website Artwork & Artefacts - File Explorer"   ; single tab
"Home and 1 more tab - File Explorer"                     ; two tabs, active = Home
"Downloads and 4 more tabs - File Explorer"               ; five tabs, active = Downloads
```

This gives two reliable signals:
1. **New tab loaded** — title changes after `Ctrl+T`
2. **Navigation complete** — title changes after `Enter` in the address bar

```ahk
; Snapshot before Ctrl+T
titleBeforeNewTab := WinGetTitle("ahk_class CabinetWClass")
Send("^t")

; Wait for title to change
Loop 40 {
    Sleep 200
    newTabTitle := WinGetTitle("ahk_class CabinetWClass")
    if newTabTitle != titleBeforeNewTab
        break
}

; Then navigate and wait for title to change again
_PastePath(newTabTitle, currentPath)
```

**What went wrong — the trailing space bug:** A "safety" measure was added to handle the edge case where a folder name might equal the current tab title — a trailing space was appended to `titleBeforeNavigate` inside `_PastePath`. Because real Explorer titles never have trailing spaces, the check `title != "Home and 1 more tab - File Explorer "` is **immediately true** on the very first poll (200ms), regardless of whether navigation actually happened.

The log made this painfully obvious:

```
_PastePath: done after 200ms, title='Home and 1 more tab - File Explorer'
```

Every single tab "confirmed" in 200ms. The real effect: `_PastePath` returned before navigation started, the next `Ctrl+T` fired while the address bar was still processing `Enter`, and keystrokes were dropped into the wrong control. Two tabs were left on Home.

**Additional issue — `Ctrl+L` not registering on the first tab:** When transitioning from a single Explorer window to tabbed mode, the newly created tab briefly does not accept keyboard input. The focus check (comparing `ControlGetFocus` before and after `Ctrl+L`) correctly detected the failure but simply "proceeded anyway" — typing the path into whatever control happened to be focused.

The log confirmed:
```
Focus before Ctrl+L: 17043272
  (3 seconds pass, focus unchanged)
Address bar focus unchanged after 3s — proceeding anyway
```

---

## Final Solution — COM Automation

All the title-polling and keyboard-injection approaches share a fundamental fragility: they rely on the window being in exactly the right state at exactly the right millisecond. A better foundation is to talk to Explorer as a COM automation server, which it has supported since Internet Explorer's shell integration in the late 1990s.

### How it works

```ahk
shell := ComObject("Shell.Application")
```

`Shell.Application` exposes every open Explorer window (and every tab within it) as a `WebBrowser`-compatible COM object. Each tab object has:

| Property / Method | Purpose |
|---|---|
| `w.HWND` | Window handle of the containing window |
| `w.FullName` | Path to the executable (`explorer.exe`) |
| `w.Busy` | `true` while the tab is loading |
| `tab.Navigate2(path)` | Navigate to a path directly — no keyboard needed |
| `tab.Document.Folder.Self.Path` | Read back the current folder path |

### The algorithm

1. **Snapshot** all existing Explorer COM objects before opening anything.
2. **Open** the first folder with `Run('explorer.exe "..."')`.
3. **Find the new COM object** by looking for one whose `HWND` wasn't in the snapshot.
4. **For each additional folder:**
   - Send `Ctrl+T` (still needed — COM cannot create a new tab directly)
   - Find the new tab via COM: it's the one in our window whose path is empty or a shell GUID (the Home tab marker)
   - Call `tab.Navigate2(path)` — no address bar, no keyboard, no timing guesses
   - Confirm by reading `tab.Document.Folder.Self.Path` and comparing it to the target (normalised, case-insensitive)
   - Wait for `tab.Busy` to clear before moving on

### Why this is robust

- **No hwnd tracking after initial detection** — `Ctrl+T` still creates a new window handle when transitioning to tabbed mode, but the COM object for the tab is stable and survives the hwnd change.
- **No keyboard injection for navigation** — `Navigate2()` is a direct API call into the Explorer shell; it cannot miss or land in the wrong control.
- **Confirmation via COM, not title** — the title reflects the active tab; COM lets us confirm the exact tab we navigated, even if the user switches tabs mid-run.
- **Retry built in** — `NAV_ATTEMPTS` retries the navigate call if the tab is still busy or the path doesn't confirm.

### Key tunables (top of script)

```ahk
NAV_ATTEMPTS := 3       ; retries of Navigate2 per tab before giving up
IDLE_TIMEOUT := 3000    ; ms to let a tab go idle before touching it
CONFIRM_MS   := 6000    ; ms to wait for navigation to confirm
SETTLE_MS    := 600     ; ms to let a tab fully render before the next Ctrl+T
```

---

## Lessons Learned

| # | Lesson |
|---|---|
| 1 | **Never rely on Windows 11 Explorer's hwnd being stable.** It recreates its window handle at least once during the single→tabbed transition. |
| 2 | **Fixed sleeps are a maintenance liability.** They pass on the dev machine and fail in production. Always replace with condition polling or direct API confirmation. |
| 3 | **Title-delta polling is fragile.** When multiple tabs are open, the title reflects only the active tab, and a compound format like "X and N more tabs" changes for reasons unrelated to navigation. |
| 4 | **A "safety" string tweak can break more than it fixes.** The trailing-space sentinel made every navigation check trivially true in 200ms, causing cascading keystroke injection failures. Read the log carefully. |
| 5 | **COM automation is the right tool when it exists.** `Shell.Application` has been part of Windows since IE4. It gives you a stable object reference to each tab, busy-state polling, and direct navigation — no timing guesses required. |
| 6 | **Log everything, not just errors.** The `OpenFoldersTabbedExplorer.log` file written beside the script was essential to diagnosing each failure. Without it, the title-delta timing issues would have been very hard to spot. |

---

## Potential Video Outline

1. **The itch** — demo the utility, show the broken "Home" tabs, explain why you'd want this
2. **Naive approach** — AHK with fixed sleeps; show it failing on a real machine
3. **Down the hwnd rabbit hole** — explain Windows 11 Explorer's window recreation; show the error dialog
4. **Title-delta approach** — cleaner, explain compound titles; show the subtle trailing-space bug via the log
5. **The AHA moment** — open the Windows SDK docs / AutoHotkey COM docs; show `Shell.Application` and what it exposes
6. **COM approach** — walk through the final script; show it running cleanly for all 5 tabs including the WSL UNC path
7. **Lessons** — the broader principle: when an app exposes an automation API, use it instead of simulating input
