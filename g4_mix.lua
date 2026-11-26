-- Offline NDS SSEQ -> chip converter.  The NDS ROM reader supplies raw SSEQ
-- event data and SBNK instruments; this module replays the event stream into
-- minimal M4A track bytecode and a synthetic voicegroup, then hands both to
-- the existing g3_mix.buildSpecs.  No engine module is required here.

local M = {}

local CONVERTER_VERSION = "g4_v17"
local RAW_PREFIX = "G4:"
local MAX_TRACKS = 16
local MAX_EVENTS = 20000
local MAX_TICKS = 200000
local MAX_STEPS = 100000
local MAX_VOICES = 255
-- clockAt index 0..48 maps to ticks 0..96, covering every SSEQ (48 PPQN)
-- note/wait value without rounding.
local CLOCK_MAX = 48

local deps = {}
local sequenceCache, bankCache, songCache = {}, {}, nil
local sampleCache = {}
local clockIndex
local versionsModule

function M.setVersions(value)
  versionsModule = type(value) == "table" and value or nil
end

local function versions()
  if versionsModule then return versionsModule end
  local ok, module = pcall(require, "versions")
  if ok and type(module) == "table" then versionsModule = module return module end
  return nil
end

local function setError(reason)
  M.lastError = tostring(reason)
  return nil, M.lastError
end

function M.install(d)
  if type(d) ~= "table" then return M.available() end
  deps = d
  if d.versions then M.setVersions(d.versions) end
  sequenceCache, bankCache, songCache, sampleCache, clockIndex =
    {}, {}, nil, {}, nil
  M.lastError = nil
  return M.available()
end

local function byte(data, off)
  if type(data) ~= "string" or off < 0 or off >= #data then return nil end
  return data:byte(off + 1)
end

local function u16le(data, off)
  local b0 = byte(data, off)
  if not b0 then return nil end
  return b0 + (byte(data, off + 1) or 0) * 256
end

local function u24le(data, off)
  local b0 = byte(data, off)
  if not b0 then return nil end
  return b0 + (byte(data, off + 1) or 0) * 256
    + (byte(data, off + 2) or 0) * 65536
end

-- SSEQ variable-length ints are big-endian 7-bit groups; continuation is the
-- high bit of each byte (ndspy _readVariableLengthInt).
local function varint(data, off)
  local value = 0
  for _ = 1, 5 do
    local b = byte(data, off)
    if not b then return nil, off end
    off = off + 1
    value = value * 128 + (b % 128)
    if b < 128 then return value, off end
  end
  return nil, off
end

local function signed8(value)
  value = tonumber(value) or 0
  return value >= 128 and value - 256 or value
end

local function clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

local function clockAt(index)
  if deps.g3Mix and type(deps.g3Mix.clockAt) == "function" then
    local ok, value = pcall(deps.g3Mix.clockAt, index)
    if ok and type(value) == "number" then return value end
  end
  if index <= 24 then return index end
  return ({ [25] = 28, [26] = 30, [27] = 32, [28] = 36, [29] = 40,
    [30] = 42, [31] = 44, [32] = 48, [33] = 52, [34] = 54, [35] = 56,
    [36] = 60, [37] = 64, [38] = 66, [39] = 68, [40] = 72, [41] = 76,
    [42] = 78, [43] = 80, [44] = 84, [45] = 88, [46] = 90, [47] = 92,
    [48] = 96 })[index] or index
end

