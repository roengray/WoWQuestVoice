WoWQuestVoice = WoWQuestVoice or {}
local addon = WoWQuestVoice

local musicVolumeCVar = "Sound_MusicVolume"
local sfxVolumeCVar = "Sound_SFXVolume"
local backgroundSoundCVar = "Sound_EnableSoundWhenGameIsInBG"
local musicDuckFactor = 0.30
local sfxDuckFactor = 0.40
local activeSoundDuration = 0
local questSounds = WoWQuestVoiceQuestAudio or {}
local soundHandle
local activeQuestID
local activeQuestSource
local elapsed = 0
local soundCheckElapsed = 0
local currentQuest
local mapPlayButton
local mapStopButton
local mapButtonsCreated = false
local mapHookInstalled = false
local lastAnnouncedQuestID
local scanState
local scanToken = 0
local scanDelay = 0.75
local frame = CreateFrame("Frame", "WoWQuestVoiceFrame")
local playbackMonitor = CreateFrame("Frame")
local refreshMapButtons
local originalBackgroundSound
local backgroundSoundOverridden = false

local function getQuestSound(questID, source)
    local sounds = questID and questSounds[questID]
    return sounds and sounds[source or "accept"] or nil
end

function addon.HasQuestAudio(questID, source)
    return getQuestSound(questID, source or "accept") ~= nil
end

function addon.GetAudioStats()
    local mapped = 0
    local paths = {}
    for _, sources in pairs(questSounds) do
        local sound = sources and sources.accept
        if sound and sound.path then
            mapped = mapped + 1
            paths[sound.path] = true
        end
    end
    local unique = 0
    for _ in pairs(paths) do unique = unique + 1 end
    return mapped, unique
end

local function restoreMusicVolume()
    if WoWQuestVoiceDB and WoWQuestVoiceDB.musicDucked then
        if WoWQuestVoiceDB.originalMusicVolume then
            SetCVar(musicVolumeCVar, WoWQuestVoiceDB.originalMusicVolume)
        end
        if WoWQuestVoiceDB.originalSFXVolume then
            SetCVar(sfxVolumeCVar, WoWQuestVoiceDB.originalSFXVolume)
        end
        WoWQuestVoiceDB.originalMusicVolume = nil
        WoWQuestVoiceDB.originalSFXVolume = nil
        WoWQuestVoiceDB.musicDucked = nil
    end
end

local function restoreBackgroundSound()
    if backgroundSoundOverridden and originalBackgroundSound ~= nil and SetCVar then
        SetCVar(backgroundSoundCVar, originalBackgroundSound)
    end
    originalBackgroundSound = nil
    backgroundSoundOverridden = false
end

local function enableBackgroundSoundForPlayback()
    if not WoWQuestVoiceDB or WoWQuestVoiceDB.backgroundAudio == false then return end
    if not GetCVar or not SetCVar then return end
    local current = GetCVar(backgroundSoundCVar)
    if current ~= nil and tostring(current) ~= "1" then
        originalBackgroundSound = current
        backgroundSoundOverridden = true
        SetCVar(backgroundSoundCVar, 1)
    end
end

local function lowerMusicVolume()
    WoWQuestVoiceDB = WoWQuestVoiceDB or {}
    if WoWQuestVoiceDB.musicDucked then return end

    local currentVolume = tonumber(GetCVar(musicVolumeCVar))
    local currentSFXVolume = tonumber(GetCVar(sfxVolumeCVar))
    if not currentVolume and not currentSFXVolume then return end

    if currentVolume then
        WoWQuestVoiceDB.originalMusicVolume = currentVolume
        SetCVar(musicVolumeCVar, math.max(0, currentVolume * musicDuckFactor))
    end
    if currentSFXVolume then
        WoWQuestVoiceDB.originalSFXVolume = currentSFXVolume
        SetCVar(sfxVolumeCVar, math.max(0, currentSFXVolume * sfxDuckFactor))
    end
    WoWQuestVoiceDB.musicDucked = true
end

local function stopAudio(message, alreadyStopped)
    local handle = soundHandle
    soundHandle = nil
    activeQuestID = nil
    activeQuestSource = nil
    if handle and not alreadyStopped then
        pcall(StopSound, handle)
    end
    playbackMonitor:Hide()
    elapsed = 0
    soundCheckElapsed = 0
    restoreMusicVolume()
    restoreBackgroundSound()
    if refreshMapButtons then refreshMapButtons() end
end

