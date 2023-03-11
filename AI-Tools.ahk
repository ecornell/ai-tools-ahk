; ai-tools-ahk - AutoHotkey scripts for AI tools
; https://github.com/ecornell/ai-tools-ahk
; MIT License

#Requires AutoHotkey v2.0
#singleInstance force
#Include "_jxon.ahk"

Persistent
SendMode "Input"

;# init setup
if not (FileExist("settings.ini")) {
    api_key := InputBox("Enter our OpenAI key", "AI-Tools-AHK : Setup", "W400 H100").value
    if(api_key == "") {
        MsgBox("You must enter an OpenAI key to use this script. Please restart the script and try again.")
        ExitApp
    }
    FileCopy("settings.ini.default", "settings.ini")
    IniWrite(api_key,".\settings.ini","settings","default_api_key")
}

;#

displayResponse := false
activeWin := ""
oldClipboard := ""

defaultMode := GetSetting("settings", "default_mode")
defaultApiKey := GetSetting("settings", "default_api_key")

;#

tray := A_TrayMenu
tray.add
tray.add "Github readme", OpenGithub
StartWithWindows()

;#

^+j:: {
    SelectText()
    PromptHandler("spelling")
}

^+k:: {
    SelectText()
    ShowPopupMenu()
}

^!+k:: {
    ShowPopupMenu()
}

;###

ShowPopupMenu() {
    global displayResponse := false
    id := 1

    iMenu := Menu()
    iMenu.add "&`` - Display response in new window", MyMenuDisplayCheck
    iMenu.Add  ; Add a separator line.
    iMenu.Add "&" id++ " - Improve writting", (*) => PromptHandler("writting")
    iMenu.Add "&" id++ " - Fix spelling && grammar", (*) => PromptHandler("spelling")
    iMenu.Add "&" id++ " - Make shorter", (*) => PromptHandler("shorter")
    iMenu.Add "&" id++ " - Make longer", (*) => PromptHandler("longer")
    iMenu.Add "&" id++ " - Change Tone - Professional", (*) => PromptHandler("tone-professional")
    iMenu.Add "&" id++ " - Simplify language", (*) => PromptHandler("simplify")
    iMenu.Add  ; Add a separator line.
    iMenu.Add "&" id++ " - Summarize", (*) => PromptHandler("summarize")
    iMenu.Add "&" id++ " - Explain this", (*) => PromptHandler("explain")
    iMenu.Add "&" id++ " - Find action items", (*) => PromptHandler("items")
    iMenu.Add  ; Add a separator line.
    iMenu.Add "& Space - Continue writting", (*) => PromptHandler("continue")
    iMenu.Show()

    MyMenuDisplayCheck(*) {
        iMenu.ToggleCheck "&`` - Display response in new window"
        global displayResponse := !displayResponse
        iMenu.Show()
    }
}

PromptHandler(promptName, append := false) {
    try {

        prompt := GetSetting("prompt_" promptName, "prompt")
        promptEnd := GetSetting("prompt_" promptName, "prompt_end")
        mode := GetSetting("prompt_" promptName, "mode", defaultMode)
        input := GetTextFromClip()

        CallAPI(mode, promptName, prompt, input, promptEnd)

    } catch as err {
        ToolTip()
        MsgBox Format("{1}: {2}.`n`nFile:`t{3}`nLine:`t{4}`nWhat:`t{5}", type(err), err.Message, err.File, err.Line, err.What), , 16
        throw err
    }
}

;###

SelectText() {
    if WinActive("ahk_exe WINWORD.EXE") or
        WinActive("ahk_exe OUTLOOK.EXE") {
        ; In Word/Outlook select the current paragraph
        Send "^{Up}^+{Down}+{Left}" ; Move to para start, select para, move left to not include para end
    } else if WinActive("ahk_exe notepad++.exe") {
        ; In Notepad++ select the current line
        Send "{End}+{Home}"
    } else {
        Send "^a"
    }
    sleep 50
}

GetTextFromClip() {

    global activeWin := WinGetTitle("A")
    global oldClipboard := A_Clipboard

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
    value := IniRead(".\settings.ini", section, key, defaultValue)
    if IsNumber(value) {
        value := Number(value)
    }
    return value
}

