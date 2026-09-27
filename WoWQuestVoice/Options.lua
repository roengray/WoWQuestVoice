local addon = WoWQuestVoice
if not addon then return end

local window
local checks = {}
local audioStatus

local function collectorToolsEnabled()
    return WoWQuestVoiceDB and WoWQuestVoiceDB.collectorToolsEnabled == true
end

local optionSpecs = {
    {
        key = "autoAccept",
        title = "퀘스트 자동 수락 + 첫 퀘스트 음성 재생",
        help = "NPC가 주는 퀘스트를 자동으로 받습니다. 여러 퀘스트가 있으면 처음 받은 퀘스트 음성만 재생합니다.",
    },
    {
        key = "autoTurnIn",
        title = "완료한 퀘스트 자동 보고",
        help = "완료 가능한 퀘스트를 자동으로 보고합니다. 선택 보상이 두 개 이상이면 직접 고를 때까지 기다립니다.",
    },
    {
        key = "showQuestTextInChat",
        title = "퀘스트 내용을 대화창에 표시",
        help = "퀘스트를 열거나 받을 때 퀘스트 ID, 제목과 본문을 대화창에 자동으로 표시합니다.",
    },
    {
        key = "backgroundAudio",
        title = "음성 재생 중 알트탭 소리 유지",
        help = "퀘스트 음성을 읽는 동안만 WoW의 백그라운드 소리를 켜고, 재생이 끝나면 기존 설정으로 되돌립니다.",
    },
}

local function refresh()
    for key, check in pairs(checks) do
        check:SetChecked(addon.GetAutomationOption and addon.GetAutomationOption(key))
    end
    if audioStatus and addon.GetAudioStats then
        local mapped, unique = addon.GetAudioStats()
        audioStatus:SetText(string.format("현재 게임에 로드된 연결: 퀘스트 %d개 · 음성 %d개", mapped, unique))
    end
end

local function createOptionRow(parent, spec, y)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(28, 28)
    check:SetPoint("TOPLEFT", 22, y)

    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", check, "RIGHT", 4, 1)
    title:SetText(spec.title)
    title:SetTextColor(1, 0.82, 0)

    local help = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 32, -1)
    help:SetWidth(520)
    help:SetJustifyH("LEFT")
    help:SetText(spec.help)
    help:SetTextColor(0.78, 0.78, 0.78)

    check:SetScript("OnClick", function(self)
        addon.SetAutomationOption(spec.key, self:GetChecked())
        print(string.format(
            "|cff80ff80WoWQuestVoice:|r %s: %s",
            spec.title,
            self:GetChecked() and "켜짐" or "꺼짐"
        ))
    end)

    checks[spec.key] = check
end

local function buildWindow()
    if window then return window end

    window = CreateFrame("Frame", "WoWQuestVoiceOptionsWindow", UIParent, "BasicFrameTemplateWithInset")
    window:SetSize(620, collectorToolsEnabled() and 575 or 500)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetClampedToScreen(true)
    window:SetScript("OnShow", refresh)
    window:Hide()

    if window.TitleText then
        window.TitleText:SetText("WoWQuestVoice 설정")
    end
    if UISpecialFrames then
        table.insert(UISpecialFrames, "WoWQuestVoiceOptionsWindow")
    end

    local note = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    note:SetPoint("TOPLEFT", 22, -42)
    note:SetWidth(570)
    note:SetJustifyH("LEFT")
    note:SetText("퀘스트 음성과 NPC 자동 처리 기능을 설정합니다. Shift 키를 누른 채 NPC와 대화하면 이번 대화의 자동 처리를 건너뜁니다.")

    createOptionRow(window, optionSpecs[1], -88)
    createOptionRow(window, optionSpecs[2], -164)
    createOptionRow(window, optionSpecs[3], -240)
    createOptionRow(window, optionSpecs[4], -316)

    audioStatus = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    audioStatus:SetPoint("TOPLEFT", 22, -392)
    audioStatus:SetWidth(360)
    audioStatus:SetJustifyH("LEFT")

    local reload = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    reload:SetSize(190, 26)
    reload:SetPoint("TOPRIGHT", -22, -384)
    reload:SetText("새 음성 목록 불러오기")
    reload:SetScript("OnClick", function()
        print("|cff80ff80WoWQuestVoice:|r 최신 음성 목록을 다시 불러옵니다.")
        ReloadUI()
    end)

    if collectorToolsEnabled() then
        local collect = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        collect:SetSize(230, 26)
        collect:SetPoint("TOPLEFT", 22, -432)
        collect:SetText("포에버 신규 ID·제목 일괄 확인")
        collect:SetScript("OnClick", function()
            if addon.StartQuestScan then addon.StartQuestScan("custom") end
        end)

        local scanStatus = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        scanStatus:SetSize(120, 26)
        scanStatus:SetPoint("LEFT", collect, "RIGHT", 8, 0)
        scanStatus:SetText("수집 상태")
        scanStatus:SetScript("OnClick", function()
            if addon.PrintQuestScanStatus then addon.PrintQuestScanStatus() end
        end)

        local scanStop = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        scanStop:SetSize(120, 26)
        scanStop:SetPoint("LEFT", scanStatus, "RIGHT", 8, 0)
        scanStop:SetText("수집 중단")
        scanStop:SetScript("OnClick", function()
            if addon.StopQuestScan then addon.StopQuestScan() end
        end)

        local collectHelp = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        collectHelp:SetPoint("TOPLEFT", 22, -466)
        collectHelp:SetWidth(570)
        collectHelp:SetJustifyH("LEFT")
        collectHelp:SetText("캐릭터로 직접 열지 않고 신규 ID의 제목과 목표를 확인합니다. 서버 API상 전체 본문은 직접 열린 퀘스트만 제공될 수 있습니다.")
        collectHelp:SetTextColor(0.72, 0.85, 1)
    end

    local conflict = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    conflict:SetPoint("BOTTOMLEFT", 22, 22)
    conflict:SetWidth(570)
    conflict:SetJustifyH("LEFT")
    conflict:SetText("자동 기능을 켜면 중복 동작 방지를 위해 BigMacSet의 기존 퀘스트 자동 처리 옵션은 꺼집니다.")
    conflict:SetTextColor(1, 0.55, 0.2)

    refresh()

    return window
end

function addon.OpenOptions()
    local frame = buildWindow()
    if frame:IsShown() then
        frame:Hide()
    else
        refresh()
        frame:Show()
        frame:Raise()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self)
    buildWindow()
    self:UnregisterAllEvents()
end)