local function isSoundPlaying(handle)
    if C_Sound and C_Sound.IsPlaying then
        local ok, playing = pcall(C_Sound.IsPlaying, handle)
        if ok then return playing and true or false end
    end
    if IsSoundHandlePlaying then
        local ok, playing = pcall(IsSoundHandlePlaying, handle)
        if ok then return playing and true or false end
    end
    return nil
end

playbackMonitor:SetScript("OnUpdate", function(_, delta)
    if not soundHandle then
        playbackMonitor:Hide()
        return
    end

    elapsed = elapsed + delta
    soundCheckElapsed = soundCheckElapsed + delta
    if elapsed >= 0.5 and soundCheckElapsed >= 0.2 then
        soundCheckElapsed = 0
        if isSoundPlaying(soundHandle) == false then
            stopAudio("재생 완료", true)
            return
        end
    end

    -- 일부 클라이언트에는 재생 상태 확인 API가 없으므로 등록된 길이를
    -- 안전망으로 사용한다. 파일 길이보다 조금 늦게 상태를 되돌린다.
    if activeSoundDuration > 0 and elapsed >= activeSoundDuration + 1.0 then
        stopAudio("재생 완료")
    end
end)
playbackMonitor:Hide()

local function playAudio(overrideQuestID)
    stopAudio()
    local selectedSound
    local selectedQuestID
    local selectedSource
    if type(overrideQuestID) == "number" and questSounds[overrideQuestID] then
        selectedQuestID = overrideQuestID
        selectedSource = "accept"
        selectedSound = getQuestSound(selectedQuestID, selectedSource)
    elseif currentQuest and questSounds[currentQuest.id] then
        selectedQuestID = currentQuest.id
        selectedSource = currentQuest.source
        selectedSound = getQuestSound(selectedQuestID, selectedSource)
    end

    if not selectedSound or not selectedSound.path then
        print("|cffffcc00WoWQuestVoice:|r 이 퀘스트에는 아직 연결된 음성이 없습니다.")
        if refreshMapButtons then refreshMapButtons() end
        return false
    end

    activeSoundDuration = tonumber(selectedSound.duration) or 0
    local willPlay, handle = PlaySoundFile(selectedSound.path, "Master")
    if not willPlay or not handle then
        print("|cffff8080WoWQuestVoice:|r 재생 실패. 게임 재시작 후 전체 소리 설정을 확인하세요.")
        if refreshMapButtons then refreshMapButtons() end
        return false
    end
    soundHandle = handle
    activeQuestID = selectedQuestID
    activeQuestSource = selectedSource
    enableBackgroundSoundForPlayback()
    lowerMusicVolume()
    elapsed = 0
    soundCheckElapsed = 0
    playbackMonitor:Show()
    if refreshMapButtons then refreshMapButtons() end
    return true
end

addon.PlayQuest = playAudio
addon.StopAudio = stopAudio
addon.IsPlaying = function()
    return soundHandle ~= nil
end

local function showCurrentQuestInChat()
    if not currentQuest then
        print("|cffffcc00WoWQuestVoice:|r 현재 선택된 퀘스트가 없습니다.")
        return
    end

    print(string.format("|cff80ff80WoWQuestVoice:|r ID %d · %s", currentQuest.id, currentQuest.title))
    if currentQuest.text and currentQuest.text ~= "" then
        print("|cffdddddd본문:|r " .. currentQuest.text)
    else
        print("|cffffcc00본문을 읽지 못했습니다.|r")
    end
end

local function saveQuest(questID, title, text, source)
    if not questID or questID == 0 then return end

    if soundHandle
        and (activeQuestID ~= questID or activeQuestSource ~= source)
        and not addon.automationQuestChainActive then
        stopAudio("선택한 퀘스트 변경")
    end

    currentQuest = {
        id = questID,
        title = title or "",
        text = text or "",
        source = source,
    }

    WoWQuestVoiceDB = WoWQuestVoiceDB or {}
    WoWQuestVoiceDB.capturedQuests = WoWQuestVoiceDB.capturedQuests or {}
    WoWQuestVoiceDB.capturedQuests[questID] = WoWQuestVoiceDB.capturedQuests[questID] or {}
    WoWQuestVoiceDB.capturedQuests[questID][source] = {
        title = currentQuest.title,
        text = currentQuest.text,
    }

    if lastAnnouncedQuestID ~= questID then
        lastAnnouncedQuestID = questID
        if not WoWQuestVoiceDB or WoWQuestVoiceDB.showQuestTextInChat ~= false then
            showCurrentQuestInChat()
        end
    end
    if refreshMapButtons then refreshMapButtons() end
