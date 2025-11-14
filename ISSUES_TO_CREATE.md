# GitHub Issues to Create

This document contains formatted issues ready to be created on GitHub based on the code review findings.

---

## Issue 1: [CRITICAL] Incorrect Model Name in Default Settings

**Labels**: `bug`, `critical`, `configuration`

**Title**: Fix incorrect model name in settings.ini.default

**Description**:
The default settings file contains an invalid model name that will cause API failures on first run.

**Problem**:
- Location: `settings.ini.default:188, 197`
- Current value: `model="gpt-4.1-mini"`
- This model name doesn't exist in OpenAI's API

**Expected Behavior**:
Should use a valid OpenAI model name such as:
- `gpt-4o-mini` (recommended - latest mini model)
- `gpt-3.5-turbo` (alternative)
- `gpt-4o` (if premium model desired)

**Impact**:
- Users will get API errors immediately after setup
- Poor first-run experience
- Confusing error messages

**Affected Lines**:
- Line 188: `[mode_chat_completion]` section
- Line 197: `[mode_chat_completion_azure]` section

**Fix Required**:
```ini
# Change from:
model="gpt-4.1-mini"

# To:
model="gpt-4o-mini"
```

---

## Issue 2: [CRITICAL] API Key Stored in Plaintext

**Labels**: `security`, `critical`, `enhancement`

**Title**: API keys are stored in plaintext in settings.ini

**Description**:
API keys are currently stored in plaintext in the `settings.ini` file, which poses a security risk.

**Problem**:
- Location: `AI-Tools.ahk:70-74`
- API key is saved directly to INI file without encryption
- If the file is accessed, committed to git, or backed up to cloud storage, the key is exposed

**Current Behavior**:
```ahk
api_key := InputBox("Enter your OpenAI API key"...
IniWrite(api_key, SETTINGS_FILE, "settings", "default_api_key")
```

**Risk Level**: HIGH
- Exposed credentials in version control
- Cloud backup services may sync the file
- Malware could read the file
- Shared computers expose keys to other users

**Recommendations** (prioritized):

1. **Short-term** (Do immediately):
   - Add clear warning in README.md about not committing settings.ini
   - Add prominent comment in settings.ini.default about security
   - Verify .gitignore properly excludes settings.ini

2. **Medium-term** (Next release):
   - Use Windows Credential Manager for key storage
   - Implement basic encryption using Windows DPAPI

3. **Long-term** (Future enhancement):
   - Add option to use environment variables
   - Support Windows Credential Manager as primary storage
   - Add key rotation/update mechanism

**Example Fix for README**:
```markdown
## Security Warning

⚠️ **IMPORTANT**: Your API key is stored in `settings.ini`. This file should:
- NEVER be committed to version control
- NEVER be shared or uploaded
- Be excluded from cloud backup services
- Have restricted file permissions on shared systems

Consider using environment variables or Windows Credential Manager for enhanced security.
```

---

## Issue 3: ~~[HIGH] Typo in Prompt Configuration~~ ✅ FIXED

**Status**: Fixed in commit a569a1d

---

## Issue 4: [HIGH] Missing Input Validation in API Call

**Labels**: `bug`, `high`, `validation`

**Title**: Add input validation before API calls to prevent malformed requests

**Description**:
The API request builder doesn't validate that required parameters are non-empty before concatenation.

**Problem**:
- Location: `lib/API.ahk:56`
- No validation that `prompt` and `input` are non-empty
- Could send malformed requests to API

**Current Code**:
```ahk
content := prompt . input . promptEnd
```

**Risk**:
- Empty prompt could send just user input (unclear intent)
- Empty input could send just prompt (wasting API calls)
- Concatenation of empty strings creates confusing API behavior

**Proposed Fix**:
```ahk
; Validate required parameters
if (prompt == "" && input == "") {
    throw Error("Both prompt and input cannot be empty")
}
if (input == "") {
    throw Error("No input text provided")
}

; Ensure promptEnd is never unset
if (!IsSet(promptEnd)) {
    promptEnd := ""
}

content := prompt . input . promptEnd
```

