#Requires AutoHotkey v2.0
; ================================================
; https://github.com/TheArkive/M-ArkDown_ahk2
;
; Example Script - this just asks for a file and
; uses make_html() to convert the M-ArkDown into html.
;
; MIT License
; Copyright (c) 2021 TheArkive
;
; Permission is hereby granted, free of charge, to any person obtaining a 
; copy of this software and associated documentation files (the "Software"),
; to deal in the Software without restriction, including without limitation
; the rights to use, copy, modify, merge, publish, distribute, sublicense, 
; and/or sell copies of the Software, and to permit persons to whom the 
; Software is furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be included 
;  in all copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS 
; OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
; THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
; FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
; IN THE SOFTWARE.
; ================================================

; file_path := FileSelect("1",A_ScriptDir '\index.md',"Select markdown file:","Markdown (*.md)")
; If !file_path
    ; ExitApp

; SplitPath file_path,,&dir,,&file_title

; If FileExist(dir "\" file_title ".html")
    ; FileDelete dir "\" file_title ".html"

; md_txt := FileRead(file_path)

; css := FileRead("style.css")

; options := {css:css
          ; , font_name:"Segoe UI"
          ; , font_size:16
          ; , font_weight:400
          ; , line_height:"1.6"} ; 1.6em - put decimals in "" for easier accuracy/handling.

; html := make_html(md_txt, options, true) ; true/false = use some github elements

; FileAppend html, dir "\" file_title ".html", "UTF-8"

; Run dir "\" file_title ".html" ; open and test

; dbg(_in) { ; AHK v2
    ; Loop Parse _in, "`n", "`r"
        ; OutputDebug "AHK: " A_LoopField
; }

; ================================================
; make_html(_in_html, options_obj:="", github:=false)
;
;   Ignore the last 2 params.  Those are used internally.
;
;   See above for constructing the options_obj.
;
;   The "github" param is a work in progress, and tries to enforce some of the expected basics
;   that are circumvented with my "flavor" of markdown.
;
;       Current effects when [ github := true ]:
;           * H1 and H2 always have underline (the [underline] tag still takes effect when specified)
;           * the '=' is not usable for making an <hr>, but --- *** and ___ still make <hr>
;
; ================================================

make_html(_in_text, options:="", github:=false, final:=true, md_type:="") {
    
    If !RegExMatch(_in_text,"[`r`n]+$") && (final) && md_type!="header" { ; add trailing CRLF if doesn't exist
        _in_text .= "`r`n"
    }
    
    html1 := "<html><head><style>`r`n"
    html2 := "`r`n</style></head>`r`n`r`n<body>"
    toc_html1 := '<div id="toc-container">'
               . '<div id="toc-icon" align="right">&#9776;</div>' ; hamburger (3 horizontal lines) icon
               . '<div id="toc-contents">'
    toc_html2 := "</div></div>" ; end toc-container and toc-contents
    html3 := '<div id="body-container"><div id="main">`r`n' ; <div id=" q "body-container" q ">
    html4 := "</div></div></body></html>" ; </div>
    
    body := ""
    toc := [], do_toc := false
    do_nav := false, nav_arr := []
    ref := Map(), ref.CaseSense := false
    foot := Map(), ref.CaseSense := false
    
    link_ico := "•" ; 🔗 •
    
    Static chk_id := 0 ; increments throughout entire document
    
    If (final)
        css := options.css
    
    a := StrSplit(_in_text,"`n","`r")
    i := 0
    
    ref_link_rgx := '^\x5B(\^)?([\w ]+)\x5D:([^"]+)(?:"([^"]+)")?'
    in_code := false, code_tag := ""
    
    While (i < a.Length) { ; parse for ref-style links and footnotes first
        i++, line := strip_comment(a[i])
        
        If !in_code && RegExMatch(line,"^(``{3,4})$",&c)
            in_code := true, code_tag := c[1] ; , msgbox("IN CODE`n`n" line "`n" a[i+1] "`n" a[i+2] "`n" a[i+3])
        
        Else If in_code && RegExMatch(line,"^(``{3,4})",&c) && c[1]=code_tag
            in_code := false, code_tag := ""
        
        If !in_code && RegExMatch(line,ref_link_rgx,&m) {
            If m[1]
                foot[m[2]] := {link:m[3],title:m[4]}    ; foot notes
            Else
                ref[m[2]] := {link:m[3],title:m[4]}     ; reference-style links / images
        }
    }
    
    i := 0
    While (i < a.Length) { ; ( ) \x28 \x29 ; [ ] \x5B \x5D ; { } \x7B \x7D
        
        i++, line := strip_comment(a[i])
        ul := "", ul2 := ""
        ol := "", ol2 := "", ol_type := ""
        
        If RegExMatch(line,ref_link_rgx) ; skip ref-style links and footnotes
            Continue
        
        If RegExMatch(line,"^<nav")
            Continue
        
        If (final && line = "<toc>") {
            do_toc := True
            Continue
        }
        
        While RegExMatch(line,"\\$") { ; concat lines ending in '\'
            If !line_inc(line := SubStr(line,1,-1) '<br>')
                Break
        }
        
        While (i < a.Length && RegExMatch(line,"\\$")) ; concatenate lines ending in `\` with next line
            line := SubStr(line,1,-1) '<br>' strip_comment(a[++i])
        
        If final && RegExMatch(line, "^<nav\|") && a.Has(i+1) && (a[i+1] = "") {
            do_nav := True
            nav_arr := StrSplit(Trim(line,"<>"),"|")
            nav_arr.RemoveAt(1)
            Continue
        }
        
        code_block := "" ; code block
        If (line = "``````") || (line = "````````") {
            match := line
            If !line_inc()
                Break
            
            While (line != match) {
                code_block .= (code_block?"`r`n":"") line
                If !line_inc()
                    Break
            }
            
            body .= (body?"`r`n":"") "<pre><code>" convert(code_block) "</code></pre>"
            Continue
        }
        
        ; header h1 - h6
        If RegExMatch(line, "^(#+) (.+?)(?:\x5B[ \t]*(\w+)[ \t]*\x5D)?$", &n) {
            depth := StrLen(n[1]), title := inline_code(Trim(n[2]," `t"))
            _class := (depth <= 2 || n[3]="underline") ? "underline" : ""
            
            id := RegExReplace(RegExReplace(StrLower(title),"[\[\]\{\}\(\)\@\!]",""),"[ \.]","-")
            opener := "<h" depth (id?' id="' id '" ':'') (_class?' class="' _class '"':'') '>'
            
            body .= (body?"`r`n":"") opener title
                  . '<a href="#' id '"><span class="link">' link_ico '</span></a>'
                  . '</h' depth '>'
            
            toc.Push([depth, title, id])
            Continue
        }
        
        ; alt header h1 and h2
        ; ------ or ======= as underline in next_line
        next_line := a.Has(i+1) ? strip_comment(a[i+1]) : ""
        If next_line && line && RegExMatch(next_line,"^(\-+|=+)$") {
            depth := (SubStr(next_line,1,1) = "=") ? 1 : 2
            
            id := RegExReplace(RegExReplace(StrLower(line),"[\[\]\{\}\(\)\@\!<>\|]",""),"[ \.]","-")
            opener := "<h" depth ' id="' id '" class="underline">'
                    
            body .= (body?"`r`n":"") opener inline_code(line)
                  . '<a href="#' id '"><span class="link">' link_ico '</span></a>'
                  . '</h' depth '>'
            
            toc.Push([depth, line, id]), i++ ; increase line count to skip the ---- or ==== form next_line
            Continue
        }
        
        ; check list
        If RegExMatch(line,"^\- \x5B([ xX])\x5D (.+)",&n) {
            body .= (body?"`r`n":"") '<ul class="checklist">'
            While RegExMatch(line,"^\- \x5B([ xX])\x5D (.+)",&n) {
                chk := (n[1]="x") ? 'checked=""' : ''
                body .= '`r`n<li><input type="checkbox" id="check' chk_id '" disabled="" ' chk '>'
                               . '<label for="check' chk_id '">  ' n[2] '</label></li>'
                chk_id++
                If !line_inc()
                    Break
            }
            body .= '</ul>'
            Continue
        }
        
        ; spoiler
        spoiler_text := ""
        If RegExMatch(line, "^<spoiler=([^>]+)>$", &match) {
            disp_text := match[1]
            If !line_inc()
                Break
            
            While !RegExMatch(line, "^</spoiler>$") {
                spoiler_text .= (spoiler_text?"`r`n":"") line
                If !line_inc()
                    throw Error("No closing </spoiler> tag found.",-1)
            }
            
            body .= (body?"`r`n":"") '<p><details><summary class="spoiler">'
                  . disp_text "</summary>" make_html(spoiler_text,,github,false,"spoiler") "</details></p>"
            Continue
        }
        
        ; hr
        if RegExMatch(line, "^(\-{3,}|_{3,}|\*{3,}|={3,})(?:\x5B[ \t]*([^\x5D]+)*[ \t]*\x5D)?$", &match) {
            hr_style := ""
            
            If match[2] {
                For i, style in StrSplit(match[2]," ","`t") {
                    If (SubStr(style, -2) = "px")
                        hr_style .= (hr_style?" ":"") "border-top-width: " style ";"
                    Else If RegExMatch(style, "(dotted|dashed|solid|double|groove|ridge|inset|outset|none|hidden)")
                        hr_style .= (hr_style?" ":"") "border-top-style: " style ";"
                    Else If InStr(style,"opacity")=1
                        hr_style .= (hr_style?" ":"") style ";"
                    Else
                        hr_style .= (hr_style?" ":"") "border-top-color: " style ";"
                }
                
            } Else {
                hr_style := "opacity: 0.25;"
            }
            
            body .= (body?"`r`n":"") '<hr style="' hr_style '">'
            Continue
        }
        
        ; blockquote
        If RegExMatch(line, "^\> *(.*)") {
            blockquote := ""
            While RegExMatch(line, "^\> *(.*)", &match) {
                blockquote .= (blockquote?"`r`n":"") match[1]
                If !line_inc()
                    Break
            }
            
            body .= (body?"`r`n":"") "<blockquote>" make_html(blockquote,,github, false, "blockquote") "</blockquote>"
            Continue
        }
        
        ; table
        If RegExMatch(line, "^\|.*?\|$") {
            table := "", lines := 0
            While RegExMatch(line, "^\|.*?\|$") {
                table .= (table?"`r`n":"") line, lines++
                If !line_inc()
                    Break
            }
            
            If lines < 3
                Continue
            
            If (table) {
                b := [], h := [], body .= (body?"`r`n":"") '<table class="normal">'
                
                Loop Parse table, "`n", "`r"
                {
                    body .= "<tr>"
                    c := StrSplit(A_LoopField,"|"), c.RemoveAt(1), c.RemoveAt(c.Length)
                    
                    If (A_Index = 1) {
                        For i, t in c { ; table headers
                            txt := inline_code(Trim(t," `t")) ; , align := "center"
                            If RegExMatch(txt,"^(:)?(.+?)(:)?$",&n) {
                                align := (n[1]&&n[3]) ? "center" : (n[3]) ? "right" : "left"
                                txt := n[2], h.Push([align,txt])
                            } Else
                                h.Push(["",txt])
                        }
                        
                    } Else If (A_Index = 2) {
                        For i, t in c {
                            align := "left" ; column alignment
                            If RegExMatch(t,"^(:)?\-+(:)?$",&n)
                                align := (n[1]&&n[2]) ? "center" : (n[2]) ? "right" : "left"
                            b.Push(align)
                            body .= '<th align="' (h[i][1]?h[i][1]:'center') '">' h[i][2] '</th>'
                        }
                        
                    } Else {
                        For i, t in c
                            body .= '<td align="' b[i]  '">' Trim(inline_code(t)," `t") '</td>'
                        
                    }
                    body .= "</tr>"
                }
                body .= "</table>"
                Continue
            }
        }
        
        ; ordered and unordered lists
        list_rgx := '^( *)'                     ; leading spaces (no tabs)
                  . '([\*\+\-]|\d+(?:\.|\x29))' ; */+/- or 1. or 1)
                  . '( +)'                      ; at least one more space
                  . '(.+)'                      ; list content
        
        list := []
        While RegExMatch(line,list_rgx,&n) {
            itm := LT_spec(n[2])                ; bullet item ... [ -, *, +, 1., or 1) ]
            tag := LT_tag(n[2])                 ; ol or ul
            pre := n.Len[1]                     ; spaces before bullet item
            lead := pre + n.Len[2] + n.Len[3]   ; # chars before actual list text
            
            txt := n[4]
            While RegExMatch(txt,"\\$") && (i < a.Length) ; append lines ending in '\'
                txt := SubStr(txt,1,-1) '<br>' strip_comment(a[++i])
            
            list.Push({itm:t, tag:tag, pre:pre, lead:lead, txt:txt, line:n[2] ' ' txt})
            
            If !line_inc()
                Break
        }
        
        d := 1 ; depth - for make_list()
        err := false ; checking for poorly formatted ordered lists
        While list.Length { ; add all lists, normally is one, but can be multiple
            body .= '`r`n' make_list(list)
            If err
                Break
            Continue
        }
        
        If list.Length {                ; if no errs in list, then list array should be blank at this point
            body .= '`r`n' AtoT(list)   ; dump remaining plain text
            Continue
        }
        
        ; =======================================================================
        ; ...
        ; =======================================================================
        
        If RegExMatch(md_type,"^(ol|ul)") { ; ordered/unordered lists
            body .= (body?"`r`n":"") inline_code(line)
            Continue
        }
        
        body .= (body?"`r`n":"") "<p>" inline_code(line) "</p>"
    }
    
    ; processing toc ; try to process exact height
    final_toc := "", toc_width := 0, toc_height := 0
    If (Final && do_toc) {
        temp := Gui()
        temp.SetFont("s" options.font_size, options.font_name)
        
        depth := toc[1][1]
        diff := (depth > 1) ? depth - 1 : 0
        indent := "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"
        
        For i, item in toc { ; 1=depth, 2=title, 3=id
            depth := item[1] - diff - 1
            
            ctl := temp.Add("Text",, rpt("     ",depth) "• " item[2])
            ctl.GetPos(,,&w, &h)
            toc_width := (w > toc_width) ? w : toc_width
            toc_height += options.font_size * 2
            
            final_toc .= (final_toc?"`r`n":"") '<a href="#' item[3] '">'
                       . '<div class="toc-item">' (depth?rpt(indent,depth):"")
                       . "• " item[2] "</div></a>"
        }
        
        temp.Destroy()
    }
    
    ; processing navigation menu
    nav_str := ""
    If (final && do_nav) {
        temp := Gui()
        temp.SetFont("s" options.font_size, options.font_name)
        
        Loop nav_arr.Length {
            title := SubStr((txt := nav_arr[A_Index]), 1, (sep := InStr(txt, "=")) - 1)
            
            ctl := temp.Add("Text",,title)
            ctl.GetPos(,,&w)
            toc_width := (w > toc_width) ? w : toc_width
            toc_height += options.font_size * 2
            
            nav_str .= (final_toc?"`r`n":"") '<a href="' SubStr(txt, sep+1) '" target="_blank" rel="noopener noreferrer">'
                       . '<div class="toc-item">' title '</div></a>'
        }
        
        (do_toc) ? nav_str .= "<hr>" : ""
        temp.Destroy()
    }
    
    ; processing TOC
    user_menu := ""
    If Final && (do_nav || do_toc)
        user_menu := toc_html1 nav_str final_toc toc_html2
    
    If final {
        If (do_nav && do_toc)
            toc_height += Round(options.font_size * Float(options.line_height)) ; multiply by body line-height
        
        css := StrReplace(css, "[_toc_width_]",toc_width + 25) ; account for scrollbar width
        css := StrReplace(css, "[_toc_height_]",Round(toc_height))
        css := StrReplace(css, "[_font_name_]", options.font_name)
        css := StrReplace(css, "[_font_size_]", options.font_size)
        css := StrReplace(css, "[_font_weight_]", options.font_weight)
        css := StrReplace(css, "[_line_height_]", Round(options.line_height,1))
        
        If (do_toc || do_nav)
            result := html1 . css . html2 . user_menu . html3 . body . html4
        Else
            result := html1 . css . html2 . html3 . body . html4
    } Else
        result := body
    
    return result
    
    ; =======================================================================
    ; Local Functions
    ; =======================================================================
    
    ; GitHub spec for lists:
    ; https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#lists
    make_list(_L_) { ; o props = {itm, tag, pre, lead, txt}
        _tag := _L_[1].tag, _itm := _L_[1].itm
        _pre := _L_[1].pre, _lead := _L_[1].lead, t := ""
        _txt := inline_code(_L_[1].txt) ; process escapes first line of list to determine optional list style
        
        rgx := '\x5B *(?:type=([1AaIi]|disc|circle|square|none)) *\x5D$'
        If (_typ := RegExMatch(_txt,rgx,&y) ? y[1] : '')    ; if list style found ...
            _L_[1].txt := RegExReplace(_L_[1].txt,rgx)      ; ... remove it after recording it
        
        If (_tag = 'ol')
            t := (_typ) ? (' type="' _typ '"') : (' type="' ((d=1) ? '1' : (d=2) ? 'i' : 'a') '"')
        Else
            t := (_typ) ? (' style="list-style-type:' _typ ';"') : ''
        
        list_html := '<' _L_[1].tag t '>' ; GitHub list levels ... 1.  >  i.  >  a.
        end_tag := '</' _L_[1].tag '>'
        
        _i := 0
        While (_L_.Length) {
            o := _L_[1]
            
            If (o.pre >= _lead) { ; step in on proper indent (check GitHub spec)          o.pre != _pre
                d++ ; increase depth
                If (r:=make_list(_L_)) && err         ; if ordered list isn't properly numbered return only the 'good' part of the list
                    return list_html '`r`n' end_tag ; ... and quit parsing
                list_html .= r
                
                Continue
            } Else If (o.pre < _pre) { ; stepping back
                d-- ; decrease depth
                return '`r`n' list_html '`r`n' end_tag
            } Else If (o.tag != _tag)                   ; if changing unordered list types ...
                   || (o.tag="ul" && o.itm != _itm) {   ; ... or if next bullet type (*, +, -) doesn't match previous
                d := 1 ; reset depth for new list
                return '`r`n' list_html '`r`n' end_tag  ; ... this starts a new list, according to GitHub spec
            }
            
            _i++
            
            If ( o.tag = 'ol' && _i != Integer(o.itm) ) {   ; if ordered list numbers are not in sequence ...
                err := true                                 ; ... flag err and return the 'good' part of the list
                return '`r`n' list_html '`r`n' end_tag
            }
            
            list_html .= '`r`n<li>' inline_code(o.txt) '</li>'
            
            _tag := o.tag, _itm := o.itm
            _pre := o.pre, _lead := o.lead
            _L_.RemoveAt(1)
        }
        
        list_html .= '`r`n' end_tag
        
        return list_html
    }
    
    AtoT(_a_) { ; for dumping the remaining text of a poorly formated list
        _txt_ := '<p>'
        For i, o in _a_
            _txt_ .= ((i>1)?'<br>':'') o.line
        return _txt_ '</p>'
    }
    
    LT_tag(_in_) => IsInteger(t:=Trim(_in_,".)")) ? "ol" : IsAlpha(t) ? "" : "ul" ; list type
    
    LT_spec(_in_) => IsInteger(t:=Trim(_in_,".)")) ? Integer(t) : t
    
    inline_code(_in) {
        output := _in, check := ""
        
        While (check != output) { ; repeat until no changes are made
            check := output
            
            ; inline code
            While RegExMatch(output, "``(.+?)``", &x) {
                
                If RegExMatch(x[1],"^\#[\da-fA-F]{6,6}$")
                || RegExMatch(x[1],"^rgb\(\d{1,3}, *\d{1,3}, *\d{1,3}\)$")
                || RegExMatch(x[1],"^hsl\(\d{1,3}, *\d{1,3}%, *\d{1,3}%\)$") {
                    output := '<code>' x[1] ' <span class="circle" style="background-color: ' x[1] ';'
                                                                      . ' width: ' (options.font_size//2) 'px;'
                                                                      . ' height: ' (options.font_size//2) 'px;'
                                                                      . ' display: inline-block;'
                                                                      . ' border: 2px solid ' x[1] ';'
                                                                      . ' border-radius: 50%;"></span></code>'
                } Else If !IsInCode()
                    output := StrReplace(output, x[0], "<code>" convert(x[1]) "</code>",,,1)
            }
            
            ; escape characters
            While RegExMatch(output,"(\\)(.)",&x)
                output := StrReplace(output,x[0],"&#" Ord(x[2]) ";")
            
            ; image
            While RegExMatch(output, "!\x5B *([^\x5D]*) *\x5D\x28 *([^\x29]+) *\x29(?:\x28 *([^\x29]+) *\x29)?", &x) && !IsInCode() {
                dims := (dm:=Trim(x[3],"()")) ? " " dm : ""
                output := StrReplace(output, x[0], '<img src="' x[2] '"' dims ' alt="' x[1] '" title="' x[1] '">',,,1)
            }
            
            ; image reference-style
            While RegExMatch(output, "!\x5B *([^\x5D]*) *\x5D\x5B *([^\x5D]+) *\x5D(?:\x28 *([^\x29]+) *\x29)?", &x)
               && ref.Has(x[2]) ; ref link stored
               && !IsInCode() {
                dims := x[3] ? " " x[3] : ""
                output := StrReplace(output, x[0], '<img src="' ref[x[2]].link '"' dims ' alt="' x[1] '" title="' ref[x[2]].title '">',,,1)
            }
            
            ; link / url
            While RegExMatch(output, "\x5B *([^\x5D]+) *\x5D\x28 *([^\x29]+) *\x29", &x) && !IsInCode() {
                rel := RegExMatch(x[2],"^#[\w\-]+") ? "" : 'noopener noreferrer'
                tgt := RegExMatch(x[2],"^#[\w\-]+") ? "" : '_blank'
                output := StrReplace(output, x[0], '<a href="' x[2] '" target="" rel="noopener noreferrer">' x[1] "</a>",,,1)
            }
            
            ; link / url reference-style 1
            While RegExMatch(output, "\x5B *([^\x5D]+) *\x5D\x5B *([^\x5D]+) *\x5D", &x)
               && ref.Has(x[2])
               && !IsInCode() {
                ; rel := 
                output := StrReplace(output, x[0]
                        , '<a href="' ref[x[2]].link '" title="' ref[x[2]].title '" target="_blank" rel="noopener noreferrer">' x[1] "</a>",,,1)
            }
            
            ; link / url reference-style 2
            While RegExMatch(output, "\x5B *([^\x5D]+) *\x5D", &x)
               && ref.Has(x[1])
               && !IsInCode()
                output := StrReplace(output, x[0]
                        , '<a href="' ref[x[1]].link '" title="' ref[x[1]].title '" target="_blank" rel="noopener noreferrer">'
                        . (ref[x[1]].title?ref[x[1]].title:x[1]) "</a>",,,1)
            
            ; strong + emphasis (bold + italics)
            While (RegExMatch(output, "(?<![\*\w])[\*]{3,3}([^\*]+)[\*]{3,3}", &x)
               ||  RegExMatch(output, "(?<!\w)[\_]{3,3}([^\_]+)[\_]{3,3}", &x)) && !IsInCode() {
                output := StrReplace(output, x[0], "<em><strong>" x[1] "</strong></em>",,,1)
            }
            
            ; strong (bold)
            While (RegExMatch(output, "(?<![\*\w])[\*]{2,2}([^\*]+)[\*]{2,2}", &x)
               ||  RegExMatch(output, "(?<!\w)[\_]{2,2}([^\_]+)[\_]{2,2}", &x)) && !IsInCode() {
                output := StrReplace(output, x[0], "<strong>" x[1] "</strong>",,,1)
            }
            
            ; emphasis (italics)
            While (RegExMatch(output, "(?<![\*\w])[\*]{1,1}([^\*]+)[\*]{1,1}", &x)
               ||  RegExMatch(output, "(?<![\w])[\_]{1,1}([^\_]+)[\_]{1,1}", &x)) && !IsInCode() {
                output := StrReplace(output, x[0], "<em>" x[1] "</em>",,,1)
            }
            
            ; strikethrough
            While RegExMatch(output, "(?<!\w)~{2,2}([^~]+)~{2,2}", &x) && !IsInCode()
                output := StrReplace(output, x[0], "<del>" x[1] "</del>",,,1)
        }
        
        return output
        
        IsInCode() => ((st := x.Pos[0]-6) < 1) ? false : RegExMatch(output,"<code> *\Q" x[0] "\E",,st) ? true : false
    }
    
    line_inc(concat:="") {
       (i < a.Length) ? (line := (concat?concat:"") strip_comment(a[++i]), result:=true) : (line := "", result:=false)
        return result
    }
    
    strip_comment(_in_) => RTrim(RegExReplace(_in_,"^(.+)<\!\-\-[^>]+\-\->","$1")," `t")
    
    convert(_in_) { ; convert markup chars so they don't get recognized, a forced kind of escaping in certain contexts
        output := _in_
        For i, v in ["&","<",">","\","*","_","-","=","~","``","[","]","(",")","!","{","}"]
            output := StrReplace(output,v,"&#" Ord(v) ";")
        return output
    }
    
    rpt(x,y) => StrReplace(Format("{:-" y "}","")," ",x) ; string repeat ... x=str, y=iterations
}