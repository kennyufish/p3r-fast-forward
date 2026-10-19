-- Game speed plus AtomComponent pitch-multiplier audio speed-up (resampling raises pitch).
-- Optional pitch fix routes sped non-BGM sounds through PitchShifter buses added by xrd777_ff.acf.
local function log(message) print("[P3RFF] " .. message .. "\n") end
-- 5x passes 5 to SetPitchMultiplier uncompensated (user choice); CRI clamps it (see logAudioLimits).
local RATES = {1.0, 1.5, 2.0, 5.0} -- F6 cycles through these; gui.ps1 offers the same list.
if _G.P3RFF_loaded then
    log("Duplicate execution ignored; restart the game to reload this mod.")
    return
end
local ok, helpers = pcall(require, "UEHelpers")
if not ok then log("INIT FAILED: UEHelpers: " .. tostring(helpers)); return end
for _, name in ipairs({"RegisterKeyBind", "ExecuteInGameThread", "LoopAsync", "StaticFindObject", "FindFirstOf"}) do
    if type(_G[name]) ~= "function" then
        log("INIT FAILED: missing " .. name .. "; use the documented UE4SS 3.0.1 setup.")
        return
    end
end
if not Key or not Key.F6 or not Key.F8 then log("INIT FAILED: Key.F6/F8 unavailable"); return end
for _, key in ipairs({"F6", "F8"}) do
    if type(IsKeyBindRegistered) == "function" and IsKeyBindRegistered(Key[key]) then
        log("INIT FAILED: " .. key .. " is already registered; resolve the other binding and restart.")
        return
    end
end
-- Equalizer APO reloads on file change; its config.txt has "Include: p3r_pitch.txt".
local APO_FILE = "C:\\Program Files\\EqualizerAPO\\config\\p3r_pitch.txt"
-- APO is system-wide and would pitch the 1x BGM down too, so compensation is off at every rate (chunks in handoff.md).
local function writeApoPitch(rate)
    local text = string.format("# %.1fx: no pitch compensation\n", rate)
    local ok, err = pcall(function()
        local file = assert(io.open(APO_FILE, "w"))
        file:write(text)
        file:close()
    end)
    if not ok then log("APO pitch file write failed (game speed unaffected): " .. tostring(err)) end
end
-- settings.txt is shared with gui.ps1: either side writes it, the other polls for changes.
local MOD_DIR = (debug.getinfo(1, "S").source:match("^@(.*[\\/])[Ss]cripts[\\/]") or "Mods\\P3R_FastForward\\")
local SETTINGS_FILE = MOD_DIR .. "settings.txt"
local cfg = {rate = 1.0, game = true, sfx = true, pitch = true}
local lastSettingsText = nil
local function isRate(value)
    for _, rate in ipairs(RATES) do
        if math.abs(value - rate) <= 0.001 then return true end
    end
    return false
end
local function serializeSettings(s)
    local function flag(b) return b and 1 or 0 end
    return string.format("rate=%.1f\ngame=%d\nsfx=%d\npitch=%d\n", s.rate, flag(s.game), flag(s.sfx), flag(s.pitch))
end
-- Returns nil for partial writes or typos; the caller keeps the previous settings.
local function parseSettings(text)
    local map = {}
    for key, value in text:gmatch("(%a+)=([%d%.]+)") do map[key] = value end
    local rate = tonumber(map.rate)
    if not rate or not isRate(rate) then return nil end
    local s = {rate = rate}
    for _, key in ipairs({"game", "sfx"}) do -- "bgm" (removed in v0.6.5) is ignored: BGM always stays 1x
        if map[key] ~= "0" and map[key] ~= "1" then return nil end
        s[key] = map[key] == "1"
    end
    s.pitch = map.pitch ~= "0" -- added in v0.6.0; files from v0.5.0 lack it
    return s
end
assert(parseSettings(serializeSettings({rate = 1.5, game = true, sfx = false, pitch = false})).pitch == false)
assert(parseSettings("rate=2.0\ngame=1\nsfx=1\nbgm=0\n").pitch == true)
assert(parseSettings("rate=3.0\ngame=1\nsfx=1\nbgm=0\n") == nil and parseSettings("rate=2.0\ngame=1\n") == nil)
local function readSettingsFile()
    local file = io.open(SETTINGS_FILE, "r")
    if not file then return nil, nil end
    local text = file:read("a")
    file:close()
    return text, parseSettings(text)
end
local function writeSettingsFile()
    local text = serializeSettings(cfg)
    local ok, err = pcall(function()
        local file = assert(io.open(SETTINGS_FILE, "w"))
        file:write(text)
        file:close()
    end)
    if ok then lastSettingsText = text else log("settings.txt write failed: " .. tostring(err)) end
