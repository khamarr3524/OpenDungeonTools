local ODT = ODT
local L = ODT.L
local ODTcommsObject = ODTcommsObject
local twipe,tinsert = table.wipe,table.insert

local timer
local requestTimer
---LiveSession_Enable
function ODT:LiveSession_Enable()
    if self.liveSessionActive then return end
    self.main_frame.LiveSessionButton:SetText(L["*Live*"])
    self.main_frame.LiveSessionButton.text:SetTextColor(0,1,0)
    self.main_frame.LinkToChatButton:SetDisabled(true)
    self.main_frame.LinkToChatButton.text:SetTextColor(0.5,0.5,0.5)
    self.main_frame.sidePanelDeleteButton:SetDisabled(true)
    self.main_frame.sidePanelDeleteButton.text:SetTextColor(0.5,0.5,0.5)
    self.liveSessionActive = true
    --check if there is other clients having live mode active
    self:LiveSession_RequestSession()
    --set id here incase there is no other sessions
    self:SetUniqueID(self:GetCurrentPreset())
    self.livePresetUID = self:GetCurrentPreset().uid
    self:UpdatePresetDropdownTextColor()
    self:SetThrottleValues()
    timer = C_Timer.NewTimer(2, function()
        self.liveSessionRequested = false
        local distribution = self:IsPlayerInGroup()
        local preset = self:GetCurrentPreset()
        local prefix = "[ODTLive: "
        local dungeon = self:GetDungeonName(preset.value.currentDungeonIdx)
        local presetName = preset.text
        local name, realm = UnitFullName("player")
        local fullName = name.."+"..realm
        SendChatMessage(prefix..fullName.." - "..dungeon..": "..presetName.."]",distribution)
    end)
end

---LiveSession_Disable
function ODT:LiveSession_Disable()
    local widget = ODT.main_frame.LiveSessionButton
    widget.text:SetTextColor(widget.normalTextColor.r,widget.normalTextColor.g,widget.normalTextColor.b)
    widget.text:SetText(L["Live"])
    ODT.main_frame.LinkToChatButton:SetDisabled(false)
    self.main_frame.LinkToChatButton.text:SetTextColor(1,0.8196,0)
    local db = ODT:GetDB()
    if db.presets[db.currentDungeonIdx][1] == ODT:GetCurrentPreset() then
        ODT.main_frame.sidePanelDeleteButton:SetDisabled(true)
        ODT.main_frame.sidePanelDeleteButton.text:SetTextColor(0.5,0.5,0.5)
    else
        self.main_frame.sidePanelDeleteButton:SetDisabled(false)
        self.main_frame.sidePanelDeleteButton.text:SetTextColor(1,0.8196,0)
    end
    self.liveSessionActive = false
    self.liveSessionAcceptingPreset = false
    self:UpdatePresetDropdownTextColor()
    self.main_frame.liveReturnButton:Hide()
    self.main_frame.setLivePresetButton:Hide()
    if timer then timer:Cancel() end
    self.liveSessionRequested = false
    self.main_frame.SendingStatusBar:Hide()
    self:SetThrottleValues(true)
    if self.main_frame.LoadingSpinner then
        self.main_frame.LoadingSpinner:Hide()
        self.main_frame.LoadingSpinner.Anim:Stop()
    end
end

---Notify specific group member that my live session is active
local lastNotify
function ODT:LiveSession_NotifyEnabled()
    local now = GetTime()
    if not lastNotify or lastNotify < now - 0.2 then
        lastNotify = now
        local distribution = self:IsPlayerInGroup()
        if (not distribution) or (not self.liveSessionActive) then return end
        local uid = self.livePresetUID
        ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.enabled, uid, distribution, nil, "ALERT")
    end
    --self:SendToGroup(self:IsPlayerInGroup(),true,self:GetCurrentLivePreset())
end

---Send a request to the group to send notify messages for active sessions
function ODT:LiveSession_RequestSession()
    local distribution = self:IsPlayerInGroup()
    if (not distribution) or (not self.liveSessionActive) then return end
    self.liveSessionRequested = true
    self.liveSessionActiveSessions = self.liveSessionActiveSessions or {}
    twipe(self.liveSessionActiveSessions)
    ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.request, "0", distribution, nil, "ALERT")
end


function ODT:LiveSession_SessionFound(fullName, uid)
    local fullNamePlayer,realm = UnitFullName("player")
    fullNamePlayer = fullNamePlayer.."-"..realm

    if (not self.liveSessionAcceptingPreset) and fullNamePlayer ~= fullName then
        if timer then timer:Cancel() end
        self.liveSessionAcceptingPreset = true
        --request the preset from one client only after a short delay
        --we have to delay a bit to catch all active clients
        requestTimer = C_Timer.NewTimer(0.5, function()
            if self.liveSessionActiveSessions[1][1] ~= fullNamePlayer then
                self.main_frame.SendingStatusBar:Show()
                self.main_frame.SendingStatusBar:SetValue(0/1)
                self.main_frame.SendingStatusBar.value:SetText(L["Receiving: ..."])
                if not self.main_frame.LoadingSpinner then
                    self.main_frame.LoadingSpinner = CreateFrame("Button", "ODTLoadingSpinner", self.main_frame, "LoadingSpinnerTemplate")
                    self.main_frame.LoadingSpinner:SetPoint("CENTER",self.main_frame,"CENTER")
                    self.main_frame.LoadingSpinner:SetSize(60,60)
                end
                self.main_frame.LoadingSpinner:Show()
                self.main_frame.LoadingSpinner.Anim:Play()
                self:UpdatePresetDropdownTextColor(true)

                self.liveSessionRequested = false
                self:LiveSession_RequestPreset(self.liveSessionActiveSessions[1][1])
                self.livePresetUID = self.liveSessionActiveSessions[1][2]
            else
                self.liveSessionAcceptingPreset = false
                self.liveSessionRequested = false
            end
        end)
    end
    --catch clients
    tinsert(self.liveSessionActiveSessions,{fullName,uid})