end


local function captureMapQuest(questID)
    if not questID or questID == 0 then return end

    local title = ""
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        title = C_QuestLog.GetTitleForQuestID(questID) or ""
    end

    local questLogIndex
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        questLogIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    elseif GetQuestLogIndexByID then
        questLogIndex = GetQuestLogIndexByID(questID)
    end

    local text = ""
    if questLogIndex and questLogIndex > 0 then
        if C_QuestLog and C_QuestLog.SetSelectedQuest then
            C_QuestLog.SetSelectedQuest(questID)
        elseif SelectQuestLogEntry then
            SelectQuestLogEntry(questLogIndex)
        end
        if GetQuestLogQuestText then
            text = GetQuestLogQuestText() or ""
        end
        if title == "" and GetQuestLogTitle then
            title = GetQuestLogTitle(questLogIndex) or ""
        end
    end

    saveQuest(questID, title, text, "accept")
end

local function captureNpcQuest(source)
    local questID = GetQuestID and GetQuestID() or 0
    if not questID or questID == 0 then return end

    local title = GetTitleText and GetTitleText() or ""
    local text = ""
    if source == "accept" and GetQuestText then
        text = GetQuestText() or ""
    elseif source == "progress" and GetProgressText then
        text = GetProgressText() or ""
    elseif source == "complete" and GetRewardText then
        text = GetRewardText() or ""
    end
    saveQuest(questID, title, text, source)
end

local function copyQuestObjectives(questID)
    local copied = {}
    if not C_QuestLog or not C_QuestLog.GetQuestObjectives then return copied end

    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if type(objectives) ~= "table" then return copied end
    for index, objective in ipairs(objectives) do
        copied[index] = {
            text = objective.text or "",
            type = objective.type or "",
            numFulfilled = objective.numFulfilled or 0,
            numRequired = objective.numRequired or 0,
            finished = objective.finished and true or false,
        }
    end
    return copied
end

local function readLoadedQuest(questID, success)
    local title = ""
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        title = C_QuestLog.GetTitleForQuestID(questID) or ""
    end

    local description = ""
    local objectiveSummary = ""
    local questLogIndex
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        questLogIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    elseif GetQuestLogIndexByID then
        questLogIndex = GetQuestLogIndexByID(questID)
    end
    if questLogIndex and questLogIndex > 0 and GetQuestLogQuestText then
        local ok, loadedDescription, loadedObjectives = pcall(GetQuestLogQuestText, questLogIndex)
        if ok then
            description = loadedDescription or ""
            objectiveSummary = loadedObjectives or ""
        end
    end

    -- Forever keeps the full query response internally even for quests that
    -- are not in the player's log. Some client builds expose that response
    -- through the selected-quest slot after RequestLoadQuestByID completes.
    -- Restore the user's selection immediately so a background scan does not
    -- disturb the quest map.
    if (not questLogIndex or questLogIndex == 0)
        and C_QuestLog and C_QuestLog.SetSelectedQuest and GetQuestLogQuestText then
        local previousQuestID = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest() or 0
        local selected = pcall(C_QuestLog.SetSelectedQuest, questID)
        if selected then
            local ok, loadedDescription, loadedObjectives = pcall(GetQuestLogQuestText)
            if ok then
                description = loadedDescription or ""
                objectiveSummary = loadedObjectives or ""
            end
        end
        if previousQuestID and previousQuestID > 0 then
            pcall(C_QuestLog.SetSelectedQuest, previousQuestID)
        end
    end

    -- Diagnostic probe: newer clients sometimes accept a quest ID here even
    -- though the documented argument is a quest-log index. Only try IDs that
    -- cannot be mistaken for a normal quest-log row.
    local probeDescription = ""
    local probeObjectives = ""
    if (not questLogIndex or questLogIndex == 0) and questID > 100 and GetQuestLogQuestText then
        local ok, loadedDescription, loadedObjectives = pcall(GetQuestLogQuestText, questID)
        if ok then
            probeDescription = loadedDescription or ""
            probeObjectives = loadedObjectives or ""
        end
    end

    return {
        success = success and true or false,
        title = title,
        description = description,
        objectiveSummary = objectiveSummary,
        probeDescription = probeDescription,
        probeObjectives = probeObjectives,
        objectives = copyQuestObjectives(questID),
        capturedAt = date("!%Y-%m-%dT%H:%M:%SZ"),
    }
