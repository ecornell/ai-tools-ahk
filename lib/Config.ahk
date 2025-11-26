; Config.ahk - Settings and configuration management
; Part of ai-tools-ahk - https://github.com/ecornell/ai-tools-ahk

;# Globals (shared with main script)
global _settingsCache := Map()
global _lastModified := ""
global _debug := false
global _reload_on_change := false

;# Initialize configuration
InitConfig() {
    global _lastModified, _debug, _reload_on_change, SETTINGS_FILE

    _lastModified := FileGetTime(SETTINGS_FILE)
    _debug := GetSetting("settings", "debug", false)
    _reload_on_change := GetSetting("settings", "reload_on_change", false)
}

;# Get setting from INI file with caching
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

;# Validate that a setting is not empty or a placeholder
IsValidSetting(value, fieldName := "") {
    ; Check if setting is empty, unset (matches field name), or still has default placeholder
    if (value == "" or value == fieldName or value == "model" or value == "endpoint" or value == "default_api_key" or value == "default_api_key_gemini") {
        return false
    }
    return true
}

;# Unescape setting values (handle \n, etc.)
UnescapeSetting(obj) {
    obj := StrReplace(obj, "\n", "`n")
    return obj
}

;# Load selection mapping from INI section
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

;# Check for settings file changes and reload if needed
CheckSettings() {
    global _reload_on_change, _lastModified, SETTINGS_FILE, SETTINGS_CHECK_INTERVAL

    if (_reload_on_change and FileExist(SETTINGS_FILE)) {
        lastModified := FileGetTime(SETTINGS_FILE)
        if (lastModified != _lastModified) {
            _lastModified := lastModified
            TrayTip("Settings Updated", "Restarting...", TRAY_TIP_DURATION)
            Sleep RESTART_DELAY
            Reload
        }
        SetTimer CheckSettings, -SETTINGS_CHECK_INTERVAL
    }
}

;# Clear settings cache (for manual reload)
ReloadSettingsCache() {
    global _settingsCache
    _settingsCache.Clear()
}