**Additional Validation Needed**:
Should also validate in `GetBody()` function:
- `model` is not empty (already done ✓)
- `max_tokens` is positive number (already done ✓)
- `temperature` is in valid range 0-2 (already done ✓)
- `frequency_penalty` is in valid range -2.0 to 2.0 (MISSING)
- `presence_penalty` is in valid range -2.0 to 2.0 (MISSING)

---

## Issue 5: [HIGH] Race Condition in Request Handling

**Labels**: `bug`, `high`, `concurrency`

**Title**: Atomic operation needed for _running flag to prevent race condition

**Description**:
The `_running` flag check is not atomic, allowing multiple hotkey presses to bypass the protection.

**Problem**:
- Location: `lib/API.ahk:349-356`
- Race condition window between check and set
- Multiple rapid hotkey presses could trigger duplicate API calls

**Current Code**:
```ahk
if (_running) {
    ToolTip("Request already in progress...")
    return
}
_running := true
```

**Scenario**:
1. User presses hotkey at time T
2. Check passes: `_running` is false
3. User presses hotkey again at time T+1ms (before `_running := true` executes)
4. Check passes again: `_running` is still false
5. Both requests proceed → duplicate API calls

**Impact**:
- Wasted API tokens and money
- Confusing behavior (two responses)
- Potential clipboard corruption

**Proposed Solutions**:

**Option 1** (Recommended - Simple):
```ahk
; Use Critical directive to make operation atomic
Critical
if (_running) {
    Critical "Off"
    ToolTip("Request already in progress...")
    SetTimer(() => ToolTip(), -TOOLTIP_CLEAR_DELAY)
    return
}
_running := true
Critical "Off"
```

**Option 2** (More robust - Using mutex):
```ahk
; At top of file
global _requestMutex := ""

; In PromptHandler
if (_requestMutex != "" && _requestMutex.TryLock(0)) {
    _requestMutex.Unlock()
    ToolTip("Request already in progress...")
    return
}
if (_requestMutex == "") {
    _requestMutex := Mutex()
}
_requestMutex.Lock()
```

**Testing Required**:
- Rapid hotkey pressing
- Multiple hotkeys configured
- Stress testing with auto-repeat

---

## Issue 6: [MEDIUM] No Retry Logic for 5xx HTTP Errors

**Labels**: `enhancement`, `medium`, `api`

**Title**: Add retry logic for transient HTTP 5xx server errors

**Description**:
The API client retries on network failures (status 0) but not on HTTP 5xx errors, which are often transient.

**Problem**:
- Location: `lib/API.ahk:130-155`
- HTTP 500, 502, 503, 504 errors are not retried
- These are typically transient server issues

**Current Code**:
```ahk
if (req.status == 0) {
    ; retry logic
} else if (req.status == 200) {
    ; success
} else {
    ; HTTP error - don't retry
    MsgBox "Error: Status " req.status...
    return
}
```

**Why This Matters**:
- 502 Bad Gateway: Temporary proxy/gateway issue
- 503 Service Unavailable: Server overload (common with OpenAI)
- 504 Gateway Timeout: Upstream timeout
- 500 Internal Server Error: Sometimes transient

**Proposed Fix**:
```ahk
; Define retryable status codes
retryableErrors := [500, 502, 503, 504]

if (req.status == 0 || retryableErrors.IndexOf(req.status) > 0) {
    ; Network failure or retryable server error
    lastStatus := req.status
    lastError := req.status == 0
        ? "Unable to connect to the API"
        : "Server error (HTTP " req.status ")"

    if (attempt < maxRetries) {
        retryDelay := retryDelays[attempt + 1]
        ToolTip("Error: " lastError ". Retrying in " (retryDelay / 1000) " seconds... (Attempt " (attempt + 2) "/" (maxRetries + 1) ")")
        Sleep retryDelay
        ToolTip()
        attempt++
        req := ""
        continue
    }
} else if (req.status == 200) {
    ; Success
    ...
} else {
    ; Non-retryable error (4xx client errors)
    MsgBox "Error: Status " req.status " - " req.responseText, , 16
    req := ""
    return
}
```

