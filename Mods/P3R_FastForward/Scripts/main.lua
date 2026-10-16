-- Game speed plus AtomComponent pitch-multiplier audio speed-up.
-- User accepted raised pitch (resampling), so no time-stretch DSP is used.
local function log(message) print("[P3RFF] " .. message .. "\n") end
-- 5x passes 5 to SetPitchMultiplier uncompensated (user choice); CRI clamps it (see logAudioLimits).
local RATES = {1.0, 1.5, 2.0, 5.0} -- F6 cycles through these.
local rateIndex = 1
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
if not Key or not Key.F6 then log("INIT FAILED: Key.F6 unavailable"); return end
if type(IsKeyBindRegistered) == "function" and IsKeyBindRegistered(Key.F6) then
    log("INIT FAILED: F6 is already registered; resolve the other binding and restart.")
    return
end
-- Optional: set true only if Equalizer APO + Pitchproof are set up (see README).
local APO_ENABLED = false
-- Equalizer APO reloads on file change; its config.txt has "Include: p3r_pitch.txt".
-- Pitchproof chunk = Blend,Detune,Pitch,Key,Transient,MonoStereo,Detect,Function; Pitch 0.833=-7 st, 1.000=-12 st.
local APO_FILE = "C:\\Program Files\\EqualizerAPO\\config\\p3r_pitch.txt"
local PITCHPROOF = {
    [1.5] = "MS4wMDAsMC41MDAsMC44MzMsMC4wMDAsMS4wMDAsMC4wMDAsMC4wMDAsMC4wMDAA",
    [2.0] = "MS4wMDAsMC41MDAsMS4wMDAsMC4wMDAsMS4wMDAsMC4wMDAsMC4wMDAsMC4wMDAA",
}
local function writeApoPitch(rate)
    if not APO_ENABLED then return end
    local chunk = PITCHPROOF[rate]
    local text = chunk and ('VSTPlugin: Library pitchproof-x64.dll ChunkData "' .. chunk .. '"\n')
        or string.format("# %.1fx: no pitch compensation\n", rate)
    local ok, err = pcall(function()
        local file = assert(io.open(APO_FILE, "w"))
        file:write(text)
        file:close()
    end)
    if not ok then log("APO pitch file write failed (game speed unaffected): " .. tostring(err)) end
end
local desired, dirty, queued = 1.0, false, false
local lastWorld, lastError, correctionCount = nil, nil, 0
local statics = nil
local function failOnce(message)
    if message ~= lastError then log(message); lastError = message end
end
local function valid(object) return object ~= nil and object:IsValid() end
local function isModRate(value)
    for _, rate in ipairs(RATES) do
        if math.abs(value - rate) <= 0.001 then return true end
    end
    return false
end
-- CRI clamps frequency ratios above MaxPitch (cents) or a pool's max sampling rate.
local settingsLogged = false
local function logAudioLimits()
    if settingsLogged then return end
    settingsLogged = true
    local settings = StaticFindObject("/Script/CriWareRuntime.Default__CriWarePluginSettings")
    if not valid(settings) then log("CriWarePluginSettings not found; audio clamp limits UNKNOWN"); return end
    for _, field in ipairs({"MaxPitch", "StandardMemoryVoiceSamplingRate", "StandardStreamingVoiceSamplingRate"}) do
        local ok, value = pcall(function() return settings[field] end)
        log("Audio limit " .. field .. "=" .. tostring(ok and value or ("read failed: " .. tostring(value))))
    end
    log("2.0x on 48 kHz audio needs MaxPitch>=1200 and SamplingRate>=96000, otherwise CRI clamps the speed-up.")
