#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

CoordMode("Caret", "Screen")
CoordMode("Mouse", "Screen")

dataDir := A_ScriptDir "\data"
promptsFile := dataDir "\prompts.txt"
promptOrder := []
promptsMap := Map()
attachmentsFile := dataDir "\attachments.ini"
attachmentsMap := Map()
genresFile := dataDir "\genres.ini"
genresMap := Map()
pasteInProgress := false

asciiBuf := ""
compKana := ""
compPending := ""
bufHwnd := 0
dismissed := false
imeKana := false

matchYomis := []
selIndex := 0
popupVisible := false
popupGui := ""
popupLB := ""

regGui := ""
regYomiEdit := ""
regWordEdit := ""
regFilesEdit := ""
regListView := ""
regEditingYomi := ""
regGenreEdit := ""
regGenreFilter := ""
regTypeFilter := ""
regSearchEdit := ""
regCountText := ""
regRefreshing := false

romajiMap := Map()
romajiPrefixes := Map()
inputHookObj := ""

; ===== データ読み書き =====

InitializeData() {
    global dataDir, promptsFile, attachmentsFile, genresFile
    DirCreate(dataDir)
    for name in ["prompts.txt", "attachments.ini", "genres.ini"] {
        destination := dataDir "\" name
        if !FileExist(destination)
            FileCopy(A_ScriptDir "\samples\" name, destination, false)
    }
}

LoadPrompts() {
    global promptsFile, promptOrder, promptsMap, attachmentsFile, attachmentsMap, genresFile, genresMap
    promptOrder := []
    promptsMap := Map()
    if !FileExist(promptsFile)
        return
    content := FileRead(promptsFile, "UTF-8")
    lines := StrSplit(content, "`n", "`r")
    curYomi := ""
    curBody := ""
    for line in lines {
        if RegExMatch(line, "^===(.+)===\s*$", &m) {
            if curYomi != "" {
                promptOrder.Push(curYomi)
                promptsMap[curYomi] := RTrim(curBody, "`r`n")
            }
            curYomi := Trim(m[1])
            curBody := ""
        } else if curYomi != "" {
            curBody .= RegExReplace(line, "^\\(\\*===)", "$1") "`n"
        }
    }
    if curYomi != "" {
        promptOrder.Push(curYomi)
        promptsMap[curYomi] := RTrim(curBody, "`r`n")
    }
    attachmentsMap := Map()
    genresMap := Map()
    for yomi in promptOrder {
        paths := IniRead(attachmentsFile, "Attachments", yomi, "")
        if paths != ""
            attachmentsMap[yomi] := StrReplace(paths, "|", "`n")
        genre := IniRead(genresFile, "Genres", yomi, "")
        if genre != ""
            genresMap[yomi] := genre
    }
}

SavePrompts() {
    global promptsFile, promptOrder, promptsMap, attachmentsFile, attachmentsMap, genresFile, genresMap
    out := ""
    for yomi in promptOrder {
        body := StrReplace(promptsMap[yomi], "`r`n", "`n")
        ; 本文中の「===」行が見出しに誤認されないようエスケープする
        out .= "===" yomi "===`n" RegExReplace(body, "m)^(\\*===)", "\$1") "`n`n"
    }
    tmp := promptsFile ".tmp"
    if FileExist(tmp)
        FileDelete(tmp)
    FileAppend(out, tmp, "UTF-8")
    FileMove(tmp, promptsFile, 1)
    iniTmp := attachmentsFile ".tmp"
    if FileExist(iniTmp)
        FileDelete(iniTmp)
    for yomi in promptOrder {
        if attachmentsMap.Has(yomi) && attachmentsMap[yomi] != ""
            IniWrite(StrReplace(attachmentsMap[yomi], "`n", "|"), iniTmp, "Attachments", yomi)
    }
    if !FileExist(iniTmp)
        FileAppend("[Attachments]`r`n", iniTmp, "UTF-16")
    FileMove(iniTmp, attachmentsFile, 1)
    genreTmp := genresFile ".tmp"
    if FileExist(genreTmp)
        FileDelete(genreTmp)
    for yomi in promptOrder {
        if genresMap.Has(yomi) && genresMap[yomi] != ""
            IniWrite(genresMap[yomi], genreTmp, "Genres", yomi)
    }
    if !FileExist(genreTmp)
        FileAppend("[Genres]`r`n", genreTmp, "UTF-16")
    FileMove(genreTmp, genresFile, 1)
}

; ===== ローマ字→かな =====

BuildRomajiTable() {
    global romajiMap, romajiPrefixes
    table := "a=あ i=い u=う e=え o=お ka=か ki=き ku=く ke=け ko=こ ca=か ci=し cu=く ce=せ co=こ qu=く"
        . " sa=さ si=し shi=し su=す se=せ so=そ ta=た ti=ち chi=ち tu=つ tsu=つ te=て to=と"
        . " na=な ni=に nu=ぬ ne=ね no=の ha=は hi=ひ hu=ふ fu=ふ he=へ ho=ほ"
        . " ma=ま mi=み mu=む me=め mo=も ya=や yi=い yu=ゆ ye=いぇ yo=よ"
        . " ra=ら ri=り ru=る re=れ ro=ろ wa=わ wi=うぃ wu=う we=うぇ wo=を nn=ん n'=ん xn=ん"
        . " ga=が gi=ぎ gu=ぐ ge=げ go=ご za=ざ zi=じ ji=じ zu=ず ze=ぜ zo=ぞ"
        . " da=だ di=ぢ du=づ de=で do=ど ba=ば bi=び bu=ぶ be=べ bo=ぼ pa=ぱ pi=ぴ pu=ぷ pe=ぺ po=ぽ"
        . " kya=きゃ kyi=きぃ kyu=きゅ kye=きぇ kyo=きょ"
        . " sya=しゃ syi=しぃ syu=しゅ sye=しぇ syo=しょ sha=しゃ shu=しゅ she=しぇ sho=しょ"
        . " tya=ちゃ tyi=ちぃ tyu=ちゅ tye=ちぇ tyo=ちょ cha=ちゃ chu=ちゅ che=ちぇ cho=ちょ"
        . " cya=ちゃ cyi=ちぃ cyu=ちゅ cye=ちぇ cyo=ちょ"
        . " nya=にゃ nyi=にぃ nyu=にゅ nye=にぇ nyo=にょ hya=ひゃ hyi=ひぃ hyu=ひゅ hye=ひぇ hyo=ひょ"
        . " mya=みゃ myi=みぃ myu=みゅ mye=みぇ myo=みょ rya=りゃ ryi=りぃ ryu=りゅ rye=りぇ ryo=りょ"
        . " gya=ぎゃ gyi=ぎぃ gyu=ぎゅ gye=ぎぇ gyo=ぎょ"
        . " zya=じゃ zyi=じぃ zyu=じゅ zye=じぇ zyo=じょ ja=じゃ ju=じゅ je=じぇ jo=じょ"
        . " jya=じゃ jyi=じぃ jyu=じゅ jye=じぇ jyo=じょ dya=ぢゃ dyi=ぢぃ dyu=ぢゅ dye=ぢぇ dyo=ぢょ"
        . " bya=びゃ byi=びぃ byu=びゅ bye=びぇ byo=びょ pya=ぴゃ pyi=ぴぃ pyu=ぴゅ pye=ぴぇ pyo=ぴょ"
        . " fa=ふぁ fi=ふぃ fe=ふぇ fo=ふぉ fya=ふゃ fyu=ふゅ fyo=ふょ va=ゔぁ vi=ゔぃ vu=ゔ ve=ゔぇ vo=ゔぉ"
        . " tha=てゃ thi=てぃ thu=てゅ the=てぇ tho=てょ dha=でゃ dhi=でぃ dhu=でゅ dhe=でぇ dho=でょ"
        . " twu=とぅ dwu=どぅ tsa=つぁ tsi=つぃ tse=つぇ tso=つぉ kwa=くぁ qa=くぁ qi=くぃ qe=くぇ qo=くぉ gwa=ぐぁ"
        . " wha=うぁ whi=うぃ whe=うぇ who=うぉ xa=ぁ xi=ぃ xu=ぅ xe=ぇ xo=ぉ la=ぁ li=ぃ lu=ぅ le=ぇ lo=ぉ"
        . " xya=ゃ xyu=ゅ xyo=ょ lya=ゃ lyu=ゅ lyo=ょ xtu=っ ltu=っ xtsu=っ ltsu=っ xwa=ゎ lwa=ゎ"
    for pair in StrSplit(table, " ") {
        kv := StrSplit(pair, "=")
        romajiMap[kv[1]] := kv[2]
        Loop StrLen(kv[1])
            romajiPrefixes[SubStr(kv[1], 1, A_Index)] := true
    }
}

FeedRomaji(ch) {
    global compKana, compPending, romajiMap, romajiPrefixes
    c := StrLower(ch)
    if (c = "-") {
        compKana .= compPending "ー"
        compPending := ""
        return
    }
    if !RegExMatch(c, "^[a-z']$") {
        compKana .= compPending c
        compPending := ""
        return
    }
    compPending .= c
    loop {
        if romajiMap.Has(compPending) {
            compKana .= romajiMap[compPending]
            compPending := ""
            return
        }
        if romajiPrefixes.Has(compPending)
            return
        first := SubStr(compPending, 1, 1)
        second := SubStr(compPending, 2, 1)
        if (first = "n" && second != "") {
            compKana .= "ん"
        } else if (first = second && RegExMatch(first, "[a-z]")) || (first = "t" && second = "c") {
            compKana .= "っ"
        } else {
            compKana .= first
        }
        compPending := SubStr(compPending, 2)
        if (compPending = "")
            return
    }
}

ToHiragana(text) {
    out := ""
    Loop Parse text {
        code := Ord(A_LoopField)
        out .= (code >= 0x30A1 && code <= 0x30F6) ? Chr(code - 0x60) : A_LoopField
    }
    return out
}

; ===== IME状態 =====

ImeKanaMode() {
    hwnd := WinExist("A")
    if !hwnd
        return false
    info := Buffer(A_PtrSize = 8 ? 72 : 48, 0)
    NumPut("UInt", info.Size, info)
    thread := DllCall("GetWindowThreadProcessId", "ptr", hwnd, "ptr", 0, "uint")
    if DllCall("GetGUIThreadInfo", "uint", thread, "ptr", info) {
        focus := NumGet(info, A_PtrSize = 8 ? 16 : 12, "ptr")
        if focus
            hwnd := focus
    }
    imeWnd := DllCall("imm32\ImmGetDefaultIMEWnd", "ptr", hwnd, "ptr")
    if !imeWnd
        return false
    try {
        if !SendMessage(0x283, 5, 0, , imeWnd, , , , 200)
            return false
        return (SendMessage(0x283, 1, 0, , imeWnd, , , , 200) & 1) != 0
    } catch {
        return false
    }
}

; ===== 予測候補ポップアップ =====

ResetBuffer() {
    global asciiBuf, compKana, compPending, dismissed, matchYomis, selIndex
    asciiBuf := ""
    compKana := ""
    compPending := ""
    dismissed := false
    matchYomis := []
    selIndex := 0
    HidePopup()
}

IsPrefix(key, text) => StrLen(key) >= 2 && SubStr(text, 1, StrLen(key)) = key

RefreshMatches() {
    global asciiBuf, compKana, imeKana, promptOrder, matchYomis, selIndex, dismissed
    matchYomis := []
    selIndex := 0
    for yomi in promptOrder {
        normalized := ToHiragana(yomi)
        if IsPrefix(asciiBuf, normalized) || (imeKana && IsPrefix(compKana, normalized))
            matchYomis.Push(yomi)
    }
    if matchYomis.Length && !dismissed
        ShowPopup()
    else
        HidePopup()
}

ShowPopup() {
    global popupGui, popupLB, matchYomis, popupVisible, promptsMap
    if !IsObject(popupGui) {
        popupGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Border +E0x08000000", "PromptIME候補")
        popupGui.BackColor := "White"
        popupGui.SetFont("s10", "Yu Gothic UI")
        popupLB := popupGui.AddListBox("x4 y4 w380 r5")
        popupGui.SetFont("s9 cGray")
        popupGui.AddText("x6 y+2 w376", "Tab：確定　↓↑で選んでEnter　Esc：閉じる")
        popupGui.Show("Hide AutoSize")
    }
    items := []
    for yomi in matchYomis {
        preview := StrReplace(StrReplace(promptsMap[yomi], "`r"), "`n", " ")
        if StrLen(preview) > 24
            preview := SubStr(preview, 1, 24) "…"
        items.Push(yomi "：" preview)
    }
    popupLB.Delete()
    popupLB.Add(items)
    popupLB.Choose(0)
    popupGui.GetPos(, , &w, &h)
    PopupPosition(w, h, &x, &y)
    popupGui.Show("x" x " y" y " NA")
    popupVisible := true
}

PopupPosition(w, h, &x, &y) {
    global imeKana
    if !CaretGetPos(&cx, &cy)
        MouseGetPos(&cx, &cy)
    left := 0, top := 0, right := A_ScreenWidth, bottom := A_ScreenHeight
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        if (cx >= l && cx < r && cy >= t && cy < b) {
            left := l, top := t, right := r, bottom := b
            break
        }
    }
    below := cy + 24
    above := cy - h - 6
    ; IMEオン時は下にMicrosoft IME自身の予測一覧が出るので上に置く
    if imeKana
        y := above >= top ? above : below
    else
        y := below + h <= bottom ? below : above
    x := Max(left, Min(cx + 4, right - w))
    y := Max(top, Min(y, bottom - h))
}