end

function ODT:LiveSession_RequestPreset(fullName)
    local distribution = self:IsPlayerInGroup()
    if (not distribution) or (not self.liveSessionActive) then return end
    ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.reqPre, fullName, distribution,nil, "ALERT")
end

---Sends a map ping
function ODT:LiveSession_SendPing(x, y, sublevel)
    --only send ping if we are in the livesession preset
    if self:GetCurrentPreset().uid == self.livePresetUID then
        local distribution = self:IsPlayerInGroup()
        if distribution then
            local scale = self:GetScale()
            ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.ping, x*(1/scale)..":"..y*(1/scale)..":"..sublevel, distribution, nil, "ALERT")
        end
    end
end

---Sends a preset object
function ODT:LiveSession_SendObject(obj)
    if self:GetCurrentPreset().uid == self.livePresetUID then
        local distribution = self:IsPlayerInGroup()
        if distribution then
            local export = ODT:TableToString(obj,false,5)
            ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.obj, export, distribution, nil, "ALERT")
        end
    end
end

---Sends updated object offsets (move object)
function ODT:LiveSession_SendObjectOffsets(objIdx, x, y)
    if self:GetCurrentPreset().uid == self.livePresetUID then
        local distribution = self:IsPlayerInGroup()
        if distribution then
            ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.objOff, objIdx..":"..x..":"..y, distribution, nil, "ALERT")
        end
    end
end

---Sends updated objects - instead of sending an update every time we erase a part of an object we send one message after mouse up
function ODT:LiveSession_SendUpdatedObjects(changedObjects)
    if self:GetCurrentPreset().uid == self.livePresetUID then
        local distribution = self:IsPlayerInGroup()
        if distribution then
            local export = ODT:TableToString(changedObjects,false,5)
            ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.objChg, export, distribution, nil, "ALERT")
        end
    end
end

---Sends various commands: delete all drawings, clear preset, undo, redo
function ODT:LiveSession_SendCommand(cmd)
    if self:GetCurrentPreset().uid == self.livePresetUID then
        local distribution = self:IsPlayerInGroup()
        if distribution then
            ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.cmd, cmd, distribution, nil, "ALERT")
        end
    end
end

---Sends a note text update
function ODT:LiveSession_SendNoteCommand(cmd, noteIdx, text, y)
    if self:GetCurrentPreset().uid == self.livePresetUID then
        local distribution = self:IsPlayerInGroup()
        if distribution then
            text = text..":"..(y or "0")
            ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.note, cmd..":"..noteIdx..":"..text, distribution, nil, "ALERT")
        end
    end
end

---Sends a new preset to be used as the new live session preset
function ODT:LiveSession_SendPreset(preset)
    local distribution = self:IsPlayerInGroup()
    if distribution then
        local db = self:GetDB()
        preset.mdiEnabled = db.MDI.enabled
        preset.difficulty = db.currentDifficulty
        local export = ODT:TableToString(preset,false,5)
        ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.preset, export, distribution, nil, "ALERT")
    end
end

---Sends all pulls
function ODT:LiveSession_SendPulls(pulls)
    local distribution = self:IsPlayerInGroup()
    if distribution then
        local msg = ODT:TableToString(pulls,false,5)
        ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.pull, msg, distribution, nil, "ALERT")
    end
end

---Sends Affix Week Change
function ODT:LiveSession_SendAffixWeek(week)
    local distribution = self:IsPlayerInGroup()
    if distribution then
        ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.week, week.."", distribution, nil, "ALERT")
    end
end

---Sends freehold selector updates
function ODT:LiveSession_SendFreeholdSelector(value, week)
    local distribution = self:IsPlayerInGroup()
    if distribution then
        value = value and "T:" or "F:"
        local msg = value..week
        ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.free, msg, distribution, nil, "ALERT")
    end
end

---sends boralus selector updates
function ODT:LiveSession_SendBoralusSelector(faction)
    local distribution = self:IsPlayerInGroup()
    if distribution then
        local msg = faction..""
        ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.bora, msg, distribution, nil, "ALERT")
    end
end

---Sends MDI selector updates
function ODT:LiveSession_SendMDI(action, data)
    local distribution = self:IsPlayerInGroup()
    if distribution then
        local msg = action..":"..data
        ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.mdi, msg, distribution, nil, "ALERT")
    end
end

do
    local timer
    ---LiveSession_QueueColorUpdate
    ---Disgusting workaround for shitty colorpicker
    ---Only send an update once a color of a pull has not changed for 0.2 seconds
    function ODT:LiveSession_QueueColorUpdate()
        if timer then timer:Cancel() end
        timer = C_Timer.NewTimer(0.2, function()
            self:LiveSession_SendPulls(self:GetPulls())
        end)
    end
end

---Sends Corrupted NPC Offset Positions
function ODT:LiveSession_SendCorruptedPositions(offsets)
    local distribution = self:IsPlayerInGroup()
    if distribution then
        local export = ODT:TableToString(offsets,false,5)
        ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.corrupted, export, distribution, nil, "ALERT")
    end
end

---Sends current difficulty
function ODT:LiveSession_SendDifficulty()
    local distribution = self:IsPlayerInGroup()
    if distribution then
        local export = self:GetDB().currentDifficulty
        ODTcommsObject:SendCommMessage(self.liveSessionPrefixes.difficulty, export.."", distribution, nil, "ALERT")
    end
end