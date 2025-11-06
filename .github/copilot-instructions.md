## AI Coding Instructions for ai-tools-ahk

Purpose: quick orientation for an automated coding agent (or reviewer) to be productive in this Windows AutoHotkey v2 project.

This repository is a modular AutoHotkey application with clean separation of concerns. Key facts below let an AI agent make safe, useful changes quickly.

Entry points
- `AI-Tools.ahk` — the main entry point (143 lines). Handles initialization, constants, and hotkey registration.
- `lib/` directory — modular application code:
  - `Config.ahk` — Settings management (GetSetting, LoadSelectionMapping, CheckSettings)
  - `Selection.ahk` — Text selection logic (SelectText, GetTextFromClip)
  - `API.ahk` — OpenAI/Azure API client (PromptHandler, CallAPI, GetBody, HandleResponse)
  - `UI.ahk` — User interface (menus, GUI, tray)
  - `Utils.ahk` — Utility functions (logging, tooltips, helpers)
- `_jxon.ahk`, `_Cursor.ahk`, `_MD2HTML.ahk` — external helper libraries (JSON, cursor management, markdown→HTML rendering).
- `settings.ini` / `settings.ini.default` — runtime configuration. `settings.ini.default` seeds new installs and documents prompt schemas.

Big-picture architecture
- Modular design with clear separation of concerns across lib/ files.
- Main script (`AI-Tools.ahk`) includes all modules and sets up hotkeys.
- Typical flow: hotkey → `SelectText()` (lib/Selection.ahk - process/class/title mappings) → `GetTextFromClip()` → `PromptHandler()` → `CallAPI()` (lib/API.ahk - via `GetBody()`/`GetBodyParams()`) → network using `Msxml2.ServerXMLHTTP` → `HandleResponse()` (paste or GUI ActiveX render).
- Selection mappings: `selection_process`, `selection_class`, `selection_title` are parsed by `LoadSelectionMapping()` (lib/Config.ahk) and may contain send-keys sequences (e.g. editors needing specific selection keys).

Implementation notes & conventions (do this when editing)
- Use `GetSetting(section,key,default)` for INI reads (it caches results in `_settingsCache` and normalizes types).
- Follow prompt key conventions: `prompt`, `prompt_end`, `prompt_system`, `menu_text`, `response_type`, `replace_selected`. `GetBody()` and `HandleResponse()` show how they are consumed.
- Keep API payloads within `MAX_TEXT_LENGTH`. JSON helper functions are in `_jxon.ahk` (`Jxon_dump`, `Jxon_Load`).
- Networking uses `Msxml2.ServerXMLHTTP`. The code sets both `Authorization: Bearer <key>` and `api-key: <key>` to support OpenAI and Azure endpoints configured per-mode in `settings.ini`.
- Response parsing expects the Chat Completions shape and uses `choices[1].message.content`. HandleResponse defensively checks for these fields.

Developer workflows (manual)
- Run: install AutoHotkey v2 and run `AI-Tools.ahk` (or use packaged `.exe`).
- First run creates `settings.ini` from `settings.ini.default` and prompts for an API key.
- Debug: enable `settings.debug` to write into `./debug.log` via `LogDebug()`.
- Reloading settings: enable `reload_on_change` or use the tray menu `Reload settings`.

Patterns to respect
- Use existing timing constants (`SLEEP_AFTER_SELECTION`, `CLIPBOARD_WAIT_SHORT`, `SLEEP_BEFORE_RESTORE`, etc.) rather than hard-coded sleeps.
- Preserve and restore the clipboard via `_oldClipboard` (pattern in `SelectText()` / `HandleResponse()`); failing to do so is disruptive to users.
- ActiveX GUI: responses render via an IE-based `Shell.Explorer` ActiveX instance. Keep changes conservative and provide a clipboard fallback when HTML rendering might fail.

Integration points & limitations
- The script depends on Windows COM/ActiveX — tests and manual debugging must be performed on Windows.
- There are no automated tests in the repo; changes that affect network shape, timeouts, or clipboard behavior should be validated manually.

Files to inspect for examples
- `AI-Tools.ahk` — main entry point: initialization, constants, hotkey registration.
- `lib/Config.ahk` — settings management and INI parsing.
- `lib/Selection.ahk` — text selection logic with process/class/title mappings.
- `lib/API.ahk` — API client implementation, request/response handling.
- `lib/UI.ahk` — menu and GUI management.
- `lib/Utils.ahk` — logging, tooltips, and helper utilities.
- `settings.ini.default` — canonical example of prompt/mode configuration.
- `_jxon.ahk` — JSON helpers used for request/response handling.
- `style.css` — CSS used by the response HTML renderer.

Don't change without sign-off
- Global hotkey defaults and selection mapping semantics (affects user workflows).
- API headers, endpoint formatting and timeout semantics (can break OpenAI/Azure integration).
- Clipboard handling and restore logic (high-risk for user data loss).

# End of AI Coding Instructions