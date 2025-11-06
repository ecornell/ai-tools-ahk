; API.ahk - OpenAI/Azure API client
; Part of ai-tools-ahk - https://github.com/ecornell/ai-tools-ahk

;# Globals (shared with main script)
global _running := false

;# Get model parameters with mode defaults and prompt overrides
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

;# Build request body for API call
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

;# Make API call to OpenAI/Azure with retry logic
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

    ; Retry configuration
    maxRetries := 4
    retryDelays := [2000, 4000, 8000, 16000]  ; Exponential backoff in milliseconds
    attempt := 0
    lastError := ""
    lastStatus := 0

    ; Retry loop for network failures
    while (attempt <= maxRetries) {
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
                ; Network failure - eligible for retry
                lastStatus := 0
                lastError := "Unable to connect to the API"

                if (attempt < maxRetries) {
                    retryDelay := retryDelays[attempt + 1]
                    ToolTip("Network error. Retrying in " (retryDelay / 1000) " seconds... (Attempt " (attempt + 2) "/" (maxRetries + 1) ")")
                    Sleep retryDelay
                    ToolTip()  ; Clear tooltip
                    attempt++
                    req := ""  ; Clean up before retry
                    continue
                }
            } else if (req.status == 200) {
                ; Success!
                data := req.responseText
                req := ""  ; Clean up COM object
                HandleResponse(data, mode, promptName, input)
                return
            } else {
                ; HTTP error (400, 500, etc.) - don't retry
                MsgBox "Error: Status " req.status " - " req.responseText, , 16
                req := ""
                return
            }
        } catch as e {
            ; Connection exception - eligible for retry
            lastError := "Exception: " e.message

            if (attempt < maxRetries) {
                retryDelay := retryDelays[attempt + 1]
                ToolTip("Connection error. Retrying in " (retryDelay / 1000) " seconds... (Attempt " (attempt + 2) "/" (maxRetries + 1) ")")
                Sleep retryDelay
                ToolTip()  ; Clear tooltip
                attempt++
                req := ""  ; Clean up before retry
                continue
            }
        } finally {
            ; Always ensure COM object cleanup
            if (IsSet(req) && req != "") {
                req := ""
            }
        }

        ; If we get here, we've exhausted retries
        break
    }

    ; All retries exhausted - show final error
    if (lastStatus == 0 || lastError != "") {
        MsgBox "Error: Unable to connect to the API after " (maxRetries + 1) " attempts.`n`nLast error: " lastError "`n`nPlease check your internet connection and try again.", , 16
    }

    ; Ensure cleanup happens in all paths if HandleResponse didn't complete
    if (_running) {
        _running := false
        ClearWaitTooltip()
        RestoreCursor()
    }
}

;# Handle API response and display result
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
                css := FileRead("res/style.css")
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

;# Main prompt handler - orchestrates the entire flow
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
