-- Offline Pokemon Stadium 2 (N64) -> PCM-only song specs.
-- Sequences are Zelda64/EAD AudioSeq streams; samples come from CTL/TBL banks
-- decoded by n64_import.lua.  No chip voices are emitted: every note is a PCM
-- event on a silent ChipAsm carrier spec.

local M = {}

local CONVERTER_VERSION = "n64_v2_pcm"

local SEQ_LEN = {
  [0x60] = 2, [0x90] = 2, [0xA0] = 2, [0xB0] = 3, [0xC1] = 1,
  [0xC2] = 2, [0xC4] = 2, [0xC5] = 2, [0xC6] = 1, [0xC7] = 3,
  [0xC8] = 1, [0xC9] = 1, [0xCC] = 1, [0xCD] = 2, [0xCE] = 1,
  [0xCF] = 2, [0xD0] = 0, [0xD1] = 1, [0xD2] = 2, [0xD3] = 1,
  [0xD5] = 1, [0xD6] = 2, [0xD7] = 2, [0xD8] = 1, [0xD9] = 1,
  [0xDA] = 3, [0xDB] = 1, [0xDC] = 1, [0xDD] = 1, [0xDE] = 1,
  [0xDF] = 1,
}

local CHANNEL_LEN = {
  [0xB2] = 2, [0xB3] = 1, [0xB7] = 2, [0xB8] = 1, [0xB9] = 1,
  [0xBA] = 1, [0xBB] = 3, [0xBC] = 2, [0xBD] = 4, [0xC1] = 1,
  [0xC2] = 2, [0xC6] = 1, [0xC7] = 3, [0xC8] = 1, [0xC9] = 1,
  [0xCA] = 1, [0xCB] = 2, [0xCC] = 1, [0xCD] = 1, [0xCE] = 2,
  [0xCF] = 2, [0xD0] = 1, [0xD1] = 1, [0xD2] = 1, [0xD3] = 1,
  [0xD4] = 1, [0xD5] = 1, [0xD6] = 1, [0xD7] = 1, [0xD8] = 1,
  [0xD9] = 1, [0xDA] = 2, [0xDB] = 1, [0xDC] = 1, [0xDD] = 1,
  [0xDE] = 2, [0xDF] = 1, [0xE0] = 1, [0xE1] = 3, [0xE2] = 2,
  [0xE3] = 1, [0xE5] = 1, [0xE6] = 1, [0xE7] = 2, [0xE8] = 8,
  [0xE9] = 1, [0xEB] = 2, [0xED] = 1, [0xEE] = 1, [0xEF] = 3,
  [0xF1] = 1, [0xF2] = 1, [0xF3] = 1, [0xF4] = 1, [0xF5] = 2,
}

local LAYER_LEN = {
  [0xC1] = 1, [0xC2] = 1, [0xC3] = 0, [0xC5] = 0, [0xC6] = 1,
  [0xC7] = 3, [0xC8] = 0, [0xC9] = 1, [0xCA] = 1, [0xCB] = 3,
  [0xCC] = 0, [0xCD] = 1, [0xCE] = 1, [0xCF] = 1, [0xF2] = 1,
  [0xF3] = 1, [0xF4] = 1, [0xF5] = 2, [0xF7] = 0, [0xF8] = 1,
  [0xF9] = 2, [0xFA] = 2, [0xFB] = 2, [0xFC] = 2,
}

local function byte(data, pos)
  if pos < 1 or pos > #data then return nil end
  return data:byte(pos)
end

local function u16(data, pos)
  local a, b = byte(data, pos), byte(data, pos + 1)
  if not a or not b then return nil end
  return a * 256 + b
end

local function timeValue(data, pos, limit)
  local first = byte(data, pos)
  if not first then return 0, pos + 1 end
  if first >= 0x80 then
    local second = byte(data, pos + 1) or 0
    return (first - 0x80) * 256 + second, pos + 2
  end
  return first, pos + 1
end

local function freshChannel()
  return { instrument = 0, pan = 0x40, volume = 0x7F, coarse = 0, started = false }
end

