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

;# init setup
if not (FileExist("settings.ini")) {
    api_key := InputBox("Enter your OpenAI API key", "AI-Tools-AHK : Setup", "W400 H100").value
    if (api_key == "") {
        MsgBox("To use this script, you need to enter an OpenAI key. Please restart the script and try again.")
        ExitApp
    }
    try {
        if not FileExist("settings.ini.default") {
            MsgBox("Error: settings.ini.default not found. Please reinstall the script.", , 16)
            ExitApp
        }
        FileCopy("settings.ini.default", "settings.ini")
        IniWrite(api_key, "./settings.ini", "settings", "default_api_key")
    } catch as e {
        MsgBox("Error creating settings file: " e.Message, , 16)
        ExitApp
    }
}
RestoreCursor()


;# globals
_running := false
_startTime := 0
_settingsCache := Map()
_lastModified := fileGetTime("./settings.ini")
_displayResponse := false
_activeWin := ""
_oldClipboard := ""
_iMenu := ""
_iMenuItemParms := Map()
_debug := GetSetting("settings", "debug", false)
_reload_on_change := GetSetting("settings", "reload_on_change", false)

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
            MsgBox("Error setting hotkey_1 '" hotkey1 "': " e.Message, , 16)
        }
    }
} catch as e {
    MsgBox("Error reading hotkey_1 setting: " e.Message, , 16)
}

try {
    hotkey2 := GetSetting("settings", "hotkey_2")
    if (hotkey2 != "") {
        try {
            HotKey hotkey2, (*) => (
                SelectText()
                ShowPopupMenu())
        } catch as e {
            MsgBox("Error setting hotkey_2 '" hotkey2 "': " e.Message, , 16)
        }
    }
} catch as e {
    MsgBox("Error reading hotkey_2 setting: " e.Message, , 16)
}

try {
    menuHotkey := GetSetting("settings", "menu_hotkey")
    if (menuHotkey != "") {
        try {
            HotKey menuHotkey, (*) => (
                ShowPopupMenu())
        } catch as e {
            MsgBox("Error setting menu_hotkey '" menuHotkey "': " e.Message, , 16)
        }
    }
} catch as e {
    MsgBox("Error reading menu_hotkey setting: " e.Message, , 16)
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
            ;MsgBox "Already running. Please wait for the current request to finish."
            RestoreCursor()
            Reload
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
            MsgBox("Error: Mode not configured for prompt '" promptName "'.`n`nPlease check your settings.ini file.", , 16)
            return
        }
        if (prompt == "" or prompt == "prompt") {
            MsgBox("Error: Prompt text not configured for '" promptName "'.`n`nPlease check your settings.ini file.", , 16)
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

    A_Clipboard := ""
    Send "^c"
    if !ClipWait(2) {
        ; ClipWait timed out - clipboard operation failed
        A_Clipboard := _oldClipboard
        return
    }
    text := A_Clipboard
    
    if WinActive("ahk_exe WINWORD.EXE") or WinActive("ahk_exe OUTLOOK.EXE") {
        ; In Word/Outlook select the current paragraph
        Send "^{Up}^+{Down}+{Left}" ; Move to para start, select para, move left to not include para end
    } else if WinActive("ahk_exe notepad++.exe") or WinActive("ahk_exe Code.exe") {
        ; In Notepad++ select the current line
        Send "{End}{End}+{Home}+{Home}"
    } else {
        ; Select all text if no text is selected
        if StrLen(text) < 1 {
            Send "^a"
        }
    }
    sleep 50
}

GetTextFromClip() {
    global _activeWin

    _activeWin := WinGetTitle("A")
    ; _oldClipboard should already be saved by SelectText()
    
    A_Clipboard := ""
    Send "^c"
    if !ClipWait(2) {
        throw Error("Clipboard operation timed out")
    }
    text := A_Clipboard

    if StrLen(text) < 1 {
        throw Error("No text selected")
    } else if StrLen(text) > 16000 {
        throw Error("Text is too long")
    }

    return text
}

ShowWarning(message) {
    MsgBox message
}

GetSetting(section, key, defaultValue := "") {
    global _settingsCache
    
    if (_settingsCache.Has(section . key . defaultValue)) {
        return _settingsCache.Get(section . key . defaultValue)
    } else {
        try {
            value := IniRead("./settings.ini", section, key, defaultValue)
            if IsNumber(value) {
                value := Number(value)
            } else {
                value := UnescapeSetting(value)
            }
            _settingsCache.Set(section . key . defaultValue, value)
            return value
        } catch as e {
            ; If IniRead fails, return default value
            return defaultValue
        }
    }
}

