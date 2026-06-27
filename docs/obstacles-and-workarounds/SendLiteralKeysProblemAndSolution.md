# The Keyboard-Injection Navigation Problem and the COM Solution

## Overview

For most of the script's lifetime, navigating a tab to a target folder was done by simulating user keystrokes into Explorer's address bar. This is called **keyboard injection** or **SendLiteralKeys** navigation. It looked deceptively simple. It was, in practice, the single largest source of failures in the entire automation: tabs left on Home, paths silently entered into the wrong control, and confirmation logic that lied.

This document records exactly what went wrong and why, then explains how switching to `Shell.Application` COM automation resolved each issue cleanly.

---

## The Original Approach: `_PastePath`

After opening a new tab with `Ctrl+T`, the script called `_PastePath(path)` to navigate it:

```ahk
_PastePath(path) {
    WinActivate "ahk_class CabinetWClass"
    if !WinWaitActive("ahk_class CabinetWClass", , 5) {
        _Log("_PastePath: Explorer did not become active — aborting")
        return false
    }

    Send("^l")          ; focus the address bar
    Sleep 600

    Send("^a")          ; select all existing text
    Sleep 200

    SendText path       ; type the path literally
    Sleep 300

    Send("{Enter}")     ; commit the navigation
    Sleep 1800          ; wait blindly for navigation to complete
    return true
}
```

The idea was straightforward: get the address bar focused, clear it, type the path, press Enter. Every step requires the window to be active and focused correctly. The `Sleep` values were chosen by hand-testing on a development machine.

---

## Failure Mode 1 — Focus Is a Global, Shared Resource

`WinActivate "ahk_class CabinetWClass"` asks the system to give keyboard focus to Explorer. The system does not guarantee it will *stay* there.

Between `WinActivate` returning and `Send("^l")` executing — even in the same script, even 15ms later — any of the following can steal focus:

- A Windows 11 notification toast appearing and auto-focusing
- The Explorer window itself re-focusing an internal control (the navigation pane, the file list) as a side-effect of the new tab being created
- A background process raising a modal dialog
- The transition from single-window mode to tabbed mode (Explorer recreates its UI and briefly has no focused control)

When focus was stolen between `WinActivate` and `Send("^l")`, the `Ctrl+L` keystroke went to whichever window happened to be active at that instant. The script had no way of knowing this had happened. It continued sending `Ctrl+A`, `SendText`, and `Enter` into the wrong target.

**Log evidence — address bar focus not confirmed:**

```
_PastePath: activating Explorer
_PastePath: Ctrl+L to focus address bar
_PastePath: Ctrl+A to select all
_PastePath: SendText path: E:\Projects\Portfolio
_PastePath: Enter to navigate
_PastePath: complete
```

The log showed no gap between these entries. The address bar never reported back whether it was actually focused. The script was flying blind.

---

## Failure Mode 2 — `Ctrl+L` Does Not Register During the Tabbed-Mode Transition

Windows 11 Explorer maintains different window modes: a **single-tab mode** (one pane, classic toolbar) and a **tabbed mode** (tab strip visible, slightly different chrome). When the first `Ctrl+T` is issued, Explorer transitions from single-tab to tabbed mode. During this transition it recreates internal controls and, for a brief window, does not accept keyboard input on the address bar.

The script added a `ControlGetFocus` check to detect this:

```ahk
focusBefore := ControlGetFocus("ahk_class CabinetWClass")
Send("^l")
Sleep 3000
focusAfter := ControlGetFocus("ahk_class CabinetWClass")

if focusBefore = focusAfter {
    _Log("Address bar focus unchanged after 3s — proceeding anyway")
}
```

**Log evidence — confirmed non-registration:**

```
Focus before Ctrl+L: 17043272
  (3 seconds pass)
Focus before Ctrl+L: 17043272
Address bar focus unchanged after 3s — proceeding anyway
```

The `Ctrl+L` made no difference to the focused control. The script detected this correctly — and then proceeded anyway. The subsequent `SendText` typed the path into whatever control ID `17043272` happened to be. On the first tab (the one going through the transition), that control was often the file list view, which simply ignored the text.