local function copyState(state)
  return {
    instrument = state.instrument, pan = state.pan, volume = state.volume,
    coarse = state.coarse, started = state.started,
  }
end

local function clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

local function addNote(out, tick, duration, note, velocity, channel, state)
  if #out >= 8192 then return end
  out[#out + 1] = {
    tick = tick, gate = math.max(1, duration), note = clamp(note, 0, 127),
    vel = clamp(velocity, 0, 127), channel = channel,
    instrument = state.instrument, pan = state.pan, volume = state.volume,
  }
end

local function parseLayer(ctx, data, offset, limit, channel, state, out, tickState, depth)
  if depth > 8 or #out >= 8192 then return end
  local seen = {}
  local pos = offset
  local lastTimestamp = 0
  local guard = 0
  while pos <= limit and guard < 16384 do
    guard = guard + 1
    local mark = pos .. ":" .. channel
    if seen[mark] then return end
    seen[mark] = true
    local command = byte(data, pos)
    if command == nil or command == 0xFF or command == 0xFE then return end
    if command == 0xC0 or command == 0xFD then
      local delta, nextPos = timeValue(data, pos + 1, limit)
      pos = nextPos
      if command == 0xC0 then
        tickState.tick = tickState.tick + delta
        lastTimestamp = delta
      end
    elseif command == 0xFC then
      local target = u16(data, pos + 1)
      if not target then return end
      -- EAD offsets are 0-based; Lua strings are 1-based.
      parseLayer(ctx, data, target + 1, limit, channel, state, out, tickState, depth + 1)
      return
    elseif command == 0xC2 then
      local value = byte(data, pos + 1) or 0
      state.coarse = value >= 0x80 and value - 256 or value
      pos = pos + 1 + (LAYER_LEN[command] or 0)
    elseif command < 0xC0 then
      local rawNote = command % 0x40
      local note = rawNote + state.coarse + 0x15
      local delta, nextPos = timeValue(data, pos + 1, limit)
      pos = nextPos
      local velocity, duration
      local skipTail = false
      if not state.started then
        velocity, duration = 0x7F, delta
        -- Source reads the next byte but does not advance the stream here.
      elseif command >= 0x80 then
        velocity = byte(data, pos) or 0x7F
        local percent = byte(data, pos + 1) or 0
        pos = pos + 2
        duration = lastTimestamp - math.floor((percent * lastTimestamp) / 256)
        tickState.tick = tickState.tick + lastTimestamp
        lastTimestamp = lastTimestamp
        addNote(out, tickState.tick, duration, note, velocity, channel, state)
        skipTail = true
      elseif command >= 0x40 then
        velocity = byte(data, pos) or 0x7F
        pos = pos + 1
        duration = delta
      else
        velocity = byte(data, pos) or 0x7F
        local percent = byte(data, pos + 1) or 0
        pos = pos + 2
        duration = delta - math.floor((percent * delta) / 256)
      end
      if not skipTail then
        tickState.tick = tickState.tick + delta
        lastTimestamp = delta
        addNote(out, tickState.tick, duration, note, velocity, channel, state)
      end
    else
      local length = LAYER_LEN[command] or 0
      pos = pos + 1 + length
    end
  end
end