**Testing Considerations**:
- Test with OpenAI rate limiting (429 status)
- Should 429 be retried? (Separate issue to consider)
- Verify exponential backoff still works correctly

---

## Issue 7: [MEDIUM] Hardcoded GitHub URLs

**Labels**: `maintenance`, `medium`, `refactoring`

**Title**: Move hardcoded repository URLs to constants

**Description**:
Repository URLs are hardcoded in multiple locations, making the code harder to maintain and fork.

**Problem**:
- `lib/UI.ahk:116`: GitHub README URL
- `.github/workflows/build-release.yml:19,23`: AutoHotkey download URLs

**Current Code**:
```ahk
; lib/UI.ahk
OpenGithub(*) {
    Run "https://github.com/ecornell/ai-tools-ahk#usage"
}
```

**Impact on Forks**:
- Forks need to manually find and update URLs
- Easy to miss references
- Build pipeline could download wrong versions

**Proposed Fix**:

In `AI-Tools.ahk` (add to constants section):
```ahk
;## Repository Constants
REPO_OWNER := "ecornell"
REPO_NAME := "ai-tools-ahk"
REPO_URL := "https://github.com/" . REPO_OWNER . "/" . REPO_NAME
REPO_USAGE_URL := REPO_URL . "#usage"
```

In `lib/UI.ahk`:
```ahk
OpenGithub(*) {
    Run REPO_USAGE_URL
}
```

**Also Consider**:
- Move AutoHotkey version numbers to constants
- Document which values should be updated for forks
- Add CONTRIBUTING.md with forking instructions

---

## Issue 8: [MEDIUM] Missing Validation for Penalty Parameters

**Labels**: `bug`, `medium`, `validation`

**Title**: Add validation for frequency_penalty and presence_penalty parameters

**Description**:
The `frequency_penalty` and `presence_penalty` parameters lack validation, unlike other numeric parameters.

**Problem**:
- Location: `lib/API.ahk:66-68`
- No range validation for penalty parameters
- According to OpenAI docs, valid range is -2.0 to 2.0

**Current Code**:
```ahk
; These are validated:
if (!IsNumber(max_tokens) or max_tokens <= 0) {
    max_tokens := DEFAULT_MAX_TOKENS
}
if (!IsNumber(temperature) or temperature < 0 or temperature > 2) {
    temperature := DEFAULT_TEMPERATURE
}
if (!IsNumber(top_p) or top_p < 0 or top_p > 1) {
    top_p := DEFAULT_TOP_P
}

; These are NOT validated:
body["frequency_penalty"] := frequency_penalty
body["presence_penalty"] := presence_penalty
```

**Proposed Fix**:
```ahk
; Add default constants
DEFAULT_FREQUENCY_PENALTY := 0.0
DEFAULT_PRESENCE_PENALTY := 0.0

; Add validation
if (!IsNumber(frequency_penalty) or frequency_penalty < -2.0 or frequency_penalty > 2.0) {
    frequency_penalty := DEFAULT_FREQUENCY_PENALTY
}
if (!IsNumber(presence_penalty) or presence_penalty < -2.0 or presence_penalty > 2.0) {
    presence_penalty := DEFAULT_PRESENCE_PENALTY
}
```

**API Documentation**:
- OpenAI API accepts values from -2.0 to 2.0
- Values outside this range cause API errors
- Default should be 0.0 (no penalty)

---

## Issue 9: [MEDIUM] Clipboard Operation Race Condition

**Labels**: `bug`, `medium`, `clipboard`

**Title**: Fix clipboard race condition in text selection logic

**Description**:
If the first clipboard operation fails, the code sends Ctrl+A but doesn't re-copy the text.

**Problem**:
- Location: `lib/Selection.ahk:95-103`
- First copy attempt with short wait
- If it fails, selects all text but doesn't retry copy
- User ends up with all text selected but not captured

**Current Code**:
```ahk
Sleep SLEEP_AFTER_SELECTION
A_Clipboard := ""
Send "^c"
ClipWait(CLIPBOARD_WAIT_SHORT, 0)
text := A_Clipboard

if StrLen(text) < MIN_TEXT_LENGTH {
    Send "^a"
}
Sleep SLEEP_AFTER_CLIPBOARD
```

