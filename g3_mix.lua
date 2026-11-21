-- Offline GBA -> chip converter.  Reads already-imported FRLG/RSE song blobs
-- from the version cache and turns M4A track bytecode into ChipAsm specs.
-- One spec holds at most four tracks; extra tracks become extra engines.

local M = {}

local CONVERTER_VERSION = 5
local AUDIO_ROOT = "data/generated/gba/audio/"

-- pret gClockTable: waits use cmd-0x80, notes use cmd-0xCF.
local CLOCK = {
  [0] = 0,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
  16, 17, 18, 19, 20, 21, 22, 23, 24, 28, 30, 32, 36, 40, 42, 44,
  48, 52, 54, 56, 60, 64, 66, 68, 72, 76, 78, 80, 84, 88, 90, 92, 96,
}

local function copyTable(t)
  if type(t) ~= "table" then return nil end
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

function M.clockAt(index)
  index = tonumber(index) or 0
  if index < 0 then index = 0 end
  return CLOCK[index] or index
end

-- Local copy of the engine's M4A header parser. Engine game3 modules are
-- sandbox-denied on Gen1/Gen2 hosts, so conversion cannot require them.
local function u8(blob, off)
  if off < 0 or off >= #blob then return nil end
  return blob:byte(off + 1)
end

local function u32le(blob, off)
  local b0 = u8(blob, off)
  if not b0 then return nil end
  return b0 + (u8(blob, off + 1) or 0) * 256
    + (u8(blob, off + 2) or 0) * 65536
    + (u8(blob, off + 3) or 0) * 16777216
end