local function parseChannel(ctx, data, offset, limit, channel, state, tickState, depth)
  if depth > 8 then return end
  local seen = {}
  local pos = offset
  local guard = 0
  while pos <= limit and guard < 16384 do
    guard = guard + 1
    local mark = pos .. ":" .. channel
    if seen[mark] then return end
    seen[mark] = true
    local command = byte(data, pos)
    if command == nil or command == 0xFF or command == 0xFE then return end
    if command < 0x10 then
      tickState.tick = tickState.tick + command
      pos = pos + 1
    elseif command < 0x20 then
      pos = pos + 1
    elseif command < 0x30 then
      local target = u16(data, pos + 1)
      if not target then return end
      parseChannel(ctx, data, target + 1, limit, channel % 0x10, copyState(state), tickState, depth + 1)
      pos = pos + 3
    elseif command >= 0x78 and command < 0x80 then
      local rel = u16(data, pos + 1)
      if not rel then return end
      local layer = command % 4
      pos = pos + 3
      if rel > 0 then
        parseLayer(ctx, data, pos + rel, limit, channel, copyState(state), ctx.out, tickState, depth + 1)
      end
    elseif command >= 0x88 and command < 0x90 then
      local target = u16(data, pos + 1)
      if not target then return end
      local layer = command % 4
      pos = pos + 3
      parseLayer(ctx, data, target + 1, limit, channel, copyState(state), ctx.out, tickState, depth + 1)
    elseif command == 0xC1 then
      state.instrument = byte(data, pos + 1) or 0
      pos = pos + 2
    elseif command == 0xC3 then
      state.started = false
      pos = pos + 1
    elseif command == 0xC4 then
      state.started = true
      pos = pos + 1
    elseif command == 0xDD then
      state.pan = byte(data, pos + 1) or 0x40
      pos = pos + 2
    elseif command == 0xDF then
      state.volume = byte(data, pos + 1) or 0x7F
      pos = pos + 2
    elseif command == 0xB0 then
      return
    else
      pos = pos + 1 + (CHANNEL_LEN[command] or 0)
    end
  end
end

