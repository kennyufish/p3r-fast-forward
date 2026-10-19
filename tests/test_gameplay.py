"""Execute the actual Lua entry point against a small UE4SS boundary mock.
Requires lupa (test-only). This is NOT Unreal runtime acceptance.
"""
from pathlib import Path
import sys
import unittest
from lupa.lua54 import LuaRuntime

SOURCE = Path(sys.argv.pop(1)) if len(sys.argv) > 1 and sys.argv[1].endswith('.lua') else Path(__file__).parents[1] / 'Mods/P3R_FastForward/Scripts/main.lua'
HARNESS = r'''
logs, queue, keys, loops = {}, {}, {}, {}
onGameThread, missingWorld, rejectWrite, rejectSchedule = false, false, false, false
viewportAvailable = false
world = {rate=1.0, address=100, name="World A"}
function world:IsValid() return true end
function world:GetAddress() return self.address end
function world:GetFullName() return self.name end
viewport = {}
function viewport:IsValid() return true end
function viewport:GetWorld() assert(onGameThread); return world end
function FindFirstOf(name)
    assert(onGameThread)
    if name == 'GameViewportClient' and viewportAvailable then return viewport end
    if name == 'BP_BtlPhaseFighting_C' and battle then return battle end
end
statics = {valid=true, writes=0}
function statics:IsValid() return self.valid end
function statics:GetGlobalTimeDilation(w) assert(onGameThread); return w.rate end
function statics:SetGlobalTimeDilation(w, rate)
    assert(onGameThread); self.writes = self.writes + 1
    if not rejectWrite then w.rate = rate end
end
package.preload.UEHelpers = function() return {GetWorld=function()
    assert(onGameThread)
    if missingWorld then error("no controller") end
    return world
end} end
function print(s) table.insert(logs, s) end
function RegisterBeginPlayPostHook(cb) beginPlay = cb end
files, apoText = {}, nil -- in-memory settings.txt; apoText = last write to the APO file
io.open = function(path, mode)
    if mode == 'r' then
        if files[path] == nil then return nil, 'missing' end
        return {read=function() return files[path] end, close=function() end}
    end
    return {write=function(_, s) files[path] = s; if path:find('p3r_pitch', 1, true) then apoText = s end end, close=function() end}
end
os.execute = function() end -- the mod launches gui.ps1 on load
Key = {F6=117, F8=119, TAB=9}
battle = nil -- live BP_BtlPhaseFighting_C stand-in
rack = {attaches=0}
function rack:IsValid() return true end
function rack:AttachDspBusSetting() assert(onGameThread); self.attaches = self.attaches + 1 end
function rack:SetBusVolumeByName() end
function StaticFindObject(path)
    assert(onGameThread)
    if path:find('AtomAsrRack', 1, true) then return {GetDefaultAsrRack=function() return rack end} end
    return statics
end
function IsKeyBindRegistered(k) return keys[k] ~= nil end
function RegisterKeyBind(k, cb) assert(not keys[k]); keys[k] = cb end
function LoopAsync(delay, cb) assert(delay == 500); table.insert(loops, cb) end
function ExecuteInGameThread(cb)
    if rejectSchedule then error("scheduler unavailable") end
    table.insert(queue, cb)
end
function drain()
    local pending = queue; queue = {}; onGameThread = true
    for _, cb in ipairs(pending) do cb() end
    onGameThread = false
end
function press() keys[Key.F6]() end
components = {}
function makeComponent(pitch)
    local c = {PitchMultiplier=pitch or 1.0, sets=0, alive=true, sends={}}
    function c:IsValid() return self.alive end
    function c:GetAddress() return tostring(self) end
    function c:SetBusSendLevelByName(bus, level) self.sends[bus] = level end
    function c:SetBusSendLevelOffsetByName(bus, level) self.sends[bus] = level end
    function c:SetPitchMultiplier(r) assert(onGameThread); self.sets = self.sets + 1; self.PitchMultiplier = r end
    table.insert(components, c); return c
end
function FindAllOf(name) assert(onGameThread); assert(name == 'AtomComponent'); return components end
function tick() for _, cb in ipairs(loops) do cb() end; drain() end
function hasLog(s) for _, line in ipairs(logs) do if line:find(s,1,true) then return true end end; return false end
'''