end
local function rateFor(enabled) return enabled and cfg.rate or 1.0 end
local function anySpeedUp() return cfg.rate ~= 1.0 and (cfg.game or cfg.sfx) end
local dirty, queued = false, false
local lastWorld, lastError, correctionCount = nil, nil, 0
local statics = nil
local function failOnce(message)
    if message ~= lastError then log(message); lastError = message end
end
local function valid(object) return object ~= nil and object:IsValid() end
-- CRI clamps frequency ratios above MaxPitch (cents) or a pool's max sampling rate.
local settingsLogged = false
local function logAudioLimits()
    if settingsLogged then return end
    settingsLogged = true
    local settings = StaticFindObject("/Script/CriWareRuntime.Default__CriWarePluginSettings")
    if not valid(settings) then log("CriWarePluginSettings not found; audio clamp limits UNKNOWN"); return end
    for _, field in ipairs({"MaxPitch", "StandardMemoryVoiceSamplingRate", "StandardStreamingVoiceSamplingRate", "WASAPI_SamplingRate"}) do
        local ok, value = pcall(function() return settings[field] end)
        log("Audio limit " .. field .. "=" .. tostring(ok and value or ("read failed: " .. tostring(value))))
    end
    log("2.0x on 48 kHz audio needs MaxPitch>=1200 and SamplingRate>=96000, otherwise CRI clamps the speed-up.")
end
-- Game thread only. Pooled components keep the multiplier; the poll catches new ones.
-- shortcut: BGM matched by "bgm" in the cue sheet path (unconfirmed); fix after an F7 AudioDiscovery snapshot during BGM.
local function soundPath(component)
    local ok, name = pcall(function() return component.Sound:GetFullName() end)
    return ok and type(name) == "string" and name:lower() or ""
end
local function isBgm(component) return soundPath(component):find("bgm", 1, true) ~= nil end
-- Pitch fix: xrd777_ff.acf (built by p3r-pitch/patchacf.py, loaded via Engine.ini AcfFileName) adds one bus per rate
-- whose CRIWARE/PitchShifter lowers pitch by 1/rate. Sped non-BGM components send there instead of MasterOut.
local PITCH_BUS = {[1.5] = "Zff_Pitch15", [2.0] = "Zff_Pitch20"} -- 5x would need ratio 0.2, below the plugin's 0.25 floor
local MASTER_BUS = "MasterOut"
-- In gameplay rack 0 has no DSP bus setting attached (vanilla ACF too), so only MasterOut reaches the speakers and every
-- other bus send is lost (peak meter, 2026-10-19). Attaching also revives the stock FX buses vanilla never plays: mute them.
local DSP_SETTING = "DspBusSetting_0"
local STOCK_FX_BUSES = {"Reverb", "I3DL2 Rev", "Matrix", "Surrounder"}
-- Loading a save drops the setting natively (no AtomAsrRack UFunction call, no LoadMap: P3R stays in LV_Xrd777_P and
-- streams sublevels; title 7 levels -> 19 -> 9 in gameplay, BusDiag 2026-10-19). So any change of
-- "<world address>/<loaded level count>" marks the setting stale (the count can come back to its old value) and it
-- re-attaches once that key has held for SETTLE_POLLS polls. Every settings change re-attaches too (toggling the pitch
-- fix is the manual recovery). Not every poll: each attach silences all output for ~70 ms.
local SETTLE_POLLS = 2
local dspStale = true -- key changed since the last attach
local seenKey, seenPolls = nil, 0
local function attachDsp(key)
    local rack = StaticFindObject("/Script/CriWareRuntime.Default__AtomAsrRack"):GetDefaultAsrRack()
    if not valid(rack) then error("default AtomAsrRack not found") end
    rack:AttachDspBusSetting(DSP_SETTING)
    for _, bus in ipairs(STOCK_FX_BUSES) do rack:SetBusVolumeByName(bus, 0.0) end
    dspStale = false
    log("Attached " .. DSP_SETTING .. " to rack 0 (world/levels=" .. key .. "); stock FX buses muted")
end
local routed = {} -- component address -> bus it was routed to; absent = untouched, false = restored to MasterOut
-- Player send levels multiply the cue's own levels, so a bus the cue never sends to needs the additive offset.
local function setSend(component, bus, level)
    if bus == MASTER_BUS then component:SetBusSendLevelByName(bus, level) else component:SetBusSendLevelOffsetByName(bus, level) end