end

local function printScanStatus()
    local saved = WoWQuestVoiceDB and WoWQuestVoiceDB.bulkScan
    if not saved then
        print("|cffffcc00WoWQuestVoice:|r 대량 수집 기록이 없습니다.")
        return
    end
    print(string.format(
        "|cff80ff80WoWQuestVoice:|r 수집 %d/%d · 응답 %d · 제목 %d · 본문 %d · 목표 %d%s",
        (saved.nextIndex or 1) - 1,
        saved.total or 0,
        saved.successCount or 0,
        saved.titleCount or 0,
        saved.descriptionCount or 0,
        saved.objectiveCount or 0,
        saved.running and " · 실행 중" or ""
    ))
end

local scanNext

local function finishScan()
    if not scanState then return end
    local finished = scanState
    scanState.running = false
    scanState.finishedAt = date("!%Y-%m-%dT%H:%M:%SZ")
    scanState = nil
    print("|cff80ff80WoWQuestVoice:|r 퀘스트 ID 일괄 조회가 끝났습니다. /wqv scan status 로 결과를 확인하세요.")
    printScanStatus()
    if (finished.descriptionCount or 0) < (finished.successCount or 0) then
        print(string.format(
            "|cffffcc00WoWQuestVoice:|r 서버 API 제한으로 본문은 %d/%d개만 수집됐습니다. 나머지는 제목·목표 확인 완료 상태입니다.",
            finished.descriptionCount or 0,
            finished.successCount or 0
        ))
    end
end

local function collectScanResult(questID, success, token)
    if not scanState or not scanState.running then return end
    if token ~= scanToken or scanState.currentQuestID ~= questID then return end

    local record = readLoadedQuest(questID, success)
    scanState.records[questID] = record
    if record.success then scanState.successCount = scanState.successCount + 1 end
    if record.title ~= "" then scanState.titleCount = scanState.titleCount + 1 end
    if record.description ~= "" or record.probeDescription ~= "" then
        scanState.descriptionCount = scanState.descriptionCount + 1
    end
    if #record.objectives > 0 or record.objectiveSummary ~= "" or record.probeObjectives ~= "" then
        scanState.objectiveCount = scanState.objectiveCount + 1
    end

    scanState.nextIndex = scanState.nextIndex + 1
    scanState.currentQuestID = nil
    if ((scanState.nextIndex - 1) % 100) == 0 then printScanStatus() end
    C_Timer.After(scanDelay, scanNext)
end

scanNext = function()
    if not scanState or not scanState.running then return end
    local questID = scanState.ids[scanState.nextIndex]
    if not questID then
        finishScan()
        return
    end

    scanToken = scanToken + 1
    local token = scanToken
    scanState.currentQuestID = questID
    if C_QuestLog and C_QuestLog.RequestLoadQuestByID then
        C_QuestLog.RequestLoadQuestByID(questID)
        C_Timer.After(3.0, function()
            collectScanResult(questID, HaveQuestData and HaveQuestData(questID), token)
        end)
    else
        collectScanResult(questID, false, token)
    end
end

