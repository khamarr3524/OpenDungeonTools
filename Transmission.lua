local ODT = ODT
local L = ODT.L
local Compresser = LibStub:GetLibrary("LibCompress")
local Encoder = Compresser:GetAddonEncodeTable()
local Serializer = LibStub:GetLibrary("AceSerializer-3.0")
local LibDeflate = LibStub:GetLibrary("LibDeflate")
local configForDeflate = {
    [1]= {level = 1},
    [2]= {level = 2},
    [3]= {level = 3},
    [4]= {level = 4},
    [5]= {level = 5},
    [6]= {level = 6},
    [7]= {level = 7},
    [8]= {level = 8},
    [9]= {level = 9},
}
ODTcommsObject = LibStub("AceAddon-3.0"):NewAddon("ODTCommsObject","AceComm-3.0","AceSerializer-3.0")

-- Lua APIs
local tostring, string_char, strsplit,tremove,tinsert = tostring, string.char, strsplit,table.remove,table.insert
local pairs, type, unpack = pairs, type, unpack
local bit_band, bit_lshift, bit_rshift = bit.band, bit.lshift, bit.rshift

--Based on code from WeakAuras2, all credit goes to the authors
local bytetoB64 = {
    [0]="a","b","c","d","e","f","g","h",
    "i","j","k","l","m","n","o","p",
    "q","r","s","t","u","v","w","x",
    "y","z","A","B","C","D","E","F",
    "G","H","I","J","K","L","M","N",
    "O","P","Q","R","S","T","U","V",
    "W","X","Y","Z","0","1","2","3",
    "4","5","6","7","8","9","(",")"
}

local B64tobyte = {
    a =  0,  b =  1,  c =  2,  d =  3,  e =  4,  f =  5,  g =  6,  h =  7,
    i =  8,  j =  9,  k = 10,  l = 11,  m = 12,  n = 13,  o = 14,  p = 15,
    q = 16,  r = 17,  s = 18,  t = 19,  u = 20,  v = 21,  w = 22,  x = 23,
    y = 24,  z = 25,  A = 26,  B = 27,  C = 28,  D = 29,  E = 30,  F = 31,
    G = 32,  H = 33,  I = 34,  J = 35,  K = 36,  L = 37,  M = 38,  N = 39,
    O = 40,  P = 41,  Q = 42,  R = 43,  S = 44,  T = 45,  U = 46,  V = 47,
    W = 48,  X = 49,  Y = 50,  Z = 51,["0"]=52,["1"]=53,["2"]=54,["3"]=55,
    ["4"]=56,["5"]=57,["6"]=58,["7"]=59,["8"]=60,["9"]=61,["("]=62,[")"]=63
}

-- This code is based on the Encode7Bit algorithm from LibCompress
-- Credit goes to Galmok (galmok@gmail.com)
local decodeB64Table = {}

function decodeB64(str)
    local bit8 = decodeB64Table
    local decoded_size = 0
    local ch
    local i = 1
    local bitfield_len = 0
    local bitfield = 0
    local l = #str
    while true do
        if bitfield_len >= 8 then
            decoded_size = decoded_size + 1
            bit8[decoded_size] = string_char(bit_band(bitfield, 255))
            bitfield = bit_rshift(bitfield, 8)
            bitfield_len = bitfield_len - 8
        end
        ch = B64tobyte[str:sub(i, i)]
        bitfield = bitfield + bit_lshift(ch or 0, bitfield_len)
        bitfield_len = bitfield_len + 6
        if i > l then
            break
        end
        i = i + 1
    end
    return table.concat(bit8, "", 1, decoded_size)
end

function ODT:TableToString(inTable, forChat,level)
    local serialized = Serializer:Serialize(inTable)
    local compressed = LibDeflate:CompressDeflate(serialized, configForDeflate[level])
    -- prepend with "!" so that we know that it is not a legacy compression
    -- also this way, old versions will error out due to the "bad" encoding
    local encoded = "!"
    if(forChat) then
        encoded = encoded .. LibDeflate:EncodeForPrint(compressed)
    else
        encoded = encoded .. LibDeflate:EncodeForWoWAddonChannel(compressed)
    end
    return encoded
