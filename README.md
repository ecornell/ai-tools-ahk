# AI-Tools-AHK

<!-- <a href="url"><img src="http://i.imgur.com/xlONmxY.gif"></a><br></br> -->

### Table of Contents

- [What's this?](#whats-this)  
- [Installation](#installation)  
- [Usage](#usage)  
- [Options](#options)  
- [Credits](#credits)  
&nbsp;

## What's this?  

A Windows tool that allows custom OpenAI prompts to be run on text in any window via global hotkeys.

**Where can it be used?**  

Almost anywhere in windows where you can enter text. Any text editor, search box or command line... even the text edit box that you use to rename files.  
&nbsp;  


## Installation  

Download and extract the [latest release](https://github.com/ecornell/ai-tools-ahk/releases) .zip file. If you already have [AutoHotkey](https://www.autohotkey.com) installed then run `AI-Tools.ahk`, otherwise run the `.exe` version which lets you use the script without having AutoHotkey installed. The script doesn't install anything and it's also portable so it can be run from any location.  

On first run, the script will copy the included `setting.ini.default` file to a new `settings.ini` file in the same directory. This file contains the settings for the script. You can edit this file to change the hotkeys or to add your own prompts.

It will also prompt you to enter your OpenAI API key. You can get a API key from [OpenAI](https://platform.openai.com/).


## Usage

`Ctrl+Shift+j` - Run the "Fix Spelling" prompt and replaces the current line or paragraph of text with the corrected version.

`Ctrl+Shift+k` - Run the "Continuation" prompt and append it to the text on the current line.

`Ctrl+Alt+Shift+k` - Open prompt menu to select the prompt to run on the selected text.

### How does it work?



## Options

`settings.ini` contains the settings for the script. You can edit this file to change the hotkeys or to add your own prompts. 


**Start with windows**  

To have the script start when windows boots up, select "Start With Windows" from the tray icon.  
&nbsp;


## Supported APIs
OpenAI 

    /v1/chat/completions (Default)
    /v1/completions  
    /v1/edits

Azure 

    /openai/deployments/***/completions


## Credits

TheArkive (JXON_ahk2) and the AHK community.