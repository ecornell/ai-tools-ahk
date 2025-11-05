; ai-tools-ahk - AutoHotkey scripts for AI tools
; https://github.com/ecornell/ai-tools-ahk
; MIT License

#Requires AutoHotkey v2.0
#singleInstance force
#Warn All, Off  ; Suppress false positive linter warnings
#Include "_jxon.ahk"
#include "_Cursor.ahk"
#Include "_MD2HTML.ahk"

Persistent
SendMode "Input"

;# Constants
SETTINGS_FILE := A_ScriptDir . "\settings.ini"
SETTINGS_DEFAULT_FILE := A_ScriptDir . "\settings.ini.default"
DEBUG_LOG_FILE := "./debug.log"

;## Text Processing Constants
MIN_TEXT_LENGTH := 1
MAX_TEXT_LENGTH := 16000

;## Timing Constants (milliseconds unless noted)
CLIPBOARD_WAIT_SHORT := 1          ; seconds - for quick clipboard operations
CLIPBOARD_WAIT_LONG := 2           ; seconds - for reliable clipboard capture
SLEEP_AFTER_SELECTION := 50        ; ms - delay after text selection
SLEEP_AFTER_CLIPBOARD := 50        ; ms - delay after clipboard operations
SLEEP_BEFORE_RESTORE := 500        ; ms - delay before restoring clipboard
TOOLTIP_CLEAR_DELAY := 2000        ; ms - auto-clear tooltip after this time
WAIT_TOOLTIP_UPDATE_INTERVAL := 500 ; ms - update frequency for wait tooltip
SETTINGS_CHECK_INTERVAL := 30000   ; ms - poll interval for settings file changes
TRAY_TIP_DURATION := 5000          ; ms - duration for tray notifications
RESTART_DELAY := 2000              ; ms - delay before restarting on settings change
WINDOW_ACTIVATION_TIMEOUT := 2     ; seconds - timeout for WinWaitActive

;## Default API Timeout Values (seconds)
DEFAULT_API_TIMEOUT := 120         ; Total request timeout
DEFAULT_CONNECT_TIMEOUT := 10      ; Connection establishment timeout
DEFAULT_SEND_TIMEOUT := 30         ; Request send timeout
HTTP_RESOLVE_TIMEOUT := 5000       ; ms - DNS resolution timeout

;## Response Window UI Constants
RESPONSE_WINDOW_WIDTH := 800
RESPONSE_WINDOW_HEIGHT := 480
RESPONSE_BUTTON_WIDTH := 80
RESPONSE_GUI_MARGIN_RIGHT := 30
RESPONSE_GUI_MARGIN_BOTTOM := 55
RESPONSE_BUTTON_OFFSET := 40

;## Default Model Parameters
DEFAULT_MAX_TOKENS := 1000
DEFAULT_TEMPERATURE := 0.7
DEFAULT_TOP_P := 1.0

;## Input Validation Constants
MSGBOX_ERROR := 16                 ; Error icon for MsgBox

;# init setup
if not (FileExist(SETTINGS_FILE)) {
    api_key := InputBox("Enter your OpenAI API key", "AI-Tools-AHK : Setup", "W400 H100").value
    if (api_key == "") {
        MsgBox("To use this script, you need to enter an OpenAI key. Please restart the script and try again.")
        ExitApp
    }
    try {
        if not FileExist(SETTINGS_DEFAULT_FILE) {
            MsgBox("Error: settings.ini.default not found. Please reinstall the script.", , MSGBOX_ERROR)
            ExitApp
        }
        FileCopy(SETTINGS_DEFAULT_FILE, SETTINGS_FILE)
        IniWrite(api_key, SETTINGS_FILE, "settings", "default_api_key")
    } catch as e {
        MsgBox("Error creating settings file: " e.Message, , MSGBOX_ERROR)
        ExitApp
    }
}
RestoreCursor()


;# globals
_running := false
_startTime := 0
_settingsCache := Map()
_lastModified := fileGetTime(SETTINGS_FILE)
_displayResponse := false
_activeWin := ""
_oldClipboard := ""
_iMenu := ""
_iMenuItemParms := Map()
_debug := GetSetting("settings", "debug", false)
_reload_on_change := GetSetting("settings", "reload_on_change", false)
_waitTooltipActive := false

