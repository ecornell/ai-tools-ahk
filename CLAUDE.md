# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Windows AutoHotkey v2 tool enabling custom AI prompts on text in any window using global hotkeys. It's a modular application that provides "spicy autocomplete" functionality anywhere in Windows by integrating with OpenAI, Azure OpenAI, and Google Gemini APIs.

## Running & Testing

**Requirements**: AutoHotkey v2.0+ or use the packaged `.exe` version (portable, no installation required).

**Run the script**:
```
AI-Tools.ahk
```

**First-run behavior**: Creates `settings.ini` from `settings.ini.default` and prompts for an API key.

**Debug mode**: Enable `debug = true` in `settings.ini` to write logs to `./debug.log` via `LogDebug()`.

**Reload settings**: Enable `reload_on_change = true` in settings.ini, or use the tray menu "Reload settings" option.

**No automated tests**: Changes affecting network shape, timeouts, or clipboard behavior require manual validation on Windows (COM/ActiveX dependencies).

## Architecture

### Modular Structure

The codebase follows a clean separation of concerns:

**Entry point**: [AI-Tools.ahk](AI-Tools.ahk) (143 lines)
- Initialization, constants, and hotkey registration
- Includes all lib modules and helper libraries

**Core modules** (in [lib/](lib/)):
- [Config.ahk](lib/Config.ahk) - Settings management (`GetSetting`, `LoadSelectionMapping`, caching)
- [Selection.ahk](lib/Selection.ahk) - Text selection with process/class/title mappings
- [API.ahk](lib/API.ahk) - Multi-provider API client (OpenAI, Azure, Gemini)
- [UI.ahk](lib/UI.ahk) - Menus, GUI, tray interface
- [Utils.ahk](lib/Utils.ahk) - Logging, tooltips, helpers

**Helper libraries** (in [lib/](lib/)):
- `_jxon.ahk` - JSON parsing (`Jxon_dump`, `Jxon_Load`)
- `_Cursor.ahk` - System cursor management
- `_MD2HTML.ahk` - Markdown to HTML rendering

### Request Flow

The typical execution path:

1. **Hotkey triggered** → `SelectText()` ([lib/Selection.ahk](lib/Selection.ahk))
2. **Selection logic** → Uses process/class/title mappings from `settings.ini` sections (`selection_process`, `selection_class`, `selection_title`) to determine the correct key sequence for selecting text in the active window
3. **Text extraction** → `GetTextFromClip()` validates length (MIN_TEXT_LENGTH to MAX_TEXT_LENGTH)
4. **Prompt handling** → `PromptHandler()` ([lib/API.ahk](lib/API.ahk)) validates mode and prompt configuration
5. **API request** → `CallAPI()` detects provider via endpoint, builds request body using `GetBody()` or `GetBodyGemini()`
6. **Network call** → `Msxml2.ServerXMLHTTP` with retry logic (4 retries, exponential backoff)
7. **Response parsing** → `HandleResponse()` extracts text from provider-specific JSON structure
8. **Output** → Either pastes result (`^v`) or displays in ActiveX GUI using `Shell.Explorer`

### Multi-Provider Support

