# Offline test of main.lua pitch-bus routing and DSP bus setting attach with stubbed UE4SS globals.
# Requires lupa (test-only). Run: python tests/test_pitch.py
import os, sys, tempfile
from lupa.lua54 import LuaRuntime
SRC = os.path.join(os.path.dirname(__file__), '..', 'Mods', 'P3R_FastForward', 'Scripts', 'main.lua')
tmp = tempfile.mkdtemp().replace('\\', '/') + '/'
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
sends, pitches, loop, logs, attaches, volumes, worldAddr, rackOK = {}, {}, nil, {}, {}, {}, 7, true
local function comp(addr, sound)
  local c = {addr = addr}
  function c:IsValid() return true end
  function c:GetAddress() return addr end
  c.Sound = {GetFullName = function() return sound end}
  c.PitchMultiplier = 1.0
  function c:SetPitchMultiplier(v) self.PitchMultiplier = v; pitches[addr] = v end
  function c:SetBusSendLevelByName(bus, v) sends[#sends + 1] = addr .. ":" .. bus .. "=" .. v end
  function c:SetBusSendLevelOffsetByName(bus, v) sends[#sends + 1] = addr .. ":" .. bus .. "+=" .. v end
  return c
end
comps = {comp(1, "/Game/Sound/se_battle"), comp(2, "/Game/Sound/BGM_town"),
  comp(3, "/Game/Xrd777/CriData/CueSheet/Event/Voice_Event_Cmmu_103_030_C.Voice_Event_Cmmu_103_030_C")}
function FindAllOf(name) return comps end
levels = {1, 2, 3}
local world = {IsValid = function() return true end, GetAddress = function() return worldAddr end, GetFullName = function() return "World" end,
  Levels = levels}
function FindFirstOf() return {IsValid = function() return true end, GetWorld = function() return world end} end
local dil = 1.0
local statics = {IsValid = function() return true end,
  GetGlobalTimeDilation = function() return dil end, SetGlobalTimeDilation = function(_, _, r) dil = r end}
local rack = {IsValid = function() return true end,
  AttachDspBusSetting = function(_, name) attaches[#attaches + 1] = name end,
  SetBusVolumeByName = function(_, bus, v) volumes[bus] = v end}
local rackClass = {GetDefaultAsrRack = function() return rackOK and rack or nil end}
function StaticFindObject(path)
  if path:find("GameplayStatics") then return statics end
  if path:find("AtomAsrRack") then return rackClass end
  return nil
end
function RegisterKeyBind() end
function ExecuteInGameThread(f) f() end
function LoopAsync(ms, f) loop = f end
Key = {F6 = 1, F8 = 2}
package.preload.UEHelpers = function() return {GetWorld = function() return world end} end
os.execute = function() end
print = function(s) logs[#logs + 1] = s end
''')
src = open(SRC, encoding='utf-8').read()
fn = lua.eval('function(src, name) return assert(load(src, name)) end')(src, '@' + tmp + 'Scripts/main.lua')
fn()
def settings(text):
    open(tmp + 'settings.txt', 'w').write(text); lua.eval('loop')()
def sends(): r = list(lua.eval('sends').values()); lua.execute('sends = {}'); return r
def attaches(): return len(lua.eval('attaches'))
settings('rate=1.5\ngame=1\nsfx=1\nbgm=1\npitch=1\n')  # pre-v0.6.5 file: bgm=1 is ignored, BGM stays 1x
s = sends(); assert s == ['1:Zff_Pitch15+=1.0', '1:MasterOut=0.0', '3:Zff_Pitch15+=1.0', '3:MasterOut=0.0'], s  # voice routed too
assert lua.eval('pitches[1]') == 1.5 and lua.eval('pitches[2]') is None and lua.eval('pitches[3]') == 1.5
assert attaches() == 1 and lua.eval('attaches[1]') == 'DspBusSetting_0'
assert dict(lua.eval('volumes').items()) == {'Reverb': 0.0, 'I3DL2 Rev': 0.0, 'Matrix': 0.0, 'Surrounder': 0.0}
settings('rate=2.0\ngame=1\nsfx=1\npitch=1\n')
s = sends(); assert s == ['1:Zff_Pitch15+=0.0', '1:Zff_Pitch20+=1.0', '1:MasterOut=0.0',
                          '3:Zff_Pitch15+=0.0', '3:Zff_Pitch20+=1.0', '3:MasterOut=0.0'], s
assert attaches() == 2  # any settings change re-attaches (toggling the fix is the manual recovery)
settings('rate=2.0\ngame=1\nsfx=1\npitch=1\n')  # unchanged file: no resend
lua.eval('loop')(); assert sends() == [] and attaches() == 2  # plain poll: no re-attach
def polls(n):
    for _ in range(n): lua.eval('loop')()
lua.execute('levels[4] = 4'); polls(2); assert attaches() == 2  # save load streams levels: wait until the count holds
lua.execute('levels[4] = nil'); polls(2); assert attaches() == 2  # count still moving
polls(1); assert attaches() == 3  # held for 2 polls: re-attach (same world address, setting dropped)
RESEND = ['1:Zff_Pitch20+=1.0', '1:MasterOut=0.0', '3:Zff_Pitch20+=1.0', '3:MasterOut=0.0']
s = sends(); assert s == RESEND, s  # every attach re-sends all routes, like toggling the fix off and on
polls(3); assert attaches() == 3 and sends() == []
lua.execute('comps[3].PitchMultiplier = 1.0'); polls(1)  # new component at a recycled address the cache maps to Zff_Pitch20
s = sends(); assert s == ['3:Zff_Pitch20+=1.0', '3:MasterOut=0.0'] and lua.eval('pitches[3]') == 2.0, s
lua.execute('worldAddr = 8'); polls(3); assert attaches() == 4 and sends() == RESEND  # travel re-attaches
settings('rate=5.0\ngame=1\nsfx=1\npitch=1\n')
s = sends(); assert s == ['1:Zff_Pitch20+=0.0', '1:MasterOut=1.0', '3:Zff_Pitch20+=0.0', '3:MasterOut=1.0'], s  # no 5x bus: restored
settings('rate=1.0\ngame=1\nsfx=1\npitch=1\n')
assert sends() == [] and lua.eval('pitches[1]') == 1.0
settings('rate=1.5\ngame=1\nsfx=1\npitch=0\n')
assert sends() == []
lua.execute('worldAddr = 9'); polls(3); assert attaches() == 4  # pitch fix off: never attaches
settings('rate=2.0\ngame=1\nsfx=1\npitch=1\n'); sends(); assert attaches() == 5
lua.execute('comps[1].Sound = {GetFullName = function() return "/Game/CueSheet/BGM/bgm.bgm" end}')  # pooled component reused for BGM
settings('rate=1.5\ngame=1\nsfx=1\npitch=1\n')
s = sends(); assert s == ['1:Zff_Pitch20+=0.0', '1:MasterOut=1.0', '3:Zff_Pitch20+=0.0', '3:Zff_Pitch15+=1.0', '3:MasterOut=0.0'], s
lua.execute('rackOK = false; worldAddr = 10'); polls(3)  # attach failure must not stop audio routing
logs = list(lua.eval('logs').values())
assert any('DSP bus setting attach failed' in l for l in logs), logs
assert not any('failed: ' in l and 'Audio apply' in l for l in logs), logs
print('ok;', [l for l in logs if 'pitchRouted' in l][-1].strip())