end
-- force re-sends a bus route the cache already holds (the cache cannot see a new component at a recycled address).
local function route(component, bus, force)
    local key = tostring(component:GetAddress())
    local previous = routed[key]
    if (previous or nil) == bus and not (force and bus) then return false end
    if previous == nil and bus == nil then return false end -- never routed: leave the cue's own sends alone
    if previous and previous ~= bus then setSend(component, previous, 0.0) end
    if bus then setSend(component, bus, 1.0) end
    setSend(component, MASTER_BUS, bus and 0.0 or 1.0)
    routed[key] = bus or false
    return true
end
local function applyAudio(sfxRate, resend)
    local changed, failed, bgm, routedCount = 0, 0, 0, 0
    for _, component in ipairs(FindAllOf("AtomComponent") or {}) do
        local ok, wrote = pcall(function()
            if not component:IsValid() then return false end
            -- Pooled components can switch between BGM and SFX, so every component is re-targeted each poll.
            local target, music = sfxRate, isBgm(component)
            if music then target = 1.0; bgm = bgm + 1 end
            local bus = cfg.pitch and not music and PITCH_BUS[target] or nil
            local readOK, current = pcall(function() return component.PitchMultiplier end)
            local pitched = readOK and type(current) == "number" and math.abs(current - target) <= 0.001
            -- Off target = a new component (maybe at a recycled address the cache maps to a bus) or a rate change: re-send.
            -- Scene changes left such sounds sped up on MasterOut until the user toggled the fix (2026-10-19).
            local rerouted = route(component, bus, resend or not pitched)
            if bus then routedCount = routedCount + 1 end
            if pitched then return rerouted end
            component:SetPitchMultiplier(target)
            return true
        end)
        if not ok then failed = failed + 1; failOnce("Audio apply failed: " .. tostring(wrote)) elseif wrote then changed = changed + 1 end
    end
    return changed, failed, bgm, routedCount
end
local function resolveWorld()
    -- UEHelpers requires a possessed pawn; a live viewport does not.
    local viewportOK, viewportWorld = pcall(function()
        local viewport = FindFirstOf("GameViewportClient")
        if not valid(viewport) then return nil end
        local world = viewport:GetWorld()
        if valid(world) then return world end
    end)
    if viewportOK and viewportWorld then return viewportWorld, "GameViewportClient" end
    local helperOK, helperWorld = pcall(function()
        local world = helpers.GetWorld()
        if valid(world) then return world end
    end)
    if helperOK and helperWorld then return helperWorld, "UEHelpers" end
    return nil, "viewport=" .. (viewportOK and "no valid world" or tostring(viewportWorld))
        .. "; UEHelpers=" .. (helperOK and "no valid world" or tostring(helperWorld))
end
-- Called ONLY on the game thread, and only from reconcile.
local function applyDilation(world, rate)
    local before = statics:GetGlobalTimeDilation(world)
    if type(before) ~= "number" or before ~= before then error("Invalid time-dilation readback") end
    -- shortcut: preserve game-owned slow motion; global dilation cannot compose
    -- every cinematic clock. Revisit after measured game-specific timing tests.
    -- A fresh user request (dirty) for a speed-up still overrides it.
    if not isRate(before) and (rate == 1.0 or not dirty) then
        failOnce("Game-owned dilation=" .. tostring(before) .. "; not overriding cinematic slow motion.")
        return before, before
    end
    if math.abs(before - rate) > 0.001 then
        statics:SetGlobalTimeDilation(world, rate)
        if not dirty then
            correctionCount = correctionCount + 1
            if correctionCount == 1 or correctionCount % 30 == 0 then
                log("Game reset dilation; corrections=" .. correctionCount .. ". If speed oscillates, disable mod and report scene.")
            end
        end
    end
    local after = statics:GetGlobalTimeDilation(world)
    if type(after) ~= "number" or after ~= after or math.abs(after - rate) > 0.001 then
        error("SetGlobalTimeDilation readback mismatch: requested=" .. rate .. " actual=" .. tostring(after))
    end
    return before, after
