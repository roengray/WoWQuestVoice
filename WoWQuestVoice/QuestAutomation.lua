local addon = WoWQuestVoice
if not addon then return end

WoWQuestVoiceDB = WoWQuestVoiceDB or {}
if WoWQuestVoiceDB.autoAccept == nil then WoWQuestVoiceDB.autoAccept = false end
if WoWQuestVoiceDB.autoTurnIn == nil then WoWQuestVoiceDB.autoTurnIn = false end
if WoWQuestVoiceDB.showQuestTextInChat == nil then WoWQuestVoiceDB.showQuestTextInChat = true end
if WoWQuestVoiceDB.backgroundAudio == nil then WoWQuestVoiceDB.backgroundAudio = true end

local waitingForChoice = false
local pendingChoiceQuest
local pendingAutoPlayQuestID
local skipped = {}
local scheduled = false
local interactionActive = false
local interactionGUID
local interactionSerial = 0
local autoPlayClaimed = false
local bigMacNoticeShown = false

local function after(seconds, callback)
    if C_Timer and C_Timer.After then
        C_Timer.After(seconds, callback)
        return
    end

    local ticker = CreateFrame("Frame")
    local waited = 0
    ticker:SetScript("OnUpdate", function(self, delta)
        waited = waited + delta
        if waited >= seconds then
            self:SetScript("OnUpdate", nil)
            callback()
        end
    end)
end

local function optionEnabled(key)
    return WoWQuestVoiceDB and WoWQuestVoiceDB[key] and not IsShiftKeyDown()
end

local function anyAutomationEnabled()
    return optionEnabled("autoAccept") or optionEnabled("autoTurnIn")
end

local function disableBigMacAutoQuest()
    if type(BigMacSetDB) ~= "table" or not BigMacSetDB.autoQuest then return end
    BigMacSetDB.autoQuest = false
    if not bigMacNoticeShown then
        bigMacNoticeShown = true
        print("|cff80ff80WoWQuestVoice:|r 중복 동작을 막기 위해 BigMacSet의 퀘스트 자동 처리 기능을 껐습니다.")
    end
end

function addon.SetAutomationOption(key, enabled)
    if key ~= "autoAccept" and key ~= "autoTurnIn" and key ~= "showQuestTextInChat" and key ~= "backgroundAudio" then return end
    WoWQuestVoiceDB = WoWQuestVoiceDB or {}
    WoWQuestVoiceDB[key] = enabled and true or false
    if enabled then disableBigMacAutoQuest() end
    if key == "autoAccept" and not enabled then
        pendingAutoPlayQuestID = nil
    elseif key == "autoTurnIn" and not enabled then
        waitingForChoice = false
        pendingChoiceQuest = nil
    end
end

function addon.GetAutomationOption(key)
    return WoWQuestVoiceDB and WoWQuestVoiceDB[key] and true or false
end

local function currentQuestID()
    if GetQuestID then return GetQuestID() or 0 end
    return 0
end

local function gossipVisible()
    return GossipFrame and GossipFrame:IsVisible()
end

local function greetingVisible()
    return QuestFrameGreetingPanel and QuestFrameGreetingPanel:IsVisible()
end

local function questFrameVisible()
    return QuestFrame and QuestFrame:IsShown()
end

local function resetInteraction()
    interactionActive = false
    interactionGUID = nil
    autoPlayClaimed = false
    pendingAutoPlayQuestID = nil
    waitingForChoice = false
    pendingChoiceQuest = nil
    wipe(skipped)
    addon.automationQuestChainActive = false
end

local function touchInteraction()
    local guid = UnitGUID and UnitGUID("npc") or nil
    if not interactionActive or (guid and interactionGUID and guid ~= interactionGUID) then
        resetInteraction()
        interactionActive = true
        interactionGUID = guid
    elseif guid and not interactionGUID then
        interactionGUID = guid
    end
    interactionSerial = interactionSerial + 1
end

local function scheduleInteractionEnd()
    interactionSerial = interactionSerial + 1
    local serial = interactionSerial
    after(1.0, function()
        if serial ~= interactionSerial then return end
        if gossipVisible() or greetingVisible() or questFrameVisible() or scheduled then return end
        resetInteraction()
    end)
end

local function hasGossipAPI()
    return C_GossipInfo and C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetActiveQuests
end

local function selectAvailable(info)
    if hasGossipAPI() and C_GossipInfo.SelectAvailableQuest then
        C_GossipInfo.SelectAvailableQuest(info.questID or info.index)
    elseif SelectGossipAvailableQuest then
        SelectGossipAvailableQuest(info.index)
    end
end

local function selectActive(info)
    if hasGossipAPI() and C_GossipInfo.SelectActiveQuest then
        C_GossipInfo.SelectActiveQuest(info.questID or info.index)
    elseif SelectGossipActiveQuest then
        SelectGossipActiveQuest(info.index)
    end
end