end

function ODT:StringToTable(inString, fromChat)
    -- if gsub strips off a ! at the beginning then we know that this is not a legacy encoding
    local encoded, usesDeflate = inString:gsub("^%!", "")
    local decoded
    if(fromChat) then
        if usesDeflate == 1 then
            decoded = LibDeflate:DecodeForPrint(encoded)
        else
            decoded = decodeB64(encoded)
        end
    else
        decoded = LibDeflate:DecodeForWoWAddonChannel(encoded)
    end

    if not decoded then
        return "Error decoding."
    end

    local decompressed, errorMsg = nil, "unknown compression method"
    if usesDeflate == 1 then
        decompressed = LibDeflate:DecompressDeflate(decoded)
    else
        decompressed, errorMsg = Compresser:Decompress(decoded)
    end
    if not(decompressed) then
        return "Error decompressing: " .. errorMsg
    end

    local success, deserialized = Serializer:Deserialize(decompressed)
    if not(success) then
        return "Error deserializing "..deserialized
    end
    return deserialized
end

local function filterFunc(_, event, msg, player, l, cs, t, flag, channelId, ...)
    if flag == "GM" or flag == "DEV" or (event == "CHAT_MSG_CHANNEL" and type(channelId) == "number" and channelId > 0) then
        return
    end
    local newMsg = ""
    local remaining = msg
    local done
    repeat
        local start, finish, characterName, displayName = remaining:find("%[MythicDungeonTools: ([^%s]+) %- ([^%]]+)%]")
        local startLive, finishLive, characterNameLive, displayNameLive = remaining:find("%[ODTLive: ([^%s]+) %- ([^%]]+)%]")
        if(characterName and displayName) then
            characterName = characterName:gsub("|c[Ff][Ff]......", ""):gsub("|r", "")
            displayName = displayName:gsub("|c[Ff][Ff]......", ""):gsub("|r", "")
            newMsg = newMsg..remaining:sub(1, start-1)
            newMsg = "|cfff49d38|Hgarrmission:ODT-"..characterName.."|h["..displayName.."]|h|r"
            remaining = remaining:sub(finish + 1)
        elseif (characterNameLive and displayNameLive) then
            characterNameLive = characterNameLive:gsub("|c[Ff][Ff]......", ""):gsub("|r", "")
            displayNameLive = displayNameLive:gsub("|c[Ff][Ff]......", ""):gsub("|r", "")
            newMsg = newMsg..remaining:sub(1, startLive-1)
            newMsg = newMsg.."|Hgarrmission:ODTlive-"..characterNameLive.."|h[".."|cFF00FF00Live Session: |cfff49d38"..""..displayNameLive.."]|h|r"
            remaining = remaining:sub(finishLive + 1)
        else
            done = true
        end
    until(done)
    if newMsg ~= "" then
        return false, newMsg, player, l, cs, t, flag, channelId, ...
    end
end

local presetCommPrefix = "ODTPreset"

ODT.liveSessionPrefixes = {
    ["enabled"] = "ODTLiveEnabled",
    ["request"] = "ODTLiveReq",
    ["ping"] = "ODTLivePing",
    ["obj"] = "ODTLiveObj",
    ["objOff"] = "ODTLiveObjOff",
    ["objChg"] = "ODTLiveObjChg",
    ["cmd"] = "ODTLiveCmd",
    ["note"] = "ODTLiveNote",
    ["preset"] = "ODTLivePreset",
    ["pull"] = "ODTLivePull",
    ["week"] = "ODTLiveWeek",
    ["free"] = "ODTLiveFree",
    ["bora"] = "ODTLiveBora",
    ["mdi"] = "ODTLiveMDI",
    ["reqPre"] = "ODTLiveReqPre",
    ["corrupted"] = "ODTLiveCor",
    ["difficulty"] = "ODTLiveLvl",
}

ODT.dataCollectionPrefixes = {
    ["request"] = "ODTDataReq",
    ["distribute"] = "ODTDataDist",
}

