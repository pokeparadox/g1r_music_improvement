-- Offline GBA -> chip converter.  Reads already-imported FRLG/RSE song blobs
-- from the version cache and turns M4A track bytecode into ChipAsm specs.
-- One spec holds at most four tracks; extra tracks become extra engines.

local M = {}

local CONVERTER_VERSION = 1
local AUDIO_ROOT = "data/generated/gba/audio/"

-- pret gClockTable: waits use cmd-0x80, notes use cmd-0xCF.
local CLOCK = {
  [0] = 0,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
  16, 17, 18, 19, 20, 21, 22, 23, 24, 28, 30, 32, 36, 40, 42, 44,
  48, 52, 54, 56, 60, 64, 66, 68, 72, 76, 78, 80, 84, 88, 90, 92, 96,
}

function M.clockAt(index)
  index = tonumber(index) or 0
  if index < 0 then index = 0 end
  return CLOCK[index] or index
end

function M.decodeTrack(data)
  if type(data) ~= "string" or #data == 0 then return { events = {} } end
  local events = {}
  local pc, tick, wait = 0, 0, 0
  local key, vel, voice = 60, 100, 0
  local volume, pan, tempo = 100, 0x40, 150
  local keyShift, bend, bendRange = 0, 0, 2
  local repeats, jumps = {}, 0
  local loopTo
  local function read()
    if pc >= #data then return nil end
    local b = data:byte(pc + 1)
    pc = pc + 1
    return b
  end
  local function read32()
    local n = 0
    for i = 0, 3 do n = n + (read() or 0) * 256 ^ i end
    return n
  end
  local function add(kind, fields)
    local event = fields or {}
    event.kind = kind
    event.tick = tick
    event.address = pc
    events[#events + 1] = event
  end

  local guard = 0
  while guard < 400000 do
    guard = guard + 1
    if wait > 0 then
      wait = wait - 1
      tick = tick + 1
    elseif tick > 200000 then
      break
    else
      local cmd = read()
      if cmd == nil then break end
      if cmd >= 0x80 and cmd <= 0xB0 then
        wait = M.clockAt(cmd - 0x80)
      elseif cmd == 0xB1 then
        break
      elseif cmd == 0xB2 then
        local target = read32()
        if target < #data and target < pc then
          loopTo = nil
          for index, event in ipairs(events) do
            if event.address >= target then loopTo = index break end
          end
          break
        elseif target < #data and jumps < 64 then
          jumps = jumps + 1
          pc = target
        end
      elseif cmd == 0xB3 or cmd == 0xB4 or cmd == 0xB5 then
        -- Calls/repeats are flattened; only backward repeats become loops.
        local countOrAddr = cmd == 0xB5 and read() or nil
        local target = read32()
        if target < #data and jumps < 64 then
          repeats[target] = (repeats[target] or 0) + 1
          if countOrAddr == nil or countOrAddr == 0
              or repeats[target] < countOrAddr then
            jumps = jumps + 1
            pc = target
          end
        end
      elseif cmd == 0xBB then
        tempo = (read() or 75) * 2
        add("tempo", { tempo = tempo })
      elseif cmd == 0xBC then
        keyShift = read() or 0
        if keyShift > 127 then keyShift = keyShift - 256 end
      elseif cmd == 0xBD then
        voice = read() or 0
      elseif cmd == 0xBE then
        volume = read() or 100
      elseif cmd == 0xBF then
        pan = read() or 0x40
      elseif cmd == 0xC0 then
        bend = (read() or 0x40) - 0x40
      elseif cmd == 0xC1 then
        bendRange = read() or 2
      elseif cmd == 0xC8 then
        -- TUNE is centred on 0x40; approximation folds it into semitones.
        local tune = (read() or 0x40) - 0x40
        keyShift = keyShift + math.floor(tune / 8)
      elseif cmd == 0xCD then
        local xop = read() or 0
        if xop == 12 then read(); read()
        elseif xop == 13 or xop == 1 then read(); read(); read(); read()
        elseif xop == 8 or xop == 9 or xop == 2 or xop == 4 or xop == 5
            or xop == 6 or xop == 7 or xop == 10 or xop == 11 then read()
        end
      elseif cmd == 0xCE then
        local nextByte = data:byte(pc + 1)
        if nextByte and nextByte < 0x80 then pc = pc + 1 end
      elseif cmd >= 0xCF then
        local gate = M.clockAt(cmd - 0xCF)
        local nextByte = data:byte(pc + 1)
        if nextByte and nextByte < 0x80 then
          key = read()
        end
        nextByte = data:byte(pc + 1)
        if nextByte and nextByte < 0x80 then
          vel = read()
        end
        nextByte = data:byte(pc + 1)
        if nextByte and nextByte < 0x80 then
          gate = gate + read()
        end
        if gate < 1 then gate = 1 end
        if gate > 512 then gate = 512 end
        add("note", {
          key = key + keyShift + bend * bendRange,
          rawKey = key,
          vel = vel,
          gate = gate,
          voice = voice,
          volume = volume,
          pan = pan,
          tempo = tempo,
        })
      elseif cmd == 0xCC then
        read(); read()
      elseif cmd == 0xB9 then
        local op = read() or 0
        read(); read()
        if op >= 6 and op <= 17 then read32() end
      else
        break
      end
    end
  end
  table.sort(events, function(a, b)
    if a.tick ~= b.tick then return a.tick < b.tick end
    return a.address < b.address
  end)
  return { events = events, loopTo = loopTo, ticks = tick }
end

local WAVES = {
  { -1, -0.75, -0.5, -0.25, 0, 0.25, 0.5, 0.75,
     1, 0.75, 0.5, 0.25, 0, -0.25, -0.5, -0.75,
     -1, -0.75, -0.5, -0.25, 0, 0.25, 0.5, 0.75,
     1, 0.75, 0.5, 0.25, 0, -0.25, -0.5, -0.75 },
  { -1, -1, -1, -1, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0,
     -1, -1, -1, -1, 0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0 },
  { -1, -0.5, 0, 0.5, 1, 0.5, 0, -0.5, -1, -0.5, 0, 0.5, 1, 0.5, 0, -0.5,
     -1, -0.5, 0, 0.5, 1, 0.5, 0, -0.5, -1, -0.5, 0, 0.5, 1, 0.5, 0, -0.5 },
  { -1, -1, -1, -1, -1, -1, -1, -1, 1, 1, 1, 1, 1, 1, 1, 1,
     -1, -1, -1, -1, -1, -1, -1, -1, 1, 1, 1, 1, 1, 1, 1, 1 },
}

local DRUMS = {
  [1] = { { len = 12, volume = 14, fade = 6, parameter = 1 } },
  [2] = { { len = 8, volume = 12, fade = 8, parameter = 3 } },
  [3] = { { len = 16, volume = 10, fade = 4, parameter = 5 } },
  [4] = { { len = 6, volume = 15, fade = 10, parameter = 7 } },
}

local function tableValue(t, key)
  if type(t) ~= "table" then return nil end
  return t[key] or t[tostring(key)]
end

local function resolveTone(voicegroups, vgId, voiceId, rawKey, depth)
  depth = depth or 0
  if depth > 6 or not vgId then return nil end
  local tone = tableValue(voicegroups and tableValue(voicegroups, vgId), voiceId)
  if not tone then return nil end
  local typ = tone.type or 0
  local split = math.floor(typ / 64) % 2 == 1
  local rhythm = typ >= 128
  if split then
    local keys = tone.keySplit
    local index = 0
    if type(keys) == "table" then index = tableValue(keys, rawKey) or 0 end
    return resolveTone(voicegroups, tone.subVgId, index, rawKey, depth + 1)
  end
  if rhythm then
    local sub = resolveTone(voicegroups, tone.subVgId, rawKey, rawKey, depth + 1)
    if not sub then return nil end
    local copy = {}
    for _, field in ipairs({ "type", "key", "wavParam", "wave" }) do
      copy[field] = sub[field]
    end
    copy.isRhy = true
    return copy
  end
  return tone
end

local function toneInfo(voicegroups, vgId, note)
  local tone = resolveTone(voicegroups, vgId, note.voice, note.rawKey)
  local typ = tone and tone.type or 0
  local kind = typ % 8
  if kind < 1 or kind > 4 then kind = 1 end
  if kind == 1 or kind == 2 then
    local wp = tone and tone.wavParam or 0
    return kind, wp <= 3 and wp or 2, nil
  end
  if kind == 3 then
    local wave = tone and tone.wave
    local waveIndex = 0
    if type(wave) == "table" and #wave >= 32 then
      local sum = 0
      for i = 1, 16 do sum = sum + (tonumber(wave[i]) or 0) end
      waveIndex = math.abs(math.floor(sum / 4)) % 4
    end
    return kind, 0, waveIndex
  end
  return 4, 0, nil
end

local function gbTempo(tempo)
  local value = math.floor(38400 / math.max(1, tempo) + 0.5)
  if value < 1 then value = 1 end
  if value > 0xFFFF then value = 0xFFFF end
  return value
end

local function roleFor(kind, used)
  local order
  if kind == 4 then order = { 4, 1, 2, 3 }
  elseif kind == 3 then order = { 3, 1, 2, 4 }
  else order = { 1, 2, 3, 4 } end
  for _, hw in ipairs(order) do
    if not used[hw] then used[hw] = true return hw end
  end
  return 1
end

local function emitRest(program, ticks)
  local remaining = math.floor(ticks + 0.5)
  while remaining > 0 do
    local chunk = math.min(remaining, 16)
    program[#program + 1] = { notetype = { speed = 1 } }
    program[#program + 1] = { rest = chunk }
    remaining = remaining - chunk
  end
end

local function emitNote(program, note, role, duty, waveIndex)
  local tempo = math.max(1, note.tempo or 150)
  local speed = math.max(1, math.min(15, math.ceil(note.gate / 16)))
  local length = math.max(1, math.floor(note.gate / speed + 0.5))
  local volume = math.max(0, math.min(15,
    math.floor((note.vel or 100) / 127 * (note.volume or 100) / 100 * 15 + 0.5)))
  local key = math.max(12, math.min(119, math.floor(note.key or 60)))
  local pitch, octave = key % 12, math.floor(key / 12) - 1
  if role == 4 then
    program[#program + 1] = { notetype = { speed = speed, volume = volume } }
    local drum = ((note.rawKey or key) % 4) + 1
    local remaining = length
    while remaining > 0 do
      local chunk = math.min(remaining, 16)
      program[#program + 1] = { drum = drum, len = chunk }
      remaining = remaining - chunk
    end
    return
  end
  if role == 3 then
    program[#program + 1] = {
      notetype = { speed = speed, waveLevel = 3, waveInstrument = waveIndex or 0 },
    }
    -- ChipSynth's wave channel sounds an octave below the pulse register.
    pitch = key % 12
    octave = math.floor(key / 12)
  else
    program[#program + 1] = { notetype = { speed = speed, volume = volume, fade = 0 } }
    program[#program + 1] = { duty = duty or 2 }
  end
  if octave < 1 then octave = 1 elseif octave > 8 then octave = 8 end
  program[#program + 1] = { octave = octave }
  local remaining = length
  while remaining > 0 do
    local chunk = math.min(remaining, 16)
    program[#program + 1] = { pitch = pitch, len = chunk }
    remaining = remaining - chunk
  end
end

function M.buildSpecs(song, voicegroups, info)
  if type(song) ~= "table" or not song.tracks or song.tracks < 1 then return nil end
  local vgId = song.voicegroup or (info and info.voicegroupId)
  local decoded = {}
  for i = 1, song.tracks do
    decoded[i] = M.decodeTrack(song.trackData and song.trackData[i] or "")
  end
  local lastTick = 1
  for _, track in ipairs(decoded) do
    local ticks = track.ticks or 0
    for _, event in ipairs(track.events) do
      if event.kind == "note" then
        ticks = math.max(ticks, event.tick + (event.gate or 1))
      end
    end
    lastTick = math.max(lastTick, ticks)
  end
  if lastTick < 1 then lastTick = 1 end
  if lastTick > 200000 then lastTick = 200000 end

  local programs = {}
  for index, track in ipairs(decoded) do
    local kinds = {}
    for _, event in ipairs(track.events) do
      if event.kind == "note" then
        local kind = toneInfo(voicegroups, vgId, event)
        kinds[kind] = (kinds[kind] or 0) + 1
      end
    end
    local dominant = 1
    local best = 0
    for kind, count in pairs(kinds) do
      if count > best then dominant, best = kind, count end
    end
    local program = {}
    local cursor, currentTempo = 0, 150
    for _, event in ipairs(track.events) do
      if event.tick > cursor then
        emitRest(program, event.tick - cursor)
        cursor = event.tick
      end
      if event.kind == "tempo" then
        currentTempo = event.tempo or currentTempo
        program[#program + 1] = { tempo = gbTempo(currentTempo) }
      elseif event.kind == "note" then
        local kind, duty, waveIndex = toneInfo(voicegroups, vgId, event)
        local role = dominant
        if dominant == 1 then role = kind end
        emitNote(program, event, role, duty, waveIndex)
      end
    end
    if cursor < lastTick then emitRest(program, lastTick - cursor) end
    if #program == 0 then emitRest(program, 16) end
    program[#program + 1] = { loop = { count = 0, to = 1 } }
    programs[index] = program
  end

  local specs = {}
  for start = 1, #programs, 4 do
    local used, channels = {}, {}
    for i = start, math.min(start + 3, #programs) do
      local kinds = {}
      for _, event in ipairs(decoded[i].events) do
        if event.kind == "note" then
          local kind = toneInfo(voicegroups, vgId, event)
          kinds[kind] = (kinds[kind] or 0) + 1
        end
      end
      local dominant, best = 1, 0
      for kind, count in pairs(kinds) do
        if count > best then dominant, best = kind, count end
      end
      channels[#channels + 1] = { hw = roleFor(dominant, used), program = programs[i] }
    end
    specs[#specs + 1] = {
      tempo = 256,
      channels = channels,
      waves = WAVES,
      drums = DRUMS,
      engine = 1,
    }
  end
  return specs
end

local function luaTable(version, file)
  local okCache, CacheFs = pcall(require, "src.import.CacheFs")
  if not okCache or type(CacheFs) ~= "table" or not CacheFs.readAt then return nil end
  local okVersion, GameVersion = pcall(require, "src.core.GameVersion")
  if not okVersion or type(GameVersion) ~= "table" or not GameVersion.cachePrefix then
    return nil
  end
  local bytes = CacheFs.readAt(GameVersion.cachePrefix(version) .. AUDIO_ROOT .. file)
  if type(bytes) ~= "string" then return nil end
  local chunk = load(bytes, "@gba/" .. version .. "/" .. file)
  if not chunk then return nil end
  local ok, result = pcall(chunk)
  if not ok or type(result) ~= "table" then return nil end
  return result
end

local function audioFile(version, name)
  local okCache, CacheFs = pcall(require, "src.import.CacheFs")
  if not okCache or type(CacheFs) ~= "table" or not CacheFs.readAt then return nil end
  local okVersion, GameVersion = pcall(require, "src.core.GameVersion")
  if not okVersion or type(GameVersion) ~= "table" or not GameVersion.cachePrefix then
    return nil
  end
  return CacheFs.readAt(GameVersion.cachePrefix(version) .. AUDIO_ROOT .. name)
end

local cache = {}
local function dataFor(version)
  if cache[version] ~= nil then return cache[version] or nil end
  local index = luaTable(version, "index.lua")
  local voicegroups = luaTable(version, "voicegroups.lua")
  if not index or not voicegroups then cache[version] = false return nil end
  local data = { index = index, voicegroups = voicegroups }
  cache[version] = data
  return data
end

local function songIds(version)
  local ok, Song = pcall(require, "src.core.game3.song_ids")
  if not ok or type(Song) ~= "table" or not Song.forVersion then return {} end
  local okSongs, songs = pcall(Song.forVersion, version)
  if not okSongs or type(songs) ~= "table" then return {} end
  return songs
end

function M.availableVersions(versions)
  local out = {}
  for _, entry in ipairs((versions and versions.VERSIONS) or {}) do
    if entry.generation == 3 and dataFor(entry.id) then out[#out + 1] = entry.id end
  end
  return out
end

function M.songList(version, labelFilter)
  local data = dataFor(version)
  if not data then return {} end
  local out = {}
  for label, id in pairs(songIds(version)) do
    if type(label) == "string" and label:match("^MUS_")
        and (not labelFilter or labelFilter[label]) then
      local info = tableValue(data.index, "songs")
      info = info and (tableValue(info, id) or tableValue(info, tostring(id)))
      if info and info.kind == "bgm" and (info.tracks or 0) > 0 then
        out[#out + 1] = label
      end
    end
  end
  table.sort(out)
  return out
end

function M.has(version, label)
  local data = dataFor(version)
  if not data or type(label) ~= "string" then return false end
  local id = songIds(version)[label]
  if not id then return false end
  local songs = tableValue(data.index, "songs")
  local info = songs and (tableValue(songs, id) or tableValue(songs, tostring(id)))
  return info ~= nil and info.kind == "bgm" and (info.tracks or 0) > 0
end

function M.convert(version, label)
  local data = dataFor(version)
  if not data then return nil end
  local id = songIds(version)[label]
  if not id then return nil end
  local songs = tableValue(data.index, "songs")
  local info = songs and (tableValue(songs, id) or tableValue(songs, tostring(id)))
  if not info or info.kind ~= "bgm" or (info.tracks or 0) < 1 then return nil end
  local blob = audioFile(version, "songs/" .. tostring(id) .. ".bin")
  if type(blob) ~= "string" then return nil end
  local okSeq, Seq = pcall(require, "src.core.game3.m4a_seq")
  if not okSeq or type(Seq) ~= "table" or not Seq.parseSongBin then return nil end
  local okParse, song = pcall(Seq.parseSongBin, blob)
  if not okParse or type(song) ~= "table" then return nil end
  local specs = M.buildSpecs(song, data.voicegroups, info)
  if not specs or #specs == 0 then return nil end
  local def = specs[1]
  def.generation = 1
  def.g3Mix = true
  def.converter = CONVERTER_VERSION
  local extra = {}
  for i = 2, #specs do
    local spec = specs[i]
    spec.generation = 1
    spec.g3Mix = true
    spec.pan = (((i - 2) % 3) - 1) * 0.5
    extra["g3_" .. tostring(i)] = spec
  end
  return { def = def, extra = extra, tracks = song.tracks }
end

return M