**Provider detection**: Automatic based on endpoint URL ([lib/API.ahk:8-18](lib/API.ahk#L8-L18))
- Gemini: `generativelanguage.googleapis.com`
- Azure: `openai.azure.com`
- OpenAI: default

**Request body differences**:
- OpenAI/Azure: `messages[]` array with `role` and `content` ([lib/API.ahk:39-85](lib/API.ahk#L39-L85))
- Gemini: `contents[].parts[].text` structure with `generationConfig` ([lib/API.ahk:88-158](lib/API.ahk#L88-L158))

**Response parsing differences**:
- OpenAI/Azure: `choices[0].message.content` ([lib/API.ahk:356-378](lib/API.ahk#L356-L378))
- Gemini: `candidates[0].content.parts[0].text` ([lib/API.ahk:322-354](lib/API.ahk#L322-L354))

**Authentication**:
- Gemini: `x-goog-api-key` header
- OpenAI: `Authorization: Bearer` header
- Azure: Both `Authorization: Bearer` and `api-key` headers

### Configuration System

**Settings cache**: `_settingsCache` Map in [lib/Config.ahk](lib/Config.ahk) - all `GetSetting()` calls are cached and automatically normalize types (numbers vs strings).

**Prompt structure** (in `settings.ini`):
- `prompt` - Main prompt text
- `prompt_end` - Appended after user text
- `prompt_system` - System message (OpenAI) or merged into content (Gemini)
- `menu_text` - Display name in popup menu
- `response_type` - "popup" for GUI, otherwise paste
- `replace_selected` - "false" to append, true to replace
- `mode` - Overrides `default_mode` per-prompt
- Model parameters: `model`, `max_tokens`, `temperature`, `top_p`, etc.

**Selection mappings**: Three INI sections define how to select text in different applications:
- `[selection_process]` - Process name → key sequence (case-insensitive)
- `[selection_class]` - Window class → key sequence
- `[selection_title]` - Title substring → key sequence (case-insensitive)
- Fallback: `{End}+{Home}` if no match, then `^a` if clipboard empty

## Implementation Patterns

### Must Follow

**Timing constants**: Use defined constants ([AI-Tools.ahk:24-50](AI-Tools.ahk#L24-L50)) instead of hard-coded sleeps:
- `SLEEP_AFTER_SELECTION`, `CLIPBOARD_WAIT_SHORT`, `SLEEP_BEFORE_RESTORE`, etc.

**Clipboard preservation**: Always save/restore `_oldClipboard` ([lib/Selection.ahk:10-12](lib/Selection.ahk#L10-L12), [lib/API.ahk:480-485](lib/API.ahk#L480-L485))
- Pattern: Save before selection, restore after response handling
- Critical for user experience - data loss risk if not followed

**Settings access**: Use `GetSetting(section, key, default)` ([lib/Config.ahk:20-42](lib/Config.ahk#L20-L42))
- Never read INI directly except in `LoadSelectionMapping()`
- Caching prevents repeated file I/O

**Prompt key conventions**: Follow existing schema for all prompt sections:
- Required: `prompt`, `menu_text`
- Optional: `prompt_end`, `prompt_system`, `response_type`, `replace_selected`, `mode`, model params

**JSON handling**: Use `_jxon.ahk` functions for all JSON operations:
- `Jxon_dump(obj, indent)` for serialization
- `Jxon_Load(&json)` for parsing

### Don't Change Without Approval

**Global hotkey defaults**: Affects user workflows and muscle memory

**API headers/endpoints**: Can break OpenAI/Azure/Gemini integration
- Both `Authorization` and `api-key` headers required for Azure compatibility
- Gemini endpoint must contain `{model}` placeholder

**Clipboard logic**: High risk for user data loss
- Always restore clipboard in `finally` blocks
- Handle failures gracefully with try/catch

**Selection mapping semantics**: Users rely on process/class/title matching behavior

**ActiveX rendering**: IE-based `Shell.Explorer` has limitations
- Conservative changes only
- Always provide clipboard fallback when HTML rendering fails

## Supported APIs

**OpenAI**: `https://api.openai.com/v1/chat/completions` - Models: gpt-4, gpt-4-turbo, gpt-3.5-turbo

**Azure OpenAI**: `https://[resource].openai.azure.com/openai/deployments/[model]/chat/completions`

**Google Gemini**: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
- Models: gemini-2.5-flash, gemini-1.5-pro, gemini-1.5-flash
- Optional `thinking_budget` parameter enables extended reasoning mode

**Configuration**: Edit `default_mode` in `settings.ini`:
- `mode_chat_completion` (OpenAI)
- `mode_chat_completion_azure` (Azure)
- `mode_gemini` (Google Gemini)

Individual prompts can override via `mode=mode_name` in their section.

## Compatibility

Tested on Windows 10 Pro 22H2 and Windows 11 Pro 25H2. Requires Windows COM/ActiveX support.