HidePopup() {
    global popupGui, popupVisible
    if IsObject(popupGui)
        popupGui.Hide()
    popupVisible := false
}

DismissPopup() {
    global dismissed, selIndex
    dismissed := true
    selIndex := 0
    HidePopup()
}

MoveSelection(delta) {
    global selIndex, matchYomis, popupLB
    selIndex += delta
    if selIndex < 1
        selIndex := matchYomis.Length
    else if selIndex > matchYomis.Length
        selIndex := 1
    popupLB.Choose(selIndex)
}

ConfirmCandidate(index) {
    global matchYomis, promptsMap, asciiBuf, compKana, compPending, imeKana, attachmentsMap, pasteInProgress
    Critical()
    if pasteInProgress || (index < 1 || index > matchYomis.Length)
        return
    yomi := matchYomis[index]
    word := promptsMap[yomi]
    paths := attachmentsMap.Has(yomi) ? attachmentsMap[yomi] : ""
    try paths := ValidateAttachments(paths)
    catch Error as err {
        DismissPopup()
        MsgBox(err.Message)
        return
    }
    removeCount := imeKana ? StrLen(compKana) + StrLen(compPending) : StrLen(asciiBuf)
    ResetBuffer()
    if removeCount > 0
        Send("{Backspace " removeCount "}")
    PasteText(word, paths)
}