GetBody(mode, promptName, prompt, input, promptStop) {
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
    model := GetSetting("prompt_" promptName, "model", model)
    max_tokens := GetSetting("prompt_" promptName, "max_tokens", max_tokens)
    temperature := GetSetting("prompt_" promptName, "temperature", temperature)
    frequency_penalty := GetSetting("prompt_" promptName, "frequency_penalty", frequency_penalty)
    presence_penalty := GetSetting("prompt_" promptName, "presence_penalty", presence_penalty)
    top_p := GetSetting("prompt_" promptName, "top_p", top_p)
    best_of := GetSetting("prompt_" promptName, "best_of", best_of)
    stop := GetSetting("prompt_" promptName, "stop", stop)

    ;

    if (mode == "mode_completion" or mode == "mode_completion_azure") {
        fullPrompt := prompt . input . promptStop

        body["prompt"] := fullPrompt
        body["max_tokens"] := max_tokens
        body["temperature"] := temperature
        body["frequency_penalty"] := frequency_penalty
        body["presence_penalty"] := presence_penalty
        body["top_p"] := top_p
        body["best_of"] := best_of
        body["stop"] := stop
        body["model"] := model

    } else if (mode == "mode_chat_completion") {
        content := prompt . input

        body["messages"] := [
            Map("role", "user", "content", content)
        ]
        body["max_tokens"] := max_tokens
        body["temperature"] := temperature
        body["frequency_penalty"] := frequency_penalty
        body["presence_penalty"] := presence_penalty
        body["top_p"] := top_p
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

CallAPI(mode, promptName, prompt, input, promptStop) {

    statusMessage := "Running . . ."
    ToolTip statusMessage

    body := GetBody(mode, promptName, prompt, input, promptStop)
    endpoint := GetSetting(mode, "endpoint") 
    apiKey := GetSetting(mode, "api_key", defaultApiKey) 

    req := ComObject("Msxml2.XMLHTTP")
    req.open("POST", endpoint, true)
    req.onreadystatechange := Ready

    req.SetRequestHeader("Content-Type", "application/json") 
    req.SetRequestHeader("Authorization", "Bearer " apiKey) ; openai
    req.SetRequestHeader("api-key", apiKey) ; azure

    bodyJson := Jxon_dump(body, 4)
    ;MsgBox bodyJson

    req.send(bodyJson)

    Ready() {
        if (req.readyState != 4) {  ; Not done yet.
            statusMessage := statusMessage . " ."
            ToolTip statusMessage
            return
        }
        ToolTip()
        if (req.status == 200) { ; OK.
            data := req.responseText
            ;MsgBox data
            HandleResponse(data, mode, promptName, input)
        } else {
            MsgBox "Status " req.status " " req.responseText, , 16
        }
    }
    return

}

HandleResponse(data, mode, promptName, input) {

    ;MsgBox data

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

    append := GetSetting("prompt_" promptName, "append")
    if StrLower(append) == "true" {
        text := input . text
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

    if displayResponse {
        MyGui := Gui(, "Response")
        MyGui.SetFont("s14")
        MyGui.Opt("+AlwaysOnTop +Owner +Resize")  ; +Owner avoids a taskbar button.
        MyGui.Add("Edit", "r20 vMyEdit w600 Wrap", text)
        MyGui.Add("Button", , "Close").OnEvent("Click", (*) => WinClose())
        MyGui.Show("NoActivate")
    } else {
        WinActivate activeWin
        A_Clipboard := text
        send "^v"
    }

    Sleep 500
    A_Clipboard := oldClipboard

}

OpenGithub(*) {
    Run "https://github.com/ecornell/ai-tools-ahk#usage"
}

StartWithWindows() {
    global sww_shortcut
    tray.add "Start with Windows", StartWithWindowsAction
    SplitPath a_scriptFullPath, , , , &script_name
    sww_shortcut := a_startup "\" script_name ".lnk"
    if FileExist(sww_shortcut) {
        fileGetShortcut sww_shortcut, &target  ;# update if script has moved
        if (target != a_scriptFullPath) {
            fileCreateShortcut a_scriptFullPath, sww_shortcut
        }
        tray.Check("Start with Windows")
    } else {
        tray.Uncheck("Start with Windows")
    }
}

StartWithWindowsAction(*) {
    if FileExist(sww_shortcut) {
        fileDelete(sww_shortcut)
        tray.Uncheck("Start with Windows")
        trayTip("Start With Windows", "Shortcut removed", 5)
    } else {
        fileCreateShortcut(a_scriptFullPath, sww_shortcut)
        tray.Check("Start with Windows")
        trayTip("Start With Windows", "Shortcut created", 5)
    }
}