local function parseSequence(data)
  local ctx = { tempo = 120, out = {}, tickStates = {} }
  -- Each channel pointer starts at the master-track clock; sharing one tick
  -- across pointers would stack unrelated sections into hours of dead time.
  local function channelTick(start)
    local state = { tick = start }
    ctx.tickStates[#ctx.tickStates + 1] = state
    return state
  end
  local pos, limit, absoluteTick = 1, #data, 0
  local guard = 0
  while pos <= limit and guard < 16384 do
    guard = guard + 1
    local command = byte(data, pos)
    if command == nil or command == 0xFF or command == 0xFE then break end
    if command >= 0x90 and command < 0xA0 then
      local target = u16(data, pos + 1)
      if not target then break end
      local channel = command % 0x10
      parseChannel(ctx, data, target + 1, limit, channel, freshChannel(),
        channelTick(absoluteTick), 0)
      pos = pos + 3
    elseif command >= 0xA0 and command < 0xB0 then
      local rel = u16(data, pos + 1)
      if not rel then break end
      local channel = command % 0x10
      pos = pos + 3
      parseChannel(ctx, data, pos + rel, limit, channel, freshChannel(),
        channelTick(absoluteTick), 0)
    elseif command == 0xFD then
      local delta, nextPos = timeValue(data, pos + 1, limit)
      absoluteTick = absoluteTick + delta
      pos = nextPos
    elseif command == 0xDD then
      -- N64MidiTool writes MIDI tempo as 60000000 / operand, so the byte is
      -- already the BPM.  EAD sequences use 48 ticks per quarter note.
      local value = byte(data, pos + 1)
      if value and value > 0 then ctx.tempo = value end
      pos = pos + 2
    else
      local length = SEQ_LEN[command] or 0
      pos = pos + 1 + length
      if pos == guard - 16383 then break end
    end
  end
  table.sort(ctx.out, function(a, b)
    if a.tick == b.tick then return a.channel < b.channel end
    return a.tick < b.tick
  end)
  local maxTick = 0
  for _, state in pairs(ctx.tickStates) do
    if state.tick > maxTick then maxTick = state.tick end
  end
  return { events = ctx.out, tempo = ctx.tempo, ticks = maxTick }
end

local function keyBaseToPitch(value)
  value = tonumber(value) or 1
  if math.abs(value) < 0.00001 then value = 1 end
  local best, bestDistance = 60, math.huge
  for x = 0, 127 do
    local distance = math.abs(value - 2 ^ ((60 - x) / 12))
    if distance < bestDistance then
      bestDistance, best = distance, x
    end
  end
  return best
end

local function adsrFields(def)
  local adsr = def and def.adsr
  if type(adsr) ~= "table" or #adsr < 4 then
    return 127, 100, 100, 80
  end
  local function scale(index, fallback)
    local value = tonumber(adsr[index])
    if not value then return fallback end
    return clamp(math.floor(value / 65535 * 255), 1, 255)
  end
  return scale(2, 127), scale(3, 100), scale(4, 100), scale(6, 80)
end

local function buildPcm(decoded, bankIndex, bank, songName)
  local events = {}
  local lastTick = 0
  local bankKey = "n64:" .. tostring(bankIndex)
  for _, note in ipairs(decoded.events) do
    local def = bank[(note.instrument or 0) + 1] or bank[1]
    if def and def.wave then
      local attack, decay, sustain, release = adsrFields(def)
      local event = {
        tick = note.tick, gate = note.gate, track = note.channel,
        key = note.note, pitch = keyBaseToPitch(def.keyBase),
        vel = note.vel, volume = note.volume, pan = note.pan,
        bank = bankKey, archive = def.waveArchiveID, wave = def.waveID,
        attack = attack, decay = decay, sustain = sustain, release = release,
      }
      events[#events + 1] = event
    end
    if note.tick > lastTick then lastTick = note.tick end
  end
  if #events == 0 then return nil, 0 end
  table.sort(events, function(a, b)
    if a.tick == b.tick then return a.track < b.track end
    return a.tick < b.tick
  end)
  return {
    events = events,
    -- extra_audio legacy rate is tempo/2.5 ticks per second; EAD runs at
    -- BPM * 48 / 60 = BPM * 0.8 ticks per second.
    tempoTimeline = { { tick = 0, tempo = decoded.tempo * 2 } },
    loopStartTick = 0, loopEndTick = lastTick + 1, loopTick = lastTick + 1,
  }, lastTick + 1
end

local function carrierTrack(lastTick)
  local wait = clamp(lastTick, 0, 0xFFFF)
  return string.char(0xCD, 0x0C, wait % 256, math.floor(wait / 256) % 256)
    .. string.char(0xB2, 0, 0, 0, 0)
end

local function convertSong(song, bankIndex, bank, name)
  local sequence = M.deps.n64.readSequence(song.index or song)
  if not sequence then return nil end
  local decoded = parseSequence(sequence.data)
  local pcm, lastTick = buildPcm(decoded, bankIndex, bank, name)
  if not pcm then return nil end
  local carrier = carrierTrack(lastTick)
  local specs = M.deps.g3Mix.buildSpecs({
    name = name, tracks = 1, trackData = { carrier }, voicegroup = 1,
  }, { voicegroupId = 1 })
  if not specs or #specs == 0 then return nil end
  specs[#specs].pcm = pcm
  return {
    def = {
      name = name, generation = 1, n64Mix = true,
      converter = CONVERTER_VERSION, sourceTracks = 1,
    },
    extra = {}, tracks = 1, specs = specs, tempo = decoded.tempo,
  }
end

function M.install(deps)
  M.deps = deps
end

function M.available()
  if M.deps and M.deps.available then
    local ok, value = pcall(M.deps.available)
    return ok and value == true
  end
  return M.deps and M.deps.n64 and M.deps.n64.available and M.deps.n64.available() or false
end

function M.listSongs()
  if not M.available() then return {} end
  return M.deps.n64.listSongs() or {}
end

function M.has(version, label)
  if not M.available() then return false end
  local song = M.deps.songMap and M.deps.songMap.mappedSongFor
      and M.deps.songMap.mappedSongFor(label, "pcm")
  if not song then return false end
  local index = tonumber(song.index)
  if not index then return false end
  for _, entry in ipairs(M.listSongs()) do
    if entry.index == index then return true end
  end
  return false
end

function M.convert(version, label, mode)
  if not M.available() then return nil end
  local song = M.deps.songMap and M.deps.songMap.mappedSongFor
      and M.deps.songMap.mappedSongFor(label, "pcm")
  if not song then return nil end
  local fontBank = M.deps.n64.bankForSequence
      and M.deps.n64.bankForSequence(song.index)
  local bankIndex = fontBank ~= nil and fontBank or tonumber(song.bank) or 0
  local bank = M.deps.n64.readBank(bankIndex) or {}
  local out = convertSong(song, bankIndex, bank, label)
  if not out then return nil end
  out.def.converter = CONVERTER_VERSION .. "_pcm"
  out.def.key = label
  out.def.version = version
  return out
end

return M