**Problem Scenario**:
1. Smart selection captures 0 characters (empty line)
2. Code sends Ctrl+A to select all text
3. But... never copies again!
4. Later `GetTextFromClip()` calls another Ctrl+C
5. Race condition: might not wait long enough

**Proposed Fix**:
```ahk
Sleep SLEEP_AFTER_SELECTION
A_Clipboard := ""
Send "^c"
ClipWait(CLIPBOARD_WAIT_SHORT, 0)
text := A_Clipboard

; If selection failed, try selecting all and copy again
if StrLen(text) < MIN_TEXT_LENGTH {
    A_Clipboard := ""
    Send "^a"
    Sleep SLEEP_AFTER_SELECTION
    Send "^c"
    ClipWait(CLIPBOARD_WAIT_SHORT, 0)
    text := A_Clipboard
}
Sleep SLEEP_AFTER_CLIPBOARD
```

**Alternative Fix** (More robust):
```ahk
; Try smart selection first
maxAttempts := 2
text := ""

Loop maxAttempts {
    A_Clipboard := ""

    ; First attempt: smart selection; second: select all
    if (A_Index == 1) {
        Sleep SLEEP_AFTER_SELECTION
    } else {
        Send "^a"
        Sleep SLEEP_AFTER_SELECTION
    }

    Send "^c"
    if ClipWait(CLIPBOARD_WAIT_SHORT, 0) {
        text := A_Clipboard
        if StrLen(text) >= MIN_TEXT_LENGTH {
            break
        }
    }
}

Sleep SLEEP_AFTER_CLIPBOARD
```

---

## Issue 10: [LOW] Inconsistent Error Message Constants

**Labels**: `refactoring`, `low`, `code-quality`

**Title**: Use MSGBOX_ERROR constant consistently throughout codebase

**Description**:
Error messages inconsistently use the `MSGBOX_ERROR` constant vs hardcoded "16".

**Problem**:
- Some places use `MSGBOX_ERROR` constant (AI-Tools.ahk:109)
- Others use hardcoded `16` (API.ahk:152, 182)
- Inconsistent code style

**Examples**:

Using constant (good):
```ahk
; AI-Tools.ahk:109
MsgBox("Error setting hotkey_1...", , MSGBOX_ERROR)
```

Using hardcoded value (bad):
```ahk
; lib/API.ahk:152
MsgBox "Error: Status " req.status..., , 16

; lib/API.ahk:182
MsgBox "Error: Unable to connect...", , 16
```

**Fix Required**:
Replace all instances of `, 16` with `, MSGBOX_ERROR`

**Search Pattern**:
```
MsgBox.*,\s*16
```

**Files to Update**:
- `lib/API.ahk` (multiple instances)

**Why This Matters**:
- Maintainability: Magic numbers are harder to understand
- Consistency: Rest of codebase uses constant
- Future-proofing: If error style changes, only update constant

---

## Issue 11: [LOW] Missing Function Documentation

**Labels**: `documentation`, `low`, `enhancement`

**Title**: Add inline documentation for complex functions

**Description**:
Complex functions like `HandleResponse` and `SelectText` lack detailed inline documentation.

**Problem**:
- Makes onboarding new contributors harder
- Function purposes not immediately clear
- Parameter meanings undocumented

**Functions Needing Documentation**:

1. `HandleResponse()` (lib/API.ahk:193-341)
   - 148 lines, complex logic
   - Multiple code paths
   - Clipboard manipulation
   - GUI creation

2. `SelectText()` (lib/Selection.ahk:8-111)
   - 103 lines, intricate logic
   - Multiple selection strategies
   - Process/class/title mapping

3. `CallAPI()` (lib/API.ahk:74-191)
   - 117 lines
   - Retry logic
   - Multiple exit points