The result: the first additional tab was reliably left on Home regardless of what path was passed.

---

## Failure Mode 3 — Confirmation Was Meaningless

After `Send("{Enter}")`, the script waited with a fixed `Sleep 1800`. Nothing was actually checked. A `true` return from `_PastePath` meant only that the function ran without throwing — not that navigation succeeded.

An attempt was later made to confirm by watching the window title change:

```ahk
titleBefore := WinGetTitle("ahk_class CabinetWClass")
; ... navigate ...
Loop 40 {
    Sleep 200
    if WinGetTitle("ahk_class CabinetWClass") != titleBefore
        break
}
```

**The trailing-space sentinel bug:** To avoid a spurious match in the edge case where the new folder name happened to equal the current title, a trailing space was appended:

```ahk
titleBefore := WinGetTitle("ahk_class CabinetWClass") . " "   ; <-- the bug
```

Real Explorer titles never contain a trailing space. This meant `WinGetTitle(...) != titleBefore` was **always immediately true** — on the very first poll (200ms after `Enter`), before navigation had even started. The confirmation loop exited immediately every time.

**Log evidence:**

```
_PastePath: done after 200ms, title='Home and 1 more tab - File Explorer'
```

The title shown was `"Home and 1 more tab - File Explorer"` — *Home*, not the target folder. Navigation had not happened. The script reported success. The next `Ctrl+T` fired immediately, landing on a tab that was still processing the previous `Enter`, and its keystrokes were dropped.

---

## Failure Mode 4 — Addressing the Wrong Tab When Multiple Are Open

`WinGetTitle("ahk_class CabinetWClass")` returns the title of the **active (foreground) tab**, not the tab that was last navigated. On Windows 11, Explorer's compound title format is:

```
"Downloads and 4 more tabs - File Explorer"
```

The active tab is the one shown by name. If the user clicked on a different tab while the script was running, or if Explorer's internal focus logic brought a different tab to the front during a transition, the title reflected *that* tab — not the one the script had just tried to navigate. The confirmation check was watching the wrong thing.

There was no mechanism to target a specific tab. All keyboard input went to whichever tab was active at the moment the keystroke arrived. With five tabs being opened in quick succession, the probability of at least one keystroke missing its intended tab was high.

---

## Summary of Root Cause

All four failure modes share a single underlying cause: **keyboard injection depends on implicit global state** (which window is active, which control is focused, which tab is foreground) rather than on explicit references to the thing being operated on. Every step of `_PastePath` was a bet that the state happened to be correct at that millisecond. On a fast machine with no other activity, the bets usually paid off. Under any real-world variation they did not.

| Failure mode | Root cause |
|---|---|
| Ctrl+L going to wrong window | Focus is global; anything can steal it |
| Ctrl+L not registering | Explorer doesn't accept input during tabbed-mode transition |
| Confirmation always passing in 200ms | Trailing-space sentinel made the check trivially true |
| Title watch confirms wrong tab | Title reflects active tab, not the tab being navigated |

---

## The COM Solution

`Shell.Application` is a COM automation server that Explorer has exposed since the IE4 shell integration. It gives the script a **direct object reference** to each open Explorer window and to each tab within it.

```ahk
shell := ComObject("Shell.Application")
```

From this single object, every Explorer tab can be enumerated:

```ahk
for w in shell.Windows {
    if _IsFileExplorer(w)   ; filter to file browser tabs, not IE/WebBrowser hosts
        ...
}
```

Each `w` is a `IWebBrowser2`-compatible COM object with the following interface:

| Property / Method | What it gives us |
|---|---|
| `w.HWND` | The containing window's handle |
| `w.FullName` | Path to the executable — used to filter out non-Explorer COM objects |
| `w.Busy` | `true` while the tab is actively loading |
| `tab.Navigate2(path)` | Navigate that specific tab to a filesystem path |
| `tab.Navigate(path)` | Fallback if `Navigate2` throws |
| `tab.Document.Folder.Self.Path` | Read the current folder path of that specific tab |
| `tab.Refresh()` | Force the file-listing view to re-enumerate |