;#
CheckSettings()

;# menu
InitPopupMenu()
InitTrayMenu()

;# hotkeys

try {
    hotkey1 := GetSetting("settings", "hotkey_1")
    if (hotkey1 != "") {
        try {
            HotKey hotkey1, (*) => (
                SelectText()
                PromptHandler(GetSetting("settings", "hotkey_1_prompt")))
        } catch as e {
            MsgBox("Error setting hotkey_1 '" hotkey1 "': " e.Message, , MSGBOX_ERROR)
        }
    }
} catch as e {
    MsgBox("Error reading hotkey_1 setting: " e.Message, , MSGBOX_ERROR)
}

try {
    hotkey2 := GetSetting("settings", "hotkey_2")
    if (hotkey2 != "") {
        try {
            HotKey hotkey2, (*) => (
                SelectText()
                ShowPopupMenu())
        } catch as e {
            MsgBox("Error setting hotkey_2 '" hotkey2 "': " e.Message, , MSGBOX_ERROR)
        }
    }
} catch as e {
    MsgBox("Error reading hotkey_2 setting: " e.Message, , MSGBOX_ERROR)
}

try {
    menuHotkey := GetSetting("settings", "menu_hotkey")
    if (menuHotkey != "") {
        try {
            HotKey menuHotkey, (*) => (
                ShowPopupMenu())
        } catch as e {
            MsgBox("Error setting menu_hotkey '" menuHotkey "': " e.Message, , MSGBOX_ERROR)
        }
    }
} catch as e {
    MsgBox("Error reading menu_hotkey setting: " e.Message, , MSGBOX_ERROR)
}

;###

ShowPopupMenu() {
    global _iMenu
    _iMenu.Show()
}

PromptHandler(promptName, append := false) {
    global _running, _startTime
    
    try {

        if (_running) {
            ToolTip("Request already in progress. Please wait for it to complete.")
            SetTimer(() => ToolTip(), -TOOLTIP_CLEAR_DELAY)
            return
        }

        _running := true
        _startTime := A_TickCount

        ShowWaitTooltip()
        SetSystemCursor(GetSetting("settings", "cursor_wait_file", "wait"))

        prompt := GetSetting(promptName, "prompt")
        promptEnd := GetSetting(promptName, "prompt_end")
        mode := GetSetting(promptName, "mode", GetSetting("settings", "default_mode"))
        
        ; Validate required settings
        if (mode == "" or mode == "default_mode") {
            MsgBox("Error: Mode not configured for prompt '" promptName "'.`n`nPlease check your settings.ini file.", , MSGBOX_ERROR)
            return
        }
        if (prompt == "" or prompt == "prompt") {
            MsgBox("Error: Prompt text not configured for '" promptName "'.`n`nPlease check your settings.ini file.", , MSGBOX_ERROR)
            return
        }
        
        try {
            input := GetTextFromClip()
        } catch {
            _running := false
            RestoreCursor()
            return
        }

        CallAPI(mode, promptName, prompt, input, promptEnd)

    } catch as err {
        MsgBox Format("{1}: {2}.`n`nFile:`t{3}`nLine:`t{4}`nWhat:`t{5}", type(err), err.Message, err.File, err.Line, err.What), , 16
    } finally {
        ; Ensure cleanup happens in all error paths
        if (_running) {
            _running := false
            ClearWaitTooltip()
            RestoreCursor()
        }
    }
}

;###

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
        matchedCmd := "{Home}+{End}"
        Send "{Home}"
        Sleep 30
        Send "+{End}"
        Sleep 30
    }

    sleep SLEEP_AFTER_SELECTION
    A_Clipboard := ""
    Send "^c"
    ClipWait(CLIPBOARD_WAIT_SHORT, 0)
    text := A_Clipboard

    if StrLen(text) < MIN_TEXT_LENGTH {
        Send "^a"
    }
    sleep SLEEP_AFTER_CLIPBOARD

    ; Log the selection decision (which mapping was used and contextual info)
    try {
        LogDebug(Format("Selection decision -> process: {}, class: {}, title: {}, matchedBy: {}, matchedKey: {}, matchedCmd: {}, textLen: {}", activeProcess, activeClass, activeTitle, matchedBy, matchedKey, matchedCmd, StrLen(text)))
    } catch {
        ; ignore logging errors
    }
}

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