**Proposed Format**:
```ahk
;# Handle API response and display result
;#
;# Parses the API response JSON, extracts the generated text, and either
;# displays it in a popup window or pastes it back into the active window.
;#
;# @param data (String) - Raw JSON response from API
;# @param mode (String) - Mode name from settings (e.g., "mode_chat_completion")
;# @param promptName (String) - Prompt name from settings (e.g., "prompt_spelling")
;# @param input (String) - Original user input text
;#
;# @global _running - Set to false when complete
;# @global _oldClipboard - Restored after operation
;# @global _activeWin - Window to activate for paste
;# @global _displayResponse - Whether to show popup vs paste
;#
;# @throws Error if JSON parsing fails
;# @throws Error if response structure is invalid
;#
HandleResponse(data, mode, promptName, input) {
    ...
}
```

---

## Issue 12: [LOW] Add Automated Testing

**Labels**: `testing`, `low`, `enhancement`

**Title**: Implement automated tests for core functionality

**Description**:
The project has no automated tests, making it difficult to verify changes don't break existing features.

**Current State**:
- No unit tests
- No integration tests
- Manual testing only
- Risky refactoring

**Proposed Test Coverage**:

1. **Unit Tests** (lib/Config.ahk):
   - GetSetting() with various inputs
   - Cache behavior
   - UnescapeSetting() string handling
   - LoadSelectionMapping() parsing

2. **Unit Tests** (lib/API.ahk):
   - GetBody() parameter validation
   - GetBodyParams() with overrides
   - IsValidSetting() edge cases

3. **Integration Tests**:
   - Mock API responses
   - Test retry logic
   - Test clipboard operations (challenging)

4. **End-to-End Tests**:
   - Hotkey registration
   - Full workflow with mock API

**Challenges**:
- AutoHotkey v2 testing frameworks are limited
- GUI testing is complex
- Clipboard testing requires special handling
- COM object mocking is difficult

**Recommendations**:
1. Start with pure functions (GetBody, GetSetting)
2. Use AutoHotkey's Unit Testing framework
3. Mock file system operations
4. Document manual test procedures for UI/clipboard

**Resources**:
- https://github.com/Keysharp/AutoHotkey-Unit-Testing
- Consider creating manual test checklist as interim solution

---

## Issue 13: [LOW] Update GitHub Actions to Latest Versions

**Labels**: `dependencies`, `low`, `ci-cd`

**Title**: Update GitHub Actions checkout to v4

**Description**:
The build workflow uses outdated GitHub Actions that could benefit from updates.

**Current**:
```yaml
# .github/workflows/build-release.yml:12
uses: actions/checkout@v3
```

**Recommended**:
```yaml
uses: actions/checkout@v4
```

**Benefits of v4**:
- Better performance
- Improved security
- Bug fixes
- Better Git operations

**Also Consider Updating**:
```yaml
# Current
uses: softprops/action-gh-release@v1

# Check for latest version
uses: softprops/action-gh-release@v2  # if available
```

**Testing Required**:
- Verify build still succeeds
- Check release artifacts are created correctly
- Ensure AutoHotkey downloads still work

---

## Summary Table

| # | Priority | Title | Status |
|---|----------|-------|--------|
| 1 | CRITICAL | Incorrect Model Name | 🔴 Open |
| 2 | CRITICAL | API Key Plaintext Storage | 🔴 Open |
| 3 | HIGH | Typo in Configuration | ✅ Fixed |
| 4 | HIGH | Missing Input Validation | 🔴 Open |
| 5 | HIGH | Race Condition | 🔴 Open |
| 6 | MEDIUM | No 5xx Retry Logic | 🔴 Open |
| 7 | MEDIUM | Hardcoded URLs | 🔴 Open |
| 8 | MEDIUM | Missing Penalty Validation | 🔴 Open |
| 9 | MEDIUM | Clipboard Race Condition | 🔴 Open |
| 10 | LOW | Inconsistent Constants | 🔴 Open |
| 11 | LOW | Missing Documentation | 🔴 Open |
| 12 | LOW | No Automated Tests | 🔴 Open |
| 13 | LOW | Outdated GitHub Actions | 🔴 Open |

**Total**: 13 issues (1 fixed, 12 to create)
