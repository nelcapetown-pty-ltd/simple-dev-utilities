; Paths to open as Explorer tabs
_ExplorerPaths := [
    "E:\src\nelcapetown.com portfolio website\Portfolio Website Artwork & Artefacts",
    "D:\Obsidian_Parent\DefaultVault",
    "D:\OneDrive Root\OneDrive - Nel Cape Town\Documents\NelCapeTownPtyLtdDotCom",
    "D:\Downloads",
    "\\wsl.localhost\Ubuntu-24.04\home\nel\projects\nelcapetowndotcom"
]

_ExplorerLogFile := "E:\src\AutoHotKeyScripts\Output.log"

^+#e::OpenStartupExplorer()

OpenStartupExplorer() {
    global _ExplorerPaths, _ExplorerLogFile
    SendMode "Input"
    SetKeyDelay 15, 15

    _ExplorerLog("About to wake WSL")
    RunWait 'wsl.exe -d Ubuntu-24.04 -e true', , "Hide"
    _ExplorerLog("WSL wake complete")

    _ExplorerLog("Opening first Explorer window: " . _ExplorerPaths[1])
    Run 'explorer.exe "' _ExplorerPaths[1] '"'

    if !WinWait("ahk_class CabinetWClass", , 10) {
        _ExplorerLog("Explorer window did not appear within 10 seconds - aborting")
        MsgBox "Explorer didn't open.", "StartupExplorer", 48
        return
    }
    _ExplorerLog("Explorer window appeared")

    _ExplorerLog("Beginning activation retry loop")
    loop 5 {
        _ExplorerLog("Activation attempt " . A_Index)
        WinActivate "ahk_class CabinetWClass"
        if WinWaitActive("ahk_class CabinetWClass", , 2) {
            _ExplorerLog("Explorer activated on attempt " . A_Index)
            break
        }
        Sleep 500
        if A_Index = 5 {
            _ExplorerLog("Explorer could not be activated after 5 attempts - aborting")
            MsgBox "Explorer opened but could not be activated.", "StartupExplorer", 48
            return
        }
    }

    Sleep 1200
    _ExplorerLog("First folder settled, beginning tab loop for " . (_ExplorerPaths.Length - 1) . " more tabs")

    Loop _ExplorerPaths.Length - 1 {
        _ExplorerLog("Opening tab " . (A_Index + 1) . " for: " . _ExplorerPaths[A_Index + 1])
        Send "^t"
        Sleep 800

        if !WinWaitActive("ahk_class CabinetWClass", , 5) {
            _ExplorerLog("Explorer did not become active after opening tab " . (A_Index + 1) . " - aborting")
            MsgBox "Explorer did not become active after opening a new tab.", "StartupExplorer", 48
            return
        }

        if !_ExplorerPastePath(_ExplorerPaths[A_Index + 1]) {
            _ExplorerLog("PastePath failed for tab " . (A_Index + 1) . " - aborting")
            return
        }
        _ExplorerLog("Tab " . (A_Index + 1) . " navigation complete")
        Sleep 1400
    }

    Send "^1"
    _ExplorerLog("StartupExplorer completed successfully")
}

_ExplorerPastePath(path) {
    _ExplorerLog("Inside PastePath: " . path)

    WinActivate "ahk_class CabinetWClass"
    if !WinWaitActive("ahk_class CabinetWClass", , 5) {
        _ExplorerLog("Explorer window did not become active before navigation.")
        MsgBox "Explorer window did not become active before navigation.", "StartupExplorer", 48
        return false
    }

    Send "^l"
    Sleep 600
    Send "^a"
    Sleep 200
    SendText path
    Sleep 300
    Send "{Enter}"
    Sleep 1800
    _ExplorerLog("PastePath successful")
    return true
}

_ExplorerLog(message) {
    global _ExplorerLogFile
    timestamp := FormatTime(, "yyyyMMdd HH:mmss")
    try {
        SplitPath _ExplorerLogFile, , &logDir
        if (logDir != "" && !DirExist(logDir))
            DirCreate logDir
        FileAppend timestamp " - " message "`r`n", _ExplorerLogFile, "UTF-8"
    } catch {
        ; Logging must never stop the script.
    }
}