function ODTcommsObject:OnEnable()
    self:RegisterComm(presetCommPrefix)
    for _,prefix in pairs(ODT.liveSessionPrefixes) do
        self:RegisterComm(prefix)
    end
    for _,prefix in pairs(ODT.dataCollectionPrefixes) do
        self:RegisterComm(prefix)
    end
    ODT.transmissionCache = {}
    ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY", filterFunc)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY_LEADER", filterFunc)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID", filterFunc)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID_LEADER", filterFunc)
end

--handle preset chat link clicks
hooksecurefunc("SetItemRef", function(link, text)
    if(link and link:sub(0, 19) == "garrmission:ODTlive") then
        local sender = link:sub(21, string.len(link))
        local name,realm = string.match(sender,"(.*)+(.*)")
        sender = name.."-"..realm
        --ignore importing the live preset when sender is player, open ODT only
        local playerName,playerRealm = UnitFullName("player")
        playerName = playerName.."-"..playerRealm
        if sender==playerName then
            ODT:ShowInterface(true)
        else
            ODT:ShowInterface(true)
            ODT:LiveSession_Enable()
        end
        return
    elseif (link and link:sub(0, 15) == "garrmission:ODT") then
        local sender = link:sub(17, string.len(link))
        local name,realm = string.match(sender,"(.*)+(.*)")
        if (not name) or (not realm) then
            print(string.format(L["receiveErrorUpdate"],sender))
            return
        end
        sender = name.."-"..realm
        local preset = ODT.transmissionCache[sender]
        if preset then
            ODT:ShowInterface(true)
            ODT:OpenChatImportPresetDialog(sender,preset)
        end
        return
    end
end)