end
-- Called ONLY on the game thread. Never retain a world across travel/GC.
local function reconcile(reason)
    if not anySpeedUp() and not dirty then return end
    local world, worldSource = resolveWorld()
    if not world then
        failOnce("World lookup pending; requested settings retained. " .. worldSource)
        return
    end
    if not valid(statics) then
        statics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    end
    if not valid(statics) then error("GameplayStatics lookup failed; check UE4SS scan/reflection logs") end
    local identity = tostring(world:GetAddress())
    local changedWorld = identity ~= lastWorld
    if changedWorld then
        log("World=" .. world:GetFullName() .. " address=" .. identity .. " source=" .. worldSource .. "; GameplayStatics resolved")
        lastWorld = identity
    end
    local gameRate, sfxRate = rateFor(cfg.game), rateFor(cfg.sfx)
    local before, after = applyDilation(world, gameRate)
    logAudioLimits()
    local levels = "?"
    pcall(function() levels = tostring(#world.Levels) end)
    local key = identity .. "/" .. levels
    if key == seenKey then seenPolls = seenPolls + 1 else seenKey, seenPolls, dspStale = key, 0, true end
    -- Every attach also re-sends every component's bus sends: the same as toggling the fix off and on.
    local resend = cfg.pitch and PITCH_BUS[sfxRate] and (dirty or (dspStale and seenPolls >= SETTLE_POLLS)) or false
    if resend then
        local attached, why = pcall(attachDsp, key)
        if not attached then failOnce("DSP bus setting attach failed; pitch-fixed sounds may be silent: " .. tostring(why)) end
    end
    local audioChanged, audioFailed, audioBgm, audioRouted = applyAudio(sfxRate, resend)
    if dirty or changedWorld or resend then
        log(string.format("%s game=%.1f sfx=%.1f pitchFix=%s; dilation %.3f -> %.3f; audio changed=%d failed=%d bgmMatched=%d pitchRouted=%d",
            reason, gameRate, sfxRate, tostring(cfg.pitch), before, after, audioChanged, audioFailed, audioBgm, audioRouted))
    end
    -- ASCII only: GUI console glyph support for UTF-8 is unverified.
    if dirty then log(string.format("===== GAME %.1fx  SFX %.1fx =====", gameRate, sfxRate)) end
    lastWorld, lastError, dirty = identity, nil, false
end
-- Coalesce dispatches: rapid presses retain parity; restore survives loading.
local function schedule(reason)
    if queued then return end
    queued = true
    local scheduled, err = pcall(ExecuteInGameThread, function()
        queued = false
        local applied, why = pcall(reconcile, reason)
        if not applied then failOnce("Apply failed (will retry): " .. tostring(why)) end
    end)
    if not scheduled then
        queued = false
        failOnce("Game-thread scheduling failed: " .. tostring(err))
    end
end
local function pollSettings()
    local text, parsed = readSettingsFile()
    if not text or text == lastSettingsText or not parsed then return end -- unparsed: partial write, retry next poll
    lastSettingsText, cfg, dirty = text, parsed, true
    log("settings.txt changed: " .. text:gsub("\n", " "))
end
local function launchGui()
    -- start returns at once; the window closes itself when P3R exits.
    local cmd = 'start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' .. MOD_DIR .. 'gui.ps1"'
    local ok, err = pcall(os.execute, cmd)
    if not ok then log("GUI launch failed: " .. tostring(err)) end
end
local active = false
local loopOK, loopError = pcall(LoopAsync, 500, function()
    if not active then return true end
    pollSettings()
    if anySpeedUp() or dirty then schedule("poll/travel") end
    return false
end)
if not loopOK then log("INIT FAILED: LoopAsync: " .. tostring(loopError)); return end
local keyOK, keyError = pcall(RegisterKeyBind, Key.F6, function()
    local index = 1
    for i, rate in ipairs(RATES) do
        if math.abs(rate - cfg.rate) <= 0.001 then index = i end
    end
    cfg.rate = RATES[index % #RATES + 1]
    writeSettingsFile() -- the GUI polls this file and shows the new rate
    dirty = true
    log(string.format("F6 detected; rate=%.1f; dispatch queued", cfg.rate))
    schedule("F6")
end)
if not keyOK then log("INIT FAILED: F6 registration: " .. tostring(keyError)); return end
local guiKeyOK, guiKeyError = pcall(RegisterKeyBind, Key.F8, launchGui)
if not guiKeyOK then log("F8 registration failed (GUI reopen unavailable): " .. tostring(guiKeyError)) end
-- Keep the saved toggles but always boot at 1.0x, as before the GUI existed.
local _, saved = readSettingsFile()
if saved then cfg = saved end
cfg.rate = 1.0
writeSettingsFile()
active, _G.P3RFF_loaded = true, true
writeApoPitch(1.0) -- clear compensation left over from a session that exited at 1.5x/2x
launchGui()
log("Loaded v0.6.6; " .. _VERSION .. "; settings=" .. SETTINGS_FILE .. "; F6 cycles 1.0/1.5/2.0/5.0, F8 opens GUI; LoopAsync=500ms.")
log("Restore with F6 before disabling. Hot unload unsupported; exit/restart game for reliable cleanup.")