local function gossipQuests()
    local available, active = {}, {}
    if hasGossipAPI() then
        for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            if not info.isIgnored then available[#available + 1] = info end
        end
        for _, info in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            if not info.isIgnored then active[#active + 1] = info end
        end
        return available, active
    end

    if GetNumGossipAvailableQuests then
        for index = 1, GetNumGossipAvailableQuests() do
            available[#available + 1] = { index = index }
        end
    end
    if GetNumGossipActiveQuests then
        for index = 1, GetNumGossipActiveQuests() do
            active[#active + 1] = { index = index }
        end
    end
    return available, active
end

local function greetingQuests()
    local available, active = {}, {}
    local numActive = GetNumActiveQuests and GetNumActiveQuests() or 0
    for index = 1, numActive do
        local _, isComplete = GetActiveTitle(index)
        active[#active + 1] = {
            index = index,
            questID = GetActiveQuestID and GetActiveQuestID(index),
            isComplete = isComplete,
        }
    end

    local numAvailable = GetNumAvailableQuests and GetNumAvailableQuests() or 0
    for index = 1, numAvailable do
        available[#available + 1] = {
            index = index,
            questID = GetAvailableQuestID and GetAvailableQuestID(index),
        }
    end
    return available, active
end

local function isSkipped(info)
    local questID = info and info.questID
    return questID and skipped[questID]
end

local function processList(available, active, availableSelector, activeSelector)
    if optionEnabled("autoTurnIn") then
        for _, info in ipairs(active) do
            if info.isComplete ~= false and not isSkipped(info) then
                activeSelector(info)
                return true
            end
        end
    end

    if optionEnabled("autoAccept") then
        for _, info in ipairs(available) do
            if not isSkipped(info) then
                availableSelector(info)
                return true
            end
        end
    end
    return false
end

local function processNPCQuests()
    if waitingForChoice or not anyAutomationEnabled() then return end

    if gossipVisible() then
        local available, active = gossipQuests()
        processList(available, active, selectAvailable, selectActive)
    elseif greetingVisible() then
        local available, active = greetingQuests()
        processList(available, active, function(info)
            SelectAvailableQuest(info.index)
        end, function(info)
            SelectActiveQuest(info.index)
        end)
    end
end

local function scheduleProcess()
    if scheduled or waitingForChoice or not anyAutomationEnabled() then return end
    scheduled = true
    after(0.12, function()
        scheduled = false
        processNPCQuests()
    end)
end

local function completeReward()
    local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
    if choices > 1 then
        waitingForChoice = true
        pendingChoiceQuest = currentQuestID()
        print("|cffffcc00WoWQuestVoice:|r 보상 아이템을 고르면 남은 퀘스트를 이어서 처리합니다.")
        return
    end

    waitingForChoice = false
    pendingChoiceQuest = nil
    GetQuestReward(choices == 1 and 1 or 0)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("GOSSIP_SHOW")
events:RegisterEvent("QUEST_GREETING")
events:RegisterEvent("QUEST_DETAIL")
events:RegisterEvent("QUEST_PROGRESS")
events:RegisterEvent("QUEST_COMPLETE")
events:RegisterEvent("QUEST_ACCEPT_CONFIRM")
events:RegisterEvent("QUEST_FINISHED")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("GOSSIP_CLOSED")
pcall(events.RegisterEvent, events, "QUEST_TURNED_IN")

events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == "BigMacSet" and (addon.GetAutomationOption("autoAccept") or addon.GetAutomationOption("autoTurnIn")) then
            disableBigMacAutoQuest()
        end
        return
    end

    if event == "GOSSIP_CLOSED" then
        scheduleInteractionEnd()
        return
    end

    if not anyAutomationEnabled() then return end
    disableBigMacAutoQuest()

    if event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
        touchInteraction()
        if waitingForChoice then return end
        scheduleProcess()
        return
    end

    if event == "QUEST_DETAIL" then
        touchInteraction()
        if optionEnabled("autoAccept") then
            pendingAutoPlayQuestID = currentQuestID()
            AcceptQuest()
        end
        return
    end

    if event == "QUEST_ACCEPT_CONFIRM" then
        if optionEnabled("autoAccept") then ConfirmAcceptQuest() end
        return
    end

    if event == "QUEST_PROGRESS" then
        touchInteraction()
        if optionEnabled("autoTurnIn") then
            if IsQuestCompletable() then
                CompleteQuest()
            else
                local questID = currentQuestID()
                if questID ~= 0 then skipped[questID] = true end
                CloseQuest()
                scheduleProcess()
            end
        end
        return
    end

    if event == "QUEST_COMPLETE" then
        touchInteraction()
        if optionEnabled("autoTurnIn") then completeReward() end
        return
    end

    if event == "QUEST_ACCEPTED" then
        if optionEnabled("autoAccept") and pendingAutoPlayQuestID and pendingAutoPlayQuestID ~= 0 then
            local acceptedQuestID = pendingAutoPlayQuestID
            pendingAutoPlayQuestID = nil
            if not autoPlayClaimed then
                autoPlayClaimed = true
                addon.automationQuestChainActive = true
                addon.PlayQuest(acceptedQuestID)
            end
        end
        scheduleProcess()
        return
    end

    if event == "QUEST_TURNED_IN" then
        waitingForChoice = false
        pendingChoiceQuest = nil
        scheduleProcess()
        return
    end

    if event == "QUEST_FINISHED" then
        if waitingForChoice and pendingChoiceQuest and pendingChoiceQuest ~= 0 then
            skipped[pendingChoiceQuest] = true
            waitingForChoice = false
            pendingChoiceQuest = nil
        end
        scheduleProcess()
        scheduleInteractionEnd()
    end
end)
