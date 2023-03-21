; ai-tools-ahk - AutoHotkey scripts for AI tools
; https://github.com/ecornell/ai-tools-ahk
; MIT License

#Requires AutoHotkey v2.0
#singleInstance force
#Include "_jxon.ahk"
#include "_Cursor.ahk"

Persistent
SendMode "Input"

;# init setup
if not (FileExist("settings.ini")) {
    api_key := InputBox("Enter your OpenAI API key", "AI-Tools-AHK : Setup", "W400 H100").value
    if (api_key == "") {
        MsgBox("You must enter an OpenAI key to use this script. Please restart the script and try again.")
        ExitApp
    }
    FileCopy("settings.ini.default", "settings.ini")
    IniWrite(api_key, ".\settings.ini", "settings", "default_api_key")
}
RestoreCursor()


;# globals
_settingsCache := Map()
_lastModified := fileGetTime("./settings.ini")
_displayResponse := false
_activeWin := ""
_oldClipboard := ""
_debug := GetSetting("settings", "debug", false)
_reload_on_change := GetSetting("settings", "reload_on_change", false)

;#
CheckSettings()

;# menu
InitPopupMenu()
InitTrayMenu()

;# hotkeys

HotKey GetSetting("settings", "hotkey_1"), (*) => (
    SelectText()
    PromptHandler(GetSetting("settings", "hotkey_1_prompt")))

HotKey GetSetting("settings", "hotkey_2"), (*) => (
    SelectText()
    ShowPopupMenu())

HotKey GetSetting("settings", "menu_hotkey"), (*) => (
    ShowPopupMenu())

;###

ShowPopupMenu() {
    _iMenu.Show()
}

PromptHandler(promptName, append := false) {
    try {

        global _running := true
        global _startTime := A_TickCount

        ShowWaitTooltip()
        SetSystemCursor(GetSetting("settings", "cursor_wait_file", "wait"))

        prompt := GetSetting(promptName, "prompt")
        promptEnd := GetSetting(promptName, "prompt_end")
        mode := GetSetting(promptName, "mode", GetSetting("settings", "default_mode"))
        input := GetTextFromClip()

        CallAPI(mode, promptName, prompt, input, promptEnd)

    } catch as err {
        global _running := false
        RestoreCursor()
        MsgBox Format("{1}: {2}.`n`nFile:`t{3}`nLine:`t{4}`nWhat:`t{5}", type(err), err.Message, err.File, err.Line, err.What), , 16
        ;throw err
    }
}

;###

SelectText() {
    if WinActive("ahk_exe WINWORD.EXE") or
        WinActive("ahk_exe OUTLOOK.EXE") {
        ; In Word/Outlook select the current paragraph
        Send "^{Up}^+{Down}+{Left}" ; Move to para start, select para, move left to not include para end
    } else if WinActive("ahk_exe notepad++.exe") or
        WinActive("ahk_exe Code.exe") {
        ; In Notepad++ select the current line
        Send "{End}{End}+{Home}+{Home}"
    } else {
        Send "^a"
    }
    sleep 50
}

GetTextFromClip() {

    global _activeWin := WinGetTitle("A")
    global _oldClipboard := A_Clipboard

    A_Clipboard := ""
    Send "^c"
    ClipWait(2)
    text := A_Clipboard

    if StrLen(text) < 1 {
        throw ValueError("No text selected", -1)
    } else if StrLen(text) > 2048 {
        throw ValueError("Text is too long", -1)
    }

    return text
}


