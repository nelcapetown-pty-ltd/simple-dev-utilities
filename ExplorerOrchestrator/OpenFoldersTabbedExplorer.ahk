#Requires AutoHotkey v2.0
#SingleInstance Off

; --- Tunables ----------------------------------------------------------------
NAV_ATTEMPTS := 3       ; retries of Navigate2 per tab before giving up
IDLE_TIMEOUT := 3000    ; ms to let a tab go idle before we touch it
CONFIRM_MS   := 6000    ; ms to wait for a navigation to confirm
SETTLE_MS    := 600     ; ms to let a tab fully render before the next Ctrl+T
; -----------------------------------------------------------------------------

_LogFile := A_ScriptDir . "\OpenFoldersTabbedExplorer.log"
_Log("=== OpenFoldersTabbedExplorer (COM v2) started -- received " . A_Args.Length . " path(s) ===")

if A_Args.Length = 0 {
    _Log("No arguments received -- exiting")
    ExitApp
}

Loop A_Args.Length
    _Log("  Arg[" . A_Index . "]: " . A_Args[A_Index])

SendMode "Input"
SetKeyDelay 15, 15

shell := ComObject("Shell.Application")

; -- Snapshot existing Explorer window hwnds so we can spot our new one --------
preHwnds := Map()
for w in shell.Windows {
    try {
        if _IsFileExplorer(w)
            preHwnds[w.HWND] := true
    }
}
_Log("Pre-existing Explorer windows (by hwnd): " . preHwnds.Count)

; -- Open the first folder in a brand-new window ------------------------------
_Log("Opening first folder: " . A_Args[1])
Run('explorer.exe "' . A_Args[1] . '"')

; -- Find OUR new window -------------------------------------------------------
ourHwnd  := 0
firstTab := 0
Loop 50 {                                  ; up to ~10s
    Sleep 200
    for w in shell.Windows {
        try {
            if _IsFileExplorer(w) && !preHwnds.Has(w.HWND) {
                ourHwnd  := w.HWND
                firstTab := w
                break
            }
        }
    }
    if ourHwnd {
        _Log("  Found new window hwnd=" . ourHwnd . " after " . (A_Index * 200) . "ms")
        break
    }
}

if !ourHwnd {
    _Log("Could not find new Explorer window -- aborting")
    ExitApp
}

; Track which folder paths are already "claimed" by a tab. The first tab counts.
assigned := Map()
_WaitIdle(firstTab, IDLE_TIMEOUT)
firstPath := _TabPath(firstTab)
assigned[_NormPath(firstPath != "" ? firstPath : A_Args[1])] := true

if A_Args.Length = 1 {
    _Log("Only one path provided -- done")
    _Log("=== Completed ===")
    ExitApp
}

; -- For each remaining path: new tab, then COM-navigate it -------------------
_Log("Beginning tab loop for " . (A_Args.Length - 1) . " additional folder(s)")

Loop A_Args.Length - 1 {
    path := A_Args[A_Index + 1]
    tabNo := A_Index + 1
    _Log("--- Tab " . tabNo . " -- target: " . path . " ---")

    WinActivate("ahk_id " . ourHwnd)
    if !WinWaitActive("ahk_id " . ourHwnd, , 5) {
        _Log("  Our window did not activate before Ctrl+T -- skipping")
        continue
    }

    Send("^t")

    newTab := _FindNewTab(shell, ourHwnd, assigned)
    if !newTab {
        _Log("  Could not locate the new (unassigned) tab -- skipping")
        continue
    }

    if _NavigateTab(newTab, path, tabNo) {
        assigned[_NormPath(path)] := true
        actual := _TabPath(newTab)
        if (actual != "")
            assigned[_NormPath(actual)] := true
        _Log("  Tab " . tabNo . " navigated OK")
    } else {
        _Log("  Tab " . tabNo . " could not be confirmed -- left as-is")
    }
}

_Log("Switching to first tab (Ctrl+1)")
WinActivate("ahk_id " . ourHwnd)
Send("^1")
_Log("=== OpenFoldersTabbedExplorer (COM v2) completed ===")


