; Selection.ahk - Text selection and clipboard management
; Part of ai-tools-ahk - https://github.com/ecornell/ai-tools-ahk

;# Globals (shared with main script)
global _oldClipboard := ""
global _activeWin := ""

;# Intelligent text selection with process/class/title mapping
SelectText() {
    global _oldClipboard

    _oldClipboard := A_Clipboard
    processSelection := Map()
    classSelection := Map()

    ; Read from INI sections: selection_process, selection_class, selection_title
    iniProc := LoadSelectionMapping("selection_process")
    for k, v in iniProc {
        processSelection[StrLower(k)] := v
    }
    iniClass := LoadSelectionMapping("selection_class")
    for k, v in iniClass {
        classSelection[k] := v
    }
    iniTitle := LoadSelectionMapping("selection_title")
    titleSelection := Map()
    for k, v in iniTitle {
        ; store search key lowercased for case-insensitive substring match
        titleSelection[StrLower(k)] := v
    }

    activeProcess := WinGetProcessName("A")
    activeProcessLower := (activeProcess ? StrLower(activeProcess) : "")
    activeClass := WinGetClass("A")
    activeTitle := WinGetTitle("A")

    selected := false
    matchedBy := "none"    ; one of: process, class, title, fallback, none
    matchedKey := ""
    matchedCmd := ""

    ; Try process-specific selection first (case-insensitive)
    if (activeProcessLower != "" && processSelection.Has(activeProcessLower)) {
        matchedBy := "process"
        matchedKey := activeProcessLower
        matchedCmd := processSelection[activeProcessLower]
        Send matchedCmd
        selected := true
    }

    ; Then try window-class based selection
    if (!selected) {
        for className, command in classSelection {
            if (WinActive("ahk_class " . className)) {
                matchedBy := "class"
                matchedKey := className
                matchedCmd := command
                Send command
                selected := true
                break
            }
        }
    }

    ; Next try title-based selection (case-insensitive substring match)
    if (!selected && !MapIsEmpty(titleSelection)) {
        activeTitleLower := (activeTitle ? StrLower(activeTitle) : "")
        if (activeTitleLower != "") {
            for searchKey, command in titleSelection {
                if (InStr(activeTitleLower, StrLower(searchKey))) {
                    matchedBy := "title"
                    matchedKey := searchKey
                    matchedCmd := command
                    Send command
                    selected := true
                    break
                }
            }
        }
    }

    ; Minimal fallback: attempt a quick line selection, otherwise we'll fall back to Ctrl+A later
    if (!selected) {
        ; Try selecting to end then back to start of line (may work in many editors)
        matchedBy := "fallback"
        matchedKey := "quick-line"
        matchedCmd := "{End}+{Home}"
        Send "{End}"
        Sleep 30
        Send "+{Home}"
        Sleep 30
    }

    Sleep SLEEP_AFTER_SELECTION
    A_Clipboard := ""
    Send "^c"
    ClipWait(CLIPBOARD_WAIT_SHORT, 0)
    text := A_Clipboard

    if StrLen(text) < MIN_TEXT_LENGTH {
        Send "^a"
    }
    Sleep SLEEP_AFTER_CLIPBOARD

    ; Log the selection decision (which mapping was used and contextual info)
    try {
        LogDebug(Format("Selection decision -> process: {}, class: {}, title: {}, matchedBy: {}, matchedKey: {}, matchedCmd: {}, textLen: {}", activeProcess, activeClass, activeTitle, matchedBy, matchedKey, matchedCmd, StrLen(text)))
    } catch {
        ; ignore logging errors
    }
}

;# Get selected text from clipboard with validation
GetTextFromClip() {
    global _activeWin

    _activeWin := WinGetTitle("A")
    ; _oldClipboard should already be saved by SelectText()

    A_Clipboard := ""
    Send "^c"
    if !ClipWait(CLIPBOARD_WAIT_LONG) {
        throw Error("Clipboard operation timed out")
    }
    text := A_Clipboard

    if StrLen(text) < MIN_TEXT_LENGTH {
        throw Error("No text selected")
    } else if StrLen(text) > MAX_TEXT_LENGTH {
        throw Error("Text is too long (max " MAX_TEXT_LENGTH " characters)")
    }

    return text
}