class Gameplay(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime()
        self.lua.execute(HARNESS)
        self.source = SOURCE.read_text(encoding='utf-8-sig')
        self.lua.execute(self.source)

    def run_lua(self, code):
        self.lua.execute(code)

    def test_supported_scheduler_and_toggle(self):
        self.run_lua('assert(#loops == 1); assert(statics.writes == 0); press(); assert(world.rate == 1); drain(); assert(world.rate == 1.5); press(); drain(); assert(world.rate == 2.0); press(); drain(); assert(world.rate == 5.0); press(); drain(); assert(world.rate == 10.0); press(); drain(); assert(world.rate == 1)')

    def test_rapid_parity_and_bounded_dispatch(self):
        self.run_lua('for i=1,100 do press() end; assert(#queue == 1); drain(); assert(world.rate == 1); press(); drain(); assert(world.rate == 1.5)')

    def test_loading_retains_fast_and_restore(self):
        self.run_lua('missingWorld=true; press(); drain(); missingWorld=false; tick(); assert(world.rate == 1.5); missingWorld=true; press(); press(); press(); press(); drain(); missingWorld=false; tick(); assert(world.rate == 1)')

    def test_viewport_world_without_possessed_pawn(self):
        self.run_lua('missingWorld=true; viewportAvailable=true; press(); drain(); assert(world.rate == 1.5)')

    def test_travel_same_name_new_address_and_reset(self):
        self.run_lua('press(); drain(); world.address=200; world.rate=1; tick(); assert(world.rate == 1.5); world.rate=1; tick(); assert(world.rate == 1.5)')

    def test_preserves_cinematic_and_idle_normal(self):
        self.run_lua('world.rate=0.5; tick(); assert(world.rate == 0.5); world.rate=1; press(); drain(); world.rate=0.2; tick(); assert(world.rate == 0.2); world.rate=1; tick(); assert(world.rate == 1.5); press(); drain(); world.rate=0.7; tick(); assert(world.rate == 0.7)')

    def test_failed_setter_is_not_success(self):
        self.run_lua('rejectWrite=true; press(); drain(); assert(world.rate == 1); assert(hasLog("readback mismatch")); rejectWrite=false; tick(); assert(world.rate == 1.5)')

    def test_schedule_failure_retries(self):
        self.run_lua('rejectSchedule=true; press(); rejectSchedule=false; tick(); assert(world.rate == 1.5)')

    def test_duplicate_entry_no_new_callbacks(self):
        self.lua.execute(self.source)
        self.run_lua('assert(#loops == 1); press(); drain(); assert(world.rate == 1.5)')

    def test_waiting_logs_do_not_spam(self):
        self.run_lua('missingWorld=true; press(); drain(); local count=#logs; for i=1,100 do tick() end; assert(#logs == count)')

    def test_audio_pitch_follows_rate_and_restores(self):
        self.run_lua('''
            local a, b = makeComponent(), makeComponent()
            b.alive = false
            press(); drain(); assert(a.PitchMultiplier == 1.5); assert(b.PitchMultiplier == 1.0)
            local n = a.sets; tick(); assert(a.sets == n)
            local c = makeComponent(); tick(); assert(c.PitchMultiplier == 1.5)
            press(); drain(); assert(a.PitchMultiplier == 2.0 and c.PitchMultiplier == 2.0)
            press(); drain(); assert(a.PitchMultiplier == 5.0 and c.PitchMultiplier == 5.0)
            press(); drain(); assert(a.PitchMultiplier == 10.0 and c.PitchMultiplier == 10.0)
            press(); drain(); assert(a.PitchMultiplier == 1.0 and c.PitchMultiplier == 1.0)
            assert(hasLog("Audio limit MaxPitch="))
        ''')

    def test_apo_cleared_on_load_only(self):
        self.run_lua('assert(apoText:find("^# 1.0x: no pitch compensation")); apoText = nil; press(); drain(); assert(world.rate == 1.5); assert(apoText == nil)')

    def test_settings_file_drives_rate_and_f6_writes_it(self):
        self.run_lua('''
            local path; for p in pairs(files) do if p:find("settings.txt", 1, true) then path = p end end
            assert(files[path]:find("rate=1.0", 1, true))
            press(); assert(files[path]:find("rate=1.5", 1, true))
            files[path] = "rate=2.0\\ngame=1\\nsfx=1\\nbgm=0\\npitch=1\\n"; tick(); assert(world.rate == 2.0)
            files[path] = "rate=1.5\\ngame="; tick(); assert(world.rate == 2.0) -- partial write ignored
        ''')

    def test_speed_banner_logs_readback_after_f6_only(self):
        self.run_lua('''
            press(); drain(); assert(hasLog("GAME 1.5x"))
            local count=#logs; tick(); assert(#logs == count)
            press(); drain(); assert(hasLog("GAME 2.0x"))
            press(); drain(); assert(hasLog("GAME 5.0x"))
            press(); drain(); assert(hasLog("GAME 10.0x"))
            press(); drain(); assert(hasLog("GAME 1.0x"))
            logs = {}; rejectWrite=true; press(); drain(); assert(not hasLog("====="))
        ''')

    def test_rush_forces_5x_in_battle_and_restores_after(self):
        self.run_lua('''
            press(); drain(); assert(world.rate == 1.5)
            keys[Key.TAB](); drain(); assert(world.rate == 1.5) -- no battle: ignored
            battle = {IsValid=function() return true end}
            keys[Key.TAB](); drain(); assert(world.rate == 5.0)
            tick(); assert(world.rate == 5.0)
            keys[Key.TAB](); drain(); assert(world.rate == 1.5) -- Tab again cancels
            keys[Key.TAB](); drain(); assert(world.rate == 5.0)
            local fight = battle
            battle = nil; tick(); assert(world.rate == 5.0) -- one miss: phase actor may blink between turns
            battle = fight; tick(); battle = nil; tick(); assert(world.rate == 5.0)
            tick(); assert(world.rate == 1.5); assert(hasLog("Battle ended"))
            press(); press(); press(); press(); drain(); assert(world.rate == 1.0)
            battle = {IsValid=function() return true end}; keys[Key.TAB](); drain(); assert(world.rate == 5.0)
            battle = nil; tick(); tick(); assert(world.rate == 1.0)
            local path; for p in pairs(files) do if p:find("settings.txt", 1, true) then path = p end end
            files[path] = "rate=1.0\\ngame=1\\nsfx=1\\npitch=1\\nrush=1\\nrushrate=3.5\\n"; tick()
            battle = {IsValid=function() return true end}; keys[Key.TAB](); drain(); assert(world.rate == 3.5) -- custom RUSH rate
            tick(); assert(world.rate == 3.5) -- 3.5 is ours, not game-owned slow motion
            files[path] = "rate=1.0\\ngame=1\\nsfx=1\\npitch=1\\nrush=0\\nrushrate=3.5\\n"; tick(); assert(world.rate == 1.0) -- disabling ends it
            keys[Key.TAB](); drain(); assert(world.rate == 1.0); assert(hasLog("(disabled)"))
        ''')

    def test_audio_failure_does_not_block_game_speed(self):
        self.run_lua('''
            local bad = makeComponent(); function bad:SetPitchMultiplier() error("boom") end
            press(); drain(); assert(world.rate == 1.5); assert(hasLog("failed=1"))
        ''')

if __name__ == '__main__':
    unittest.main()
