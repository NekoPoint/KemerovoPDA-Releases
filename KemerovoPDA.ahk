#NoEnv
#SingleInstance, Force
SetWorkingDir, %A_ScriptDir%
FileEncoding, UTF-8

; --- HWID + АКТИВАЦИЯ ---
DriveGet, Serial, Serial, C:\\
Global HWID := Abs(Serial)
Global ExpectedKey := "KEM-" . ((HWID * 3) + 777) . "-" . ((HWID * 7) + 1337)
Global PROMO_SECRET := 7331
Global AppVersion := "1.4"

; --- ПРОВЕРКА ОБНОВЛЕНИЙ ---
try {
    HttpU := ComObjCreate("WinHttp.WinHttpRequest.5.1")
    HttpU.Open("GET", "https://kemerevopda-default-rtdb.asia-southeast1.firebasedatabase.app/updater.json?t=" . A_TickCount, false)
    HttpU.Send()
    RespU := HttpU.ResponseText
    if (RespU != "null" && RespU != "") {
        RegExMatch(RespU, """version"":\s*""([^""]+)""", MatchVer)
        RegExMatch(RespU, """url"":\s*""([^""]+)""", MatchUrl)
        RegExMatch(RespU, """laws_version"":\s*(\d+)", MatchLawsVer)
        NewVer := MatchVer1
        UpdateUrl := MatchUrl1
        LawsCloudVer := MatchLawsVer1
        if (LawsCloudVer != "") {
            LocalLawsVer := 0
            IniRead, LocalLawsVer, settings.ini, Auth, LawsVer, 0
            if (!FileExist("laws_cache.json") || LocalLawsVer != LawsCloudVer) {
                UrlDownloadToFile, https://kemerevopda-default-rtdb.asia-southeast1.firebasedatabase.app/laws.json, laws_cache.json
                if (!ErrorLevel)
                    IniWrite, %LawsCloudVer%, settings.ini, Auth, LawsVer
            }
        }
        if (NewVer != "" && NewVer != AppVersion) {
            MsgBox, 68, Доступно обновление!, Вышла версия v%NewVer%.`nОбновить?
            IfMsgBox Yes
            {
                UrlDownloadToFile, %UpdateUrl%, KemerovoPDA_new.exe
                if !ErrorLevel {
                    BatContent =
                    (LTrim
                    @echo off
                    timeout /t 2 /nobreak >nul
                    move /y "KemerovoPDA_new.exe" "%A_ScriptName%"
                    start "" "%A_ScriptName%"
                    del "`%~f0"
                    )
                    FileDelete, update_pda.bat
                    FileAppend, %BatContent%, update_pda.bat
                    Run, update_pda.bat,, Hide
                    ExitApp
                }
            }
        }
    }
} catch e {
    ; Нет сети — ок
}

; --- ПРОВЕРКА АКТИВАЦИИ ---
IniRead, SavedKey, settings.ini, Auth, Key, None
Global Activated := false
if (SavedKey = ExpectedKey) {
    Activated := true
} else if (InStr(SavedKey, "|")) {
    Parts := StrSplit(SavedKey, "|")
    if (Parts.MaxIndex() == 3) {
        EKey := Parts[1]
        PExpiry := Parts[2]
        PHash := Parts[3]
        if (EKey = ExpectedKey) {
            CH := 0
            Combined := EKey . PExpiry
            Loop, % StrLen(Combined)
                CH += Asc(SubStr(Combined, A_Index, 1))
            CH := CH * PROMO_SECRET
            if (PHash = CH) {
                if (PExpiry = "NONE") {
                    Activated := true
                } else {
                    NowStr := SubStr(A_Now, 1, 12)
                    if (NowStr <= PExpiry)
                        Activated := true
                    else
                        IniDelete, settings.ini, Auth, Key
                }
            }
        }
    }
}

if (!Activated) {
    Gui, Auth:+AlwaysOnTop
    Gui, Auth:Font, s10, Segoe UI
    Gui, Auth:Add, Text, x10 y10, Программа заблокирована. Ваш HWID:
    Gui, Auth:Add, Edit, x10 y30 w280 ReadOnly, %HWID%
    Gui, Auth:Add, Text, x10 y65, Ключ активации или промокод (PRO-...):
    Gui, Auth:Add, Edit, x10 y85 w280 vInputKey
    Gui, Auth:Add, Button, x10 y120 w280 h30 gCheckAuth, Разблокировать
    Gui, Auth:Show, w300 h165, Активация Kemerovo PDA
    return

    CheckAuth:
        Gui, Auth:Submit, NoHide
        Global HWID, ExpectedKey, PROMO_SECRET
        if (InputKey = ExpectedKey) {
            IniWrite, %InputKey%, settings.ini, Auth, Key
            MsgBox, 64, Успех, Ключ успешно активирован!`nПриятной игры.
            ExitApp
        } else if (InputKey != "") {
            try {
                Http := ComObjCreate("WinHttp.WinHttpRequest.5.1")
                Url := "https://kemerevopda-default-rtdb.asia-southeast1.firebasedatabase.app/promos/" . InputKey . ".json"
                Http.Open("GET", Url, false)
                Http.Send()
                Response := Http.ResponseText
                if (Response = "null") {
                    MsgBox, 16, Ошибка, Ключ не найден!
                    return
                }
                RegExMatch(Response, """uses"":\s*(-?\d+)", MatchUses)
                Uses := MatchUses1
                RegExMatch(Response, """expiry"":\s*""([^""]+)""", MatchExpiry)
                Expiry := MatchExpiry1
                if (Uses = "" || Uses == 0) {
                    MsgBox, 16, Ошибка, Промокод недействителен или исчерпан!
                    return
                }
                if (Expiry != "NONE") {
                    NowStr2 := SubStr(A_Now, 1, 12)
                    if (NowStr2 > Expiry) {
                        MsgBox, 16, Ошибка, Срок действия промокода истек!
                        return
                    }
                }
                if (Uses > 0) {
                    NewUses := Uses - 1
                    Http2 := ComObjCreate("WinHttp.WinHttpRequest.5.1")
                    Http2.Open("PATCH", Url, false)
                    Http2.SetRequestHeader("Content-Type", "application/json")
                    Http2.Send("{""uses"":" . NewUses . "}")
                }
                CH := 0
                Combined := ExpectedKey . Expiry
                Loop, % StrLen(Combined)
                    CH += Asc(SubStr(Combined, A_Index, 1))
                CH := CH * PROMO_SECRET
                FinalKey := ExpectedKey . "|" . Expiry . "|" . CH
                IniWrite, %FinalKey%, settings.ini, Auth, Key
                if (Expiry = "NONE")
                    MsgBox, 64, Активация!, Ключ активирован!`nПриятной игры.
                else {
                    FormatTime, PD, %Expiry%00, dd.MM.yyyy в HH:mm
                    MsgBox, 64, Активация!, Активирован до %PD%!`nПриятной игры.
                }
                ExitApp
            } catch e {
                MsgBox, 16, Ошибка, Нет подключения к серверу!
            }
        } else {
            MsgBox, 16, Ошибка, Введите ключ!
        }
    return

    AuthGuiClose:
        ExitApp
}

