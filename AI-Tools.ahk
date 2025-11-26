; ai-tools-ahk - AutoHotkey scripts for AI tools
; https://github.com/ecornell/ai-tools-ahk
; MIT License

#Requires AutoHotkey v2.0
#singleInstance force
#Warn All, Off  ; Suppress false positive linter warnings

;# Include helper libraries
#Include "lib/_jxon.ahk"
#include "lib/_Cursor.ahk"
#Include "lib/_MD2HTML.ahk"

;# Include application modules
#Include "lib/Utils.ahk"
#Include "lib/Config.ahk"
#Include "lib/Selection.ahk"
#Include "lib/UI.ahk"
#Include "lib/API.ahk"

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

;# First-run setup
if not (FileExist(SETTINGS_FILE)) {
    ; Create GUI for provider selection
    providerGui := Gui("+AlwaysOnTop", "AI-Tools-AHK : Setup")
    providerGui.SetFont("s10")
    providerGui.Add("Text", "x20 y20 w360", "Choose your AI provider:")

    ; Add buttons for each provider
    openaiBtn := providerGui.Add("Button", "x20 y60 w360 h50", "OpenAI")
    geminiBtn := providerGui.Add("Button", "x20 y120 w360 h50", "Google Gemini")
    cancelBtn := providerGui.Add("Button", "x20 y180 w360 h40", "Cancel")

    ; Store selection in GUI object
    providerGui.selectedProvider := ""

    openaiBtn.OnEvent("Click", (*) => (providerGui.selectedProvider := "openai", providerGui.Hide()))
    geminiBtn.OnEvent("Click", (*) => (providerGui.selectedProvider := "gemini", providerGui.Hide()))
    cancelBtn.OnEvent("Click", (*) => (providerGui.selectedProvider := "cancel", providerGui.Hide()))
    providerGui.OnEvent("Close", (*) => (providerGui.selectedProvider := "cancel", providerGui.Hide()))
    providerGui.OnEvent("Escape", (*) => (providerGui.selectedProvider := "cancel", providerGui.Hide()))

    providerGui.Show("w400 h240")

    ; Wait for user to make a selection
    while (providerGui.selectedProvider == "") {
        Sleep 100
    }

    selectedProvider := providerGui.selectedProvider
    providerGui.Destroy()

    if (selectedProvider == "cancel" or selectedProvider == "") {
        ExitApp
    }

    ; Determine provider and prompt for appropriate API key
    if (selectedProvider == "openai") {
        ; OpenAI selected
        api_key := InputBox("Enter your OpenAI API key`n`nGet your key from: https://platform.openai.com/account", "AI-Tools-AHK : Setup - OpenAI", "W500 H150").value
        if (api_key == "") {
            MsgBox("To use this script, you need to enter an API key. Please restart the script and try again.")
            ExitApp
        }
        defaultMode := "mode_chat_completion"
        settingsSection := "settings"
        apiKeyField := "default_api_key"
    } else {
        ; Google Gemini selected
        api_key := InputBox("Enter your Google Gemini API key`n`nGet your key from: https://aistudio.google.com/app/apikey", "AI-Tools-AHK : Setup - Google Gemini", "W500 H150").value
        if (api_key == "") {
            MsgBox("To use this script, you need to enter an API key. Please restart the script and try again.")
            ExitApp
        }
        defaultMode := "mode_gemini"
        settingsSection := "mode_gemini"
        apiKeyField := "api_key"
    }

    try {
        if not FileExist(SETTINGS_DEFAULT_FILE) {
            MsgBox("Error: settings.ini.default not found. Please reinstall the script.", , MSGBOX_ERROR)
            ExitApp
        }
        FileCopy(SETTINGS_DEFAULT_FILE, SETTINGS_FILE)

        ; Write the API key to the appropriate section
        if (settingsSection == "settings") {
            ; For OpenAI, write to default_api_key in settings section
            IniWrite(api_key, SETTINGS_FILE, settingsSection, apiKeyField)
        } else {
            ; For Gemini, write to api_key in mode_gemini section
            IniWrite(api_key, SETTINGS_FILE, settingsSection, apiKeyField)
            ; Also set default_mode to use Gemini
            IniWrite(defaultMode, SETTINGS_FILE, "settings", "default_mode")
        }
    } catch as e {
        MsgBox("Error creating settings file: " e.Message, , MSGBOX_ERROR)
        ExitApp
    }
}
RestoreCursor()

;# Initialize configuration from modules
InitConfig()

;# Start settings file monitoring
CheckSettings()

;# Initialize UI
InitPopupMenu()
InitTrayMenu()

;# Setup hotkeys

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
