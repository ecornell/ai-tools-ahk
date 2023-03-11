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

On first run, the script will create a `settings.ini` file in the same directory. This file contains the settings for the script. You can edit this file to change the hotkeys or to add your own prompts.

It will also prompt you to enter your OpenAI API key. You can get a API key from [OpenAI](https://platform.openai.com/).


## Usage

`Ctrl+Shift+j` - Run the quick action 1 (Correct Spelling and Grammar) prompt on the selected text.

`Ctrl+Shift+k` - Run the quick action 2 (Continuation) prompt on the selected text.

`Ctrl+Alt+Shift+k` - Open prompt menu to select the prompt to run on the selected text.

### How does it work?

## Supporting APIs
OpenAI - /v1/chat/completions (Default)
       - /v1/completions  
       - /v1/edits
Azure - /openai/deployments/***/completions



## Options

*(Any time you make any changes to the `settings.ini` file you will need to select "Reload This Script" from the tray icon to update the script with the new settings)*   


**Start with windows**  

To have the script start when windows boots up, select "Start With Windows" from the tray icon.  
&nbsp;


## Credits

Laszlo, Oldman and many others from the AHK community.