; --- ЗАГРУЖАЕМ БАЗУ ЗАКОНОВ (в auto-execute, до return!) ---
Global LawsDB := []
Global IsLawsOpen := false
if (FileExist("laws_cache.json")) {
    FileRead, LawsFileText, *P65001 laws_cache.json
    try {
        html := ComObjCreate("HTMLFile")
        html.write("<meta http-equiv=X-UA-Compatible content=IE=edge>")
        JS := html.parentWindow
        JSON := JS.JSON
        parsed := JSON.parse(LawsFileText)
        Loop % parsed.length {
            item := parsed[A_Index - 1]
            LawsDB.Push({"Category": item.category, "Article": item.article, "Title": item.title, "Text": item.text})
        }
    } catch e {
        ; Ошибка парсинга JSON
    }
}

; --- ГЛАВНОЕ МЕНЮ (GUI) ---
Global BindCommands := {}
Global IsMenuOpen := false
Global CurrentEditFile := ""
Global CapturedKey := ""

FileList := ""
Loop, *.txt
{
    FileList .= A_LoopFileName . "|"
}
if (FileList = "") {
    FileAppend,, Биндер.txt
    FileList := "Биндер.txt|"
}

Gui, +AlwaysOnTop
Gui, Font, s10, Segoe UI
Gui, Add, Text, x10 y10, Выбери профессию:
; НЕ используем gProfChanged при создании DDL — вызовем LoadBinds вручную ниже
Gui, Add, DropDownList, x10 y30 w310 vSelectedProf, %FileList%
Gui, Add, Button, x325 y29 w75 h24 gCreateProfBtn, + Новый
Gui, Add, Text, x10 y65, Список активных биндов:
Gui, Add, ListView, x10 y85 w490 h270 vBindList, Кнопка|Команда (чат)
Gui, Add, Button, x10 y360 w490 h35 gEditBindsBtn, Редактировать бинды в выбранном профиле

