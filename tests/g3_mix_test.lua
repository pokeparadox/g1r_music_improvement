-- Plain Lua asserts for the offline GBA -> ChipAsm converter.
-- Run: cd <mod> && luajit tests/g3_mix_test.lua
package.path = "./?.lua;../gen1recomp/?.lua;" .. package.path
local mix = dofile("g3_mix.lua")

local function eq(actual, expected, label)
  assert(actual == expected, string.format("%s: expected %s, got %s",
    label, tostring(expected), tostring(actual)))
end

eq(mix.clockAt(0), 0, "clock zero")
eq(mix.clockAt(1), 1, "clock one")
eq(mix.clockAt(39), 68, "clock lookup")
eq(mix.clockAt(200), 200, "clock fallback")

-- voice 1, note key 60 vel 100 gate index 4, wait 1, tempo 200, end.
local track = string.char(0xBD, 0x01, 0xD3, 60, 100, 0x81, 0xBB, 0x64, 0xB1)
local decoded = mix.decodeTrack(track)
eq(#decoded.events, 2, "event count")
eq(decoded.events[1].kind, "note", "first event kind")
eq(decoded.events[1].tick, 0, "note tick")
eq(decoded.events[1].gate, 4, "note gate")
eq(decoded.events[1].key, 60, "note key")
eq(decoded.events[2].kind, "tempo", "second event kind")
eq(decoded.events[2].tick, 1, "tempo tick")
eq(decoded.events[2].tempo, 200, "tempo value")

local wave = {}
for i = 1, 32 do wave[i] = i % 2 == 0 and 1 or -1 end
local song = {
  tracks = 5,
  trackData = {
    track, "", "", "", "",
  },
  voicegroup = 1,
}
local voicegroups = {
  [1] = {
    [1] = { type = 1, wavParam = 0 },
    [2] = { type = 3, wave = wave },
    [3] = { type = 4 },
  },
}
local specs = mix.buildSpecs(song, voicegroups, { voicegroupId = 1 })
assert(specs, "buildSpecs returned nil")
eq(#specs, 2, "engine count")
eq(#specs[1].channels, 4, "first engine channels")
eq(#specs[2].channels, 4, "second engine channels")
eq(specs[1].tempo, 256, "base tempo")
local used = {}
for _, channel in ipairs(specs[1].channels) do
  assert(channel.hw >= 1 and channel.hw <= 4, "hw range")
  assert(not used[channel.hw], "duplicate hw")
  used[channel.hw] = true
  local last = channel.program[#channel.program]
  assert(last.loop and last.loop.count == 0, "channel loop terminator")
end

-- CALL has a 4-byte address; RET has no operand.  A shared operand read here
-- would skip the note after RET and make the track silent.
local callTrack = mix.decodeTrack(string.char(
  0xBD, 0x01,
  0xB3, 0x0B, 0x00, 0x00, 0x00,
  0xD3, 0x60, 0x64,
  0xB1,
  0xD4, 0x62, 0x64,
  0xB4
))
local callNotes = {}
for _, ev in ipairs(callTrack.events) do
  if ev.kind == "note" then callNotes[#callNotes + 1] = ev.key end
end
assert(#callNotes == 2, "CALL/RET keeps both notes")
table.sort(callNotes)
assert(callNotes[1] == 0x60 and callNotes[2] == 0x62, "CALL/RET keeps note pitches")

-- REPEAT reads a count byte then a 4-byte address.
local repeatTrack = mix.decodeTrack(string.char(
  0xBD, 0x01,
  0xB5, 0x02, 0x08, 0x00, 0x00, 0x00,
  0xD5, 0x64, 0x64,
  0xB1
))
local repeatNotes = 0
for _, ev in ipairs(repeatTrack.events) do
  if ev.kind == "note" and ev.key == 0x64 then repeatNotes = repeatNotes + 1 end
end
assert(repeatNotes == 1, "REPEAT count+addr consumes exactly its operands")

-- Real FRLG tracks use LFO/mod commands and running-status notes.  Stopping on
-- 0xC2 or on a bare key byte made every converted song silent.
local stream = mix.decodeTrack(string.char(
  0xBD, 0x01,
  0xC2, 0x2C, 0xC4, 0x00,
  0xD3, 60, 100,
  0x62, 100,
  0xB1
))
local streamNotes = 0
for _, ev in ipairs(stream.events) do
  if ev.kind == "note" then streamNotes = streamNotes + 1 end
end
assert(streamNotes == 2, "LFO/mod commands and running status keep notes")

-- A new note on the same track cuts the previous one.  Notes must keep their
-- original onset spacing; old code emitted a full gate then added a rest.
local tightTrack = string.char(0xBD, 0x01, 0xDB, 60, 100, 0x84, 0xDB, 62, 100, 0xB1)
local tightSpec = mix.buildSpecs({
  tracks = 1,
  trackData = { tightTrack },
  voicegroup = 1,
}, voicegroups, { voicegroupId = 1 })[1]
local program = tightSpec.channels[1].program
local pitches, restsBeforeSecond = 0, 0
for _, event in ipairs(program) do
  if event.pitch then
    pitches = pitches + 1
    if pitches == 1 then eq(event.len, 4, "cut note keeps clamped gate") end
  elseif event.rest and pitches == 1 then
    restsBeforeSecond = restsBeforeSecond + (event.rest or 0)
  end
end
eq(pitches, 2, "tight track emits both notes")
eq(restsBeforeSecond, 0, "no extra rest between tight notes")

local okAsm, ChipAsm = pcall(require, "src.audio.ChipAsm")
if okAsm then
  local chip = ChipAsm.song(specs[1]).chip
  assert(#chip.blob > 4, "chip blob has events")
  -- Replace note events with rests; the assembled blob must change.
  local quiet = {}
  for key, value in pairs(specs[1]) do quiet[key] = value end
  quiet.channels = {}
  for channelIndex, channel in ipairs(specs[1].channels) do
    local copy = {}
    for key, value in pairs(channel) do copy[key] = value end
    copy.program = {}
    for eventIndex, event in ipairs(channel.program) do
      if event.pitch then
        copy.program[eventIndex] = { rest = event.len }
      else
        copy.program[eventIndex] = event
      end
    end
    quiet.channels[channelIndex] = copy
  end
  assert(ChipAsm.song(quiet).chip.blob ~= chip.blob, "chip blob contains note events")
end

-- 0xCD xop 12 sets a 16-bit rest; consuming bytes without applying them puts
-- the next section at the wrong tick.
local restTrack = mix.decodeTrack(string.char(
  0xBD, 0x01,
  0xCD, 0x0C, 0x05, 0x00,
  0xD3, 60, 100,
  0xB1
))
local restNote
for _, ev in ipairs(restTrack.events) do
  if ev.kind == "note" then restNote = ev end
end
assert(restNote and restNote.tick == 5, "xop 12 applies 16-bit wait")

-- MP2K memory/branch: set mem[1]=5, then conditional EQ jumps past note 60.
local branchBytes = string.char(
  0xBD, 0x01,
  0xB9, 0, 1, 5,
  0xB9, 6, 1, 5, 17, 0, 0, 0,
  0xD3, 60, 100,
  0xD3, 62, 100,
  0xB1
)
local branchNotes = {}
for _, ev in ipairs(mix.decodeTrack(branchBytes).events) do
  if ev.kind == "note" then branchNotes[#branchNotes + 1] = ev.key end
end
eq(#branchNotes, 1, "conditional branch keeps one note")
eq(branchNotes[1], 62, "conditional branch takes the jump")

-- ENDTIE releases a tied note; converter needs an off event to clamp its gate.
local tieTrack = mix.decodeTrack(string.char(
  0xBD, 0x01,
  0xCF, 60, 100,
  0x84,
  0xCE,
  0xB1
))
local tieOff
for _, ev in ipairs(tieTrack.events) do
  if ev.kind == "off" then tieOff = ev end
end
assert(tieOff and tieOff.key == 60 and tieOff.tick == 4, "ENDTIE emits note off")

-- Backward GOTO marks a loop section.  Final loop must target that section,
-- not replay the intro on every pass.
local loopTrack = string.char(
  0xBD, 0x01,
  0xD3, 60, 100,
  0xB0,
  0xD3, 62, 100,
  0xB2, 6, 0, 0, 0
)
local loopDecoded = mix.decodeTrack(loopTrack)
assert(loopDecoded.loopTo, "backward GOTO records loop target")
local loopSpec = mix.buildSpecs({
  tracks = 1,
  trackData = { loopTrack },
  voicegroup = 1,
}, voicegroups, { voicegroupId = 1 })[1]
local loopProgram = loopSpec.channels[1].program
local finalLoop = loopProgram[#loopProgram].loop
assert(finalLoop and finalLoop.to > 1, "song loop skips the intro")

-- GOTO target can land inside a long wait run with no emitted event. Resolve
-- tick from byte address, not first later note.
local gapTrack = string.char(
  0xBD, 0x01,
  0xD3, 60, 100,
  0xB0,
  0xD4, 62, 100,
  0xB2, 5, 0, 0, 0
)
local gapDecoded = mix.decodeTrack(gapTrack)
eq(gapDecoded.loopTick, 0, "GOTO target tick uses recorded address")
local gapProgram = mix.buildSpecs({
  tracks = 1,
  trackData = { gapTrack },
  voicegroup = 1,
}, voicegroups, { voicegroupId = 1 })[1].channels[1].program
assert(gapProgram[#gapProgram].loop.to < #gapProgram,
  "loop target precedes post-gap note")

-- Tempo byte is half MPlay tempo; 19200/raw keeps GB note length in sync with
-- the 0.8*raw ticks/second M4A sequencer.
local tempoTrack = string.char(
  0xBB, 100,
  0xD3, 60, 100,
  0xB1
)
local tempoSpec = mix.buildSpecs({
  tracks = 1,
  trackData = { tempoTrack },
  voicegroup = 1,
}, voicegroups, { voicegroupId = 1 })[1]
eq(tempoSpec.tempo, 192, "M4A tempo byte maps to GB tempo register")

-- FRLG song labels include bgm, fanfare and se tracks; only missing data or
-- MUS_NONE should be skipped.
assert(mix.isPlayableSong({ kind = "bgm", tracks = 1 }), "bgm accepted")
assert(mix.isPlayableSong({ kind = "fanfare", tracks = 1 }), "fanfare accepted")
assert(mix.isPlayableSong({ kind = "se", tracks = 1 }), "se accepted")
assert(not mix.isPlayableSong({ kind = "none", tracks = 1 }), "MUS_NONE skipped")
assert(not mix.isPlayableSong({ kind = "bgm", tracks = 0 }), "empty track skipped")

-- Rhythm kits are keyed by MIDI note, not rawKey % 4.
eq(mix.drumPresetFor(36).id, 4, "kick uses low noise")
eq(mix.drumPresetFor(42).id, 1, "closed hat uses high noise")
eq(mix.drumPresetFor(41).kind, 1, "tom uses pitched channel")

-- Full ADSR mapping: plucks decay, sustained tones swell.  ChipSynth treats
-- fade > 0 as decay and fade < 0 as a swell.
local pluckVolume, pluckFade, pluckDuty = mix.envelopeFor({
  vel = 100, volume = 200, tone = { attack = 0, decay = 14, sustain = 2 },
}, 2)
assert(pluckFade >= 5 and pluckDuty == 1, "pluck envelope")
local _, sustainedFade, sustainedDuty = mix.envelopeFor({
  vel = 127, volume = 255, tone = { attack = 0, decay = 2, sustain = 15 },
}, 2)
assert(sustainedFade == -1 and sustainedDuty == 3, "sustained envelope")

-- Perceptual volume curve keeps quiet M4A tracks audible without clipping.
local quietVolume = mix.envelopeFor({ vel = 127, volume = 39 })
local loudVolume = mix.envelopeFor({ vel = 127, volume = 255 })
assert(quietVolume >= 5 and quietVolume <= 7, "quiet track stays audible")
assert(loudVolume == 15, "loud track reaches full scale")
assert(loudVolume > quietVolume, "volume stays ordered")
eq(mix.envelopeFor({ vel = 127, volume = 45, gainScale = 1.4 }), 7,
  "lead gain scale raises quiet wave note")

-- BEND inside a long note splits pitch without retriggering the envelope.
local bendTrack = string.char(
  0xBB, 100,
  0xBD, 0x01,
  0xD3, 60, 100,
  0x82,
  0xC0, 0x42,
  0xB1
)
local bendSpec = mix.buildSpecs({
  tracks = 1, trackData = { bendTrack }, voicegroup = 1,
}, voicegroups, { voicegroupId = 1 })[1]
local bendProgram = bendSpec.channels[1].program
local bendPitches, bendNotetypes = {}, 0
for _, event in ipairs(bendProgram) do
  if event.pitch then bendPitches[#bendPitches + 1] = event.pitch end
  if event.notetype then bendNotetypes = bendNotetypes + 1 end
end
assert(#bendPitches >= 2, "bend emits multiple pitch segments")
assert(bendPitches[1] ~= bendPitches[2], "bend changes segment pitch")
eq(bendNotetypes, 1, "pitch split does not retrigger notetype")

-- A pitch split whose segments need different note speeds must re-emit
-- notetype; otherwise the first speed stretches the whole note and desyncs
-- later channels (Gym Leader Battle, track 2).
local splitTrack = string.char(
  0xBD, 0x01,
  0xCF, 60, 100, 60,
  0xA0,
  0xC0, 0x42,
  0xB1
)
local splitSpec = mix.buildSpecs({
  tracks = 1, trackData = { splitTrack }, voicegroup = 1,
}, voicegroups, { voicegroupId = 1 })[1]
local splitProgram = splitSpec.channels[1].program
local splitSpeeds, splitTicks = {}, 0
for _, event in ipairs(splitProgram) do
  if event.notetype and event.notetype.speed then
    splitSpeeds[#splitSpeeds + 1] = event.notetype.speed
  end
  if event.len then
    splitTicks = splitTicks + event.len * (splitSpeeds[#splitSpeeds] or 1)
  end
end
eq(#splitSpeeds, 2, "different segment speeds re-emit notetype")
eq(splitSpeeds[1], 3, "first segment uses speed 3")
eq(splitSpeeds[2], 1, "second segment uses speed 1")
eq(splitTicks, 60, "segmented note keeps original gate duration")

-- Zero-volume dummy triggers are dropped; same-tick duplicates coalesce.
local function noteCount(bytes)
  local count = 0
  for _, event in ipairs(mix.decodeTrack(bytes).events) do
    if event.kind == "note" then count = count + 1 end
  end
  return count
end
eq(noteCount(string.char(0xBD, 0x01, 0xD3, 60, 10, 0xB1)), 0, "low velocity dropped")
local duplicate = mix.decodeTrack(string.char(
  0xBD, 0x01, 0xD3, 60, 100, 0xD3, 60, 100, 0xB1
))
eq(#duplicate.events, 1, "same-tick duplicate coalesced")
assert(duplicate.events[1].volume < 100, "duplicate volume lowered")

-- Exact note timing avoids per-note rounding drift.
local noteSpeed, noteLength = mix.noteTiming(100)
eq(noteSpeed, 10, "gate 100 uses speed 10")
eq(noteLength, 10, "gate 100 uses length 10")
local oddSpeed, oddLength = mix.noteTiming(223)
assert(oddSpeed * oddLength <= 223, "unrepresentable gate never rounds up")

local oddTrack = string.char(0xBD, 1, 0xFF, 60, 100, 127, 0xB1)
local oddSpec = mix.buildSpecs({
  tracks = 1, trackData = { oddTrack }, voicegroup = 1,
}, voicegroups, { voicegroupId = 1 })[1]
local oddTotal, oddState = 0, 1
for _, event in ipairs(oddSpec.channels[1].program) do
  if event.notetype and event.notetype.speed then oddState = event.notetype.speed end
  if event.len then oddTotal = oddTotal + event.len * oddState
  elseif event.rest then oddTotal = oddTotal + event.rest * oddState end
end
eq(oddTotal, 223, "unrepresentable gate padded to exact duration")

-- Tempo changes from any track are replayed on every chip channel.
local sharedTempoSong = {
  tracks = 2,
  trackData = {
    string.char(0xBB, 100, 0xD3, 60, 100, 0x81, 0xBB, 120, 0xD3, 62, 100, 0xB1),
    string.char(0xD3, 64, 100, 0xB1),
  },
  voicegroup = 1,
}
local sharedSpec = mix.buildSpecs(sharedTempoSong, voicegroups, { voicegroupId = 1 })[1]
for _, channel in ipairs(sharedSpec.channels) do
  local tempoEvents = 0
  for _, event in ipairs(channel.program) do
    if event.tempo then tempoEvents = tempoEvents + 1 end
  end
  eq(tempoEvents, 1, "shared tempo change reaches every channel")
end

assert(loopDecoded.loopTick ~= nil, "loop tick recorded")

-- Bare bytes after 0xCD reuse it as running status: 09 08 is another XRMI
-- command, not an operand of the previous one.  Consuming 09 as a status
-- byte skipped the rest of the track (MUS_LEVEL_UP, MUS_OAK_LAB, ...).
local xrmiTrack = string.char(
  0xBC, 0x00, 0xBB, 0x57, 0xBD, 0x2E,
  0xCD, 0x08, 0x08, 0x09, 0x08,
  0xBE, 0x5A, 0xBF, 0x70, 0x88,
  0xD3, 0x47, 0x64, 0x88, 0xD3, 0x88, 0xD3, 0x88,
  0xE7, 0x50, 0x8A, 0xC4, 0x05, 0x86, 0x98, 0xB1
)
local xrmiDecoded = mix.decodeTrack(xrmiTrack)
eq(xrmiDecoded.ticks, 72, "running-status XRMI keeps full timeline")
local xrmiNotes = 0
for _, event in ipairs(xrmiDecoded.events) do
  if event.kind == "note" then xrmiNotes = xrmiNotes + 1 end
end
eq(xrmiNotes, 4, "running-status XRMI keeps all notes")
eq(xrmiDecoded.events[3].tick, 8, "first note after XRMI chain")
eq(xrmiDecoded.events[6].gate, 24, "last note gate after XRMI chain")

-- Wave tracks get a level derived from note volume; fixed quarter amplitude
-- made them disappear beside pulse tracks.
local waveTrack = string.char(
  0xBD, 0x02, 0xBE, 0x4B, 0xD3, 60, 100, 0xB1
)
local waveSpec = mix.buildSpecs({
  tracks = 1, trackData = { waveTrack }, voicegroup = 1,
}, voicegroups, { voicegroupId = 1 })[1]
local waveLevel
for _, channel in ipairs(waveSpec.channels) do
  for _, event in ipairs(channel.program) do
    if event.notetype and event.notetype.waveLevel then
      waveLevel = event.notetype.waveLevel
      break
    end
  end
end
eq(waveLevel, 1, "audible wave uses full wave level")

-- Sparse wave lead with a low M4A volume must not collapse to half amplitude.
local leadWave = {}
for i = 1, 32 do leadWave[i] = (i - 1) % 16 end
local leadVoicegroups = {
  [1] = {
    [1] = { type = 3, wave = leadWave, attack = 0, decay = 2, sustain = 4 },
    [2] = { type = 1, attack = 0, decay = 0, sustain = 15 },
  },
}
local leadSpec = mix.buildSpecs({
  tracks = 2,
  trackData = {
    string.char(0xBD, 1, 0xBE, 45, 0xD3, 79, 127, 0xB1),
    string.char(0xBD, 2, 0xBE, 90, 0xD3, 45, 127, 0xB1),
  },
  voicegroup = 1,
}, leadVoicegroups, { voicegroupId = 1 })[1]
local leadWaveLevel
for _, channel in ipairs(leadSpec.channels) do
  for _, event in ipairs(channel.program) do
    if event.notetype and event.notetype.waveLevel then
      leadWaveLevel = event.notetype.waveLevel
      break
    end
  end
end
eq(leadWaveLevel, 1, "sparse wave lead reaches full wave level")

-- Cache index voicegroupId wins over the ROM pointer in song.voicegroup.
-- Otherwise every tone lookup misses and all instruments share one envelope.
local envelopeVoicegroups = {
  [1] = { [1] = { type = 1, attack = 0, decay = 0, sustain = 15 } },
}
local envelopeSpec = mix.buildSpecs({
  tracks = 1, trackData = { string.char(0xBD, 1, 0xD3, 60, 100, 0xB1) },
  voicegroup = 999,
}, envelopeVoicegroups, { voicegroupId = 1 })[1]
local envelopeFade
for _, channel in ipairs(envelopeSpec.channels) do
  for _, event in ipairs(channel.program) do
    if event.notetype and event.notetype.fade ~= nil then
      envelopeFade = event.notetype.fade
      break
    end
  end
end
eq(envelopeFade, -1, "index voicegroupId selects instrument envelope")

-- GBA wave RAM is 0..15 while ChipSynth expects -1..1 samples, and the first
-- custom wave must be instrument 4 (after the four built-in waves).
local rawWave = {}
for i = 1, 32 do rawWave[i] = (i - 1) % 16 end
local customWaveVg = {
  [1] = { [1] = { type = 3, wave = rawWave } },
}
local customWaveSpec = mix.buildSpecs({
  tracks = 1,
  trackData = { string.char(0xBD, 1, 0xD3, 60, 100, 0xB1) },
  voicegroup = 1,
}, customWaveVg, { voicegroupId = 1 })[1]
local customInstrument
for _, channel in ipairs(customWaveSpec.channels) do
  for _, event in ipairs(channel.program) do
    if event.notetype and event.notetype.waveInstrument then
      customInstrument = event.notetype.waveInstrument
    end
  end
end
eq(customInstrument, 4, "first custom wave uses 0-based instrument index")
eq(customWaveSpec.waves[5][1], -1, "custom wave normalizes low nibble")
assert(math.abs(customWaveSpec.waves[5][16] - 1) < 0.001,
  "custom wave normalizes high nibble")

-- Mixed voices in one spec must reach different GB hardware instead of
-- collapsing to each track's dominant kind.
local mixedVg = {
  [1] = {
    [1] = { type = 1, attack = 0, decay = 0, sustain = 15 },
    [2] = { type = 3, wave = rawWave },
  },
}
local mixedSpec = mix.buildSpecs({
  tracks = 2,
  trackData = {
    string.char(0xBD, 1, 0xD3, 60, 100, 0xB1),
    string.char(0xBD, 2, 0xD3, 67, 100, 0xB1),
  },
  voicegroup = 1,
}, mixedVg, { voicegroupId = 1 })[1]
local pulseHw, waveHw
for _, channel in ipairs(mixedSpec.channels) do
  for _, event in ipairs(channel.program) do
    if event.notetype and event.notetype.volume then pulseHw = channel.hw end
    if event.notetype and event.notetype.waveLevel then waveHw = channel.hw end
  end
end
assert(pulseHw and waveHw, "mixed pulse and wave notes both survive")
assert(pulseHw ~= waveHw, "mixed notes use different hardware")
assert(type(mixedSpec.gain) == "number" and mixedSpec.gain > 0
  and mixedSpec.gain < 1, "side spec gain is scaled")

-- Slow MP2K attack is approximated by a GB swell with wide duty.
local slowAttackVolume, slowAttackFade, slowAttackDuty =
  mix.envelopeFor({ vel = 100, volume = 100,
    tone = { attack = 5, decay = 1, sustain = 15 } }, 2)
eq(slowAttackFade, -2, "slow attack swells")
eq(slowAttackDuty, 3, "slow attack uses wide duty")
assert(slowAttackVolume > 0, "slow attack keeps audible volume")

-- Gen1/Gen2 hosts deny engine game3 modules. Conversion still works with the
-- static song map and local M4A header parser.
local function u32(n)
  return string.char(n % 256, math.floor(n / 256) % 256,
    math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end
local offlineTrack = string.char(0xBD, 0x01, 0xD3, 60, 100, 0xB1)
local offlineBlob = string.char(1, 0, 0, 0, 0, 0, 0, 0)
  .. u32(16) .. u32(#offlineTrack) .. offlineTrack .. string.rep("\0", 6)
local offlineFiles = {
  ["index.lua"] = "return { songs = { [99] = { kind = 'bgm', tracks = 1, voicegroupId = 1 } } }",
  ["voicegroups.lua"] = "return { [1] = { [1] = { type = 1, attack = 0, decay = 0, sustain = 15, release = 0 } } }",
  ["songs/99.bin"] = offlineBlob,
}
package.loaded["src.import.CacheFs"] = {
  readAt = function(rel)
    rel = tostring(rel)
    for suffix, body in pairs(offlineFiles) do
      if rel:sub(-#suffix) == suffix then return body end
    end
    return nil
  end,
}
mix.setSongIds({ firered = { MUS_OFFLINE_TEST = 99 } })
local realRequire = require
_G.require = function(name, ...)
  if tostring(name):match("^src%.core%.game3%.") then
    error("game3 modules denied on this host", 0)
  end
  return realRequire(name, ...)
end
assert(mix.has("firered", "MUS_OFFLINE_TEST"), "static song map resolves labels")
local offline = mix.convert("firered", "MUS_OFFLINE_TEST")
_G.require = realRequire
assert(offline, "conversion works without engine game3 modules: " .. tostring(mix.lastError))
local offlineNotes = 0
for _, event in ipairs(offline.def.channels[1].program) do
  if event.pitch then offlineNotes = offlineNotes + 1 end
end
assert(offlineNotes > 0, "local M4A parser keeps notes")

print("g3_mix ok")
