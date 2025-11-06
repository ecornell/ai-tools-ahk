; UI.ahk - User interface (menus, GUI, tray)
; Part of ai-tools-ahk - https://github.com/ecornell/ai-tools-ahk

;# Globals (shared with main script)
global _iMenu := ""
global _iMenuItemParms := Map()
global _displayResponse := false

;# Show popup menu at cursor
ShowPopupMenu() {
    global _iMenu
    _iMenu.Show()
}

;# Initialize popup menu from settings
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

;# Handle menu item selection
MenuItemHandler(ItemName, ItemPos, MyMenu) {
    global _iMenuItemParms
    PromptHandler(_iMenuItemParms[ItemPos])
}

;# Toggle display mode (popup vs paste)
MenuNewWindowCheckHandler(*) {
    global _iMenu, _displayResponse
    _iMenu.ToggleCheck "&`` - Display response in new window"
    _displayResponse := !_displayResponse
    _iMenu.Show()
}

;# Initialize system tray menu
InitTrayMenu() {
    tray := A_TrayMenu
    tray.add
    tray.add "Open settings", OpenSettings
    tray.add "Reload settings", ReloadSettings
    tray.add
    tray.add "Github readme", OpenGithub
    TrayAddStartWithWindows(tray)
}

;# Add "Start with Windows" option to tray menu
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

;# Open GitHub readme in browser
OpenGithub(*) {
    Run "https://github.com/ecornell/ai-tools-ahk#usage"
}

;# Open settings.ini in default editor
OpenSettings(*) {
    Run A_ScriptDir . "/settings.ini"
}

;# Reload settings from file
ReloadSettings(*) {
    TrayTip("Reload Settings", "Reloading settings...", TRAY_TIP_DURATION)
    ReloadSettingsCache()
    InitPopupMenu()
}

;# Handle response window resize
ResponseGui_Size(thisGui, MinMax, Width, Height) {
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