### How each failure mode is resolved

**Failure mode 1 (focus stolen):** `tab.Navigate2(path)` is a method call on an object reference. It does not require Explorer to have keyboard focus, does not require any particular control to be active, and cannot "land in the wrong place." Focus is irrelevant.

**Failure mode 2 (Ctrl+L not registering):** There is no `Ctrl+L`. The address bar is never involved. `Navigate2` drives the navigation directly through the shell's navigation stack.

**Failure mode 3 (confirmation lies):** Confirmation is done by reading `tab.Document.Folder.Self.Path` — the actual current path of the exact COM object that was navigated — and comparing it to the target (normalised, case-insensitive). The confirmation can only pass when the tab is showing the correct folder:

```ahk
if !_TabBusy(tab) {
    cur := _TabPath(tab)
    if (cur != "" && _NormPath(cur) = wantNorm) {
        ; confirmed
    }
}
```

**Failure mode 4 (wrong tab):** Each tab in `shell.Windows` is a distinct COM object. The script holds a reference to the specific object it just asked to navigate. Reading `.Path` from that object reflects *that* tab regardless of which tab is currently active in the Explorer UI.

### How the new tab is found after Ctrl+T

COM cannot create a new tab directly — `Ctrl+T` is still sent to open one. But finding it is done by exclusion rather than guessing:

```ahk
_FindNewTab(shell, ourHwnd, assigned) {
    ; A fresh tab sits on Home: path is "" or a shell GUID like "::{"
    ; An assigned tab has a real path already in the `assigned` map.
    ; The new tab is whichever one in our window matches neither condition.
}
```

The `assigned` map accumulates the normalised paths of all tabs the script has already successfully navigated. After `Ctrl+T`, the new tab is the one — in our window, with `w.HWND = ourHwnd` — whose path is not in `assigned`. A Home tab (path `""` or `"::{..."`) is preferred as it is unambiguous. This targeting is exact, stable, and does not depend on tab ordering or focus.

---

## Before and After

| Concern | Keyboard injection (`_PastePath`) | COM (`Navigate2`) |
|---|---|---|
| **Focus dependency** | Requires Explorer to hold focus throughout | None — COM call is independent of focus |
| **Tabbed-mode transition** | `Ctrl+L` silently dropped during transition | Not applicable — no keyboard used for navigation |
| **Navigation confirmation** | Window title (active tab only); had a sentinel bug making it always pass | Reads `tab.Document.Folder.Self.Path` on the exact tab object |
| **Tab targeting** | Implicit — whatever tab is currently active | Explicit — COM object reference held from `_FindNewTab` |
| **Retry logic** | None — a failed paste was undetectable | `NAV_ATTEMPTS` retries; each attempt re-checks `tab.Busy` before navigating |
| **Timing** | Fixed `Sleep` values tuned by hand | `_WaitIdle` polls `tab.Busy`; `CONFIRM_MS` is a ceiling, not a floor |

---

## Lessons Specific to This Problem

1. **Keyboard injection is a last resort, not a first choice.** When the target application exposes a programmable interface — COM, UIA, a named pipe, a documented API — use it. Keyboard simulation is appropriate only when no such interface exists.

2. **"Proceeding anyway" after detecting a failure always makes things worse.** The `Ctrl+L` focus check correctly identified that the address bar wasn't ready. The correct response was to wait or abort, not to continue. Continuing injected keystrokes into the wrong control.

3. **A sentinel value that makes a condition always true is the same as having no condition at all.** The trailing-space bug was not a subtle off-by-one — it eliminated the entire confirmation check. Every change to a safety check must be tested against the cases that check is supposed to catch.

4. **Object identity beats state polling.** Polling the window title is a proxy measure; reading `tab.Document.Folder.Self.Path` is a direct measurement. Proxies introduce ambiguity (whose tab? which title format?). Direct measurement does not.