function ODTcommsObject:OnCommReceived(prefix, message, distribution, sender)
    --[[
        Sender has no realm name attached when sender is from the same realm as the player
        UnitFullName("Nnoggie") returns no realm while UnitFullName("player") does
        UnitFullName("Nnoggie-TarrenMill") returns realm even if you are not on the same realm as Nnoggie
        We append our realm if there is no realm
    ]]
    local name, realm = UnitFullName(sender)
    if not name then return end
    if not realm or string.len(realm)<3 then
        local _,r = UnitFullName("player")
        realm = r
    end
    local fullName = name.."-"..realm

    --standard preset transmission
    --we cache the preset here already
    --the user still decides if he wants to click the chat link and add the preset to his db
    if prefix == presetCommPrefix then
        local preset = ODT:StringToTable(message,false)
        ODT.transmissionCache[fullName] = preset
        --live session preset
        if ODT.liveSessionActive and ODT.liveSessionAcceptingPreset and preset.uid == ODT.livePresetUID then
            if ODT:ValidateImportPreset(preset) then
                ODT:ImportPreset(preset,true)
                ODT.liveSessionAcceptingPreset = false
                ODT.main_frame.SendingStatusBar:Hide()
                if ODT.main_frame.LoadingSpinner then
                    ODT.main_frame.LoadingSpinner:Hide()
                    ODT.main_frame.LoadingSpinner.Anim:Stop()
                end
                ODT.liveSessionRequested = false
            end
        end
    end

    if prefix == ODT.dataCollectionPrefixes.request then
        ODT.DataCollection:DistributeData()
    end

    if prefix == ODT.dataCollectionPrefixes.distribute then
        local package = ODT:StringToTable(message,false)
        ODT.DataCollection:MergeReceiveData(package)
    end

    if prefix == ODT.liveSessionPrefixes.enabled then
        if ODT.liveSessionRequested == true then
            ODT:LiveSession_SessionFound(fullName,message)
        end
    end

    --pulls
    if prefix == ODT.liveSessionPrefixes.pull then
        if ODT.liveSessionActive then
            local preset = ODT:GetCurrentLivePreset()
            local pulls = ODT:StringToTable(message,false)
            preset.value.pulls = pulls
            if not preset.value.pulls[preset.value.currentPull] then
                preset.value.currentPull = #preset.value.pulls
                preset.value.selection = {#preset.value.pulls}
            end
            if preset == ODT:GetCurrentPreset() then
                ODT:ReloadPullButtons()
                ODT:SetSelectionToPull(ODT:GetCurrentPull())
                ODT:POI_UpdateAll() --for corrupted spires
                ODT:UpdateProgressbar()
            end
        end
    end

    --corrupted
    if prefix == ODT.liveSessionPrefixes.corrupted then
        if ODT.liveSessionActive then
            local preset = ODT:GetCurrentLivePreset()
            local offsets = ODT:StringToTable(message,false)
            --only reposition if no blip is currently moving
            if not ODT.draggedBlip then
                preset.value.riftOffsets = offsets
                ODT:UpdateMap()
            end
        end
    end

    --difficulty
    if prefix == ODT.liveSessionPrefixes.difficulty then
        if ODT.liveSessionActive then
            local db = ODT:GetDB()
            local difficulty = tonumber(message)
            if difficulty and difficulty~= db.currentDifficulty then
                local updateSeasonal
                if ((difficulty>=10 and db.currentDifficulty<10) or (difficulty<10 and db.currentDifficulty>=10)) then
                    updateSeasonal = true
                end
                db.currentDifficulty = difficulty
                ODT.main_frame.sidePanel.DifficultySlider:SetValue(difficulty)
                ODT:UpdateProgressbar()
                if ODT.EnemyInfoFrame and ODT.EnemyInfoFrame.frame:IsShown() then ODT:UpdateEnemyInfoData() end
                ODT:ReloadPullButtons()
                if updateSeasonal then
                    ODT:DungeonEnemies_UpdateSeasonalAffix()
                    ODT.main_frame.sidePanel.difficultyWarning:Toggle(difficulty)
                    ODT:POI_UpdateAll()
                    ODT:KillAllAnimatedLines()
                    ODT:DrawAllAnimatedLines()
                end
            end
        end
    end

    --week
    if prefix == ODT.liveSessionPrefixes.week then
        if ODT.liveSessionActive then
            local preset = ODT:GetCurrentLivePreset()
            local week = tonumber(message)
            if preset.week ~= week then
                preset.week = week
                local teeming = ODT:IsPresetTeeming(preset)
                preset.value.teeming = teeming
                if preset == ODT:GetCurrentPreset() then
                    local affixDropdown = ODT.main_frame.sidePanel.affixDropdown
                    affixDropdown:SetValue(week)
                    if not ODT:GetCurrentAffixWeek() then
                        ODT.main_frame.sidePanel.affixWeekWarning.image:Hide()
                        ODT.main_frame.sidePanel.affixWeekWarning:SetDisabled(true)
                    elseif ODT:GetCurrentAffixWeek() == week then
                        ODT.main_frame.sidePanel.affixWeekWarning.image:Hide()
                        ODT.main_frame.sidePanel.affixWeekWarning:SetDisabled(true)
                    else
                        ODT.main_frame.sidePanel.affixWeekWarning.image:Show()
                        ODT.main_frame.sidePanel.affixWeekWarning:SetDisabled(false)
                    end
                    ODT:DungeonEnemies_UpdateTeeming()
                    ODT:DungeonEnemies_UpdateInspiring()
                    ODT:UpdateFreeholdSelector(week)
                    ODT:DungeonEnemies_UpdateBlacktoothEvent(week)
                    ODT:DungeonEnemies_UpdateSeasonalAffix()
                    ODT:DungeonEnemies_UpdateBoralusFaction(preset.faction)
                    ODT:POI_UpdateAll()
                    ODT:UpdateProgressbar()
                    ODT:ReloadPullButtons()
                    ODT:KillAllAnimatedLines()
                    ODT:DrawAllAnimatedLines()
                end
            end
        end
    end

    --live session messages that ignore concurrency from here on, we ignore our own messages
    if sender == UnitFullName("player") then return end


    if prefix == ODT.liveSessionPrefixes.request then
        if ODT.liveSessionActive then
            ODT:LiveSession_NotifyEnabled()
        end
    end

    --request preset
    if prefix == ODT.liveSessionPrefixes.reqPre then
        local playerName,playerRealm = UnitFullName("player")
        playerName = playerName.."-"..playerRealm
        if playerName == message then
            ODT:SendToGroup(ODT:IsPlayerInGroup(),true,ODT:GetCurrentLivePreset())
        end
    end


    --ping
    if prefix == ODT.liveSessionPrefixes.ping then
        local currentUID = ODT:GetCurrentPreset().uid
        if ODT.liveSessionActive and (currentUID and currentUID==ODT.livePresetUID) then
            local x,y,sublevel = string.match(message,"(.*):(.*):(.*)")
            x = tonumber(x)
            y = tonumber(y)
            sublevel = tonumber(sublevel)
            local scale = ODT:GetScale()
            if sublevel == ODT:GetCurrentSubLevel() then
                ODT:PingMap(x*scale,y*scale)
            end
        end
    end

    --preset objects
    if prefix == ODT.liveSessionPrefixes.obj then
        if ODT.liveSessionActive then
            local preset = ODT:GetCurrentLivePreset()
            local obj = ODT:StringToTable(message,false)
            ODT:StorePresetObject(obj,true,preset)
            if preset == ODT:GetCurrentPreset() then
                local scale = ODT:GetScale()
                local currentPreset = ODT:GetCurrentPreset()
                local currentSublevel = ODT:GetCurrentSubLevel()
                ODT:DrawPresetObject(obj,nil,scale,currentPreset,currentSublevel)
            end
        end
    end

    --preset object offsets
    if prefix == ODT.liveSessionPrefixes.objOff then
        if ODT.liveSessionActive then
            local preset = ODT:GetCurrentLivePreset()
            local objIdx,x,y = string.match(message,"(.*):(.*):(.*)")
            objIdx = tonumber(objIdx)
            x = tonumber(x)
            y = tonumber(y)
            ODT:UpdatePresetObjectOffsets(objIdx,x,y,preset,true)
            if preset == ODT:GetCurrentPreset() then ODT:DrawAllPresetObjects() end
        end
    end

    --preset object changed (deletions, partial deletions)
    if prefix == ODT.liveSessionPrefixes.objChg then
        if ODT.liveSessionActive then
            local preset = ODT:GetCurrentLivePreset()
            local changedObjects = ODT:StringToTable(message,false)
            for objIdx,obj in pairs(changedObjects) do
                preset.objects[objIdx] = obj
            end
            if preset == ODT:GetCurrentPreset() then ODT:DrawAllPresetObjects() end
        end
    end

    --various commands
    if prefix == ODT.liveSessionPrefixes.cmd then
        if ODT.liveSessionActive then
            local preset = ODT:GetCurrentLivePreset()
            if message == "deletePresetObjects" then ODT:DeletePresetObjects(preset, true) end
            if message == "undo" then ODT:PresetObjectStepBack(preset, true) end
            if message == "redo" then ODT:PresetObjectStepForward(preset, true) end
            if message == "clear" then ODT:ClearPreset(preset,true) end
        end
    end

    --note text update, delete, move
    if prefix == ODT.liveSessionPrefixes.note then
        if ODT.liveSessionActive then
            local preset = ODT:GetCurrentLivePreset()
            local action,noteIdx,text,y = string.match(message,"(.*):(.*):(.*):(.*)")
            noteIdx = tonumber(noteIdx)
            if action == "text" then
                preset.objects[noteIdx].d[5]=text
            elseif action == "delete" then
                tremove(preset.objects,noteIdx)
            elseif action == "move" then
                local x = tonumber(text)
                y = tonumber(y)
                preset.objects[noteIdx].d[1]=x
                preset.objects[noteIdx].d[2]=y
            end
            if preset == ODT:GetCurrentPreset() then ODT:DrawAllPresetObjects() end
        end
    end

    --preset
    if prefix == ODT.liveSessionPrefixes.preset then
        if ODT.liveSessionActive then
            local preset = ODT:StringToTable(message,false)
            ODT.transmissionCache[fullName] = preset
            if ODT:ValidateImportPreset(preset) then
                ODT.livePresetUID = preset.uid
                ODT:ImportPreset(preset,true)
            end
        end
    end

    --freehold
    if prefix == ODT.liveSessionPrefixes.free then
        if ODT.liveSessionActive then
            local preset = ODT:GetCurrentLivePreset()
            local value,week = string.match(message,"(.*):(.*)")
            value = value == "T" and true or false
            week = tonumber(week)
            preset.freeholdCrew = (value and week) or nil
            if preset == ODT:GetCurrentPreset() then
                ODT:DungeonEnemies_UpdateFreeholdCrew(preset.freeholdCrew)
                ODT:UpdateFreeholdSelector(week)
                ODT:ReloadPullButtons()
                ODT:UpdateProgressbar()
            end
        end
    end

    --Siege of Boralus
    if prefix == ODT.liveSessionPrefixes.bora then
        if ODT.liveSessionActive then
            local preset = ODT:GetCurrentLivePreset()
            local faction = tonumber(message)
            preset.faction = faction
            if preset == ODT:GetCurrentPreset() then
                ODT:UpdateBoralusSelector()
                ODT:ReloadPullButtons()
                ODT:UpdateProgressbar()
            end
        end
    end

    --MDI
    if prefix == ODT.liveSessionPrefixes.mdi then
        if ODT.liveSessionActive then
            local preset = ODT:GetCurrentLivePreset()
            local updateUI = preset == ODT:GetCurrentPreset()
            local action,data = string.match(message,"(.*):(.*)")
            data = tonumber(data)
            if action == "toggle" then
                ODT:GetDB().MDI.enabled = data == 1 or false
                ODT:DisplayMDISelector()
            elseif action == "beguiling" then
                preset.mdi.beguiling = data
                if updateUI then
                    ODT.MDISelector.BeguilingDropDown:SetValue(preset.mdi.beguiling)
                    ODT:DungeonEnemies_UpdateSeasonalAffix()
                    ODT:DungeonEnemies_UpdateBoralusFaction(preset.faction)
                    ODT:UpdateProgressbar()
                    ODT:ReloadPullButtons()
                    ODT:POI_UpdateAll()
                    ODT:KillAllAnimatedLines()
                    ODT:DrawAllAnimatedLines()
                end
            elseif action == "freehold" then
                preset.mdi.freehold = data
                if updateUI then
                    ODT.MDISelector.FreeholdDropDown:SetValue(preset.mdi.freehold)
                    if preset.mdi.freeholdJoined then
                        ODT:DungeonEnemies_UpdateFreeholdCrew(preset.mdi.freehold)
                    end
                    ODT:DungeonEnemies_UpdateBlacktoothEvent()
                    ODT:UpdateProgressbar()
                    ODT:ReloadPullButtons()
                end
            elseif action == "join" then
                preset.mdi.freeholdJoined = data == 1 or false
                if updateUI then
                    ODT:DungeonEnemies_UpdateFreeholdCrew()
                    ODT:ReloadPullButtons()
                    ODT:UpdateProgressbar()
                end
            end

        end
    end

end


---MakeSendingStatusBar
---Creates a bar that indicates sending progress when sharing presets with your group
---Called once from initFrames()
function ODT:MakeSendingStatusBar(f)
    f.SendingStatusBar = CreateFrame("StatusBar", nil, f)
    local statusbar = f.SendingStatusBar
    statusbar:SetMinMaxValues(0, 1)
    statusbar:SetPoint("LEFT", f.bottomPanel, "LEFT", 5, 0)
    statusbar:SetWidth(200)
    statusbar:SetHeight(20)
    statusbar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    statusbar:GetStatusBarTexture():SetHorizTile(false)
    statusbar:GetStatusBarTexture():SetVertTile(false)
    statusbar:SetStatusBarColor(0.26,0.42,1)

    statusbar.bg = statusbar:CreateTexture(nil, "BACKGROUND")
    statusbar.bg:SetTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    statusbar.bg:SetAllPoints(true)
    statusbar.bg:SetVertexColor(0.26,0.42,1)

    statusbar.value = statusbar:CreateFontString(nil, "OVERLAY")
    statusbar.value:SetPoint("CENTER", statusbar, "CENTER", 0, 0)
    statusbar.value:SetFontObject("GameFontNormalSmall")
    statusbar.value:SetJustifyH("CENTER")
    statusbar.value:SetJustifyV("CENTER")
    statusbar.value:SetShadowOffset(1, -1)
    statusbar.value:SetTextColor(1, 1, 1)
    statusbar:Hide()

    if IsAddOnLoaded("ElvUI") then
        local E, L, V, P, G = unpack(ElvUI)
        statusbar:SetStatusBarTexture(E.media.normTex)
    end
end

--callback for SendCommMessage
local function displaySendingProgress(userArgs,bytesSent,bytesToSend)
    ODT.main_frame.SendingStatusBar:Show()
    ODT.main_frame.SendingStatusBar:SetValue(bytesSent/bytesToSend)
    ODT.main_frame.SendingStatusBar.value:SetText(string.format(L["Sending: %.1f"],bytesSent/bytesToSend*100).."%")
    --done sending
    if bytesSent == bytesToSend then
        local distribution = userArgs[1]
        local preset = userArgs[2]
        local silent = userArgs[3]
        --restore "Send" and "Live" button
        if ODT.liveSessionActive then
            ODT.main_frame.LiveSessionButton:SetText(L["*Live*"])
        else
            ODT.main_frame.LiveSessionButton:SetText(L["Live"])
            ODT.main_frame.LiveSessionButton.text:SetTextColor(1,0.8196,0)
            ODT.main_frame.LinkToChatButton:SetDisabled(false)
            ODT.main_frame.LinkToChatButton.text:SetTextColor(1,0.8196,0)
        end
        ODT.main_frame.LinkToChatButton:SetText(L["Share"])
        ODT.main_frame.LiveSessionButton:SetDisabled(false)
        ODT.main_frame.SendingStatusBar:Hide()
        --output chat link
        if not silent then
            local prefix = "[MythicDungeonTools: "
            local dungeon = ODT:GetDungeonName(preset.value.currentDungeonIdx)
            local presetName = preset.text
            local name, realm = UnitFullName("player")
            local fullName = name.."+"..realm
            SendChatMessage(prefix..fullName.." - "..dungeon..": "..presetName.."]",distribution)
            ODT:SetThrottleValues(true)
        end
    end
end

---generates a unique random 11 digit number in base64 and assigns it to a preset if it does not have one yet
---credit to WeakAuras2
function ODT:SetUniqueID(preset)
    if not preset.uid then
        local s = {}
        for i=1,11 do
            tinsert(s, bytetoB64[math.random(0, 63)])
        end
        preset.uid = table.concat(s)
    end
end

---SendToGroup
---Send current preset to group/raid
function ODT:SendToGroup(distribution,silent,preset)
    ODT:SetThrottleValues()
    preset = preset or ODT:GetCurrentPreset()
    --set unique id
    ODT:SetUniqueID(preset)
    --gotta encode mdi mode / difficulty into preset
    local db = ODT:GetDB()
    preset.mdiEnabled = db.MDI.enabled
    preset.difficulty = db.currentDifficulty
    local export = ODT:TableToString(preset,false,5)
    ODTcommsObject:SendCommMessage("ODTPreset", export, distribution, nil, "BULK",displaySendingProgress,{distribution,preset,silent})
end

---GetPresetSize
---Returns the number of characters the string version of the preset contains
function ODT:GetPresetSize(forChat,level)
    local preset = ODT:GetCurrentPreset()
    local export = ODT:TableToString(preset,forChat,level)
    return string.len(export)
end

local defaultCPS = tonumber(_G.ChatThrottleLib.MAX_CPS)
local defaultBURST = tonumber(_G.ChatThrottleLib.BURST)
function ODT:SetThrottleValues(default)
    if not _G.ChatThrottleLib then return end
    if default then
        _G.ChatThrottleLib.MAX_CPS = defaultCPS
        _G.ChatThrottleLib.BURST = defaultBURST
    else --4000/16000 is fine but we go safe with 2000/10000
        _G.ChatThrottleLib.MAX_CPS= 2000
        _G.ChatThrottleLib.BURST = 10000
    end
end