; Загружаем бинды первого профиля
Gui, Submit, NoHide
if (SelectedProf != "")
    LoadBinds(SelectedProf)

; Теперь включаем обработчик смены профиля
GuiControl, +gProfChanged, SelectedProf
return

; --- ГОРЯЧАЯ КЛАВИША F2 ---
F2::
    if (!Activated)
        return
    if (IsMenuOpen) {
        Gui, Hide
        IsMenuOpen := false
    } else {
        Gui, Show, w510 h410, Kemerovo PDA - Настройки
        WinSet, AlwaysOnTop, On, Kemerovo PDA - Настройки
        IsMenuOpen := true
    }
return

; --- СОЗДАНИЕ ПРОФИЛЯ ---
CreateProfBtn:
    InputBox, NewProfName, Новый профиль, Введите название профессии:, , 250, 130
    if (ErrorLevel || NewProfName = "")
        return
    if (!InStr(NewProfName, ".txt"))
        NewProfName .= ".txt"
    if (FileExist(NewProfName)) {
        MsgBox, 16, Ошибка, Такой профиль уже существует!
        return
    }
    FileAppend,, %NewProfName%
    NewFileList := ""
    Loop, *.txt
        NewFileList .= A_LoopFileName . "|"
    GuiControl,, SelectedProf, |%NewFileList%
    GuiControl,, SelectedProf, %NewProfName%
return

; --- РЕДАКТИРОВАНИЕ БИНДОВ ---
EditBindsBtn:
    Gui, Submit, NoHide
    if (SelectedProf = "") {
        MsgBox, 16, Ошибка, Профиль не выбран!
        return
    }
    Global CurrentEditFile := SelectedProf
    Global CapturedKey := ""
    Gui, Ed:Destroy
    Gui, Ed:+AlwaysOnTop
    Gui, Ed:Font, s10, Segoe UI
    Gui, Ed:Add, Text, x10 y10 w380, Редактирование: %CurrentEditFile%
    Gui, Ed:Add, ListView, x10 y30 w380 h200 vEdBindList gEdListClick, Кнопка|Команда
    Gui, Ed:Add, Button, x310 y235 w80 h25 gEdDeleteBind, Удалить
    Gui, Ed:Add, Text, x10 y270, Текст для отправки:
    Gui, Ed:Add, Edit, x110 y267 w280 vEdCmd
    Gui, Ed:Add, Text, x10 y300, Клавиша:
    Gui, Ed:Add, Hotkey, x110 y297 w280 vCapturedKey
    Gui, Ed:Add, Button, x10 y335 w185 h30 gEdAddBind, + Добавить бинд
    Gui, Ed:Add, Button, x205 y335 w185 h30 gEdSaveBtn, Сохранить и закрыть
    ; Грузим существующие бинды из файла
    Gui, Ed:Default
    Loop, Read, %CurrentEditFile%
    {
        if (A_LoopReadLine = "" || SubStr(Trim(A_LoopReadLine), 1, 1) = ";")
            continue
        parts := StrSplit(A_LoopReadLine, "::")
        if (parts.MaxIndex() >= 2) {
            eKey := Trim(parts[1])
            cmd_raw := parts[2]
            Loop, % parts.MaxIndex() - 2
                cmd_raw .= "::" . parts[A_Index + 2]
            cmd_raw := Trim(cmd_raw)
            ; Убираем обёртку SendChat("...") — фикс: без лишней точки
            cmd := RegExReplace(cmd_raw, "i)SendChat\(""(.*)""\)", "$1")
            LV_Add("", eKey, cmd)
        }
    }
    LV_ModifyCol(1, 80)
    LV_ModifyCol(2, 280)
    Gui, Ed:Show, w400 h375, Редактор биндов
