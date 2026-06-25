#Requires AutoHotkey v2.0
#SingleInstance Off

_LogFile := A_ScriptDir . "\OpenFoldersTabbedExplorer.log"

_Log("=== OpenFoldersTabbedExplorer started — received " . A_Args.Length . " path(s) ===")

if A_Args.Length = 0 {
    _Log("No arguments received — exiting")
    ExitApp
}

Loop A_Args.Length
    _Log("  Arg[" . A_Index . "]: " . A_Args[A_Index])

SendMode "Input"
SetKeyDelay 15, 15

; ── Snapshot existing Explorer windows BEFORE opening ──────────────────────────
existingHwnds := WinGetList("ahk_class CabinetWClass")
_Log("Pre-existing Explorer windows: " . existingHwnds.Length)
for hwnd in existingHwnds
    _Log("  Pre-existing hwnd: " . hwnd)

_Log("Opening first folder: " . A_Args[1])
Run('explorer.exe "' . A_Args[1] . '"')

_Log("Waiting up to 10s for any CabinetWClass window to appear")
if !WinWait("ahk_class CabinetWClass", , 10) {
    _Log("No Explorer window appeared within 10 seconds — aborting")
    ExitApp
}
_Log("CabinetWClass appeared — activating")

Loop 5 {
    _Log("Activation attempt " . A_Index)
    WinActivate "ahk_class CabinetWClass"
    if WinWaitActive("ahk_class CabinetWClass", , 2) {
        _Log("Explorer activated on attempt " . A_Index)
        break
    }
    Sleep 500
    if A_Index = 5 {
        _Log("Could not activate Explorer after 5 attempts — aborting")
        ExitApp
    }
}

; ── Poll until the same new hwnd appears in two consecutive scans ───────────────
; Windows 11 Explorer recreates its window multiple times during initialisation.
; We only trust a hwnd once it survives two polls 500ms apart.
_Log("Polling for a stable new Explorer hwnd (checking every 500ms, up to 15s)")
explorerHwnd := 0
prevCandidate := 0
Loop 30 {
    Sleep 500
    allHwnds := WinGetList("ahk_class CabinetWClass")

    candidate := 0
    for hwnd in allHwnds {
        isNew := true
        for existing in existingHwnds {
            if hwnd = existing {
                isNew := false
                break
            }
        }
        if isNew {
            candidate := hwnd
            break
        }
    }

    _Log("  Poll " . A_Index . ": candidate=" . candidate . "  prev=" . prevCandidate
        . "  allWindows=" . allHwnds.Length)

    if candidate && candidate = prevCandidate {
        explorerHwnd := candidate
        _Log("  → Stable hwnd confirmed after " . A_Index . " polls: " . explorerHwnd)
        break
    }
    prevCandidate := candidate
}

if !explorerHwnd {
    _Log("No stable new hwnd found — falling back to topmost CabinetWClass")
    allHwnds := WinGetList("ahk_class CabinetWClass")
    _Log("  Windows available: " . allHwnds.Length)
    for hwnd in allHwnds
        _Log("  hwnd: " . hwnd)
    if allHwnds.Length > 0 {
        explorerHwnd := allHwnds[1]
        _Log("  Fallback hwnd: " . explorerHwnd)
    } else {
        _Log("No Explorer windows found at all — aborting")
        ExitApp
    }
}

if A_Args.Length = 1 {
    _Log("Only one path provided — done")
    _Log("=== Completed ===")
    ExitApp
}

_Log("Beginning tab loop for " . (A_Args.Length - 1) . " additional folder(s)")

Loop A_Args.Length - 1 {
    currentPath := A_Args[A_Index + 1]
    _Log("--- Tab " . (A_Index + 1) . " of " . (A_Args.Length - 1) . " ---")
    _Log("Target path: " . currentPath)

    _Log("Activating Explorer (hwnd=" . explorerHwnd . ")")
    if WinExist("ahk_hwnd " . explorerHwnd) {
        WinActivate("ahk_hwnd " . explorerHwnd)
        _Log("Activated by hwnd")
    } else {
        _Log("hwnd gone — falling back to topmost CabinetWClass")
        if !WinExist("ahk_class CabinetWClass") {
            _Log("No Explorer window found at all — aborting")
            break
        }
        WinActivate "ahk_class CabinetWClass"
        explorerHwnd := WinExist("ahk_class CabinetWClass")
        _Log("Fallback hwnd: " . explorerHwnd)
    }
    Sleep 200

    _Log("Sending Ctrl+T")
    Send("^t")
    Sleep 800

    _Log("Waiting for Explorer to be active after Ctrl+T")
    if !WinWaitActive("ahk_class CabinetWClass", , 5) {
        _Log("Explorer not active after Ctrl+T — aborting")
        break
    }
    _Log("Explorer active after Ctrl+T")

    if !_PastePath(currentPath) {
        _Log("_PastePath failed for tab " . (A_Index + 1) . " — aborting")
        break
    }

    _Log("Tab " . (A_Index + 1) . " complete — waiting 1400ms")
    Sleep 1400
}

_Log("Switching to first tab (Ctrl+1)")
if WinExist("ahk_hwnd " . explorerHwnd)
    WinActivate("ahk_hwnd " . explorerHwnd)
else if WinExist("ahk_class CabinetWClass")
    WinActivate "ahk_class CabinetWClass"
Send("^1")
_Log("=== OpenFoldersTabbedExplorer completed ===")


_PastePath(path) {
    _Log("_PastePath: activating Explorer")
    WinActivate "ahk_class CabinetWClass"
    if !WinWaitActive("ahk_class CabinetWClass", , 5) {
        _Log("_PastePath: Explorer did not become active — aborting")
        return false
    }

    _Log("_PastePath: Ctrl+L to focus address bar")
    Send("^l")
    Sleep 600

    _Log("_PastePath: Ctrl+A to select all")
    Send("^a")
    Sleep 200

    _Log("_PastePath: SendText path: " . path)
    SendText path
    Sleep 300

    _Log("_PastePath: Enter to navigate")
    Send("{Enter}")
    Sleep 1800
    _Log("_PastePath: complete")
    return true
}

_Log(message) {
    global _LogFile
    timestamp := FormatTime(, "yyyyMMdd HH:mmss")
    try {
        SplitPath _LogFile, , &logDir
        if (logDir != "" && !DirExist(logDir))
            DirCreate logDir
        FileAppend timestamp " - " message "`r`n", _LogFile, "UTF-8"
    } catch {
        ; Logging must never stop the script
    }
}