; ----------------------------------------------------------------------------
;  Helpers
; ----------------------------------------------------------------------------

_IsFileExplorer(w) {
    try
        return InStr(w.FullName, "explorer.exe") > 0
    return false
}

; The new tab is the one in our window that isn't already on an assigned folder.
; A freshly created tab sits on Home -> its path is "" or a shell GUID ("::..."),
; which is never one of our assigned paths, so it's preferred.
_FindNewTab(shell, ourHwnd, assigned) {
    Loop 40 {                              ; up to ~4s
        Sleep 100
        homeCandidate := 0
        unassignedCandidate := 0
        for w in shell.Windows {
            try {
                if (w.HWND != ourHwnd)
                    continue
                p := _TabPath(w)
                if (p = "" || SubStr(p, 1, 2) = "::") {
                    homeCandidate := w
                    break
                }
                if (!assigned.Has(_NormPath(p)) && !unassignedCandidate)
                    unassignedCandidate := w
            }
        }
        if homeCandidate {
            _Log("    New (Home) tab found after " . (A_Index * 100) . "ms")
            return homeCandidate
        }
        if unassignedCandidate {
            _Log("    New (unassigned) tab found after " . (A_Index * 100) . "ms")
            return unassignedCandidate
        }
    }
    return 0
}

; Navigate a specific tab object to a path; confirm by reading ITS own location.
_NavigateTab(tab, path, tabNo) {
    global NAV_ATTEMPTS, IDLE_TIMEOUT, CONFIRM_MS, SETTLE_MS
    wantNorm := _NormPath(path)

    _WaitIdle(tab, IDLE_TIMEOUT)           ; let the new tab finish being born

    Loop NAV_ATTEMPTS {
        attempt := A_Index
        navigated := false
        try {
            tab.Navigate2(path)
            navigated := true
        } catch as e {
            _Log("    [tab " . tabNo . "] Navigate2 threw: " . e.Message . " -- trying Navigate")
            try {
                tab.Navigate(path)
                navigated := true
            } catch as e2 {
                _Log("    [tab " . tabNo . "] Navigate threw: " . e2.Message)
            }
        }

        if navigated {
            tries := CONFIRM_MS // 100
            Loop tries {
                Sleep 100
                if !_TabBusy(tab) {
                    cur := _TabPath(tab)
                    if (cur != "" && _NormPath(cur) = wantNorm) {
                        _Log("    [tab " . tabNo . "] confirmed at '" . cur
                            . "' (attempt " . attempt . ", " . (A_Index * 100) . "ms)")
                        _RefreshTab(tab)       ; force the view to re-enumerate
                        Sleep SETTLE_MS        ; settle before the next Ctrl+T
                        return true
                    }
                }
            }
        }

        _Log("    [tab " . tabNo . "] attempt " . attempt . " unconfirmed -- retrying")
        _WaitIdle(tab, 1500)
    }

    _Log("    [tab " . tabNo . "] gave up after " . NAV_ATTEMPTS . " attempts")
    return false
}

_TabBusy(tab) {
    try
        return tab.Busy ? true : false
    return false                           ; if unreadable, don't block forever
}

_TabPath(tab) {
    try
        return tab.Document.Folder.Self.Path
    return ""
}

_WaitIdle(tab, timeoutMs) {
    t := 0
    while (t < timeoutMs) {
        if !_TabBusy(tab)
            return
        Sleep 100
        t += 100
    }
}

_RefreshTab(tab) {
    try
        tab.Refresh()
}

; Loose path comparison: drop trailing slash, normalise case.
_NormPath(p) {
    p := StrReplace(p, "/", "\")
    if (SubStr(p, -1) = "\")
        p := SubStr(p, 1, StrLen(p) - 1)
    return StrLower(p)
}

_Log(message) {
    global _LogFile
    timestamp := FormatTime(, "yyyyMMdd HH:mm:ss")
    try {
        SplitPath _LogFile, , &logDir
        if (logDir != "" && !DirExist(logDir))
            DirCreate logDir
        FileAppend timestamp " - " message "`r`n", _LogFile, "UTF-8"
    } catch {
        ; Logging must never stop the script
    }
}