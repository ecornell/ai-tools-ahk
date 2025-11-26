; Utils.ahk - Utility functions for logging, tooltips, and helpers
; Part of ai-tools-ahk - https://github.com/ecornell/ai-tools-ahk

;# Globals (shared with main script)
global _waitTooltipActive := false
global _startTime := 0

;# Check if a Map object is empty
MapIsEmpty(m) {
    if (!IsObject(m))
        return true
    for k, v in m
        return false
    return true
}

;# Show wait tooltip with elapsed time
ShowWaitTooltip() {
    global _running, _startTime, _waitTooltipActive, WAIT_TOOLTIP_UPDATE_INTERVAL

    if (_running) {
        _waitTooltipActive := true
        elapsedTime := (A_TickCount - _startTime) / 1000
        ToolTip "Generating response... " Format("{:0.2f}", elapsedTime) "s"
        SetTimer UpdateWaitTooltip, WAIT_TOOLTIP_UPDATE_INTERVAL
    } else {
        ClearWaitTooltip()
    }
}

;# Update wait tooltip timer callback
UpdateWaitTooltip() {
    global _running, _startTime, _waitTooltipActive

    if (_running and _waitTooltipActive) {
        elapsedTime := (A_TickCount - _startTime) / 1000
        ToolTip "Generating response... " Format("{:0.2f}", elapsedTime) "s"
    } else {
        ClearWaitTooltip()
    }
}

;# Clear wait tooltip and stop timer
ClearWaitTooltip() {
    global _waitTooltipActive
    _waitTooltipActive := false
    SetTimer UpdateWaitTooltip, 0  ; Kill the timer
    ToolTip()  ; Clear the tooltip
}

;# Write debug message to log file
LogDebug(msg) {
    global _debug, DEBUG_LOG_FILE

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