local function startScan(mode, requestedQuestID)
    if scanState and scanState.running then
        print("|cffffcc00WoWQuestVoice:|r 이미 수집 중입니다.")
        printScanStatus()
        return
    end
    if not C_QuestLog or not C_QuestLog.RequestLoadQuestByID then
        print("|cffff8080WoWQuestVoice:|r 이 클라이언트에는 퀘스트 자동 요청 API가 없습니다.")
        return
    end

    local ids
    if mode == "single" and requestedQuestID then
        ids = { requestedQuestID }
    elseif mode == "test" then
        ids = { 86585, 93746, 5545 }
        if currentQuest and currentQuest.id then table.insert(ids, 1, currentQuest.id) end
    elseif mode == "custom" then
        ids = {}
        for _, questID in ipairs(WoWQuestVoiceQuestIDs or {}) do
            if questID > 10000 then
                table.insert(ids, questID)
            end
        end
    else
        ids = WoWQuestVoiceQuestIDs
    end
    if type(ids) ~= "table" or #ids == 0 then
        print("|cffff8080WoWQuestVoice:|r Forever 퀘스트 ID 목록이 없습니다.")
        return
    end

    WoWQuestVoiceDB = WoWQuestVoiceDB or {}
    WoWQuestVoiceDB.bulkScan = {
        source = mode == "single" and "single quest"
            or (mode == "test" and "test"
            or (mode == "custom" and "Forever custom IDs" or "60.tools Forever index")),
        startedAt = date("!%Y-%m-%dT%H:%M:%SZ"),
        running = true,
        ids = ids,
        total = #ids,
        nextIndex = 1,
        successCount = 0,
        titleCount = 0,
        descriptionCount = 0,
        objectiveCount = 0,
        records = {},
    }
    scanState = WoWQuestVoiceDB.bulkScan
    print(string.format("|cff80ff80WoWQuestVoice:|r %d개 퀘스트 자동 수집을 시작합니다.", #ids))
    scanNext()
end

local function stopScan()
    scanToken = scanToken + 1
    if scanState then scanState.running = false end
    scanState = nil
    print("|cffffcc00WoWQuestVoice:|r 대량 수집을 중지했습니다.")
    printScanStatus()
end

local function resumeScan()
    if scanState and scanState.running then
        print("|cffffcc00WoWQuestVoice:|r 이미 수집 중입니다.")
        return
    end
    local saved = WoWQuestVoiceDB and WoWQuestVoiceDB.bulkScan
    if not saved or type(saved.ids) ~= "table" or not saved.nextIndex or saved.nextIndex > #saved.ids then
        print("|cffffcc00WoWQuestVoice:|r 이어갈 수집 기록이 없습니다.")
        return
    end
    saved.running = true
    scanState = saved
    print(string.format(
        "|cff80ff80WoWQuestVoice:|r %d/%d 다음부터 자동 수집을 이어갑니다.",
        saved.nextIndex,
        #saved.ids
    ))
    scanNext()
end

addon.StartQuestScan = startScan
addon.StopQuestScan = stopScan
addon.ResumeQuestScan = resumeScan
addon.PrintQuestScanStatus = printScanStatus

local function showMapButtonTooltip(button, action)
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText("퀘스트 음성 " .. action)
    if currentQuest then
        GameTooltip:AddLine(string.format("[%d] %s", currentQuest.id, currentQuest.title), 1, 1, 1)
    end
    GameTooltip:AddLine("이 퀘스트의 실제 한국어 음성을 재생합니다.", 0.8, 1, 0.8, true)
    GameTooltip:Show()
end

refreshMapButtons = function()
    if not mapPlayButton or not mapStopButton then return end

    local available = currentQuest and getQuestSound(currentQuest.id, currentQuest.source) ~= nil
    if not available then
        mapPlayButton:Hide()
        mapStopButton:Hide()
        return
    end

    mapPlayButton:Show()
    mapStopButton:Show()
    mapPlayButton:SetText(soundHandle and "재생 중" or "재생")
    mapPlayButton:SetEnabled(not soundHandle)
    mapStopButton:SetEnabled(soundHandle ~= nil)
end

local function createMapButtons()
    if mapButtonsCreated then return end
    if not QuestMapFrame or not QuestMapFrame.DetailsFrame then return end

    local detailsFrame = QuestMapFrame.DetailsFrame
    local backFrame = detailsFrame.BackFrame or detailsFrame
    local backButton = backFrame.BackButton
    if not backButton then return end

    mapPlayButton = CreateFrame("Button", "WoWQuestVoiceMapPlayButton", backFrame, "UIPanelButtonTemplate")
    mapPlayButton:SetSize(88, 22)
    mapPlayButton:SetPoint("LEFT", backButton, "RIGHT", 14, 0)
    mapPlayButton:SetText("재생")
    mapPlayButton:SetScript("OnClick", playAudio)
    mapPlayButton:SetScript("OnEnter", function(self) showMapButtonTooltip(self, "재생") end)
    mapPlayButton:SetScript("OnLeave", GameTooltip_Hide)

    mapStopButton = CreateFrame("Button", "WoWQuestVoiceMapStopButton", backFrame, "UIPanelButtonTemplate")
    mapStopButton:SetSize(88, 22)
    mapStopButton:SetPoint("LEFT", mapPlayButton, "RIGHT", 6, 0)
    mapStopButton:SetText("정지")
    mapStopButton:SetScript("OnClick", function() stopAudio() end)
    mapStopButton:SetScript("OnEnter", function(self) showMapButtonTooltip(self, "정지") end)
    mapStopButton:SetScript("OnLeave", GameTooltip_Hide)

    if not mapHookInstalled and QuestMapFrame_ShowQuestDetails then
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", function(questID)
            captureMapQuest(questID)
        end)
        mapHookInstalled = true
    end

    detailsFrame:HookScript("OnShow", function(self)
        captureMapQuest(self.questID)
    end)
    mapButtonsCreated = true
    refreshMapButtons()
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("QUEST_PROGRESS")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("QUEST_DATA_LOAD_RESULT")
frame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        restoreMusicVolume()
        if WoWQuestVoiceDB and WoWQuestVoiceDB.bulkScan and WoWQuestVoiceDB.bulkScan.running then
            WoWQuestVoiceDB.bulkScan.running = false
            print("|cffffcc00WoWQuestVoice:|r 이전 자동 수집이 중단되었습니다. /wqv scan resume 으로 이어갈 수 있습니다.")
        end
        createMapButtons()
        print("|cff80ff80WoWQuestVoice:|r 음성이 연결된 퀘스트에서 재생·정지 버튼을 사용할 수 있습니다.")
    elseif event == "PLAYER_LOGOUT" then
        restoreMusicVolume()
        restoreBackgroundSound()
    elseif event == "ADDON_LOADED" then
        WoWQuestVoiceDB = WoWQuestVoiceDB or {}
        if WoWQuestVoiceDB.backgroundAudio == nil then WoWQuestVoiceDB.backgroundAudio = true end
        createMapButtons()
    elseif event == "QUEST_DETAIL" then
        captureNpcQuest("accept")
    elseif event == "QUEST_PROGRESS" then
        captureNpcQuest("progress")
    elseif event == "QUEST_COMPLETE" then
        captureNpcQuest("complete")
    elseif event == "QUEST_DATA_LOAD_RESULT" then
        local questID, success = ...
        if scanState and scanState.running and scanState.currentQuestID == questID then
            collectScanResult(questID, success, scanToken)
        end
    end
end)
SLASH_WOWQUESTVOICE1 = "/wqv"
SLASH_WOWQUESTVOICE2 = "/wvt"
SlashCmdList.WOWQUESTVOICE = function(message)
    local command = (message or ""):match("^%s*(.-)%s*$"):lower()
    local requestedQuestID = tonumber(command:match("^play%s+(%d+)$"))
    local requestedScanID = tonumber(command:match("^scan%s+id%s+(%d+)$"))
    local collectorToolsEnabled = WoWQuestVoiceDB and WoWQuestVoiceDB.collectorToolsEnabled == true
    local hasScanRecord = WoWQuestVoiceDB and WoWQuestVoiceDB.bulkScan ~= nil
    if requestedQuestID then playAudio(requestedQuestID)
    elseif requestedScanID and collectorToolsEnabled then startScan("single", requestedScanID)
    elseif command == "stop" then stopAudio()
    elseif command == "play" then playAudio()
    elseif command == "info" then showCurrentQuestInChat()
    elseif command == "collector on" then
        WoWQuestVoiceDB = WoWQuestVoiceDB or {}
        WoWQuestVoiceDB.collectorToolsEnabled = true
        print("|cff80ff80WoWQuestVoice:|r 제작자용 수집 도구를 켰습니다. /reload 후 설정 화면에 표시됩니다.")
    elseif command == "collector off" then
        WoWQuestVoiceDB = WoWQuestVoiceDB or {}
        WoWQuestVoiceDB.collectorToolsEnabled = false
        print("|cff80ff80WoWQuestVoice:|r 제작자용 수집 도구를 숨겼습니다. /reload 후 적용됩니다.")
    elseif command == "scan test" and collectorToolsEnabled then startScan("test")
    elseif command == "scan new" and collectorToolsEnabled then startScan("custom")
    elseif command == "scan custom" and collectorToolsEnabled then startScan("custom")
    elseif command == "scan start" and collectorToolsEnabled then startScan("all")
    elseif command == "scan resume" and (collectorToolsEnabled or hasScanRecord) then resumeScan()
    elseif command == "scan stop" and (collectorToolsEnabled or hasScanRecord) then stopScan()
    elseif command == "scan status" and (collectorToolsEnabled or hasScanRecord) then printScanStatus()
    elseif command == "options" or command == "옵션" or command == "설정" or command == "" then
        if addon.OpenOptions then
            addon.OpenOptions()
        else
            print("|cffffcc00WoWQuestVoice:|r 설정 화면을 아직 불러오지 못했습니다.")
        end
    else
        print("|cff80ff80WoWQuestVoice:|r /wqv options · play [퀘스트ID] · stop · info")
    end
end