PasteText(text, paths := "") {
    global pasteInProgress
    saved := ClipboardAll()
    target := WinExist("A")
    sequence := -1
    pasteInProgress := true
    try {
        A_Clipboard := StrReplace(StrReplace(text, "`r`n", "`n"), "`n", "`r`n")
        sequence := DllCall("GetClipboardSequenceNumber", "UInt")
        Send("^v")
        Sleep(paths = "" ? 600 : 350)
        if paths != "" {
            if !WinActive("ahk_id " target)
                throw Error("入力先が変わったため添付を中止しました。")
            if DllCall("GetClipboardSequenceNumber", "UInt") != sequence
                throw Error("クリップボードが変更されたため添付を中止しました。")
            SetClipboardFiles(paths)
            sequence := DllCall("GetClipboardSequenceNumber", "UInt")
            Send("^v")
            Sleep(1500)
        }
    } catch Error as err {
        TrayTip(err.Message, "PromptIME 添付エラー")
    } finally {
        if DllCall("GetClipboardSequenceNumber", "UInt") = sequence
            A_Clipboard := saved
        pasteInProgress := false
        ResetBuffer()
    }
}

ValidateAttachments(paths) {
    out := ""
    for line in StrSplit(paths, "`n", "`r") {
        path := Trim(line, ' `t"')
        if path = ""
            continue
        if DirExist(path)
            path := RTrim(path, "\") "\SKILL.md"
        if !FileExist(path) || DirExist(path)
            throw Error("添付ファイルが見つかりません。`n" path)
        if !RegExMatch(path, "i)^(?:[a-z]:\\|\\\\)") || InStr(path, "|")
            throw Error("添付にはファイルの絶対パスを指定してください。`n" path)
        out .= (out = "" ? "" : "`n") path
    }
    return out
}

SetClipboardFiles(paths) {
    bytes := 22
    for path in StrSplit(paths, "`n")
        bytes += (StrLen(path) + 1) * 2
    handle := DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", bytes, "Ptr")
    if !handle
        throw Error("添付用のメモリを確保できませんでした。")
    opened := false
    try {
        ptr := DllCall("GlobalLock", "Ptr", handle, "Ptr")
        if !ptr
            throw Error("添付データを作成できませんでした。")
        NumPut("UInt", 20, ptr)
        NumPut("UInt", 1, ptr + 16)
        offset := 20
        for path in StrSplit(paths, "`n") {
            StrPut(path, ptr + offset, StrLen(path) + 1, "UTF-16")
            offset += (StrLen(path) + 1) * 2
        }
        DllCall("GlobalUnlock", "Ptr", handle)
        Loop 20 {
            if DllCall("OpenClipboard", "Ptr", A_ScriptHwnd) {
                opened := true
                break
            }
            Sleep(25)
        }
        if !opened
            throw Error("クリップボードを開けませんでした。")
        if !DllCall("EmptyClipboard") || !DllCall("SetClipboardData", "UInt", 15, "Ptr", handle, "Ptr")
            throw Error("添付ファイルをクリップボードに設定できませんでした。")
        handle := 0
    } finally {
        if opened
            DllCall("CloseClipboard")
        if handle
            DllCall("GlobalFree", "Ptr", handle)
    }
}

PopupItemAt(lParam) {
    global popupLB, matchYomis
    result := SendMessage(0x1A9, 0, lParam, , popupLB.Hwnd)
    index := (result & 0xFFFF) + 1
    return ((result >> 16) = 0 && index <= matchYomis.Length) ? index : 0
}

PopupLButtonDown(wParam, lParam, msg, hwnd) {
    global popupLB
    if IsObject(popupLB) && hwnd = popupLB.Hwnd
        return 0
}

PopupLButtonUp(wParam, lParam, msg, hwnd) {
    global popupLB
    if !IsObject(popupLB) || hwnd != popupLB.Hwnd
        return
    index := PopupItemAt(lParam)
    if index
        ConfirmCandidate(index)
    return 0
}

ClickReset() {
    global popupGui
    MouseGetPos(, , &under)
    if IsObject(popupGui) && under = popupGui.Hwnd
        return
    ResetBuffer()
}

; ===== キー入力の監視 =====

OnCharTyped(ih, ch) {
    global popupVisible, selIndex, regGui, bufHwnd, asciiBuf, imeKana, pasteInProgress
    if pasteInProgress || IsRegisterActive()
        return
    Critical()
    code := Ord(ch)
    if popupVisible && (code = 9 || code = 27 || ((code = 13 || code = 10) && selIndex > 0))
        return
    if (code < 0x20 || ch = " " || ch = "　" || GetKeyState("Ctrl") || GetKeyState("Alt")) {
        ResetBuffer()
        return
    }
    hwnd := WinExist("A")
    if IsObject(regGui) && hwnd = regGui.Hwnd {
        ResetBuffer()
        return
    }
    if (hwnd != bufHwnd) {
        ResetBuffer()
        bufHwnd := hwnd
    }
    imeKana := ImeKanaMode()
    if !imeKana && InStr(",.!?;:/", ch) {
        ResetBuffer()
        return
    }
    asciiBuf .= ch
    FeedRomaji(ch)
    if StrLen(asciiBuf) > 64 {
        ResetBuffer()
        return
    }
    RefreshMatches()
}

OnKeyDownHandler(ih, vk, sc) {
    global popupVisible, selIndex, asciiBuf, compKana, compPending, imeKana, pasteInProgress
    if pasteInProgress || IsRegisterActive()
        return
    static ignored := Map(0x10, 1, 0x11, 1, 0x12, 1, 0x14, 1, 0x5B, 1, 0x5C, 1, 0x90, 1, 0x91, 1, 0xA0, 1, 0xA1, 1, 0xA2, 1, 0xA3, 1, 0xA4, 1, 0xA5, 1)
    Critical()
    if ignored.Has(vk)
        return
    if popupVisible && (vk = 0x09 || vk = 0x1B || vk = 0x26 || vk = 0x28 || (vk = 0x0D && selIndex > 0))
        return
    if (vk != 0x08) {
        ResetBuffer()
        return
    }
    if (asciiBuf = "")
        return
    asciiBuf := SubStr(asciiBuf, 1, -1)
    if (compPending != "")
        compPending := SubStr(compPending, 1, -1)
    else
        compKana := SubStr(compKana, 1, -1)
    imeKana := ImeKanaMode()
    RefreshMatches()
}

StartInputHook() {
    global inputHookObj
    ; I1はレベル0の入力を無視する指定で、自分のSendはレベル0なので拾わない
    inputHookObj := InputHook("L0 V I1")
    inputHookObj.OnChar := OnCharTyped
    inputHookObj.OnKeyDown := OnKeyDownHandler
    inputHookObj.NotifyNonText := true
    inputHookObj.KeyOpt("{Backspace}{Enter}{Tab}{Escape}{Delete}", "+N")
    inputHookObj.Start()
}

; ===== 登録画面 =====

IsRegisterActive() {
    global regGui
    if !IsObject(regGui)
        return false
    active := WinExist("A")
    return active && DllCall("GetAncestor", "Ptr", active, "UInt", 3, "Ptr") = regGui.Hwnd
}

UpdateInputMonitoring(*) {
    global inputHookObj
    if !IsObject(inputHookObj)
        return
    if IsRegisterActive() {
        if inputHookObj.InProgress {
            inputHookObj.Stop()
            ResetBuffer()
        }
    } else if !inputHookObj.InProgress {
        ResetBuffer()
        inputHookObj.Start()
    }
}

OnRegisterActivate(wParam, lParam, msg, hwnd) {
    global regGui, inputHookObj
    if IsObject(regGui) && hwnd = regGui.Hwnd && (wParam & 0xFFFF) && IsObject(inputHookObj) {
        inputHookObj.Stop()
        ResetBuffer()
    }
}

ClearRegisterFields(*) {
    global regYomiEdit, regWordEdit, regFilesEdit, regListView, regEditingYomi, regGenreEdit
    regEditingYomi := ""
    regListView.Modify(0, "-Select -Focus")
    regYomiEdit.Value := ""
    regWordEdit.Value := ""
    regFilesEdit.Value := ""
    regGenreEdit.Text := ""
    ResetBuffer()
    regYomiEdit.Focus()
}

ShowRegisterGui(*) {
    global regGui, regYomiEdit, regWordEdit, regFilesEdit, regListView
    global regGenreEdit, regGenreFilter, regTypeFilter, regSearchEdit, regCountText
    if IsObject(regGui) {
        regGui.Show()
        UpdateInputMonitoring()
        return
    }
    regGui := Gui("+Resize +MinSize990x550", "プロンプトの登録")
    regGui.SetFont("s10", "Yu Gothic UI")

    regGui.AddText("x16 y16 w280", "よみ(R)：ひらがな・半角英数どちらも可")
    regYomiEdit := regGui.AddEdit("x16 y36 w280")

    regGui.AddText("x16 y70 w280", "プロンプト本文(W)：")
    regWordEdit := regGui.AddEdit("x16 y90 w280 h130 Multi WantReturn")
    regGui.AddText("x16 y230 w280", "添付ファイル（1行に1件・省略可）：")
    regFilesEdit := regGui.AddEdit("x16 y252 w280 h72 Multi WantReturn")
    regGui.AddButton("x16 y330 w130", "ファイルを追加").OnEvent("Click", OnChooseAttachment)
    regGui.AddButton("x156 y330 w140", "添付欄を空にする").OnEvent("Click", (*) => regFilesEdit.Value := "")

    regGui.AddButton("x16 y374 w68", "新規登録").OnEvent("Click", OnRegisterClick)
    regGui.AddButton("x87 y374 w68", "更新").OnEvent("Click", OnUpdateClick)
    regGui.AddButton("x158 y374 w68", "削除").OnEvent("Click", OnDeleteClick)
    regGui.AddButton("x229 y374 w68", "クリア").OnEvent("Click", ClearRegisterFields)
    regGui.AddText("x16 y412 w280", "ジャンル（自由入力・省略可）：")
    regGenreEdit := regGui.AddComboBox("x16 y434 w280", [])
    regGui.AddText("x16 y478 w280 r3 cGray", "よみを2文字以上入力しTabで確定。添付はファイル貼り付け対応の入力欄で使えます。送信は手動です。")

    regGui.AddText("x320 y16 w640", "登録済みプロンプト一覧")
    regTypeFilter := regGui.AddDropDownList("x320 y40 w205 Choose1", ["すべての種類", "スキルあり", "その他の添付あり", "添付なし"])
    regGenreFilter := regGui.AddDropDownList("x536 y40 w220 Choose1", ["すべてのジャンル", "未分類"])
    regGui.AddText("x320 y82 w46", "検索：")
    regSearchEdit := regGui.AddEdit("x370 y78 w386")
    regGui.AddButton("x770 y77 w200", "絞り込みをリセット").OnEvent("Click", ResetListFilters)
    regTypeFilter.OnEvent("Change", RefreshListView)
    regGenreFilter.OnEvent("Change", RefreshListView)
    regSearchEdit.OnEvent("Change", RefreshListView)
    regListView := regGui.AddListView("x320 y116 w650 h376 r18", ["よみ", "ジャンル", "種類", "プレビュー"])
    regListView.OnEvent("ItemSelect", OnListSelect)
    regListView.ModifyCol(1, 110)
    regListView.ModifyCol(2, 105)
    regListView.ModifyCol(3, 105)
    regListView.ModifyCol(4, 305)
    regCountText := regGui.AddText("x320 y510 w420", "")

    regGui.AddButton("x880 y505 w90", "閉じる").OnEvent("Click", (*) => regGui.Hide())
    regGui.OnEvent("Close", (*) => regGui.Hide())

    RefreshGenreChoices()
    RefreshListView()
    regGui.Show("w990 h550")
    UpdateInputMonitoring()
    SetTimer(UpdateInputMonitoring, 100)
}

OnChooseAttachment(*) {
    global regFilesEdit
    selected := FileSelect("M3", , "添付するスキルファイルを選択", "スキル・文書 (*.md; *.txt; *.pdf; *.zip)")
    if !IsObject(selected)
        return
    for path in selected
        regFilesEdit.Value .= (regFilesEdit.Value = "" ? "" : "`r`n") path
}

ReadAttachmentField() {
    global regFilesEdit
    return ValidateAttachments(regFilesEdit.Value)
}

GetPromptGenre(yomi) {
    global genresMap
    return genresMap.Has(yomi) ? genresMap[yomi] : ""
}

GetPromptType(yomi) {
    global attachmentsMap
    if !attachmentsMap.Has(yomi) || Trim(attachmentsMap[yomi]) = ""
        return 4
    for path in StrSplit(attachmentsMap[yomi], "`n", "`r") {
        if RegExMatch(path, "i)(?:^|[\\/])SKILL\.md$")
            return 2
    }
    return 3
}

RefreshGenreChoices() {
    global genresMap, regGenreEdit, regGenreFilter
    draft := regGenreEdit.Text
    filter := regGenreFilter.Text
    unique := Map()
    for yomi, genre in genresMap {
        if genre != ""
            unique[genre] := true
    }
    lines := ""
    for genre in unique
        lines .= genre "`n"
    choices := []
    if lines != "" {
        for genre in StrSplit(RTrim(Sort(lines), "`n"), "`n")
            choices.Push(genre)
    }
    regGenreEdit.Delete()
    regGenreEdit.Add(choices)
    regGenreEdit.Text := draft
    filters := ["すべてのジャンル", "未分類"]
    for genre in choices
        filters.Push(genre)
    regGenreFilter.Delete()
    regGenreFilter.Add(filters)
    regGenreFilter.Choose(1)
    for index, genre in filters {
        if genre = filter {
            regGenreFilter.Choose(index)
            break
        }
    }
}

ResetListFilters(*) {
    global regTypeFilter, regGenreFilter, regSearchEdit
    regTypeFilter.Choose(1)
    regGenreFilter.Choose(1)
    regSearchEdit.Value := ""
    RefreshListView()
}

ReadGenreField() {
    global regGenreEdit
    genre := Trim(regGenreEdit.Text)
    if genre = "未分類"
        return ""
    if genre = "すべてのジャンル"
        throw Error("ジャンル名に「すべてのジャンル」は使えません。")
    return genre
}

RefreshListView(*) {
    global regListView, promptOrder, promptsMap, attachmentsMap, regGenreFilter, regTypeFilter
    global regSearchEdit, regCountText, regRefreshing, regEditingYomi
    if !IsObject(regListView)
        return
    regRefreshing := true
    regListView.Opt("-Redraw")
    try {
        regListView.Delete()
        query := Trim(regSearchEdit.Value)
        types := ["", "スキルあり", "その他の添付", "添付なし"]
        for yomi in promptOrder {
            word := promptsMap[yomi]
            genre := GetPromptGenre(yomi)
            kind := GetPromptType(yomi)
            if regTypeFilter.Value > 1 && regTypeFilter.Value != kind
                continue
            if regGenreFilter.Value = 2 && genre != ""
                continue
            if regGenreFilter.Value > 2 && regGenreFilter.Text != genre
                continue
            paths := attachmentsMap.Has(yomi) ? attachmentsMap[yomi] : ""
            if query != "" && !InStr(yomi "`n" word "`n" genre "`n" paths, query)
                continue
            preview := StrReplace(StrReplace(word, "`r", ""), "`n", " ")
            if StrLen(preview) > 100
                preview := SubStr(preview, 1, 100) "…"
            row := regListView.Add(, yomi, genre = "" ? "未分類" : genre, types[kind], preview)
            if yomi = regEditingYomi
                regListView.Modify(row, "Select Focus")
        }
        regCountText.Value := regListView.GetCount() " 件表示 / 全 " promptOrder.Length " 件"
    } finally {
        regListView.Opt("+Redraw")
        regRefreshing := false
    }
}

OnListSelect(ctrl, item, selected) {
    global regEditingYomi, promptsMap, regYomiEdit, regWordEdit, regFilesEdit, attachmentsMap
    global regGenreEdit, regRefreshing
    if !selected || regRefreshing
        return
    yomi := ctrl.GetText(item, 1)
    regEditingYomi := yomi
    regYomiEdit.Value := yomi
    regWordEdit.Value := promptsMap.Has(yomi) ? promptsMap[yomi] : ""
    regFilesEdit.Value := attachmentsMap.Has(yomi) ? attachmentsMap[yomi] : ""
    regGenreEdit.Text := GetPromptGenre(yomi)
}

OnRegisterClick(*) {
    global regYomiEdit, regWordEdit, regFilesEdit, promptOrder, promptsMap, attachmentsMap
    global genresMap
    yomi := Trim(regYomiEdit.Value)
    word := regWordEdit.Value
    if (yomi = "" || word = "") {
        MsgBox("よみと本文の両方を入力してください。")
        return
    }
    if promptsMap.Has(yomi) {
        MsgBox("そのよみは既に登録されています。変更する場合は右の一覧から選んで「更新」を押してください。")
        return
    }
    try {
        paths := ReadAttachmentField()
        genre := ReadGenreField()
    }
    catch Error as err {
        MsgBox(err.Message)
        return
    }
    attachmentsMap[yomi] := paths
    genresMap[yomi] := genre
    promptOrder.Push(yomi)
    promptsMap[yomi] := word
    SavePrompts()
    RefreshGenreChoices()
    RefreshListView()
    ClearRegisterFields()
}

OnUpdateClick(*) {
    global regEditingYomi, regYomiEdit, regWordEdit, promptOrder, promptsMap, attachmentsMap
    global genresMap
    if (regEditingYomi = "") {
        MsgBox("更新する項目を右側の一覧から選んでください。")
        return
    }
    newYomi := Trim(regYomiEdit.Value)
    newWord := regWordEdit.Value
    if (newYomi = "" || newWord = "") {
        MsgBox("よみと本文の両方を入力してください。")
        return
    }
    try {
        paths := ReadAttachmentField()
        genre := ReadGenreField()
    }
    catch Error as err {
        MsgBox(err.Message)
        return
    }
    if (newYomi != regEditingYomi) {
        idx := 0
        for i, y in promptOrder {
            if (y = regEditingYomi) {
                idx := i
                break
            }
        }
        if idx
            promptOrder[idx] := newYomi
        promptsMap.Delete(regEditingYomi)
        if attachmentsMap.Has(regEditingYomi)
            attachmentsMap.Delete(regEditingYomi)
        if genresMap.Has(regEditingYomi)
            genresMap.Delete(regEditingYomi)
    }
    promptsMap[newYomi] := newWord
    attachmentsMap[newYomi] := paths
    genresMap[newYomi] := genre
    regEditingYomi := newYomi
    SavePrompts()
    RefreshGenreChoices()
    RefreshListView()
}

OnDeleteClick(*) {
    global regEditingYomi, promptOrder, promptsMap, regYomiEdit, regWordEdit, regFilesEdit, attachmentsMap
    global genresMap
    if (regEditingYomi = "") {
        MsgBox("削除する項目を右側の一覧から選んでください。")
        return
    }
    for i, y in promptOrder {
        if (y = regEditingYomi) {
            promptOrder.RemoveAt(i)
            break
        }
    }
    promptsMap.Delete(regEditingYomi)
    if attachmentsMap.Has(regEditingYomi)
        attachmentsMap.Delete(regEditingYomi)
    if genresMap.Has(regEditingYomi)
        genresMap.Delete(regEditingYomi)
    SavePrompts()
    RefreshGenreChoices()
    RefreshListView()
    ClearRegisterFields()
}

; ===== トレイアイコン =====

OnMessage(0x404, TrayCallback)
TrayCallback(wParam, lParam, msg, hwnd) {
    if (lParam = 0x201)
        ShowRegisterGui()
}

A_TrayMenu.Delete()
A_TrayMenu.Add("プロンプト登録画面を開く", ShowRegisterGui)
A_TrayMenu.Add("フォルダを開く", (*) => Run(dataDir))
A_TrayMenu.Add("再読み込み", (*) => Reload())
A_TrayMenu.Add()
A_TrayMenu.Add("終了", (*) => ExitApp())
A_TrayMenu.Default := "プロンプト登録画面を開く"
A_IconTip := "プロンプトIME（よみを2文字以上打つと候補表示）"

; ===== 初期化 =====

OnMessage(0x201, PopupLButtonDown)
OnMessage(0x202, PopupLButtonUp)
OnMessage(0x6, OnRegisterActivate)
InitializeData()
BuildRomajiTable()
LoadPrompts()
StartInputHook()
if A_Args.Length && A_Args[1] = "--register"
    ShowRegisterGui()

#HotIf popupVisible && !IsRegisterActive()
$Tab::ConfirmCandidate(selIndex > 0 ? selIndex : 1)
$Down::MoveSelection(1)
$Up::MoveSelection(-1)
$Esc::DismissPopup()
#HotIf popupVisible && selIndex > 0 && !IsRegisterActive()
$Enter::ConfirmCandidate(selIndex)
#HotIf
~*LButton::ClickReset()
~*RButton::ClickReset()