;###

ShowWarning(message) {
    MsgBox message
}

GetSetting(section, key, defaultValue := "") {
    global _settingsCache, SETTINGS_FILE
    
    cacheKey := section . "." . key
    
    if (_settingsCache.Has(cacheKey)) {
        return _settingsCache.Get(cacheKey)
    } else {
        try {
            value := IniRead(SETTINGS_FILE, section, key, defaultValue)
            if IsNumber(value) {
                value := Number(value)
            } else {
                value := UnescapeSetting(value)
            }
            _settingsCache.Set(cacheKey, value)
            return value
        } catch as e {
            ; If IniRead fails, return default value
            return defaultValue
        }
    }
}

IsValidSetting(value, fieldName := "") {
    ; Check if setting is empty, unset (matches field name), or still has default placeholder
    if (value == "" or value == fieldName or value == "model" or value == "endpoint" or value == "default_api_key") {
        return false
    }
    return true
}

GetBodyParams(mode, promptName) {
    ; Efficiently load all parameters with mode defaults and prompt overrides
    params := Map()
    
    ; Define the parameter keys to fetch
    paramKeys := ["model", "max_tokens", "temperature", "frequency_penalty", "presence_penalty", "top_p", "best_of", "stop"]
    
    ; Load all parameters at once (leveraging cache)
    for _, key in paramKeys {
        modeVal := GetSetting(mode, key, "")
        promptVal := GetSetting(promptName, key, "")
        params[key] := (promptVal != "" && promptVal != key) ? promptVal : modeVal
    }
    
    return params
}

GetBody(mode, promptName, prompt, input, promptEnd) {
    body := Map()

    ; Get all parameters efficiently in one call
    params := GetBodyParams(mode, promptName)
    
    model := params["model"]
    max_tokens := params["max_tokens"]
    temperature := params["temperature"]
    frequency_penalty := params["frequency_penalty"]
    presence_penalty := params["presence_penalty"]
    top_p := params["top_p"]
    stop := params["stop"]

    ;; validate model is set and not a placeholder
    if (!IsValidSetting(model, "model")) {
        throw Error("Model not configured for mode '" mode "'")
    }

    ;; validate numeric settings
    if (!IsNumber(max_tokens) or max_tokens <= 0) {
        max_tokens := DEFAULT_MAX_TOKENS
    }
    if (!IsNumber(temperature) or temperature < 0 or temperature > 2) {
        temperature := DEFAULT_TEMPERATURE
    }
    if (!IsNumber(top_p) or top_p < 0 or top_p > 1) {
        top_p := DEFAULT_TOP_P
    }

    content := prompt . input . promptEnd
    messages := []
    prompt_system := GetSetting(promptName, "prompt_system", "")
    if (prompt_system != "") {
        messages.Push(Map("role", "system", "content", prompt_system))
    }
    messages.Push(Map("role", "user", "content", content))
    body["messages"] := messages
    body["max_tokens"] := max_tokens
    body["temperature"] := temperature
    body["frequency_penalty"] := frequency_penalty
    body["presence_penalty"] := presence_penalty
    body["top_p"] := top_p
    body["model"] := model

    return body
}