local function parseSongBin(blob)
  if type(blob) ~= "string" or #blob < 8 then return nil end
  local tracks = u8(blob, 0) or 0
  if tracks > 16 then tracks = 0 end
  local out = {
    tracks = tracks,
    blocks = u8(blob, 1),
    priority = u8(blob, 2),
    reverb = u8(blob, 3),
    voicegroup = u32le(blob, 4),
    trackData = {},
    trackEntries = {},
  }
  if tracks == 0 then return out end

  local first = u32le(blob, 8) or 0
  local packed = first > 0 and first < #blob and first < 0x01000000
  if packed then
    local stride = (out.blocks or 0) >= 128 and 12 or 8
    out.blocks = (out.blocks or 0) % 128
    for t = 0, tracks - 1 do
      local base = 8 + t * stride
      local off = u32le(blob, base) or 0
      local len = u32le(blob, base + 4) or 0
      if off > 0 and len > 0 and off + len <= #blob then
        out.trackData[t + 1] = blob:sub(off + 1, off + len)
        out.trackEntries[t + 1] = stride == 12 and (u32le(blob, base + 8) or 0) or 0
      else
        out.trackData[t + 1] = ""
      end
    end
    return out
  end

  local headerSize = 8 + tracks * 4
  local ptrs = {}
  for t = 0, tracks - 1 do
    ptrs[#ptrs + 1] = { idx = t, ptr = u32le(blob, 8 + t * 4) or 0 }
  end
  table.sort(ptrs, function(a, b) return a.ptr < b.ptr end)
  local cursor = headerSize
  local packedOff = {}
  for i, p in ipairs(ptrs) do
    local remainTracks = #ptrs - i + 1
    local remainBytes = #blob - cursor
    local approx = math.floor(remainBytes / remainTracks)
    if ptrs[i + 1] and p.ptr > 0 and ptrs[i + 1].ptr > p.ptr then
      approx = math.min(approx, ptrs[i + 1].ptr - p.ptr)
    end
    approx = math.max(16, math.min(approx, remainBytes))
    packedOff[p.idx] = { off = cursor, len = approx }
    cursor = cursor + approx
  end
  for t = 0, tracks - 1 do
    local p = packedOff[t]
    out.trackData[t + 1] = p and blob:sub(p.off + 1, p.off + p.len) or ""
  end
  return out
end

function M.decodeTrack(data)
  if type(data) ~= "string" or #data == 0 then return { events = {} } end
  local events = {}
  local pc, tick, wait = 0, 0, 0
  local key, vel, voice = 60, 100, 0
  local volume, pan, tempo = 100, 0x40, 150
  local keyShift, bend, bendRange = 0, 0, 2
  local repeats, jumps, callStack, mem = {}, 0, {}, {}
  local toneOverrides
  local runningStatus
  local noteSeen = {}
  local commandAddress = 0
  local tickAt = {}
  local loopSeq, loopTick, sequence = nil, nil, 0
  local add
  local function currentPitch()
    return key + keyShift + bend * bendRange
  end
  local lastPitch
  local function emitPitch()
    local pitch = currentPitch()
    if pitch ~= lastPitch then
      lastPitch = pitch
      add("pitch", { key = pitch })
    end
  end
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
  add = function(kind, fields)
    local event = fields or {}
    event.kind = kind
    sequence = sequence + 1
    event.seq = sequence
    event.tick = tick
    event.address = commandAddress
    events[#events + 1] = event
    return event
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
      commandAddress = pc
      -- Loops revisit addresses; keep first pass tick so GOTO target resolves
      -- to original position, not a later repeat iteration.
      if tickAt[pc] == nil then tickAt[pc] = tick end
      local cmd = read()
      if cmd == nil then break end
      local noteKeyOverride
      if cmd < 0x80 and runningStatus and runningStatus >= 0xCF then
        -- A bare key byte reuses the previous note command as running status.
        noteKeyOverride = cmd
        cmd = runningStatus
      elseif cmd < 0x80 and runningStatus then
        -- Non-note running status keeps its data byte at pc.  m4a_seq.lua
        -- only advances pc for status bytes, so the reused command reads
        -- that byte as its first operand.  Consuming it here truncated
        -- 0xCD XRMI chains and dropped most of a song's notes.
        pc = pc - 1
        cmd = runningStatus
      elseif cmd < 0x80 then
        cmd = runningStatus or cmd
      elseif cmd >= 0xBD then
        runningStatus = cmd
      end
      if cmd >= 0x80 and cmd <= 0xB0 then
        wait = M.clockAt(cmd - 0x80)
      elseif cmd == 0xB1 then
        break
      elseif cmd == 0xB2 then
        local target = read32()
        if target < #data and target < pc then
          -- Native GOTO target is a byte address, not an emitted event. Long
          -- wait runs can put target in a gap; use tick recorded when decoder
          -- walked that address instead of first later event tick.
          loopTick = tickAt[target]
          if not loopTick then
            for address = target - 1, 0, -1 do
              if tickAt[address] then loopTick = tickAt[address] break end
            end
          end
          loopSeq = nil
          for _, event in ipairs(events) do
            if event.address >= target then
              loopSeq = event.seq
              if not loopTick then loopTick = event.tick end
              break
            end
          end
          break
        elseif target < #data and jumps < 64 then
          jumps = jumps + 1
          pc = target
        end
      -- CALL (4-byte addr), RET (no operand), REPEAT (count + 4-byte addr).
      -- Match m4a_seq.exec_cmd exactly; a shared read here would consume
      -- bogus bytes after RET and corrupt every following note.
      elseif cmd == 0xB3 then
        local target = read32()
        if target < #data and #callStack < 3 then
          callStack[#callStack + 1] = pc
          pc = target
        else
          break
        end
      elseif cmd == 0xB4 then
        if #callStack > 0 then pc = table.remove(callStack) end
      elseif cmd == 0xB5 then
        local count = read() or 0
        local target = read32()
        local times = (repeats[target] or 0) + 1
        repeats[target] = times
        if count == 0 or times < count then
          if target < #data then pc = target end
        else
          repeats[target] = 0
        end
      elseif cmd == 0xBA then
        read() -- priority
      elseif cmd == 0xBB then
        tempo = (read() or 75) * 2
        add("tempo", { tempo = tempo })
      elseif cmd == 0xBC then
        keyShift = read() or 0
        if keyShift > 127 then keyShift = keyShift - 256 end
        emitPitch()
      elseif cmd == 0xBD then
        voice = read() or 0
      elseif cmd == 0xBE then
        volume = read() or 100
      elseif cmd == 0xBF then
        pan = read() or 0x40
      elseif cmd == 0xC0 then
        bend = (read() or 0x40) - 0x40
        emitPitch()
      elseif cmd == 0xC1 then
        bendRange = read() or 2
        emitPitch()
      elseif cmd >= 0xC2 and cmd <= 0xC5 then
        read() -- LFO speed/delay, modulation depth/type
      elseif cmd == 0xC8 then
        -- TUNE is centred on 0x40; approximation folds it into semitones.
        local tune = (read() or 0x40) - 0x40
        keyShift = keyShift + math.floor(tune / 8)
        emitPitch()
      elseif cmd == 0xCD then
        local xop = read() or 0
        local fields = {
          [2] = "type", [4] = "attack", [5] = "decay",
          [6] = "sustain", [7] = "release", [10] = "length", [11] = "pan",
        }
        if xop == 12 then
          -- REST: 16-bit wait override (m4a_seq.lua xop 12).  Older builds
          -- only consumed the bytes, so rest sections fired too early.
          local low = read() or 0
          local high = read() or 0
          wait = low + high * 256
        elseif xop == 13 or xop == 1 then read(); read(); read(); read()
        elseif fields[xop] then
          -- Tone overrides from 0xCD are the main source of ADSR/pan changes;
          -- keeping them lets the chip spec approximate the original envelope.
          toneOverrides = toneOverrides or {}
          toneOverrides[fields[xop]] = read() or 0
        elseif xop == 8 or xop == 9 then read()
        else
          -- Engine terminates the track on unknown XRMI commands.
          break
        end
      elseif cmd == 0xCE then
        -- ENDTIE releases the current (or explicitly named) key.  Without an
        -- off event tied notes sustain until the next note or song end.
        local offKey = data:byte(pc + 1)
        if offKey and offKey < 0x80 then
          pc = pc + 1
          key = offKey
        end
        add("off", { key = key })
      elseif cmd >= 0xCF then
        local gate = M.clockAt(cmd - 0xCF)
        if noteKeyOverride then
          key = noteKeyOverride
        else
          local nextByte = data:byte(pc + 1)
          if nextByte and nextByte < 0x80 then key = read() end
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
        -- MP2K uses very low velocities for dummy/echo triggers.  Dropping
        -- them avoids audible clicks; duplicates at the same tick share one
        -- note with reduced gain.
        if vel >= 20 then
          local pitch = currentPitch()
          local slot = tick .. ":" .. key
          local existing = noteSeen[slot]
          if existing then
            if vel > (existing.vel or 0) then existing.vel = vel end
            if vel < (existing.vel or 0) then
              existing.volume = math.floor((existing.volume or 100) * 0.6)
            else
              existing.volume = math.floor((existing.volume or 100) * 0.8)
            end
          else
            local event = add("note", {
              key = pitch,
              rawKey = key,
              vel = vel,
              gate = gate,
              voice = voice,
              volume = volume,
              pan = pan,
              tempo = tempo,
              toneOverrides = toneOverrides and copyTable(toneOverrides) or nil,
            })
            noteSeen[slot] = event
            lastPitch = pitch
          end
        end
      elseif cmd == 0xCC then
        read(); read()
      elseif cmd == 0xB9 then
        -- MP2K memory/conditional jump.  Older decoder consumed operands but
        -- never took the branch, so conditional sections never sounded.
        local memOp = read() or 0
        local addr = read() or 0
        local dataByte = read() or 0
        local value = mem[addr] or 0
        local useMemory = (memOp >= 3 and memOp <= 5) or memOp >= 12
        local operand = useMemory and (mem[dataByte] or 0) or dataByte
        if memOp <= 5 then
          local action = memOp % 3
          if action == 0 then value = operand
          elseif action == 1 then value = value + operand
          else value = value - operand end
          mem[addr] = value % 256
        elseif memOp <= 17 then
          local target = read32()
          local cond = (memOp - 6) % 6
          local take = (cond == 0 and value == operand)
            or (cond == 1 and value ~= operand)
            or (cond == 2 and value > operand)
            or (cond == 3 and value >= operand)
            or (cond == 4 and value <= operand)
            or (cond == 5 and value < operand)
          if take and target and target < #data then
            pc = target
            jumps = jumps + 1
            if jumps > 4000 then break end
          end
        end
      else
        break
      end
    end
  end
  -- Execution order matters: CALL/REPEAT reach lower addresses after higher
  -- ones.  Sorting purely by address scrambles those sections.
  table.sort(events, function(a, b)
    if a.tick ~= b.tick then return a.tick < b.tick end
    return a.seq < b.seq
  end)
  local loopTo
  if loopSeq then
    for index, event in ipairs(events) do
      if event.seq == loopSeq then loopTo = index break end
    end
  end
  return { events = events, loopTo = loopTo, loopTick = loopTick, ticks = tick }
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

-- MP2K rhythm kits use MIDI key numbers to pick a drum sample.  The old
-- converter used rawKey % 4, which made kick/snare/hat interchangeable.
-- Noise presets: id 1 hat, 2 snare/rim, 3 tom, 4 kick, 5 cymbal.
local DRUM_PRESETS = {
  hat      = { id = 1, kind = 4, fade = 7, duty = 1 },
  snare    = { id = 2, kind = 4, fade = 6, duty = 1 },
  tom      = { id = 3, kind = 4, fade = 7, duty = 1 },
  kick     = { id = 4, kind = 4, fade = 7, duty = 1 },
  cymbal   = { id = 5, kind = 4, fade = 5, duty = 1 },
  tomPulse = { id = 3, kind = 1, fade = -3, duty = 1 },
}

-- Drum peaks sit just above the perceptual melody range (roughly 6-10 after
-- the volume curve below).  The old 10-14 table buried quiet tracks.
local DRUMS = {
  [1] = { { len = 4, volume = 9, fade = 7, parameter = 1 } },
  [2] = { { len = 8, volume = 8, fade = 6, parameter = 3 } },
  [3] = { { len = 12, volume = 8, fade = 7, parameter = 5 } },
  [4] = { { len = 14, volume = 10, fade = 7, parameter = 7 } },
  [5] = { { len = 16, volume = 7, fade = 5, parameter = 0 } },
}

local function drumPresetFor(rawKey)
  local key = tonumber(rawKey) or 60
  if key <= 36 then return DRUM_PRESETS.kick end
  if key == 38 or key == 40 then return DRUM_PRESETS.snare end
  if key == 41 or key == 43 or key == 45 or key == 47 then
    return DRUM_PRESETS.tomPulse
  end
  if key == 42 or key == 44 or key == 54 or key == 56 then
    return DRUM_PRESETS.hat
  end
  if key >= 46 and key <= 53 then return DRUM_PRESETS.cymbal end
  if key >= 35 and key <= 81 then return DRUM_PRESETS.snare end
  return nil
end
M.drumPresetFor = drumPresetFor

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

local function toneInfo(voicegroups, vgId, note, specWaves)
  local tone = resolveTone(voicegroups, vgId, note.voice, note.rawKey)
  if tone and tone.isRhy then
    local preset = drumPresetFor(note.rawKey or note.key)
    if preset then
      note.drumPreset = preset
      return preset.kind, preset.duty, nil, tone
    end
  end
  local typ = tone and tone.type or 0
  local kind = typ % 8
  if kind < 1 or kind > 4 then kind = 1 end
  if kind == 1 or kind == 2 then
    local wp = tone and tone.wavParam or 0
    return kind, wp <= 3 and wp or 2, nil, tone
  end
  if kind == 3 then
    local wave = tone and tone.wave
    if specWaves and type(wave) == "table" and #wave >= 32 then
      local signature, min, max = {}, math.huge, -math.huge
      for i = 1, 32 do
        local n = tonumber(wave[i]) or 0
        signature[i] = tostring(n)
        if n < min then min = n end
        if n > max then max = n end
      end
      signature = table.concat(signature, ",")
      for index, existing in ipairs(specWaves) do
        if existing.signature == signature then
          return kind, 0, #WAVES + index - 1, tone
        end
      end
      if #specWaves < 12 then
        local normalized = {}
        -- Cached GBA wave RAM is 0..15, but ChipSynth expects -1..1 samples.
        -- Scale by the samples actually present: many melodies occupy only a
        -- narrow nibble band, and a fixed 0..15 map left them near silence.
        local center, half = (min + max) / 2, (max - min) / 2
        for i = 1, #wave do
          local n = tonumber(wave[i]) or 0
          normalized[i] = half > 0
            and math.max(-1, math.min(1, (n - center) / half)) or 0
        end
        specWaves[#specWaves + 1] = { signature = signature, wave = normalized }
        return kind, 0, #WAVES + #specWaves - 1, tone
      end
    end
    local waveIndex = 0
    if type(wave) == "table" and #wave >= 32 then
      local sum = 0
      for i = 1, 16 do sum = sum + (tonumber(wave[i]) or 0) end
      waveIndex = math.abs(math.floor(sum / 4)) % 4
    end
    return kind, 0, waveIndex, tone
  end
  return 4, 0, nil, tone
end

local function gbTempo(tempo)
  -- M4A stores half the sequencer tempo. Seq.update runs one VBlank frame
  -- at a time and advances tempo/150 seq ticks per frame, so seq ticks are
  -- 60*tempo/150 = 0.4*tempo per second. GB ticks are 15360/s, hence
  -- 38400/tempo. The earlier 19200 constant played everything 2x too fast.
  local value = math.floor(38400 / math.max(1, tempo) + 0.5)
  if value < 1 then value = 1 end
  if value > 0xFFFF then value = 0xFFFF end
  return value
end

local function noteGain(note)
  local gain = (tonumber(note.vel) or 100) / 127 *
    (tonumber(note.volume) or 100) / 255
  return math.sqrt(math.max(0, math.min(1, gain)))
end

local function medianGain(values)
  if #values == 0 then return 0.7 end
  table.sort(values)
  if #values % 2 == 0 then
    return (values[#values / 2] + values[#values / 2 + 1]) / 2
  end
  return values[(#values + 1) / 2]
end

-- Side engines have a fixed master gain; scale them per song so dense harmony
-- and drum tracks do not bury the lead.  Slot 1 of each spec is lead-like.
local function trackGain(notes, dominant, slot, lastTick)
  local values = {}
  for _, note in ipairs(notes) do values[#values + 1] = note.gain end
  local gain = medianGain(values)
  if dominant == 4 then gain = gain * 0.75
  elseif slot > 1 then gain = gain * 0.85 end
  if #notes > 0 and #notes / math.max(1, lastTick) > 0.02 then
    gain = gain * 0.9
  end
  return math.max(0.35, math.min(1, gain))
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

-- Full ADSR approximation.  MP2K has no direct GB equivalent; attack/decay/
-- sustain choose the square envelope and duty.  0xCD overrides win over the
-- voicegroup tone.  Kept public for focused converter tests.
function M.envelopeFor(note, duty)
  local ov = note.toneOverrides or {}
  local tone = note.tone or {}
  local value = function(name)
    return ov[name] or tone[name]
  end
  -- Seq.trackVolume gives ~vel*volume/33025 mono gain.  GB volume steps are
  -- roughly 1.5 dB, so map gain through sqrt instead of a linear product;
  -- the linear form crushed quiet tracks into buckets 0-2.
  -- Sparse wave melodies carry a small boost; full pulse backing needs none.
  local gain = math.max(0, math.min(1,
    (note.vel or 100) / 127 * (note.volume or 100) / 255 *
    math.max(1, tonumber(note.gainScale) or 1)))
  local volume = math.max(0, math.min(15,
    math.floor(math.sqrt(gain) * 15 + 0.5)))
  local attack = tonumber(value("attack")) or 0
  local decay = tonumber(value("decay")) or 0
  local sustain = tonumber(value("sustain")) or 15
  local fade, resolvedDuty = 0, duty or 2
  if note.drumPreset then
    fade = note.drumPreset.fade or 0
    resolvedDuty = note.drumPreset.duty or resolvedDuty
  elseif sustain < 8 or decay >= 10 then
    -- Pluck/percussion: steep decay, thin duty for bite.
    fade, resolvedDuty = 5, 1
  elseif sustain < 12 then
    fade, resolvedDuty = 3, 2
  elseif attack >= 4 then
    -- Slow attack cannot be expressed as a GB attack ramp; a swell (negative
    -- fade) with wide duty is the closest available brightness.
    fade, resolvedDuty = -2, 3
  elseif attack <= 1 and sustain >= 12 and decay <= 4 then
    -- Slow strings/brass: slight swell, 50% duty.
    fade, resolvedDuty = -1, 3
  elseif sustain >= 13 then
    fade, resolvedDuty = -1, 3
  elseif decay > 0 then
    fade = 1
  end
  return volume, math.max(-7, math.min(7, fade)), resolvedDuty
end

-- Pick a GB speed/length pair that reproduces an M4A gate exactly.  Rounding
-- each note to ceil(gate/16) loses up to 15 ticks per note, which drifts
-- against the other channels and the parent base song.
function M.noteTiming(gate)
  local ticks = math.max(1, math.floor(gate + 0.5))
  local bestSpeed, bestLength, bestError = 1, 1, math.huge
  for speed = 1, 15 do
    -- Never round up: a note longer than its gate cannot be shortened by the
    -- following rest, so the error would accumulate across channels.
    local rounded = math.max(1, math.min(16, math.floor(ticks / speed)))
    local error = ticks - rounded * speed
    if error < bestError then
      bestSpeed, bestLength, bestError = speed, rounded, error
    end
    if error == 0 then break end
  end
  return bestSpeed, bestLength
end

local function emitNote(program, note, hw, kind, duty, waveIndex, withNotetype)
  local tempo = math.max(1, note.tempo or 150)
  local speed, length = note.timingSpeed, note.timingLength
  if not speed then speed, length = M.noteTiming(note.gate) end
  local volume, fade, duty = M.envelopeFor(note, duty)
  local key = math.max(12, math.min(119, math.floor(note.key or 60)))
  local pitch, octave = key % 12, math.floor(key / 12) - 1
  if hw == 4 then
    if withNotetype ~= false then
      program[#program + 1] = { notetype = { speed = speed, volume = volume } }
    end
    local drum = note.drumPreset and note.drumPreset.id
      or ((note.rawKey or key) % 4) + 1
    local remaining = length
    while remaining > 0 do
      local chunk = math.min(remaining, 16)
      program[#program + 1] = { drum = drum, len = chunk }
      remaining = remaining - chunk
    end
    return
  end
  if hw == 3 then
    if withNotetype ~= false then
      -- ChipSynth wave level 3 is quarter amplitude.  Fixed level 3 made
      -- every wave instrument inaudible next to the pulse tracks.
      -- Wave level 2 is half amplitude; start full one step earlier so low
      -- M4A melody volumes stay audible beside full-level pulse backing.
      local waveLevel = volume >= 7 and 1 or (volume >= 4 and 2 or 3)
      if note.isLead then waveLevel = 1 end
      program[#program + 1] = {
        notetype = { speed = speed, waveLevel = waveLevel, waveInstrument = waveIndex or 0 },
      }
    end
    -- ChipSynth's wave channel sounds an octave below the pulse register.
    pitch = key % 12
    octave = math.floor(key / 12)
  elseif withNotetype ~= false then
    program[#program + 1] = { notetype = { speed = speed, volume = volume, fade = fade } }
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

-- Route each note to the closest GB hardware instead of locking a whole track
-- to one duty.  When no compatible channel is free, delay it to the earliest
-- one rather than letting two programs write past the same timeline position.
local function allocateHw(kind, start, gate, busyUntil)
  local order
  if kind == 4 then order = { 4, 3, 1, 2 }
  elseif kind == 3 then order = { 3, 1, 2, 4 }
  else order = { 1, 2, 3, 4 } end
  local best, bestUntil
  for _, hw in ipairs(order) do
    local untilTick = busyUntil[hw] or 0
    if untilTick <= start then
      busyUntil[hw] = start + gate
      return hw, start
    end
    if not bestUntil or untilTick < bestUntil then
      best, bestUntil = hw, untilTick
    end
  end
  busyUntil[best] = bestUntil + gate
  return best, bestUntil
end

function M.buildSpecs(song, voicegroups, info)
  if type(song) ~= "table" or not song.tracks or song.tracks < 1 then return nil end
  -- FRLG song blobs store a ROM pointer in `voicegroup`; the playable cache
  -- index carries the real voicegroup number.  Using the pointer misses every
  -- tone, collapsing all instruments to one duty and one envelope.
  local vgId = (info and info.voicegroupId) or song.voicegroup
  local decoded = {}
  for i = 1, song.tracks do
    decoded[i] = M.decodeTrack(song.trackData and song.trackData[i] or "")
  end
  local lastTick, globalLoopTick, hasLoop = 1, 0, false
  local tempoByTick = {}
  for _, track in ipairs(decoded) do
    local ticks = track.ticks or 0
    for _, event in ipairs(track.events) do
      if event.kind == "note" then
        ticks = math.max(ticks, event.tick + (event.gate or 1))
      elseif event.kind == "tempo" then
        local tick = event.tick or 0
        local current = tempoByTick[tick]
        if not current or tick == 0 then tempoByTick[tick] = event.tempo or current end
      end
    end
    lastTick = math.max(lastTick, ticks)
    if track.loopTick ~= nil then
      globalLoopTick = math.max(globalLoopTick, track.loopTick)
      hasLoop = true
    end
  end
  if lastTick < 1 then lastTick = 1 end
  if lastTick > 200000 then lastTick = 200000 end
  if not hasLoop then globalLoopTick = lastTick end

  -- Every chip engine must obey the same tempo changes and loop boundary;
  -- otherwise the extra channels drift against the base song.
  local tempoTimeline = {}
  for tick, tempo in pairs(tempoByTick) do
    tempoTimeline[#tempoTimeline + 1] = { tick = tick, tempo = tempo }
  end
  table.sort(tempoTimeline, function(a, b) return a.tick < b.tick end)
  local baseTempo = 150
  if tempoTimeline[1] and tempoTimeline[1].tick == 0 then
    baseTempo = tempoTimeline[1].tempo or baseTempo
  end

  local function analyzeTrack(track, specWaves)
    -- A new note on the same M4A track or an ENDTIE cuts the previous voice.
    -- Clamp gate to the next cut so note spacing matches the source sequence.
    local gates = {}
    local nextNoteTick
    local offTicks = {}
    for index = #track.events, 1, -1 do
      local event = track.events[index]
      if event.kind == "off" then
        offTicks[event.key] = event.tick
      elseif event.kind == "note" then
        local gate = event.gate or 1
        local cut = offTicks[event.rawKey]
        if nextNoteTick and (not cut or nextNoteTick < cut) then cut = nextNoteTick end
        if cut then gate = math.min(gate, math.max(1, cut - event.tick)) end
        gates[index] = gate
        nextNoteTick = event.tick
      end
    end
    local panSum, panCount = 0, 0
    for _, event in ipairs(track.events) do
      if event.kind == "note" then
        panSum = panSum + (event.pan or 0x40)
        panCount = panCount + 1
      end
    end
    track.pan = panCount > 0 and math.max(-1, math.min(1,
      (panSum / panCount - 0x40) / 0x80)) or 0
    local pitchEvents = {}
    for _, event in ipairs(track.events) do
      if event.kind == "pitch" then pitchEvents[#pitchEvents + 1] = event end
    end
    local notes, kinds = {}, {}
    local keySum, keyCount = 0, 0
    for index, event in ipairs(track.events) do
      if event.kind == "note" then
        local kind, duty, waveIndex, tone = toneInfo(voicegroups, vgId, event, specWaves)
        local noteKey = tonumber(event.key) or 0
        if noteKey > 0 then
          keySum = keySum + noteKey
          keyCount = keyCount + 1
        end
        event.tone = tone
        local gate = gates[index] or event.gate or 1
        -- Split at BEND/TUNE changes so pitch glides are approximated without
        -- retriggering the envelope on each tied segment.
        local boundaries = { { tick = event.tick, key = event.key } }
        for _, pitchEvent in ipairs(pitchEvents) do
          if pitchEvent.tick > event.tick and pitchEvent.tick < event.tick + gate
              and pitchEvent.key ~= boundaries[#boundaries].key then
            boundaries[#boundaries + 1] = {
              tick = pitchEvent.tick,
              key = pitchEvent.key,
            }
          end
        end
        boundaries[#boundaries + 1] = { tick = event.tick + gate }
        local segments = {}
        for part = 1, #boundaries - 1 do
          local copy = {}
          for key, value in pairs(event) do copy[key] = value end
          copy.gate = boundaries[part + 1].tick - boundaries[part].tick
          copy.key = boundaries[part].key
          copy.tick = boundaries[part].tick
          copy.timingSpeed, copy.timingLength = M.noteTiming(copy.gate)
          segments[part] = copy
        end
        notes[#notes + 1] = {
          index = index, start = event.tick, gate = gate, kind = kind,
          duty = duty, waveIndex = waveIndex, gain = noteGain(event),
          segments = segments,
        }
        kinds[kind] = (kinds[kind] or 0) + 1
      end
    end
    local dominant, best = 1, 0
    for kind, count in pairs(kinds) do
      if count > best then dominant, best = kind, count end
    end
    return {
      notes = notes, dominant = dominant,
      avgKey = keyCount > 0 and keySum / keyCount or 0,
    }
  end

  local specs = {}
  for start = 1, #decoded, 4 do
    local analyses, specWaves = {}, {}
    for i = start, math.min(start + 3, #decoded) do
      analyses[#analyses + 1] = analyzeTrack(decoded[i], specWaves)
    end
    -- Sparse high tracks are melodies.  Wave instruments win the tiebreak,
    -- but a pulse lead must still get the boost when no wave track qualifies.
    local leadIndex, leadScore
    for index, analysis in ipairs(analyses) do
      if analysis.avgKey >= 55 and #analysis.notes > 0
          and #analysis.notes <= 160 then
        local score = analysis.avgKey - #analysis.notes * 0.02
          + (analysis.dominant == 3 and 12 or 0)
        if not leadScore or score > leadScore then
          leadIndex, leadScore = index, score
        end
      end
    end
    if leadIndex then
      for _, note in ipairs(analyses[leadIndex].notes) do
        note.gainScale = 1.4
        note.isLead = true
        for _, segment in ipairs(note.segments) do
          segment.gainScale = 1.4
          segment.isLead = true
        end
      end
    end
    local actions = {}
    for _, tempo in ipairs(tempoTimeline) do
      if tempo.tick > 0 then
        actions[#actions + 1] = {
          tick = tempo.tick, all = true, order = -1, tempo = tempo.tempo,
        }
      end
    end
    for trackIndex, analysis in ipairs(analyses) do
      for _, note in ipairs(analysis.notes) do
        actions[#actions + 1] = {
          tick = note.start, all = false, trackIndex = trackIndex,
          order = note.index, note = note,
        }
      end
    end
    table.sort(actions, function(a, b)
      if a.tick ~= b.tick then return a.tick < b.tick end
      if a.all ~= b.all then return a.all == true end
      if a.trackIndex ~= b.trackIndex then
        return (a.trackIndex or 0) < (b.trackIndex or 0)
      end
      return (a.order or 0) < (b.order or 0)
    end)

    local programs, cursors, emitCursors = {}, {}, {}
    for hw = 1, 4 do programs[hw], cursors[hw], emitCursors[hw] = {}, 0, 0 end
    local function padTo(hw, tick)
      if emitCursors[hw] < tick then
        emitRest(programs[hw], tick - emitCursors[hw])
        emitCursors[hw] = tick
      end
      if cursors[hw] < tick then cursors[hw] = tick end
    end
    local busyUntil = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 }
    local loopTargets
    for _, action in ipairs(actions) do
      if not loopTargets and action.tick >= globalLoopTick then
        loopTargets = {}
        for hw = 1, 4 do
          padTo(hw, globalLoopTick)
          loopTargets[hw] = #programs[hw] + 1
        end
      end
      for hw = 1, 4 do padTo(hw, action.tick) end
      if action.all then
        for hw = 1, 4 do
          programs[hw][#programs[hw] + 1] = { tempo = gbTempo(action.tempo) }
        end
      else
        local note = action.note
        local original = note.start
        local hw, assigned = allocateHw(note.kind, original, note.gate, busyUntil)
        if assigned > original then
          local delay = assigned - original
          note.start = assigned
          for _, segment in ipairs(note.segments) do segment.tick = segment.tick + delay end
        end
        padTo(hw, assigned)
        local previousSpeed, emittedTicks
        for part, segment in ipairs(note.segments) do
          -- Later pitch segments keep the first speed unless their gate needs
          -- a different note length; re-emit notetype so elapsed time is exact.
          emitNote(programs[hw], segment, hw, note.kind, note.duty,
            note.waveIndex, part == 1 or segment.timingSpeed ~= previousSpeed)
          previousSpeed = segment.timingSpeed
          emittedTicks = (emittedTicks or 0)
            + segment.timingSpeed * segment.timingLength
        end
        emitCursors[hw] = assigned + (emittedTicks or 0)
        cursors[hw] = assigned + note.gate
      end
    end
    if not loopTargets then
      loopTargets = {}
      for hw = 1, 4 do
        padTo(hw, globalLoopTick)
        loopTargets[hw] = #programs[hw] + 1
      end
    end
    for hw = 1, 4 do
      padTo(hw, lastTick)
      programs[hw][#programs[hw] + 1] = {
        loop = { count = 0, to = loopTargets[hw] },
      }
    end

    local waves = {}
    for index, wave in ipairs(WAVES) do waves[index] = wave end
    for _, entry in ipairs(specWaves) do
      if #waves < 15 then waves[#waves + 1] = entry.wave end
    end
    local gainSum, gainCount = 0, 0
    for slot, analysis in ipairs(analyses) do
      if #analysis.notes > 0 then
        gainSum = gainSum + trackGain(analysis.notes, analysis.dominant, slot, lastTick)
        gainCount = gainCount + 1
      end
    end
    local channels = {}
    for hw = 1, 4 do channels[#channels + 1] = { hw = hw, program = programs[hw] } end
    specs[#specs + 1] = {
      tempo = gbTempo(baseTempo),
      channels = channels,
      waves = waves,
      drums = DRUMS,
      engine = 1,
      gain = gainCount > 0 and gainSum / gainCount or 1,
    }
  end
  -- Extra chips inherit the average pan of the tracks they carry, instead of
  -- a fixed left/right rotation.  Base stays centered.
  for specIndex, spec in ipairs(specs) do
    local panSum, panCount = 0, 0
    for slot = 1, 4 do
      local track = decoded[(specIndex - 1) * 4 + slot]
      if track and track.pan then
        panSum = panSum + track.pan
        panCount = panCount + 1
      end
    end
    spec.pan = specIndex == 1 and 0
      or (panCount > 0 and math.max(-1, math.min(1, panSum / panCount)) or 0)
  end
  return specs
end

local audioFile

local function luaTable(version, file)
  local bytes = audioFile(version, file)
  if type(bytes) ~= "string" then return nil end
  local chunk = load(bytes, "@gba/" .. version .. "/" .. file)
  if not chunk then return nil end
  local ok, result = pcall(chunk)
  if not ok or type(result) ~= "table" then return nil end
  return result
end

audioFile = function(version, name)
  local okCache, CacheFs = pcall(require, "src.import.CacheFs")
  if not okCache or type(CacheFs) ~= "table" or not CacheFs.readAt then return nil end
  local okVersion, GameVersion = pcall(require, "src.core.GameVersion")
  if not okVersion or type(GameVersion) ~= "table" or not GameVersion.cachePrefix then
    return nil
  end
  M.lastPath = M.lastPath or {}
  local seen = {}
  local prefixes = {}
  local prefix = GameVersion.cachePrefix(version)
  if type(prefix) == "string" and prefix ~= "" then prefixes[#prefixes + 1] = prefix end
  prefixes[#prefixes + 1] = tostring(version) .. "/"
  prefixes[#prefixes + 1] = ""
  for _, candidate in ipairs(prefixes) do
    if not seen[candidate] then
      seen[candidate] = true
      local rel = candidate .. AUDIO_ROOT .. name
      local bytes = CacheFs.readAt(rel)
      if bytes then
        M.lastPath[version .. ":" .. name] = rel
        return bytes
      end
    end
  end
  return nil
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

-- Static map injected by main.lua. Engine game3 modules are sandbox-denied on
-- Gen1/Gen2 hosts, so the map is the only reliable source there.
local songIdMap
function M.setSongIds(map)
  if type(map) == "table" then songIdMap = map end
end

local function songIds(version)
  if songIdMap then
    local map = songIdMap[version]
    if type(map) == "table" then return map end
  end
  local ok, Song = pcall(require, "src.core.game3.song_ids")
  if not ok or type(Song) ~= "table" or not Song.forVersion then return {} end
  local okSongs, songs = pcall(Song.forVersion, version)
  if not okSongs or type(songs) ~= "table" then return {} end
  return songs
end

-- FRLG index.lua stores MUS_ jingles as bgm/fanfare/se. All carry playable
-- M4A track data; only MUS_NONE (or songs with no tracks) should be skipped.
local MUSIC_KINDS = { bgm = true, fanfare = true, se = true }

local function usableSong(info)
  return info ~= nil and MUSIC_KINDS[info.kind] == true
    and (info.tracks or 0) > 0
end
M.isPlayableSong = usableSong

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
      if usableSong(info) then
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
  return usableSong(info)
end

function M.convert(version, label)
  local function fail(reason)
    M.lastError = string.format("%s/%s: %s", tostring(version), tostring(label), reason)
    return nil
  end
  local data = dataFor(version)
  if not data then return fail("no audio index") end
  local id = songIds(version)[label]
  if not id then return fail("unknown song id") end
  local songs = tableValue(data.index, "songs")
  local info = songs and (tableValue(songs, id) or tableValue(songs, tostring(id)))
  if not usableSong(info) then return fail("no playable track data") end
  local blob = audioFile(version, "songs/" .. tostring(id) .. ".bin")
  if type(blob) ~= "string" then return fail("missing song bin") end
  local okParse, song = pcall(parseSongBin, blob)
  if not okParse or type(song) ~= "table" then return fail("song parse failed") end
  local specs = M.buildSpecs(song, data.voicegroups, info)
  if not specs or #specs == 0 then return fail("no chip specs") end
  local def = specs[1]
  def.generation = 1
  def.g3Mix = true
  def.converter = CONVERTER_VERSION
  local extra = {}
  for i = 2, #specs do
    local spec = specs[i]
    spec.generation = 1
    spec.g3Mix = true
    extra["g3_" .. tostring(i)] = spec
  end
  return { def = def, extra = extra, tracks = song.tracks }
end

return M