GetSetting(section, key, defaultValue := "") {
    global _settingsCache
    if (_settingsCache.Has(section . key . defaultValue)) {
        return _settingsCache.Get(section . key . defaultValue)
    } else {
        value := IniRead(".\settings.ini", section, key, defaultValue)
        if IsNumber(value) {
            value := Number(value)
        } else {
            value := UnescapeSetting(value)
        }
        _settingsCache.Set(section . key . defaultValue, value)
        return value
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

    ;

    if (mode == "mode_chat_completion") {
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

    } else if (mode == "mode_completion" or mode == "mode_completion_azure") {
        fullPrompt := prompt . input . promptEnd
        body["prompt"] := fullPrompt
        body["max_tokens"] := max_tokens
        body["temperature"] := temperature
        body["frequency_penalty"] := frequency_penalty
        body["presence_penalty"] := presence_penalty
        body["top_p"] := top_p
        body["best_of"] := best_of
        body["stop"] := stop
        body["model"] := model

    } else if (mode == "mode_edit") {
        body["input"] := input
        body["instruction"] := prompt
        body["temperature"] := temperature
        body["top_p"] := top_p
        body["model"] := model
    }
    return body
}

CallAPI(mode, promptName, prompt, input, promptEnd) {

    body := GetBody(mode, promptName, prompt, input, promptEnd)
    bodyJson := Jxon_dump(body, 4)
    LogDebug "bodyJson ->`n" bodyJson

    endpoint := GetSetting(mode, "endpoint")
    apiKey := GetSetting(mode, "api_key", GetSetting("settings", "default_api_key"))

    req := ComObject("Msxml2.ServerXMLHTTP")
    
    req.open("POST", endpoint, true)
    req.SetRequestHeader("Content-Type", "application/json")
    req.SetRequestHeader("Authorization", "Bearer " apiKey) ; openai
    req.SetRequestHeader("api-key", apiKey) ; azure
    req.SetRequestHeader('Content-Length', StrLen(bodyJson))
    req.SetRequestHeader("If-Modified-Since", "Sat, 1 Jan 2000 00:00:00 GMT")
    
    req.send(bodyJson)

    req.WaitForResponse(GetSetting("settings", "timeout", 60))
    if (req.status == 200) { ; OK.
        data := req.responseText
        HandleResponse(data, mode, promptName, input)
    } else {
        MsgBox "Status " req.status " " req.responseText, , 16
    }

}

HandleResponse(data, mode, promptName, input) {

    try {

        LogDebug "data ->`n" data

        var := Jxon_Load(&data)

        if (mode == "mode_chat_completion") {
            text := var.Get("choices")[1].Get("message").Get("content")
        } else {
            text := var.Get("choices")[1].Get("text")
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
            if SubStr(text, 1, 1) == '"' and SubStr(text, -1) == '"' {
                text := SubStr(text, 2, -1)
            }
        }

        if _displayResponse {
            MyGui := Gui(, "Response")
            MyGui.SetFont("s14")
            MyGui.Opt("+AlwaysOnTop +Owner +Resize")  ; +Owner avoids a taskbar button.
            MyGui.Add("Edit", "r20 vMyEdit w600 Wrap", text)
            MyGui.Add("Button", , "Close").OnEvent("Click", (*) => WinClose())
            MyGui.Show("NoActivate")
        } else {
            WinActivate _activeWin
            A_Clipboard := text
            send "^v"
        }

        global _running := false
        Sleep 500
        A_Clipboard := _oldClipboard

     } finally {
        global _running := false
        RestoreCursor()
    }
}

InitPopupMenu() {
    global _iMenu := Menu()
    iMenuItemParms := Map()

    _iMenu.add "&`` - Display response in new window", NewWindowCheckHandler
    _iMenu.Add  ; Add a separator line.

    menu_items := IniRead("./settings.ini", "popup_menu")

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

                _iMenu.Add menu_text, MenuHandler
                item_count := DllCall("GetMenuItemCount", "ptr", _iMenu.Handle)
                iMenuItemParms[item_count] := v_promptName
            }
        }
    }
    MenuHandler(ItemName, ItemPos, MyMenu) {
        PromptHandler(iMenuItemParms[ItemPos])
    }
    NewWindowCheckHandler(*) {
        _iMenu.ToggleCheck "&`` - Display response in new window"
        global _displayResponse := !_displayResponse
        _iMenu.Show()
    }
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
    _sww_shortcut := a_startup "\" script_name ".lnk"
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
    Run A_ScriptDir . "\settings.ini"
}

ReloadSettings(*) {
    TrayTip("Reload Settings", "Reloading settings...", 5)
    _settingsCache.Clear()
    InitPopupMenu()
}

UnescapeSetting(obj) {
    obj := StrReplace(obj, "\n", "`n")
    return obj
}

ShowWaitTooltip() {
    if (_running) {
        elapsedTime := (A_TickCount - _startTime) / 1000
        ToolTip "Generating response... " Format("{:0.2f}", elapsedTime) "s"
        SetTimer () => ShowWaitTooltip(), -50
    } else {
        ToolTip()
    }
}

CheckSettings() {
    if (_reload_on_change and FileExist("./settings.ini")) {
        lastModified := fileGetTime("./settings.ini")
        if (lastModified != _lastModified) {
            global _lastModified := lastModified
            TrayTip("Settings Updated", "Restarting...", 5)
            Sleep 2000
            Reload
        }
        SetTimer () => CheckSettings(), -10000   ; Check every 10 seconds
    }
}

LogDebug(msg) {
    if (_debug != false) {
        now := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        logMsg := "[" . now . "] " . msg . "`n"
        FileAppend(logMsg, "./debug.log")
    }
}