CallAPI(mode, promptName, prompt, input, promptEnd) {
    global _running

    ; Validate configuration before making API call
    try {
        body := GetBody(mode, promptName, prompt, input, promptEnd)
    } catch as e {
        MsgBox("Error: " e.Message "`n`nPlease check your settings.ini file.", , MSGBOX_ERROR)
        return
    }

    bodyJson := Jxon_dump(body, 4)
    LogDebug "bodyJson ->`n" bodyJson

    ; Pre-load all API settings at once to minimize GetSetting() calls
    endpoint := GetSetting(mode, "endpoint")
    apiKey := GetSetting(mode, "api_key", GetSetting("settings", "default_api_key"))
    timeout := GetSetting("settings", "timeout", DEFAULT_API_TIMEOUT)
    connectTimeout := GetSetting("settings", "connect_timeout", DEFAULT_CONNECT_TIMEOUT)
    sendTimeout := GetSetting("settings", "send_timeout", DEFAULT_SEND_TIMEOUT)

    ; Validate required settings
    if (!IsValidSetting(endpoint, "endpoint")) {
        MsgBox("Error: API endpoint not configured for mode '" mode "'.`n`nPlease check your settings.ini file.", , MSGBOX_ERROR)
        return
    }
    if (!IsValidSetting(apiKey, "default_api_key")) {
        MsgBox("Error: API key not configured.`n`nPlease check your settings.ini file.", , MSGBOX_ERROR)
        return
    }

    req := ComObject("Msxml2.ServerXMLHTTP")

    try {
        req.open("POST", endpoint, true)
        req.SetRequestHeader("Content-Type", "application/json")
        req.SetRequestHeader("Authorization", "Bearer " apiKey) ; openai
        req.SetRequestHeader("api-key", apiKey) ; azure
        req.SetRequestHeader('Content-Length', StrLen(bodyJson))
        req.SetRequestHeader("If-Modified-Since", "Sat, 1 Jan 2000 00:00:00 GMT")
        ; SetTimeouts: resolve, connect, send, receive (all in milliseconds)
        req.SetTimeouts(HTTP_RESOLVE_TIMEOUT, connectTimeout * 1000, sendTimeout * 1000, timeout * 1000)

        req.send(bodyJson "")
        req.WaitForResponse()

        if (req.status == 0) {
            MsgBox "Error: Unable to connect to the API. Please check your internet connection and try again.", , 16
            return
        } else if (req.status == 200) { ; OK.
            data := req.responseText
            HandleResponse(data, mode, promptName, input)
        } else {
            MsgBox "Error: Status " req.status " - " req.responseText, , 16
            return
        }
    } catch as e {
        MsgBox "Error: " "Exception thrown!`n`nwhat: " e.what "`nfile: " e.file 
        . "`nline: " e.line "`nmessage: " e.message "`nextra: " e.extra, , 16
        return
    } finally {
        ; Clean up COM object
        req := ""
        ; Ensure cleanup happens in all paths if HandleResponse didn't complete
        if (_running) {
            _running := false
            ClearWaitTooltip()
            RestoreCursor()
        }
    }
}

ResponseGui_Size(thisGui, MinMax, Width, Height)
{
    if MinMax = -1  ; The window has been minimized. No action needed.
        return
    ; Otherwise, the window has been resized or maximized. Resize the controls to match.
    try {
        ogcActiveXWBC := thisGui["IE"]
        xClose := ""
        ; Find the close button
        for ctrlName, ctrl in thisGui {
            if (ctrl.Type = "Button") {
                xClose := ctrl
                break
            }
        }
        if (ogcActiveXWBC)
            ogcActiveXWBC.Move(,, Width - RESPONSE_GUI_MARGIN_RIGHT, Height - RESPONSE_GUI_MARGIN_BOTTOM)
        if (xClose)
            xClose.Move(Width / 2 - RESPONSE_BUTTON_OFFSET, Height - RESPONSE_BUTTON_OFFSET,,)
    }
}