GetBody(mode, promptName, prompt, input, promptEnd) {
    body := Map()

    ;; load mode defaults
    model := GetSetting(mode, "model")
    max_tokens := GetSetting(mode, "max_tokens")
    temperature := GetSetting(mode, "temperature")
    frequency_penalty := GetSetting(mode, "frequency_penalty")
    presence_penalty := GetSetting(mode, "presence_penalty")
    top_p := GetSetting(mode, "top_p")
    best_of := GetSetting(mode, "best_of")
    stop := GetSetting(mode, "stop", "")

    ;; load prompt overrides
    model := GetSetting(promptName, "model", model)
    max_tokens := GetSetting(promptName, "max_tokens", max_tokens)
    temperature := GetSetting(promptName, "temperature", temperature)
    frequency_penalty := GetSetting(promptName, "frequency_penalty", frequency_penalty)
    presence_penalty := GetSetting(promptName, "presence_penalty", presence_penalty)
    top_p := GetSetting(promptName, "top_p", top_p)
    best_of := GetSetting(promptName, "best_of", best_of)
    stop := GetSetting(promptName, "stop", stop)

    ;; validate numeric settings
    if (!IsNumber(max_tokens) or max_tokens <= 0) {
        max_tokens := 1000  ; sensible default
    }
    if (!IsNumber(temperature) or temperature < 0 or temperature > 2) {
        temperature := 0.7  ; sensible default
    }
    if (!IsNumber(top_p) or top_p < 0 or top_p > 1) {
        top_p := 1  ; sensible default
    }

    ;

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

    body := GetBody(mode, promptName, prompt, input, promptEnd)
    bodyJson := Jxon_dump(body, 4)
    LogDebug "bodyJson ->`n" bodyJson

    endpoint := GetSetting(mode, "endpoint")
    apiKey := GetSetting(mode, "api_key", GetSetting("settings", "default_api_key"))

    ; Validate required settings
    if (endpoint == "" or endpoint == "endpoint") {
        MsgBox("Error: API endpoint not configured for mode '" mode "'.`n`nPlease check your settings.ini file.", , 16)
        return
    }
    if (apiKey == "" or apiKey == "default_api_key") {
        MsgBox("Error: API key not configured.`n`nPlease check your settings.ini file.", , 16)
        return
    }
    if (!body.Has("model") or body["model"] == "" or body["model"] == "model") {
        MsgBox("Error: Model not configured for mode '" mode "'.`n`nPlease check your settings.ini file.", , 16)
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
        req.SetTimeouts(0, 0, 0, GetSetting("settings", "timeout", 120) * 1000) ; read, connect, send, receive

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
            ogcActiveXWBC.Move(,, Width-30, Height-55)
        if (xClose)
            xClose.Move(Width/2 - 40, Height-40,,)
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
            text := var.Get("choices")[1].Get("message").Get("content")
        } catch as e {
            LogDebug "Error: Failed to extract content from API response: " e.Message
            MsgBox "Error: Invalid API response structure. Missing expected fields.`n`nResponse: " SubStr(data, 1, 200), , 16
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
            
            ogcActiveXWBC := MyGui.Add("ActiveX", "xm w800 h480 vIE", "Shell.Explorer")
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
                MsgBox "Error: Unable to display response in browser window. Falling back to clipboard paste.", , 16
                WinActivate _activeWin
                A_Clipboard := text
                send "^v"
                return
            }            

            ;xEdit := MyGui.Add("Edit", "r10 vMyEdit w800 Wrap", text)
            ;xEdit.Value .= "`n`n----`n`n" html

            xClose := MyGui.Add("Button", "Default w80", "Close")
            xClose.OnEvent("Click", (*) => WinClose())

            MyGui.Show("NoActivate AutoSize Center")
            MyGui.GetPos(&x,&y,&w,&h)
            xClose.Move(w/2 - 40,,,)
            MyGui.OnEvent("Size", ResponseGui_Size)
        } else {
            WinActivate _activeWin
            A_Clipboard := text
            send "^v"
        }

        Sleep 500       
        
    } finally {
        ; Ensure cleanup happens in all code paths
        _running := false
        ClearWaitTooltip()
        A_Clipboard := _oldClipboard
        _oldClipboard := ""
        RestoreCursor()
    }
}

InitPopupMenu() {
    global _iMenu, _displayResponse, _iMenuItemParms
    _iMenu := Menu()
    _iMenuItemParms := Map()

    _iMenu.add "&`` - Display response in new window", MenuNewWindowCheckHandler
    _iMenu.Add  ; Add a separator line.

    try {
        menu_items := IniRead("./settings.ini", "popup_menu")
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
            trayTip("Start With Windows", "Shortcut removed", 5)
        } else {
            fileCreateShortcut(a_scriptFullPath, _sww_shortcut)
            tray.Check("Start with Windows")
            trayTip("Start With Windows", "Shortcut created", 5)
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
    TrayTip("Reload Settings", "Reloading settings...", 5)
    _settingsCache.Clear()
    InitPopupMenu()
}

UnescapeSetting(obj) {
    obj := StrReplace(obj, "\n", "`n")
    return obj
}

ShowWaitTooltip() {
    global _running, _startTime
    
    if (_running) {
        elapsedTime := (A_TickCount - _startTime) / 1000
        ToolTip "Generating response... " Format("{:0.2f}", elapsedTime) "s"
        SetTimer UpdateWaitTooltip, 50
    } else {
        ClearWaitTooltip()
    }
}

UpdateWaitTooltip() {
    global _running, _startTime
    
    if (_running) {
        elapsedTime := (A_TickCount - _startTime) / 1000
        ToolTip "Generating response... " Format("{:0.2f}", elapsedTime) "s"
    } else {
        ClearWaitTooltip()
    }
}

ClearWaitTooltip() {
    SetTimer UpdateWaitTooltip, 0  ; Kill the timer
    ToolTip()  ; Clear the tooltip
}

CheckSettings() {
    global _reload_on_change, _lastModified
    
    if (_reload_on_change and FileExist("./settings.ini")) {
        lastModified := fileGetTime("./settings.ini")
        if (lastModified != _lastModified) {
            _lastModified := lastModified
            TrayTip("Settings Updated", "Restarting...", 5)
            Sleep 2000
            Reload
        }
        SetTimer CheckSettings, -10000   ; Check every 10 seconds
    }
}

LogDebug(msg) {
    global _debug
    
    if (_debug != false) {
        try {
            now := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
            logMsg := "[" . now . "] " . msg . "`n"
            FileAppend(logMsg, "./debug.log")
        } catch {
            ; Silently fail if unable to write to log file
        }
    }
}