return


EdListClick:
    if (A_GuiEvent != "Normal" && A_GuiEvent != "DoubleClick")
        return
    Gui, Ed:Default
    EditingRow := LV_GetNext(0)
    if (EditingRow = 0)
        return
    LV_GetText(selKey, EditingRow, 1)
    LV_GetText(selCmd, EditingRow, 2)
    CapturedKey := selKey
    GuiControl, Ed:, CapturedKey, %CapturedKey%
    GuiControl, Ed:, EdCmd, %selCmd%
return

EdAddBind:
    Gui, Ed:Submit, NoHide
    if (CapturedKey = "" || EdCmd = "") {
        MsgBox, 16, Ошибка, Захватите кнопку и введите команду!
        return
    }
    Gui, Ed:Default
    if (EditingRow > 0) {
        LV_Modify(EditingRow, "", CapturedKey, EdCmd)
        EditingRow := 0
    } else {
        LV_Add("", CapturedKey, EdCmd)
    }
    GuiControl, Ed:, EdCmd, %A_Space%
    GuiControl, Ed:, CapturedKey,
    CapturedKey := ""
return

EdDeleteBind:
    Gui, Ed:Default
    RowNumber := LV_GetNext(0)
    if (RowNumber)
        LV_Delete(RowNumber)
return