HandleResponse(data, mode, promptName, input) {
    global _running, _oldClipboard, _activeWin, _displayResponse

    try {

        LogDebug "data ->`n" data

        try {
            var := Jxon_Load(&data)
        } catch as e {
            LogDebug "Error: Failed to parse API response JSON: " e.Message
            MsgBox "Error: Invalid response from API. Unable to parse JSON.`n`nResponse: " SubStr(data, 1, 200), , 16
            return
        }
        
        try {
            ; Defensive parsing with null checks
            if (!var.Has("choices")) {
                throw Error("Missing 'choices' field in API response")
            }
            
            choices := var["choices"]
            if (choices.Length = 0) {
                throw Error("No choices returned in API response")
            }
            
            if (!choices[1].Has("message")) {
                throw Error("Missing 'message' field in response choice")
            }
            
            if (!choices[1]["message"].Has("content")) {
                throw Error("Missing 'content' field in response message")
            }
            
            text := choices[1]["message"]["content"]
            
            if (text = "") {
                throw Error("Content field is empty")
            }
        } catch as e {
            LogDebug "Error: Failed to extract content from API response: " e.Message
            MsgBox "Error: Invalid API response structure.`n`nDetails: " e.Message "`n`nResponse: " SubStr(data, 1, 200), , 16
            return
        }

        if text == "" {
            MsgBox "No text was generated. Consider modifying your input."
            return
        }

        ;; Clean up response text
        text := StrReplace(text, '`r', "") ; remove carriage returns
        replaceSelected := GetSetting(promptName, "replace_selected")

        if StrLower(replaceSelected) == "false" {
            responseStart := GetSetting(promptName, "response_start", "")
            responseEnd := GetSetting(promptName, "response_end", "")
            text := input . responseStart . text . responseEnd
        } else {
            ;# Remove leading newlines
            while SubStr(text, 1, 1) == '`n' {
                text := SubStr(text, 2)
            }
            text := Trim(text)
            ;# Remove enclosing quotes
            if StrLen(text) > 1 and SubStr(text, 1, 1) == '"' and SubStr(text, 0) == '"' {
                text := SubStr(text, 2, -1)
            }
        }

        response_type := GetSetting(promptName, "response_type", "")
        if _displayResponse or response_type == "popup" {
            MyGui := Gui(, "Response")
            MyGui.SetFont("s13")
            MyGui.Opt("+AlwaysOnTop +Owner +Resize")  ; +Owner avoids a taskbar button.

            ogcActiveXWBC := MyGui.Add("ActiveX", "xm w" RESPONSE_WINDOW_WIDTH " h" RESPONSE_WINDOW_HEIGHT " vIE", "Shell.Explorer")
            WB := ogcActiveXWBC.Value
            WB.Navigate("about:blank")
            
            try {
                css := FileRead("style.css")
            } catch {
                css := ""  ; Use default styles if file not found
            }
            
            options := {css:css
                , font_name:"Segoe UI"
                , font_size:16
                , font_weight:400
                , line_height:"1.6"} ; 1.6em - put decimals in "" for easier accuracy/handling.
            html := make_html(text, options, false)
            try {
                WB.document.write(html)
            } catch as e {
                LogDebug "Warning: Failed to write HTML to document: " e.Message
                MsgBox "Error: Unable to display response in browser window. Falling back to clipboard paste.", , MSGBOX_ERROR
                WinActivate _activeWin
                ; Wait for the window to become active before pasting
                if WinWaitActive(_activeWin, , WINDOW_ACTIVATION_TIMEOUT) {
                    A_Clipboard := text
                    send "^v"
                } else {
                    LogDebug "Warning: Failed to activate window: " _activeWin
                    MsgBox "Error: Unable to activate target window. Please manually paste the response."
                }
                return
            }            

            ;xEdit := MyGui.Add("Edit", "r10 vMyEdit w" RESPONSE_WINDOW_WIDTH " Wrap", text)
            ;xEdit.Value .= "`n`n----`n`n" html

            xClose := MyGui.Add("Button", "Default w" RESPONSE_BUTTON_WIDTH, "Close")
            xClose.OnEvent("Click", (*) => WinClose())

            MyGui.Show("NoActivate AutoSize Center")
            MyGui.GetPos(&x,&y,&w,&h)
            xClose.Move(w / 2 - RESPONSE_BUTTON_OFFSET,,,)
            MyGui.OnEvent("Size", ResponseGui_Size)
        } else {
            WinActivate _activeWin
            ; Wait for the window to become active before pasting
            if WinWaitActive(_activeWin, , WINDOW_ACTIVATION_TIMEOUT) {
                A_Clipboard := text
                send "^v"
            } else {
                LogDebug "Warning: Failed to activate window: " _activeWin
                MsgBox "Error: Unable to activate target window. Clipboard content is ready to paste manually."
            }
        }

        Sleep SLEEP_BEFORE_RESTORE

    } finally {
        ; Ensure cleanup happens in all code paths
        _running := false
        ClearWaitTooltip()
        
        ; Attempt to restore clipboard, but handle failure gracefully
        try {
            A_Clipboard := _oldClipboard
        } catch as e {
            LogDebug "Warning: Failed to restore clipboard: " e.Message
        }
        _oldClipboard := ""
        RestoreCursor()
    }
}