-- g3_mix.decodeTrack uses clock indexes 0..48 as waits; 0..24 are the only
-- single-tick-exact entries, so split longer waits into table values.
local function clockChoices()
  if clockIndex then return clockIndex end
  clockIndex = {}
  for index = 0, CLOCK_MAX do
    clockIndex[#clockIndex + 1] = { index = index, ticks = clockAt(index) }
  end
  table.sort(clockIndex, function(a, b)
    if a.ticks ~= b.ticks then return a.ticks > b.ticks end
    return a.index < b.index
  end)
  return clockIndex
end

local function emitWait(out, ticks)
  local choices = clockChoices()
  while ticks > 0 do
    local picked
    for _, entry in ipairs(choices) do
      if entry.ticks > 0 and entry.ticks <= ticks then
        picked = entry
        break
      end
    end
    if not picked then break end
    out[#out + 1] = 0x80 + picked.index
    ticks = ticks - picked.ticks
  end
end

local function gateCommand(gate)
  gate = clamp(math.floor(gate + 0.5), 1, 223)
  if gate <= 127 then return 0xCF, gate end
  local choices = clockChoices()
  local index, base = 0, 0
  for _, entry in ipairs(choices) do
    if entry.ticks <= gate then index, base = entry.index, entry.ticks break end
  end
  return 0xCF + index, gate - base
end

-- SSEQ is 48 PPQN, M4A 24 PPQN, but g3_mix decodes tempo as byte*2.  Keep the
-- tick identity and emit SSEQ BPM as the M4A byte: decoded tempo becomes 2*BPM,
-- doubling the tick rate so wall-clock duration stays exact.  clockAt() then
-- covers every SSEQ tick value (0..96) with no rounding.
local function seqTicks(ticks)
  return math.max(1, math.floor((tonumber(ticks) or 0) + 0.5))
end

local function isMusicSong(song)
  local name = song.name
  if type(name) ~= "string" or not name:match("^SEQ_") then return false end
  if name:match("^SEQ_SE_") or name:match("^SEQ_PV") then return false end
  local player = tonumber(song.player)
  if player and player > 1 then return false end
  return true
end

local function importedSongs()
  if songCache then return songCache end
  songCache = {}
  if not deps.nds or type(deps.nds.listSongs) ~= "function" then return songCache end
  local ok, list = pcall(deps.nds.listSongs)
  if not ok or type(list) ~= "table" then return songCache end
  for _, song in ipairs(list) do
    if type(song) == "table" and isMusicSong(song) then
      songCache[#songCache + 1] = song
    end
  end
  return songCache
end

local function songByName(name)
  for _, song in ipairs(importedSongs()) do
    if song.name == name then return song end
  end
  return nil
end

local function ndsReady()
  if not deps.g3Mix or not deps.nds or not deps.songMap then return false end
  if type(deps.g3Mix.buildSpecs) ~= "function"
      or type(deps.g3Mix.has) ~= "function"
      or type(deps.nds.listSongs) ~= "function" then return false end
  if type(deps.nds.status) == "function" then
    local ok, status = pcall(deps.nds.status)
    if ok then
      if status == false then return false end
      if type(status) == "table" then
        for _, key in ipairs({ "error", "ready", "available", "imported", "loaded" }) do
          if status[key] == false then return false end
        end
        if status.ok == false then return false end
        if status.ready or status.available or status.imported or status.loaded then
          return true
        end
        if (tonumber(status.songCount) or 0) > 0
            or (tonumber(status.count) or 0) > 0 then return true end
      end
    end
  end
  return #importedSongs() > 0
end

function M.available()
  return ndsReady()
end

-- Song-map keys are version-independent group keys: an EQUIVALENTS gen1/gen2
-- label where one exists, otherwise a MUS_ id for Gen3-only tunes.  Any
-- generation's dataset label resolves back to the same group.
local function groupForLabel(label)
  if type(label) ~= "string" then return nil, nil end
  local V = versions()
  local group
  if V then
    if type(V.groupFor) == "function" then group = V.groupFor(label) end
    if not group and type(V.byLabel) == "table" then group = V.byLabel[label] end
  end
  if not group then
    local generation = label:match("^MUS_") and "gen3"
      or label:match("^Music_") and "gen1" or nil
    if generation then group = { [generation] = label } end
  end
  if not group then return nil, nil end
  return group, group.gen1 or group.gen2 or group.gen3 or label
end

local function generationForVersion(version)
  local V = versions()
  local entry = V and type(V.BY_ID) == "table" and V.BY_ID[version] or nil
  if entry then return tonumber(entry.generation) or 1 end
  for _, id in ipairs({ "red", "blue", "yellow" }) do
    if version == id then return 1 end
  end
  for _, id in ipairs({ "gold", "silver", "crystal" }) do
    if version == id then return 2 end
  end
  return 3
end

local function unique(list)
  local out = {}
  for _, value in ipairs(list) do
    local seen = false
    for _, existing in ipairs(out) do
      if existing == value then seen = true break end
    end
    if not seen then out[#out + 1] = value end
  end
  return out
end

local function songNamesFor(group, key)
  local out = {}
  local map = deps.songMap
  if not map then return out end
  local function collect(value)
    local names
    if type(map.namesFor) == "function" then
      local ok, result = pcall(map.namesFor, value)
      if ok then names = result end
    elseif type(map.BY_KEY) == "table" then
      names = map.BY_KEY[value]
    elseif type(map.BY_LABEL) == "table" then
      names = map.BY_LABEL[value]
    end
    if type(names) == "table" then
      for _, name in ipairs(names) do out[#out + 1] = name end
    end
  end
  collect(key)
  if group and group.gen3 and group.gen3 ~= key then collect(group.gen3) end
  return unique(out)
end

local function labelForSong(name)
  local map = deps.songMap
  if not map then return nil end
  local key
  if type(map.keyFor) == "function" then key = map.keyFor(name)
  elseif type(map.labelFor) == "function" then key = map.labelFor(name)
  else key = map.BY_NAME and map.BY_NAME[name] end
  if type(key) ~= "string" then return nil end
  local group = groupForLabel(key)
  if group and group.gen3 then return group.gen3 end
  return key
end

function M.rawLabel(name)
  return RAW_PREFIX .. tostring(name)
end

local function isRawLabel(label)
  return type(label) == "string" and label:sub(1, #RAW_PREFIX) == RAW_PREFIX
end

local function mappedSongFor(label)
  if isRawLabel(label) then return songByName(label:sub(#RAW_PREFIX + 1)) end
  local group, key = groupForLabel(label)
  local names = songNamesFor(group, key)
  for _, name in ipairs(names) do
    local song = songByName(name)
    if song then return song end
  end
  -- Static maps may key the song by a different generation's label.
  for _, song in ipairs(importedSongs()) do
    local label = labelForSong(song.name)
    if label == key or (group and group.gen3 and label == group.gen3) then
      return song
    end
  end
  return nil
end

local function mixLabelsForLabel(label, version, group)
  local V = versions()
  local base = group and group.gen3
  if not base and type(label) == "string" and label:match("^MUS_") then base = label end
  local out = {}
  if base and V and type(V.mixLabelsFor) == "function" then
    for _, value in ipairs(V.mixLabelsFor(base, version)) do out[#out + 1] = value end
  elseif base then
    out[#out + 1] = base
  end
  if type(label) == "string" and label:match("^MUS_") then out[#out + 1] = label end
  return unique(out)
end

function M.has(version, label)
  if not M.available() then return false end
  if isRawLabel(label) then return songByName(label:sub(#RAW_PREFIX + 1)) ~= nil end
  if not mappedSongFor(label) then return false end
  local group = groupForLabel(label)
  local generation = generationForVersion(version)
  if generation == 3 then
    for _, candidate in ipairs(mixLabelsForLabel(label, version, group)) do
      if candidate:match("^MUS_") then
        local ok, result = pcall(deps.g3Mix.has, version, candidate)
        if ok and result == true then return true end
      end
    end
    return false
  end
  local datasetLabel = group and group["gen" .. generation]
  if not datasetLabel then return false end
  if type(deps.available) == "function" then
    local ok, result = pcall(deps.available, version, datasetLabel)
    return ok and result == true
  end
  return true
end

function M.songList()
  local seen, out = {}, {}
  for _, song in ipairs(importedSongs()) do
    local label = labelForSong(song.name) or M.rawLabel(song.name)
    if type(label) == "string" and not seen[label] then
      seen[label] = true
      out[#out + 1] = label
    end
  end
  table.sort(out)
  return out
end

function M.allSongs()
  local out = {}
  for _, song in ipairs(importedSongs()) do
    out[#out + 1] = {
      name = song.name,
      label = labelForSong(song.name) or M.rawLabel(song.name),
      index = song.index,
    }
  end
  return out
end

local function sequenceFor(song)
  local key = tostring(song.name or song.index or song.fileID)
  if sequenceCache[key] ~= nil then return sequenceCache[key] end
  if type(deps.nds.readSequence) ~= "function" then return nil end
  local ok, seq = pcall(deps.nds.readSequence, song)
  if not ok or type(seq) ~= "table" or type(seq.data) ~= "string" then
    sequenceCache[key] = false
    return nil
  end
  seq.base = tonumber(seq.base) or 0
  seq.start = tonumber(seq.start) or seq.base
  sequenceCache[key] = seq
  return seq
end

local function bankFor(bankID)
  local key = tonumber(bankID) or 0
  if bankCache[key] ~= nil then return bankCache[key] or nil end
  if type(deps.nds.readBank) ~= "function" then bankCache[key] = false return nil end
  local ok, bank = pcall(deps.nds.readBank, key)
  if not ok or type(bank) ~= "table" then bankCache[key] = false return nil end
  bankCache[key] = bank
  return bank
end

local DEFAULT_DEF = {
  type = 1, waveID_dutyCycle = 0, waveArchiveID = 0, pitch = 60,
  attack = 127, decay = 100, sustain = 100, release = 80, pan = 64,
}

local function noteDefFor(instrument, rawKey)
  if type(instrument) ~= "table" then return DEFAULT_DEF end
  local defs = instrument.defs or instrument.notes
  if type(defs) ~= "table" then return DEFAULT_DEF end
  if defs.type ~= nil or defs.waveID ~= nil or defs.waveID_dutyCycle ~= nil then
    defs = { defs }
  end
  -- nds_import stores note definitions at indexes 1..n; older fixtures use
  -- 0-based arrays.  Check both before falling back to a generic wave.
  local function find(from, to)
    for index = from, to do
      local def = defs[index]
      if type(def) == "table" then
        local low, high = def.keyLow, def.keyHigh
        if (low == nil or rawKey >= low) and (high == nil or rawKey <= high) then
          return def
        end
      end
    end
  end
  return find(1, 256) or find(0, 255) or DEFAULT_DEF
end

-- SWAV samples are the only real timbre information in an HGSS bank.  The GB
-- wave channel has 32 four-bit steps, so a loop segment becomes a compact
-- waveform; Gen3 also keeps a sample reference for the direct PCM mixer.
local function signed16(data, index)
  local lo, hi = data:byte(index + 1), data:byte(index + 2)
  if not lo or not hi then return 0 end
  local value = lo + hi * 256
  if value >= 32768 then value = value - 65536 end
  return value
end

local function readSample(bankID, def)
  local reader = deps.nds and deps.nds.readSample
  if type(reader) ~= "function" then return nil end
  local waveID = tonumber(def.waveID_dutyCycle or def.waveID) or 0
  local archiveID = tonumber(def.waveArchiveID) or 0
  local key = tostring(bankID) .. ":" .. archiveID .. ":" .. waveID
  if sampleCache[key] ~= nil then
    if sampleCache[key] == false then return nil end
    return sampleCache[key]
  end
  local ok, sample = pcall(reader, tonumber(bankID) or 0, def)
  if not ok or type(sample) ~= "table" or type(sample.data) ~= "string"
      or #sample.data < 4 then
    sampleCache[key] = false
    return nil
  end
  sampleCache[key] = sample
  return sample
end

local function waveFromSample(sample, fallback)
  if type(sample.data) ~= "string" or #sample.data < 64 then return fallback end
  local frames = math.floor(#sample.data / 2)
  local start = math.max(0, math.floor(tonumber(sample.loopStart) or 0))
  local last = math.min(frames - 1, math.floor(tonumber(sample.loopEnd) or frames - 1))
  if last - start < 31 then start, last = 0, math.min(frames - 1, 1023) end
  local span = last - start + 1
  local peak = 1
  for i = 0, 31 do
    local index = start + math.floor(i * span / 32)
    peak = math.max(peak, math.abs(signed16(sample.data, index * 2)))
  end
  local wave = {}
  for i = 0, 31 do
    local index = start + math.floor(i * span / 32)
    local value = signed16(sample.data, index * 2) / peak
    wave[i + 1] = math.max(0, math.min(15, math.floor(7.5 + value * 7.5 + 0.5)))
  end
  return wave
end

local function gbEnvelope(value)
  -- NDS envelopes are 0..127, GB envelopes 0..15: scale by 15/127, do not
  -- divide by eight and lose most of the range.
  return clamp(math.floor((tonumber(value) or 0) * 15 / 127 + 0.5), 0, 15)
end

local waveCache = {}
local function waveFor(mode, archive)
  local key = (mode % 4) .. ":" .. (archive or 0)
  if waveCache[key] then return waveCache[key] end
  local wave = {}
  for i = 0, 31 do
    local value
    if mode % 4 == 1 then
      value = i < 16 and 1 or -1
    elseif mode % 4 == 2 then
      value = 1 - (i % 16) / 8
    elseif mode % 4 == 3 then
      value = math.sin(i * math.pi / 8)
    else
      value = math.sin(i * math.pi / 16)
    end
    wave[i + 1] = clamp(math.floor((value + 1) * 7.5 + 0.5), 0, 15)
  end
  waveCache[key] = wave
  return wave
end

local function hashKey(text)
  local hash = 5381
  for i = 1, #text do hash = (hash * 131 + text:byte(i)) % 1000003 end
  return hash
end

-- SBNK PSG duty 0..6 is 12.5%..87.5%; GB has four duty settings.  Map to the
-- nearest available setting instead of duty%4, which wraps the wide duties.
local SBNK_DUTY = { [0] = 0, [1] = 1, [2] = 2, [3] = 2, [4] = 3, [5] = 3, [6] = 3 }

-- One synthetic voice per (bank, instrument, note definition).  More than 255
-- distinct voices reuse a slot by hash; real songs never reach that cap.
local function voiceContext(generation)
  local context = {
    voices = { [1] = {} }, byKey = {}, nextVoice = 1,
    leadStats = {}, generation = generation,
  }
  -- Gen2 has no PCM side stream, so a sampled SWAV lead is a 32-step wave
  -- "beep". Collect long/high wave voices and give them a pulse/duty fallback.
  function context:markLead(id, key, gate)
    if generation >= 3 or not id then return end
    local voice = self.voices[1][id]
    if not voice or voice.type ~= 3 then return end
    local stats = self.leadStats[id]
    if not stats then
      stats = { count = 0, long = 0, keySum = 0, gateSum = 0 }
      self.leadStats[id] = stats
    end
    local noteKey, noteGate = tonumber(key) or 0, tonumber(gate) or 0
    stats.count = stats.count + 1
    stats.keySum = stats.keySum + noteKey
    stats.gateSum = stats.gateSum + noteGate
    if noteGate >= 6 then stats.long = stats.long + 1 end
  end
  function context:finalizeLeads()
    if generation >= 3 then return end
    for id, stats in pairs(self.leadStats) do
      local count = stats.count
      if count >= 3 and stats.long / count >= 0.8
          and stats.keySum / count >= 60 and stats.gateSum / count >= 10 then
        self.voices[1][id].leadDuty = 2
      end
    end
  end
  function context:voice(bankID, program, rawKey)
    local bank = bankFor(bankID) or bankFor(0)
    local instruments = bank and bank.instruments
    -- nds_import returns 1-based instrument arrays: program N -> index N+1.
    -- Keep the 0-based lookup for older synthetic fixtures.
    local instrument = instruments and (instruments[program + 1]
      or instruments[program] or instruments[tostring(program)])
    local def = noteDefFor(instrument, rawKey)
    local duty = tonumber(def.waveID_dutyCycle or def.waveID) or 0
    local key = table.concat({
      tostring(bankID or 0), tostring(program or 0),
      tostring(def.type or 1), tostring(duty),
      tostring(def.waveArchiveID or 0), tostring(def.keyLow or ""),
      tostring(def.keyHigh or ""),
    }, ":")
    local id = self.byKey[key]
    if id then return id end
    id = self.nextVoice
    if id > MAX_VOICES then id = (hashKey(key) % MAX_VOICES) + 1 end
    local defType = tonumber(def.type) or 1
    local tone
    if defType == 2 then
      tone = { type = 1, wavParam = SBNK_DUTY[duty] or 2 }
    elseif defType == 3 then
      tone = { type = 4 }
    else
      local procedural = waveFor(duty, def.waveArchiveID)
      local sample = readSample(bankID, def)
      tone = {
        type = 3,
        wave = sample and waveFromSample(sample, procedural) or procedural,
      }
      if sample then
        local pitch = tonumber(def.pitch) or 60
        tone.pcm = {
          bank = tonumber(bankID) or 0,
          archive = tonumber(def.waveArchiveID) or 0,
          wave = duty,
          pitch = pitch > 0 and pitch or 60,
          rate = tonumber(sample.sampleRate) or 0,
        }
      end
    end
    tone.attack = gbEnvelope(def.attack)
    tone.decay = gbEnvelope(def.decay)
    tone.sustain = math.max(1, gbEnvelope(def.sustain))
    tone.release = gbEnvelope(def.release)
    self.voices[1][id] = tone
    if self.nextVoice <= MAX_VOICES then self.nextVoice = self.nextVoice + 1 end
    self.byKey[key] = id
    return id
  end
  return context
end

local function trackStarts(seq)
  local data, base = seq.data, seq.base
  local header = seq.start or base
  local starts = {}
  if byte(data, header) ~= 0xFE then
    return { { offset = header } }
  end
  local mask = u16le(data, header + 1) or 0
  local cursor = header + 3
  local explicitMain = false
  for track = 0, MAX_TRACKS - 1 do
    if math.floor(mask / (2 ^ track)) % 2 == 1 then
      if byte(data, cursor) ~= 0x93 then break end
      local trackNo = byte(data, cursor + 1) or 0
      if trackNo == 0 then explicitMain = true end
      local offset = u24le(data, cursor + 2)
      cursor = cursor + 5
      -- SequenceEvent offsets are relative to the events-data base, even when
      -- the header sits at a different absolute position (SSAR sub-songs).
      if offset and offset >= 0 and base + offset < #data then
        starts[#starts + 1] = { offset = base + offset }
      end
    end
  end
  -- SSEQ track 0 is the decoder continuation after the 0x93 header commands,
  -- not one of those commands. Older synthetic fixtures declare it explicitly
  -- with `0x93 0x00`, so only add the implicit start when none was declared.
  if not explicitMain and cursor < #data and byte(data, cursor) ~= 0xFF then
    starts[#starts + 1] = { offset = cursor }
  end
  if #starts == 0 then starts[1] = { offset = header } end
  return starts
end

-- Skip operands of variable/conditional events that do not affect audible
-- notes. Lengths follow ndspy's SequenceEvent.dataLength table. `pc` already
-- points just past the opcode, so each return is dataLength - 1.
local function randomSubLength(data, pc)
  local sub = byte(data, pc) or 0
  if sub <= 0x7F then return 7 end
  if sub == 0x80 or sub == 0x81 then return 2 end
  if sub == 0x93 then return 5 end
  if sub == 0x94 or sub == 0x95 then return 4 end
  if sub == 0xA0 then return 7 end
  if sub == 0xA1 then
    local nested = byte(data, pc + 1) or 0
    return nested >= 0xB0 and nested <= 0xBD and 4 or 3
  end
  if sub == 0xA2 or sub == 0xFC or sub == 0xFD or sub == 0xFF then return 1 end
  if sub >= 0xB0 and sub <= 0xBD then return 4 end
  if sub == 0xE0 or sub == 0xE1 or sub == 0xE3 then return 3 end
  if sub == 0xFE then return 3 end
  return 2
end

local function skipEvent(data, pc, cmd)
  if cmd == 0xA0 then
    local sub = byte(data, pc) or 0
    if sub <= 0x7F then return pc + 6 end
    return pc + 3 + randomSubLength(data, pc)
  elseif cmd == 0xA1 then
    local sub = byte(data, pc) or 0
    return pc + (sub >= 0xB0 and sub <= 0xBD and 3 or 2)
  elseif cmd >= 0xB0 and cmd <= 0xBD then
    return pc + 3
  elseif cmd >= 0xC0 and cmd <= 0xD6 then
    return pc + 1
  elseif cmd == 0xE0 or cmd == 0xE1 or cmd == 0xE3 then
    return pc + 2
  elseif cmd == 0xFE then
    return pc + 2
  end
  return pc
end

local function decodeTrack(seq, start, voices, songBank)
  local data, base = seq.data, seq.base
  local events = {}
  local pc, tick = start, 0
  local count, steps = 0, 0
  local callStack, frames = {}, { { visited = {} } }
  local bankID, program = songBank or 0, 0
  local loopPc, loopEventIndex, loopEndTick
  local volume, master, pan, transpose, bend, bendRange = 127, 127, 0x40, 0, 0, 2
  local loopStart
  local cmdPc
  -- SSEQ default is monophonic: a note blocks the track until its gate ends.
  -- C7 0 switches to polyphony, where notes overlap and only rests advance
  -- the track clock.
  local noteWait = true
  local function add(kind, fields)
    count = count + 1
    local event = fields or {}
    event.kind = kind
    event.seq = count
    event.tick = tick
    event.address = cmdPc
    events[#events + 1] = event
    return event
  end
  -- SSEQ starts at 120 BPM.  M4A defaults to 150, so seed the real default at
  -- tick 0; explicit 0xE1 at tick 0 overwrites it instead of adding a duplicate.
  local defaultTempo = add("tempo", { bpm = 120, default = true })
  -- Loop detection is per call frame. HGSS songs CALL the same subroutine
  -- from several places; a global visited set treats the second call as a
  -- loop and drops every later section. A true loop is a revisit inside the
  -- same frame, usually a JUMP back into the main body.
  while steps < MAX_STEPS and count < MAX_EVENTS and tick <= MAX_TICKS do
    steps = steps + 1
    local frame = frames[#frames]
    -- Revisiting a byte offset in the same frame means the jump chain closed
    -- a loop. Point the chip GOTO at the first event emitted from that offset,
    -- not at the declaring track start; SSEQ tracks routinely share prefixes.
    if frame.visited[pc] then
      if not loopPc then
        loopPc = pc
        loopEndTick = tick
        loopEventIndex = 1
        for index, event in ipairs(events) do
          if (event.address or -1) >= pc then loopEventIndex = index break end
        end
      end
      break
    end
    frame.visited[pc] = true
    local cmd = byte(data, pc)
    if cmd == nil then break end
    cmdPc = pc
    pc = pc + 1
    if cmd < 0x80 then
      local rawVel = byte(data, pc) or 0
      pc = pc + 1
      local duration, nextPc = varint(data, pc)
      pc = nextPc or pc
      local vel = rawVel % 128
      -- Gate is the note's sounding duration.  Only monophonic tracks wait
      -- for it before the next event; polyphonic tracks overlap notes and
      -- advance on rests alone.
      local gate = math.max(1, seqTicks(duration))
      if vel >= 20 then
        local voice = voices:voice(bankID, program, cmd)
        voices:markLead(voice, cmd + transpose, gate)
        local tone = voices.voices[1][voice]
        add("note", {
          key = cmd + transpose, rawKey = cmd, vel = vel,
          gate = gate, longGate = gate >= 6,
          voice = voice, hasPcm = tone ~= nil and tone.pcm ~= nil,
          volume = clamp(math.floor(volume * master / 127), 1, 255),
          pan = pan, bend = bend, bendRange = bendRange,
        })
      end
      if noteWait then tick = tick + gate end
    elseif cmd == 0x80 then
      local duration, nextPc = varint(data, pc)
      pc = nextPc or pc
      tick = tick + seqTicks(duration)
    elseif cmd == 0x81 then
      local value, nextPc = varint(data, pc)
      pc = nextPc or pc
      value = value or 0
      program = value % 128
      -- Bank 0 in a program event means "keep the sequence's current bank".
      local override = math.floor(value / 128)
      if override > 0 then bankID = override end
    elseif cmd == 0x93 then
      pc = pc + 4
    elseif cmd == 0x94 then
      -- JUMP destinations are relative to the SSEQ DATA block, not the start
      -- of the whole file blob returned by readSequence.  Follow the chain;
      -- a revisit of an already parsed offset is detected at loop top.
      local target = u24le(data, pc)
      pc = pc + 3
      if target then target = target + base end
      if not target or target < base or target >= #data then break end
      pc = target
    elseif cmd == 0x95 then
      local target = u24le(data, pc)
      pc = pc + 3
      if target then target = target + base end
      if not target or target < base or target >= #data or #callStack >= 8 then
        break
      end
      callStack[#callStack + 1] = pc
      frames[#frames + 1] = { visited = {} }
      pc = target
    elseif cmd == 0xA2 then
      -- Conditional skip: leave the flag unset, i.e. execute the next event.
    elseif cmd == 0xC0 then
      pan = clamp(byte(data, pc) or 0x40, 0, 127)
      add("pan", { pan = pan })
      pc = pc + 1
    elseif cmd == 0xC1 then
      volume = byte(data, pc) or 127
      add("volume", { volume = volume })
      pc = pc + 1
    elseif cmd == 0xC2 then
      master = byte(data, pc) or 127
      pc = pc + 1
    elseif cmd == 0xC3 then
      transpose = signed8(byte(data, pc))
      add("transpose", { value = transpose })
      pc = pc + 1
    elseif cmd == 0xC4 then
      bend = signed8(byte(data, pc))
      add("bend", { value = bend })
      pc = pc + 1
    elseif cmd == 0xC5 then
      bendRange = byte(data, pc) or 2
      add("bendRange", { value = bendRange })
      pc = pc + 1
    elseif cmd == 0xC7 then
      -- 0 = poly (non-blocking notes), 1 = mono (note wait).  SSEQ default
      -- is mono, so tracks that omit C7 keep the original timing.
      noteWait = (byte(data, pc) or 0) ~= 0
      pc = pc + 1
    elseif cmd >= 0xD0 and cmd <= 0xD3 then
      local value = byte(data, pc) or 0
      add("envelope", { field = cmd - 0xD0, value = value })
      pc = pc + 1
    elseif cmd == 0xD4 then
      byte(data, pc) -- loop count; chip loops are always infinite
      if not loopPc then
        loopPc = pc + 1
        loopEventIndex = #events + 1
      end
      pc = pc + 1
    elseif cmd == 0xFC then
      if loopPc then loopEndTick = tick break end
    elseif cmd == 0xFD then
      if #callStack > 0 then
        pc = table.remove(callStack)
        frames[#frames] = nil
      else
        break
      end
    elseif cmd == 0xE1 then
      local bpm = u16le(data, pc) or 120
      if tick == 0 then
        defaultTempo.bpm = bpm
        defaultTempo.default = false
      else
        add("tempo", { bpm = bpm })
      end
      pc = pc + 2
    elseif cmd == 0xFF then
      break
    else
      pc = skipEvent(data, pc, cmd)
    end
  end
  -- Keep sounding note tails in `ticks` for PCM length, but leave the loop
  -- point at the track clock.  Poly notes continue across a loop; delaying
  -- the loop until their gate ends would stretch the song.
  local ticks = tick
  for _, event in ipairs(events) do
    if event.kind == "note" then
      ticks = math.max(ticks, event.tick + event.gate)
    end
  end
  if loopEventIndex and loopEventIndex <= #events then
    loopStart = events[loopEventIndex]
    loopStart.loopStart = true
  else
    loopStart = nil
  end
  return {
    events = events, ticks = ticks,
    loopStart = loopStart, loopEndTick = loopEndTick or tick,
  }
end

local function synthTrack(decoded, perNoteState, mutePcm, muteAll)
  local out, current, lastVoice = {}, 0, nil
  local loopTarget
  local function emit(event)
    emitWait(out, math.max(0, event.tick - current))
    current = math.max(current, event.tick)
    if event.loopStart then loopTarget = #out end
    local kind = event.kind
    if kind == "tempo" then
      -- g3_mix.decodeTrack multiplies the byte by 2; emit SSEQ BPM so decoded
      -- tempo is 2*BPM and the identity tick counts keep their wall-clock time.
      local value = clamp(math.floor((event.bpm or 120) + 0.5), 1, 255)
      out[#out + 1] = 0xBB
      out[#out + 1] = value
    elseif kind == "envelope" then
      local fields = { [0] = 4, [1] = 5, [2] = 6, [3] = 7 }
      out[#out + 1] = 0xCD
      out[#out + 1] = fields[event.field] or 4
      -- SSEQ envelope overrides are 0..127; GB envelopes are 0..15.  Scale
      -- by 15/127 with rounding, not an integer divide by 8.
      out[#out + 1] = clamp(math.floor((event.value or 0) * 15 / 127 + 0.5), 0, 15)
    elseif kind == "pan" then
      out[#out + 1] = 0xBF
      out[#out + 1] = clamp(event.pan or 0x40, 0, 127)
    elseif kind == "volume" then
      -- nds_import volumes are 0..127; M4A mixer volume is 0..255.  Halving
      -- here squared with g3_mix.noteGain's sqrt and cost ~half the amplitude.
      out[#out + 1] = 0xBE
      out[#out + 1] = clamp(math.floor((event.volume or 127) * 255 / 127 + 0.5), 0, 255)
    elseif kind == "transpose" then
      out[#out + 1] = 0xBC
      out[#out + 1] = (event.value or 0) % 256
    elseif kind == "bend" then
      out[#out + 1] = 0xC0
      out[#out + 1] = clamp((event.value or 0) + 0x40, 0, 127)
    elseif kind == "bendRange" then
      out[#out + 1] = 0xC1
      out[#out + 1] = clamp(event.value or 2, 0, 255)
    elseif kind == "note" then
      -- On GB hosts PCM voices are rendered by extra_audio; muting the
      -- matching GB note avoids doubling while waits keep exact timing.
      if not (muteAll or (mutePcm and event.hasPcm)) then
        if perNoteState then
          -- Premixed tracks carry notes from several SSEQ tracks; state must be
          -- restated per note or one track's instrument/pan leaks into another.
          out[#out + 1] = 0xBD
          out[#out + 1] = clamp(event.voice or 0, 0, 255)
          out[#out + 1] = 0xBF
          out[#out + 1] = clamp(event.pan or 0x40, 0, 127)
          out[#out + 1] = 0xBE
          out[#out + 1] = clamp(math.floor((event.volume or 127) * 255 / 127 + 0.5), 0, 255)
          lastVoice = event.voice
        elseif lastVoice ~= event.voice then
          lastVoice = event.voice
          out[#out + 1] = 0xBD
          out[#out + 1] = clamp(lastVoice or 0, 0, 255)
        end
        local command, extra = gateCommand(event.gate)
        out[#out + 1] = command
        out[#out + 1] = clamp(event.key or 60, 0, 127)
        out[#out + 1] = clamp(event.vel or 100, 20, 127)
        if extra > 0 then out[#out + 1] = extra end
      end
    end
  end
  for _, event in ipairs(decoded.events) do emit(event) end
  if loopTarget and loopTarget < #out then
    emitWait(out, math.max(0, decoded.loopEndTick - current))
    out[#out + 1] = 0xB2
    for shift = 0, 24, 8 do
      out[#out + 1] = math.floor(loopTarget / 256 ^ (shift / 8)) % 256
    end
  end
  out[#out + 1] = 0xB1
  local bytes = {}
  for _, value in ipairs(out) do bytes[#bytes + 1] = string.char(value) end
  return table.concat(bytes)
end

-- Premix: g3_mix emits one spec per four tracks and extra_audio has 16 engine
-- slots.  Only when a song would exceed 16 specs, fold tracks sharing a pan
-- bucket and instrument voice (duty/wave class) into one M4A track.  All notes
-- survive; per-note state keeps each original instrument audible.
local function trackClass(track, voicegroups)
  local panSum, panCount, dominantVoice, best, counts = 0, 0, 0, 0, {}
  for _, event in ipairs(track.events or {}) do
    if event.kind == "note" then
      panSum = panSum + (event.pan or 0x40)
      panCount = panCount + 1
      local voice = event.voice or 0
      counts[voice] = (counts[voice] or 0) + 1
    end
  end
  for voice, count in pairs(counts) do
    if count > best then dominantVoice, best = voice, count end
  end
  local tone = voicegroups and voicegroups[1] and voicegroups[1][dominantVoice]
  local class = tone and (tone.type or tone.kind) or dominantVoice
  local panBucket = math.floor((panCount > 0 and panSum / panCount or 0x40) / 32)
  return panBucket .. ":" .. tostring(class) .. ":" .. tostring(dominantVoice)
end

local function mergeDecoded(tracks)
  local events, tempos = {}, {}
  for source, track in ipairs(tracks) do
    for _, event in ipairs(track.events or {}) do
      if event.kind == "tempo" then
        local key = event.tick .. ":" .. tostring(event.bpm)
        if not tempos[key] then tempos[key] = true; events[#events + 1] = event end
      else
        local copy = {}
        for key, value in pairs(event) do copy[key] = value end
        copy.loopStart = nil
        copy._source = source
        events[#events + 1] = copy
      end
    end
  end
  table.sort(events, function(a, b)
    if a.tick ~= b.tick then return a.tick < b.tick end
    if a._source ~= b._source then return (a._source or 0) < (b._source or 0) end
    return (a.seq or 0) < (b.seq or 0)
  end)
  local loopStart, loopEnd, loopSource, ticks = nil, nil, nil, 1
  for source, track in ipairs(tracks) do
    if not loopStart and track.loopStart then
      loopStart, loopEnd, loopSource = track.loopStart, track.loopEndTick, source
    end
    ticks = math.max(ticks, track.ticks or 0)
  end
  if loopStart then
    for _, event in ipairs(events) do
      if event.tick == loopStart.tick and event._source == loopSource then
        event.loopStart = true
        break
      end
    end
  end
  for _, event in ipairs(events) do
    if event.kind == "note" then ticks = math.max(ticks, event.tick + event.gate) end
  end
  return {
    events = events, ticks = ticks, loopStart = loopStart,
    loopEndTick = loopEnd or ticks,
  }
end

function M.premixDecoded(decodedTracks, voicegroups, trackData)
  if type(decodedTracks) ~= "table" or #decodedTracks == 0 then return nil end
  local buckets, classes = {}, {}
  for index, track in ipairs(decodedTracks) do
    local class = trackClass(track, voicegroups)
    local bucket = buckets[class]
    if not bucket then
      bucket = { indexes = {} }
      buckets[class] = bucket
      classes[#classes + 1] = class
    end
    bucket.indexes[#bucket.indexes + 1] = index
  end
  table.sort(classes)
  local entries = {}
  for _, class in ipairs(classes) do
    local indexes = buckets[class].indexes
    if #indexes == 1 then
      entries[#entries + 1] = { decoded = { decodedTracks[indexes[1]] },
        index = indexes[1], merged = false }
    else
      local grouped = {}
      for _, index in ipairs(indexes) do grouped[#grouped + 1] = decodedTracks[index] end
      entries[#entries + 1] = { decoded = { mergeDecoded(grouped) },
        index = indexes[1], merged = true }
    end
  end
  -- One decoded track now becomes one spec, so 16 entries is the hard limit.
  -- Fold the tail into the first bucket when a dataset has too many classes.
  while #entries > 16 do
    local last = table.remove(entries)
    local first = entries[1]
    local combined = {}
    for _, track in ipairs(first.decoded) do combined[#combined + 1] = track end
    for _, track in ipairs(last.decoded) do combined[#combined + 1] = track end
    first.decoded = { mergeDecoded(combined) }
  end
  local out, groupedDecoded = {}, {}
  for _, entry in ipairs(entries) do
    out[#out + 1] = entry.merged and synthTrack(entry.decoded[1], true)
      or trackData[entry.index]
    groupedDecoded[#groupedDecoded + 1] = entry.decoded[1]
  end
  if #out == #decodedTracks then return nil end
  return out, groupedDecoded
end

-- SSEQ 0xE1 is global even when only the implicit main track carries it.
-- Share the timeline so side engines do not stay at 120 BPM and drift.
local function propagateTempo(tracks)
  local byTick = {}
  for _, track in ipairs(tracks) do
    for _, event in ipairs(track.events or {}) do
      if event.kind == "tempo" then
        local current = byTick[event.tick]
        if not current or (current.default and not event.default) then
          byTick[event.tick] = event
        end
      end
    end
  end
  local timeline = {}
  for tick, event in pairs(byTick) do
    timeline[#timeline + 1] = { tick = tick, bpm = event.bpm }
  end
  table.sort(timeline, function(a, b) return a.tick < b.tick end)

  for _, track in ipairs(tracks) do
    local events, inserted = {}, {}
    local function addTemposBefore(limit)
      for index, item in ipairs(timeline) do
        if not inserted[index] and item.tick <= limit then
          events[#events + 1] = { kind = "tempo", tick = item.tick, bpm = item.bpm }
          inserted[index] = true
        end
      end
    end
    for _, event in ipairs(track.events or {}) do
      if event.kind ~= "tempo" then
        addTemposBefore(event.tick)
        events[#events + 1] = event
      end
    end
    addTemposBefore(math.huge)
    track.events = events
  end
end

local function buildSong(seq, bankID, generation)
  local starts = trackStarts(seq)
  local voices = voiceContext(generation)
  local trackData, decodedTracks = {}, {}
  for _, start in ipairs(starts) do
    decodedTracks[#decodedTracks + 1] =
      decodeTrack(seq, start.offset, voices, bankID, generation)
  end
  propagateTempo(decodedTracks)
  voices:finalizeLeads()
  for _, decoded in ipairs(decodedTracks) do
    trackData[#trackData + 1] = synthTrack(decoded)
  end
  return {
    name = "g4_sseq", tracks = #trackData, trackData = trackData,
    voicegroup = 1,
  }, voices.voices, decodedTracks
end

-- Keep real SWAV sample references alongside the chip spec for every host.
-- Gen3 renders them directly on the GBA source; gen1/gen2 render them on the
-- GB extra_audio source.  The baked 32-step waves stay as fallback for notes
-- without a resolved sample.
local function pcmForTracks(tracks, voicegroups, generation)
  if generation < 1 or generation > 3 then return nil end
  -- Chip tempo can only be an integer GB byte. Render PCM on that same grid
  -- so long loops cannot drift against the beeps.
  local function chipTempo(decoded)
    return clamp(math.floor(38400 / math.max(1, decoded) + 0.5), 1, 0xFFFF)
  end
  local events, timeline = {}, { { tick = 0, tempo = 240, gb = chipTempo(240) } }
  local loopStartTick, loopEndTick, loopTick
  for _, track in ipairs(tracks or {}) do
    for _, event in ipairs(track.events or {}) do
      if event.kind == "tempo" then
        local decoded = clamp(math.floor((tonumber(event.bpm) or 120) * 2 + 0.5),
          1, 0xFFFF)
        if event.tick == 0 then
          timeline[1].tempo = decoded
          timeline[1].gb = chipTempo(decoded)
        else
          timeline[#timeline + 1] = {
            tick = event.tick, tempo = decoded, gb = chipTempo(decoded),
          }
        end
      elseif event.kind == "note" then
        local tone = voicegroups and voicegroups[1] and voicegroups[1][event.voice]
        if tone and tone.pcm then
          events[#events + 1] = {
            tick = event.tick, gate = event.gate, key = event.key,
            vel = clamp(math.floor(tonumber(event.vel) or 100), 1, 127),
            volume = clamp(math.floor(tonumber(event.volume) or 100), 1, 127),
            pan = tonumber(event.pan) or 0x40,
            bank = tone.pcm.bank, archive = tone.pcm.archive,
            wave = tone.pcm.wave, pitch = tone.pcm.pitch,
          }
        end
      end
    end
    if track.loopStart and not loopTick then
      local start = tonumber(track.loopStart.tick) or 0
      local finish = tonumber(track.loopEndTick) or tonumber(track.ticks) or 0
      if finish > start then
        loopStartTick, loopEndTick = start, finish
        loopTick = finish - start
      end
    end
  end
  if #events == 0 then return nil end
  table.sort(events, function(a, b) return a.tick < b.tick end)
  table.sort(timeline, function(a, b) return a.tick < b.tick end)
  return {
    events = events, tempoTimeline = timeline,
    loopStartTick = loopStartTick or 0, loopEndTick = loopEndTick or 0,
    loopTick = loopTick or 0,
  }
end

function M.convert(version, label, mode)
  mode = mode == "chip" and "chip" or mode == "pcm" and "pcm" or "hybrid"
  if not M.available() then return setError(M.lastError or "NDS import unavailable") end
  local song = mappedSongFor(label)
  if not song then return setError("no imported SSEQ for " .. tostring(label)) end
  local seq = sequenceFor(song)
  if not seq then return setError("no sequence data for " .. tostring(song.name)) end
  local generation = generationForVersion(version)
  local songDef, voicegroups, decodedTracks =
    buildSong(seq, tonumber(song.bank), generation)
  if not songDef or songDef.tracks < 1 then
    return setError("no tracks for " .. tostring(song.name))
  end
  -- One decoded track becomes one chip spec, so 16 slots is the hard ceiling.
  -- Premix only when the source would overflow those slots.
  local sourceTracks = songDef.tracks
  local groupedTracks = decodedTracks
  if sourceTracks > 16 then
    local grouped, groupedDecoded = M.premixDecoded(decodedTracks,
      voicegroups, songDef.trackData)
    if grouped then
      songDef = {
        name = songDef.name, tracks = #grouped, trackData = grouped,
        voicegroup = songDef.voicegroup,
      }
      groupedTracks = groupedDecoded
    end
  end
  -- One spec per decoded track. The old four-tracks-per-spec grouping made
  -- short voices wait at the longest track's loop point, sounding like a pause.
  local specs, specTracks, specPcms = {}, {}, {}
  local premixed = sourceTracks > songDef.tracks
  for trackIndex, trackBytes in ipairs(songDef.trackData) do
    local pcm = mode ~= "chip"
      and pcmForTracks({ groupedTracks[trackIndex] }, voicegroups, generation)
      or nil
    specPcms[trackIndex] = pcm
    -- G4 Mix is PCM-only; G4 GB keeps every chip note and drops PCM refs.
    -- The legacy hybrid still mutes GB notes backed by PCM to avoid doubling.
    if mode == "pcm" then
      trackBytes = synthTrack(groupedTracks[trackIndex], premixed, false, true)
    elseif pcm and generation < 3 and trackIndex > 1 then
      trackBytes = synthTrack(groupedTracks[trackIndex], premixed, true)
    end
    local perTrackSong = {
      name = songDef.name, tracks = 1, trackData = { trackBytes },
      voicegroup = 1,
    }
    local built
    local ok, result = pcall(deps.g3Mix.buildSpecs, perTrackSong, voicegroups,
      { voicegroupId = 1 })
    if not ok then return setError("buildSpecs: " .. tostring(result)) end
    if type(result) ~= "table" or not result[1] then
      return setError("no chip specs for track " .. tostring(trackIndex))
    end
    for _, spec in ipairs(result) do
      specs[#specs + 1] = spec
      specTracks[#specTracks + 1] = groupedTracks[trackIndex]
    end
  end
  local def = specs[1]
  def.generation = generation
  def.g4Mix = mode ~= "chip"
  def.g4Gb = mode == "chip"
  def.converter = CONVERTER_VERSION .. "_" .. mode
  if sourceTracks > songDef.tracks then
    def.premix = true
    def.sourceTracks = sourceTracks
  end
  local extra = {}
  for i, spec in ipairs(specs) do
    spec.pcm = specPcms[i]
    if i > 1 then
      spec.generation = generation
      spec.g4Mix = mode ~= "chip"
      spec.g4Gb = mode == "chip"
      spec.converter = def.converter
      spec.premix = def.premix or nil
      extra["g4_" .. i] = spec
    end
  end
  return { def = def, extra = extra, tracks = songDef.tracks }
end

return M