EdSaveBtn:
    Gui, Ed:Submit, NoHide
    if (CapturedKey != "" && EdCmd != "") {
        Gosub, EdAddBind
    }
    Gui, Ed:Default
    RowCount := LV_GetCount()
    FileDelete, %CurrentEditFile%
    FileAppend, `; Бинды профиля`n, %CurrentEditFile%
    Loop %RowCount%
    {
        LV_GetText(eKey, A_Index, 1)
        LV_GetText(eCmd, A_Index, 2)
        FileAppend, %eKey%::SendChat("%eCmd%")`n, %CurrentEditFile%
    }
    Gui, Ed:Destroy
    MsgBox, 64, Успех, Бинды сохранены!
    Gosub, ProfChanged
return

EdGuiClose:
    Gui, Ed:Destroy
return

; --- СМЕНА ПРОФИЛЯ ---
ProfChanged:
    Gui, Submit, NoHide
    LoadBinds(SelectedProf)
return

; --- ЗАГРУЗКА БИНДОВ ИЗ ФАЙЛА ---
LoadBinds(FileName) {
    Global BindCommands
    ; Отключаем старые хоткеи
    for key, cmd in BindCommands
        Hotkey, %key%, Off, UseErrorLevel
    BindCommands := {}
    ; Очищаем ListView главного GUI
    Gui, 1:Default
    LV_Delete()
    if (FileName = "")
        return
    Loop, Read, %FileName%
    {
        if (A_LoopReadLine = "" || SubStr(Trim(A_LoopReadLine), 1, 1) = ";")
            continue
        parts := StrSplit(A_LoopReadLine, "::")
        if (parts.MaxIndex() >= 2) {
            key := Trim(parts[1])
            cmd_raw := parts[2]
            Loop, % parts.MaxIndex() - 2
                cmd_raw .= "::" . parts[A_Index + 2]
            cmd_raw := Trim(cmd_raw)
            ; Фикс regex: убрали лишнюю точку перед \)
            cmd := RegExReplace(cmd_raw, "i)SendChat\(""(.*)""\)", "$1")
            LV_Add("", key, cmd)
            BindCommands[key] := cmd
            Hotkey, IfWinActive, ahk_exe RobloxPlayerBeta.exe
            Hotkey, %key%, ActionHandler, On UseErrorLevel
        }
    }
    LV_ModifyCol(1, "AutoHdr")
    LV_ModifyCol(2, "AutoHdr")
}

; --- ВЫПОЛНЕНИЕ БИНДА ---
ActionHandler:
    targetKey := A_ThisHotkey
    Global BindCommands
    cmd := BindCommands[targetKey]
    if (cmd != "") {
        KeyWait, Alt
        KeyWait, Ctrl
        KeyWait, Shift
        ClipSaved := ClipboardAll
        Clipboard := ""
        Clipboard := cmd
        ClipWait, 1
        SendEvent, {/}
        Sleep, 500
        SendEvent, {Backspace}
        Sleep, 50
        SendEvent, ^v
        Sleep, 150
        SendEvent, {Enter}
        Sleep, 150
        Clipboard := ClipSaved
    }
return

GuiClose:
    Gui, Hide
    IsMenuOpen := false
return

; --- СПРАВОЧНИК ЗАКОНОВ (Win+End) ---
#End::
    if (!Activated)
        return
    if (IsLawsOpen) {
        Gui, Laws:Hide
        IsLawsOpen := false
        return
    }
    Gui, Laws:Destroy
    Gui, Laws:+AlwaysOnTop
    Gui, Laws:Font, s10, Segoe UI
    Gui, Laws:Add, Text, x10 y10 w480, Справочник статей (Поиск):
    Gui, Laws:Add, Edit, x10 y30 w290 vSearchBox gSearchLaws
    Gui, Laws:Add, DropDownList, x310 y30 w180 vLawCategory gSearchLaws, Все||УК РФ|КоАП РФ|ГК РФ|ТК РФ|ФЗ О полиции|ФЗ О прокуратуре|УИК РФ|КАС РФ|УПК РФ|Другие ФЗ
    Gui, Laws:Add, ListView, x10 y60 w480 h220 vLawList gLawSelected, Категория|Статья|Название
    Gui, Laws:Add, Text, x10 y290, Текст статьи:
    Gui, Laws:Add, Edit, x10 y310 w480 h150 vLawText ReadOnly Multi
    Gui, Laws:Add, Button, x10 y470 w480 h35 gCopyLaw, Скопировать текст в буфер обмена
    LV_ModifyCol(1, 100)
    LV_ModifyCol(2, 60)
    LV_ModifyCol(3, 300)
    Gosub, SearchLaws
    Gui, Laws:Show, w500 h515, Справочник (Kemerovo PDA)
    IsLawsOpen := true
return

LawsGuiClose:
    Gui, Laws:Hide
    IsLawsOpen := false
return

SearchLaws:
    Gui, Laws:Default
    GuiControlGet, sText,, SearchBox
    GuiControlGet, sCat,, LawCategory
    LV_Delete()
    StringLower, sText, sText
    textMatches := []
    for i, law in LawsDB {
        if (sCat != "Все" && law.Category != sCat)
            continue
        lArt := law.Article
        lTitle := law.Title
        lText := law.Text
        StringLower, lArt, lArt
        StringLower, lTitle, lTitle
        StringLower, lText, lText
        if (sText = "") {
            LV_Add("", law.Category, law.Article, law.Title)
        } else if (InStr(lArt, sText) || InStr(lTitle, sText)) {
            LV_Add("", law.Category, law.Article, law.Title)
        } else if (InStr(lText, sText)) {
            textMatches.Push(law)
        }
    }
    if (sText != "" && textMatches.Length() > 0) {
        LV_Add("", "--- В тексте ---", "", "")
        for i, law in textMatches
            LV_Add("", law.Category, law.Article, law.Title)
    }
return

LawSelected:
    if (A_GuiEvent != "Normal" && A_GuiEvent != "DoubleClick")
        return
    Gui, Laws:Default
    SelRow := LV_GetNext(0)
    if (SelRow = 0)
        return
    LV_GetText(selCat, SelRow, 1)
    if (selCat = "--- В тексте ---")
        return
    LV_GetText(selArt, SelRow, 2)
    for i, law in LawsDB {
        if (law.Category = selCat && law.Article = selArt) {
            GuiControl, Laws:, LawText, % law.Text
            break
        }
    }
return

CopyLaw:
    Gui, Laws:Default
    GuiControlGet, lTxt,, LawText
    if (lTxt = "")
        return
    Clipboard := lTxt
    ToolTip, Текст скопирован!
    SetTimer, RemoveTip, 2000
return

RemoveTip:
    ToolTip
    SetTimer, RemoveTip, Off
return