InitPopupMenu() {
    global _iMenu, _displayResponse, _iMenuItemParms, SETTINGS_FILE
    _iMenu := Menu()
    _iMenuItemParms := Map()

    _iMenu.add "&`` - Display response in new window", MenuNewWindowCheckHandler
    _iMenu.Add  ; Add a separator line.

    try {
        menu_items := IniRead(SETTINGS_FILE, "popup_menu")
    } catch as e {
        LogDebug "Warning: popup_menu section not found in settings.ini: " e.Message
        return
    }

    id := 1
    loop parse menu_items, "`n" {
        v_promptName := A_LoopField
        if (v_promptName != "" and SubStr(v_promptName, 1, 1) != "#") {
            if (v_promptName = "-") {
                _iMenu.Add  ; Add a separator line.
            } else {
                menu_text := GetSetting(v_promptName, "menu_text", v_promptName)
                if (RegExMatch(menu_text, "^[^&]*&[^&]*$") == 0) {
                    if (id == 10)
                        keyboard_shortcut := "&0 - "
                    else if (id > 10)
                        keyboard_shortcut := "&" Chr(id + 86) " - "
                    else
                        keyboard_shortcut := "&" id " - "
                    menu_text := keyboard_shortcut menu_text
                    id++
                }

                _iMenu.Add menu_text, MenuItemHandler
                try {
                    item_count := DllCall("GetMenuItemCount", "ptr", _iMenu.Handle)
                    _iMenuItemParms[item_count] := v_promptName
                } catch as e {
                    LogDebug "Warning: Failed to get menu item count: " e.Message
                }
            }
        }
    }
}

MenuItemHandler(ItemName, ItemPos, MyMenu) {
    global _iMenuItemParms
    PromptHandler(_iMenuItemParms[ItemPos])
}

MenuNewWindowCheckHandler(*) {
    global _iMenu, _displayResponse
    _iMenu.ToggleCheck "&`` - Display response in new window"
    _displayResponse := !_displayResponse
    _iMenu.Show()
}

InitTrayMenu() {
    tray := A_TrayMenu
    tray.add
    tray.add "Open settings", OpenSettings
    tray.add "Reload settings", ReloadSettings
    tray.add
    tray.add "Github readme", OpenGithub
    TrayAddStartWithWindows(tray)
}

TrayAddStartWithWindows(tray) {
    tray.add "Start with Windows", StartWithWindowsAction
    SplitPath a_scriptFullPath, , , , &script_name
    _sww_shortcut := a_startup "/" script_name ".lnk"
    if FileExist(_sww_shortcut) {
        fileGetShortcut _sww_shortcut, &target  ;# update if script has moved
        if (target != a_scriptFullPath) {
            fileCreateShortcut a_scriptFullPath, _sww_shortcut
        }
        tray.Check("Start with Windows")
    } else {
        tray.Uncheck("Start with Windows")
    }
    StartWithWindowsAction(*) {
        if FileExist(_sww_shortcut) {
            fileDelete(_sww_shortcut)
            tray.Uncheck("Start with Windows")
            trayTip("Start With Windows", "Shortcut removed", TRAY_TIP_DURATION)
        } else {
            fileCreateShortcut(a_scriptFullPath, _sww_shortcut)
            tray.Check("Start with Windows")
            trayTip("Start With Windows", "Shortcut created", TRAY_TIP_DURATION)
        }
    }
}

OpenGithub(*) {
    Run "https://github.com/ecornell/ai-tools-ahk#usage"
}

OpenSettings(*) {
    Run A_ScriptDir . "/settings.ini"
}