end
-- Game thread only. Pooled components keep the multiplier; the poll catches new ones.
local function applyAudio(rate)
    local changed, failed = 0, 0
    for _, component in ipairs(FindAllOf("AtomComponent") or {}) do
        local ok, wrote = pcall(function()
            if not component:IsValid() then return false end
            local readOK, current = pcall(function() return component.PitchMultiplier end)
            if readOK and type(current) == "number" and math.abs(current - rate) <= 0.001 then return false end
            component:SetPitchMultiplier(rate)
            return true
        end)
        if not ok then failed = failed + 1 elseif wrote then changed = changed + 1 end
    end
    return changed, failed
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
-- Called ONLY on the game thread. Never retain a world across travel/GC.
local function reconcile(reason)
    if desired == 1.0 and not dirty then return end
    local world, worldSource = resolveWorld()
    if not world then
        failOnce("World lookup pending; requested rate retained. " .. worldSource)
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
    local before = statics:GetGlobalTimeDilation(world)
    if type(before) ~= "number" or before ~= before then error("Invalid time-dilation readback") end
    -- shortcut: preserve game-owned slow motion; global dilation cannot compose
    -- every cinematic clock. Revisit after measured game-specific timing tests.
    if desired ~= 1.0 and not dirty and not isModRate(before) then
        failOnce("Game-owned dilation=" .. tostring(before) .. "; waiting rather than overriding cinematic slow motion.")
        return
    end
    local needsWrite = math.abs(before - desired) > 0.001
    if needsWrite then statics:SetGlobalTimeDilation(world, desired) end
    local after = statics:GetGlobalTimeDilation(world)
    if type(after) ~= "number" or after ~= after or math.abs(after - desired) > 0.001 then
        error("SetGlobalTimeDilation readback mismatch: requested=" .. desired .. " actual=" .. tostring(after))
    end
    logAudioLimits()
    local audioChanged, audioFailed = applyAudio(desired)
    if dirty or changedWorld then
        log(string.format("%s requested=%.1f readback=%.3f -> %.3f; audio pitch x%.1f changed=%d failed=%d",
            reason, desired, before, after, desired, audioChanged, audioFailed))
    elseif needsWrite then
        correctionCount = correctionCount + 1
        if correctionCount == 1 or correctionCount % 30 == 0 then
            log("Game reset dilation; corrections=" .. correctionCount .. ". If speed oscillates, disable mod and report scene.")
        end
    end
    -- ASCII only: GUI console glyph support for UTF-8 is unverified.
    if dirty then log(string.format("===== SPEED NOW %.1fx =====", after)) end
    lastWorld, lastError, dirty = identity, nil, false
end
-- Coalesce dispatches: rapid presses retain parity; restore survives loading.
local function schedule(reason)
    if queued then return end
    queued = true
    local scheduled, err = pcall(ExecuteInGameThread, function()
        queued = false
        if reason == "F6" then log("F6 game-thread callback ran") end
        local applied, why = pcall(reconcile, reason)
        if not applied then failOnce("Apply failed (will retry): " .. tostring(why)) end
    end)
    if not scheduled then
        queued = false
        failOnce("Game-thread scheduling failed: " .. tostring(err))
    end
end
local active = false
local loopOK, loopError = pcall(LoopAsync, 500, function()
    if not active then return true end
    if desired ~= 1.0 or dirty then schedule("poll/travel") end
    return false
end)
if not loopOK then log("INIT FAILED: LoopAsync: " .. tostring(loopError)); return end
local keyOK, keyError = pcall(RegisterKeyBind, Key.F6, function()
    rateIndex = rateIndex % #RATES + 1
    desired = RATES[rateIndex]
    dirty = true
    writeApoPitch(desired)
    log(string.format("F6 detected; requested=%.1f; dispatch queued", desired))
    schedule("F6")
end)
if not keyOK then log("INIT FAILED: F6 registration: " .. tostring(keyError)); return end
active, _G.P3RFF_loaded = true, true
writeApoPitch(1.0) -- clear compensation left over from a session that exited at 1.5x/2x
log("Loaded v0.4.6; " .. _VERSION .. "; F6 cycles 1.0/1.5/2.0/5.0 (game + AtomComponent pitch); APO Pitchproof "
    .. (APO_ENABLED and "ON" or "off") .. "; LoopAsync=500ms.")
log("Restore with F6 before disabling. Hot unload unsupported; exit/restart game for reliable cleanup.")