ReloadSettings(*) {
    global _settingsCache
    TrayTip("Reload Settings", "Reloading settings...", TRAY_TIP_DURATION)
    _settingsCache.Clear()
    InitPopupMenu()
}

UnescapeSetting(obj) {
    obj := StrReplace(obj, "\n", "`n")
    return obj
}

LoadSelectionMapping(sectionName) {
    ; Returns a Map of key -> value for the given INI section by parsing the file.
    global SETTINGS_FILE, _settingsCache

    cacheKey := "selection." . sectionName
    if (_settingsCache.Has(cacheKey)) {
        return _settingsCache.Get(cacheKey)
    }

    result := Map()
    try {
        content := FileRead(SETTINGS_FILE)
    } catch {
        ; cache empty result to avoid repeated file reads
        _settingsCache.Set(cacheKey, result)
        return result
    }

    inSection := false
    loop parse content, "`n"
    {
        rawLine := A_LoopField
        line := Trim(rawLine, " `t`r")
        if (line == "")
            continue
        ; Section header? (use regex to check starts with [ and ends with ])
        if (line ~= "^\[.*\]$") {
            sec := SubStr(line, 2, -1)
            if (sec = sectionName) {
                inSection := true
                continue
            } else if (inSection) {
                break
            } else {
                continue
            }
        }

        if (!inSection)
            continue

        if (SubStr(line, 1, 1) == ";" or SubStr(line, 1, 1) == "#")
            continue

        pos := InStr(line, "=")
        if (pos) {
            key := Trim(SubStr(line, 1, pos - 1))
            val := Trim(SubStr(line, pos + 1))
            val := UnescapeSetting(val)
            result[key] := val
        }
    }

    _settingsCache.Set(cacheKey, result)
    return result
}

MapIsEmpty(m) {
    if (!IsObject(m))
        return true
    for k, v in m
        return false
    return true
}

ShowWaitTooltip() {
    global _running, _startTime, _waitTooltipActive

    if (_running) {
        _waitTooltipActive := true
        elapsedTime := (A_TickCount - _startTime) / 1000
        ToolTip "Generating response... " Format("{:0.2f}", elapsedTime) "s"
        SetTimer UpdateWaitTooltip, WAIT_TOOLTIP_UPDATE_INTERVAL
    } else {
        ClearWaitTooltip()
    }
}

UpdateWaitTooltip() {
    global _running, _startTime, _waitTooltipActive
    
    if (_running and _waitTooltipActive) {
        elapsedTime := (A_TickCount - _startTime) / 1000
        ToolTip "Generating response... " Format("{:0.2f}", elapsedTime) "s"
    } else {
        ClearWaitTooltip()
    }
}

ClearWaitTooltip() {
    global _waitTooltipActive
    _waitTooltipActive := false
    SetTimer UpdateWaitTooltip, 0  ; Kill the timer
    ToolTip()  ; Clear the tooltip
}

CheckSettings() {
    global _reload_on_change, _lastModified, SETTINGS_FILE

    if (_reload_on_change and FileExist(SETTINGS_FILE)) {
        lastModified := fileGetTime(SETTINGS_FILE)
        if (lastModified != _lastModified) {
            _lastModified := lastModified
            TrayTip("Settings Updated", "Restarting...", TRAY_TIP_DURATION)
            Sleep RESTART_DELAY
            Reload
        }
        SetTimer CheckSettings, -SETTINGS_CHECK_INTERVAL
    }
}

OnFileChange(FileObj) {
    global _reload_on_change, SETTINGS_FILE

    if (_reload_on_change and FileObj.Name ~= "settings\.ini$") {
        TrayTip("Settings Updated", "Restarting...", TRAY_TIP_DURATION)
        Sleep RESTART_DELAY
        Reload
    }
}

LogDebug(msg) {
    global _debug

    if (_debug != false) {
        try {
            now := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
            logMsg := "[" . now . "] " . msg . "`n"
            FileAppend(logMsg, DEBUG_LOG_FILE)
        } catch {
            ; Silently fail if unable to write to log file
        }
    }
}
