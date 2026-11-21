-- Music Improvement: turn a source Game Boy chip arrangement into an
-- improved one, re-emitted through ChipAsm as a fresh chip program.
--
-- Source shape: a ChipAsm song spec (tempo + channels with note-event
-- programs).  Improvement shape: the same spec with upgraded channel
-- instruments and algorithmically expanded harmony channels (chords the
-- lead's note stream implies, voiced on a new quiet channel).  The improved
-- spec is what ChipAsm assembles, so improved music keeps flowing through
-- the engine's own synthesis (ChipAudio/ChipSynth) -- no FluidSynth, no
-- external samples, no second audio backend.

local NOTES = {
  C = 0, ["C#"] = 1, Db = 1, D = 2, ["D#"] = 3, Eb = 3, E = 4,
  F = 5, ["F#"] = 6, Gb = 6, G = 7, ["G#"] = 8, Ab = 8, A = 9,
  ["A#"] = 10, Bb = 10, B = 11,
}

-- event keys in ChipAsm's fixed command order (first hit wins)
local EVENT_KEYS = {
  "label", "note", "pitch", "rest", "drum", "notetype", "octave",
  "perfectPitch", "vibrato", "slide", "duty", "dutyPattern", "tempo", "pan",
  "executeMusic", "call", "ret", "loop", "squareNote", "noiseNote", "pitchSweep",
}

local HARMONY_HW = 3
local HARMONY_WAVE_LEVEL = 2 -- lower volume than the lead voicing
local HARMONY_WAVE_INSTRUMENT = 1

local MAJOR_SCALE = { 0, 2, 4, 5, 7, 9, 11 }
local MINOR_SCALE = { 0, 2, 3, 5, 7, 8, 10 }
local MODE_SCALES = {
  major = MAJOR_SCALE,
  minor = MINOR_SCALE,
  mixolydian = { 0, 2, 4, 5, 7, 9, 10 },
  dorian = { 0, 2, 3, 5, 7, 9, 10 },
  phrygian = { 0, 1, 3, 5, 7, 8, 10 },
  lydian = { 0, 2, 4, 6, 7, 9, 11 },
}
local MAJOR_PROFILE = { 6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88 }
local MINOR_PROFILE = { 6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17 }

local function cloneEvent(event)
  local copy = {}
  for key, value in pairs(event) do
    copy[key] = type(value) == "table" and cloneEvent(value) or value
  end
  return copy
end

local function cloneSpec(source)
  local out = { tempo = source.tempo }
  local channels = {}
  for _, channel in ipairs(source.channels or {}) do
    local spec = { hw = channel.hw }
    local program = {}
    for _, event in ipairs(channel.program or {}) do
      program[#program + 1] = cloneEvent(event)
    end
    if #program > 0 then spec.program = program end
    if channel.subroutines then spec.subroutines = channel.subroutines end
    channels[#channels + 1] = spec
  end
  out.channels = channels
  if source.waves then out.waves = source.waves end
  if source.drums then out.drums = source.drums end
  if source.engine then out.engine = source.engine end
  return out
end

local function eventKind(event)
  for _, key in ipairs(EVENT_KEYS) do
    if event[key] ~= nil then return key end
  end
  return nil
end

local function notePitchClass(event)
  if event.pitch ~= nil then return event.pitch % 12 end
  local name = event.note
  if type(name) ~= "string" then return nil end
  return NOTES[name]
end

local function eventLength(event)
  local len = tonumber(event.len)
  if len and len > 0 then return len end
  if type(event.rest) == "number" and event.rest > 0 then return event.rest end
  if type(event.drum) == "number" then return tonumber(event.len) or 1 end
  if type(event.noiseNote) == "table" then
    return tonumber(event.noiseNote.len) or 1
  end
  if type(event.squareNote) == "table" then
    return tonumber(event.squareNote.len) or 1
  end
  return 1
end

local function profileScore(hist, profile, tonic)
  local score = 0
  for i = 0, 11 do
    score = score + (hist[((i - tonic) % 12) + 1] or 0) * profile[i + 1]
  end
  return score
end

local function scaleIndexFor(pc, key)
  local rel = (pc - key.tonic) % 12
  local bestIdx, bestDist = 1, 99
  for i, deg in ipairs(key.scale) do
    local dist = math.abs(rel - deg)
    if dist > 6 then dist = 12 - dist end
    if dist < bestDist then bestDist, bestIdx = dist, i end
  end
  return bestIdx
end

local function diatonicSemitoneDelta(sourcePc, key, degreeOffset)
  if not key then return degreeOffset >= 0 and 4 or -3 end
  local idx = scaleIndexFor(sourcePc, key)
  local scale = key.scale
  local targetIdx = ((idx - 1 + degreeOffset) % #scale) + 1
  local octShift = math.floor((idx - 1 + degreeOffset) / #scale)
  local sourceDeg = scale[idx]
  local targetDeg = scale[targetIdx]
  return (targetDeg - sourceDeg) + octShift * 12
end

local TICKS_PER_SECOND = 15360

local function settingsOf(settings)
  settings = type(settings) == "table" and settings or {}
  local function bool(key, alt)
    if settings[key] ~= nil then return settings[key] ~= false end
    if alt and settings[alt] ~= nil then return settings[alt] ~= false end
    return true
  end
  return {
    enabled = bool("enabled"),
    extraVolume = tonumber(settings.extraVolume or settings.extra_volume) or 1.0,
    keyAware = settings.keyAware ~= false and settings.key_aware ~= false,
    dynamicIntensity = settings.dynamicIntensity ~= false and settings.dynamic_intensity ~= false,
    profile = type(settings.profile) == "table" and settings.profile or nil,
  }
end

-- A researched song profile supplies the key directly. Only key/scale maths
-- is steered here; the source song itself is never transposed.
local function profileKey(profile)
  if type(profile) ~= "table" or type(profile.key) ~= "table" then return nil end
  local key = profile.key
  local tonic = tonumber(key.tonic)
  if not tonic or tonic < 0 or tonic > 11 or tonic ~= math.floor(tonic) then
    return nil
  end
  local scale = key.scale
  if type(scale) ~= "table" or #scale < 3 then
    scale = MODE_SCALES[key.mode] or MAJOR_SCALE
  end
  local checked = {}
  for _, degree in ipairs(scale) do
    local value = tonumber(degree)
    if not value or value < 0 or value > 11 or value ~= math.floor(value) then
      return nil
    end
    checked[#checked + 1] = value
  end
  return {
    tonic = tonic,
    mode = key.mode or "major",
    scale = checked,
    confidence = 1,
    source = key.source or profile.source or "profile",
  }
end

local function buildIntensityEnvelope(spec)
  local tempo = spec.tempo or 0x100
  local windowSec = 0.75
  local function programWindows(program, baseTempo)
    local windows = {}
    local t, speed, curTempo = 0, 12, baseTempo or tempo
    local w = 0
    for _, event in ipairs(program or {}) do
      local kind = eventKind(event)
      if kind == "tempo" and type(event.tempo) == "number" then
        curTempo = event.tempo
      elseif kind == "notetype" and type(event.notetype) == "table" then
        speed = tonumber(event.notetype.speed) or speed
      elseif kind == "note" or kind == "pitch" then
        local len = tonumber(event.len) or 1
        local dur = (len * speed * curTempo) / TICKS_PER_SECOND
        local idx = math.floor(t / windowSec) + 1
        windows[idx] = (windows[idx] or 0) + 1
        t = t + dur
        if idx > w then w = idx end
      elseif kind == "rest" then
        local len = tonumber(event.rest) or 1
        t = t + (len * speed * curTempo) / TICKS_PER_SECOND
      elseif kind == "noiseNote" and type(event.noiseNote) == "table" then
        local len = tonumber(event.noiseNote.len) or 1
        t = t + (len * speed * curTempo) / TICKS_PER_SECOND
      elseif kind == "squareNote" and type(event.squareNote) == "table" then
        local len = tonumber(event.squareNote.len) or 1
        t = t + (len * speed * curTempo) / TICKS_PER_SECOND
      elseif kind == "drum" then
        local len = tonumber(event.len) or 1
        t = t + (len * speed * curTempo) / TICKS_PER_SECOND
      end
    end
    return windows, math.max(w, math.floor(t / windowSec) + 1), t
  end
  local combined, totalWindows, maxT = {}, 0, 0
  for _, channel in ipairs(spec.channels or {}) do
    if channel.hw ~= 4 and channel.program then
      local w, n, t = programWindows(channel.program, tempo)
      if n > totalWindows then totalWindows = n end
      if t > maxT then maxT = t end
      for i = 1, n do combined[i] = (combined[i] or 0) + (w[i] or 0) end
    end
  end
  if totalWindows <= 0 then
    return { { t = 0, g = 1.0 } }, 1.0
  end
  local smoothed, maxD = {}, 0
  for i = 1, totalWindows do
    local sum, count = 0, 0
    for j = math.max(1, i - 1), math.min(totalWindows, i + 1) do
      sum = sum + (combined[j] or 0)
      count = count + 1
    end
    local v = count > 0 and (sum / count) or 0
    smoothed[i] = v
    if v > maxD then maxD = v end
  end
  local envelope = {}
  local peak = 0
  for i = 1, totalWindows do
    local norm = maxD > 0 and (smoothed[i] / maxD) or 0
    local g
    if norm < 0.22 then
      g = 0.35
    elseif norm < 0.55 then
      g = 0.65
    else
      g = 1.0
    end
    envelope[#envelope + 1] = { t = (i - 1) * windowSec, g = g }
    if g > peak then peak = g end
  end
  return envelope, peak
end

local function sampleEnvelope(envelope, t)
  if type(envelope) ~= "table" or #envelope == 0 then return 1.0 end
  local g = envelope[1].g or 1.0
  for i = 1, #envelope do
    local e = envelope[i]
    if (e.t or 0) <= t then g = e.g or g else break end
  end
  return g
end

-- Improvement pass, settings-gated. Returns a clone (unchanged) when disabled.
local function improve(source, settings)
  settings = settingsOf(settings)
  local improved = cloneSpec(source)
  if not settings.enabled then return improved end
  -- G3 Mix already balances its tracks from the M4A volume bytes; lifting hw1
  -- to a floor of 12 buries the converted melody.
  local liftHw1 = source.g3Mix ~= true

  for _, channel in ipairs(improved.channels or {}) do
    if channel.program then
      for _, event in ipairs(channel.program) do
        if liftHw1 and channel.hw == 1 and event.duty ~= nil then
          event.duty = math.max(event.duty, 2)
        end
        -- decoded engine events carry volume/fade at the top level (the
        -- interpreter folds the notetype opcode into the tone event); the
        -- authored DSL carries them under notetype -- accept both shapes.
        if liftHw1 and channel.hw == 1 and event.notetype == nil and (event.volume or event.fade) then
          event.notetype = {
            speed = (event.notetype and event.notetype.speed) or 12,
            volume = event.volume or 12,
            fade = event.fade or 0,
          }
        end
        if liftHw1 and channel.hw == 1 and event.notetype and event.notetype.volume then
          event.notetype.volume = math.max(event.notetype.volume, 12)
        end
      end
    end
  end

  return improved
end

local NOTES_REV = {}
for name, pc in pairs(NOTES) do
  if not NOTES_REV[pc] then NOTES_REV[pc] = name end
end

local function resolveInterval(interval, pc, key)
  if type(interval) == "table" and interval.diatonic then
    local delta = diatonicSemitoneDelta(pc, key, interval.degree or 2)
    local shift = tonumber(interval.octaveShift) or 0
    return delta + shift * 12
  end
  return tonumber(interval) or 0
end

local function transposeProgram(program, interval, key)
  local out = {}
  local indexMap = {}
  local loopTargets = {}
  local octave = 4
  for index, event in ipairs(program or {}) do
    indexMap[index] = #out + 1
    local kind = eventKind(event)
    if kind == "octave" then
      octave = event.octave or octave
      out[#out+1] = { octave = octave }
    elseif kind == "note" or kind == "pitch" then
      local pc = notePitchClass(event)
      if pc == nil then
        out[#out+1] = cloneEvent(event)
      else
        local evOct = event.octave or octave
        local semitones = resolveInterval(interval, pc, key)
        local absolute = (evOct - 1) * 12 + pc + semitones
        local newOct = math.floor(absolute / 12) + 1
        local newPc = absolute % 12
        if newOct < 1 then newOct = 1 end
        if newOct > 8 then newOct = 8 end
        if newOct ~= octave then
          out[#out+1] = { octave = newOct }
          octave = newOct
        end
        local clone = cloneEvent(event)
        clone.note = nil
        clone.pitch = newPc
        clone.octave = nil
        out[#out+1] = clone
      end
    else
      local clone = cloneEvent(event)
      out[#out+1] = clone
      if clone.loop and type(clone.loop.to) == "number" then
        loopTargets[#loopTargets + 1] = {
          loop = clone.loop,
          target = clone.loop.to,
        }
      end
    end
  end
  for _, target in ipairs(loopTargets) do
    target.loop.to = indexMap[target.target] or target.target
  end
  return out
end

local function prependProgramEvent(program, event)
  for _, item in ipairs(program) do
    if item.loop and type(item.loop.to) == "number" then
      item.loop.to = item.loop.to + 1
    end
  end
  table.insert(program, 1, event)
end

local function leadChannel(spec)
  for _, channel in ipairs(spec.channels or {}) do
    if channel.hw == 1 and channel.program then return channel end
  end
  if spec.channels and spec.channels[1] and spec.channels[1].program then
    return spec.channels[1]
  end
  return nil
end

local function leadProgram(spec)
  local ch = leadChannel(spec)
  if ch then return ch.program end
  return nil
end

local function leadSubroutines(spec)
  local ch = leadChannel(spec)
  if ch and type(ch.subroutines) == "table" then return ch.subroutines end
  return nil
end

local function bassProgram(spec)
  for _, channel in ipairs(spec.channels or {}) do
    if channel.hw == 2 and channel.program then return channel.program end
  end
  for _, channel in ipairs(spec.channels or {}) do
    if channel.hw == 3 and channel.program then return channel.program end
  end
  if spec.channels and spec.channels[2] and spec.channels[2].program then
    return spec.channels[2].program
  end
  return leadProgram(spec)
end

local function detectKey(spec)
  local hist = {}
  for i = 1, 12 do hist[i] = 0 end
  local total, distinct = 0, 0
  local function scanProgram(program)
    local octave = 4
    for _, event in ipairs(program or {}) do
      local kind = eventKind(event)
      if kind == "octave" then
        octave = event.octave or octave
      elseif kind == "note" or kind == "pitch" then
        local pc = notePitchClass(event)
        if pc ~= nil then
          local w = eventLength(event)
          hist[pc + 1] = hist[pc + 1] + w
          total = total + w
        end
        if event.octave then octave = event.octave end
      end
    end
  end
  local lead = leadProgram(spec)
  if lead then
    scanProgram(lead)
  else
    for _, channel in ipairs(spec.channels or {}) do
      if channel.hw ~= 4 and channel.program then scanProgram(channel.program) end
    end
  end
  if total <= 0 then return nil end
  for i = 1, 12 do if hist[i] > 0 then distinct = distinct + 1 end end
  if distinct < 3 then return nil end
  local best, second, bestMode, bestTonic = -1 / 0, -1 / 0, nil, nil
  for tonic = 0, 11 do
    local maj = profileScore(hist, MAJOR_PROFILE, tonic)
    local min = profileScore(hist, MINOR_PROFILE, tonic)
    local score, mode = maj, "major"
    if min > maj then score, mode = min, "minor" end
    if score > best then
      second, best, bestMode, bestTonic = best, score, mode, tonic
    elseif score > second then
      second = score
    end
  end
  local confidence = best > 0 and (best - second) / best or 0
  if confidence < 0.03 then return nil end
  return {
    tonic = bestTonic,
    mode = bestMode,
    scale = (bestMode == "minor") and MINOR_SCALE or MAJOR_SCALE,
    confidence = confidence,
  }
end

local function voiceSpec(program, interval, volume, duty, subroutines, key)
  local subs = nil
  if type(subroutines) == "table" then
    subs = {}
    for name, sub in pairs(subroutines) do
      subs[name] = transposeProgram(sub, interval, key)
    end
  end
  return {
    hw = 1,
    subroutines = subs,
    program = (function()
      local base = transposeProgram(program, interval, key)
      -- ensure quiet instrument: inject notetype at start if missing
      local hasNoteType = false
      for _, ev in ipairs(base) do
        if ev.notetype then hasNoteType = true break end
      end
      if not hasNoteType then
        prependProgramEvent(base, {
          notetype = { speed = 12, volume = volume, fade = 1 },
        })
      else
        for _, ev in ipairs(base) do
          if ev.notetype and ev.notetype.volume then
            ev.notetype.volume = math.min(ev.notetype.volume, volume)
          end
        end
      end
      -- duty
      local hasDuty = false
      for _, ev in ipairs(base) do
        if ev.duty ~= nil then hasDuty = true break end
      end
      if not hasDuty then
        prependProgramEvent(base, { duty = duty or 1 })
      end
      return base
    end)(),
  }
end

-- A side sourced from a non-lead channel carries no tempo commands; its own
-- ChipSynth engine would stay at the header tempo forever. Mirror the lead
-- tempo timeline on a silent channel so the engine's shared tempo register
-- follows the same changes as the base song (including after a loop).
local function tempoFollowerChannel(leadProgram)
  local hasTempo = false
  for _, event in ipairs(leadProgram or {}) do
    if event.tempo ~= nil then hasTempo = true break end
  end
  if not hasTempo then return nil end
  local program = {}
  for _, event in ipairs(leadProgram or {}) do
    if event.tempo ~= nil then
      program[#program + 1] = { tempo = event.tempo }
    elseif event.loop and type(event.loop.to) == "number" then
      program[#program + 1] = cloneEvent(event)
    elseif event.notetype ~= nil then
      program[#program + 1] = cloneEvent(event)
    else
      program[#program + 1] = { rest = eventLength(event) }
    end
  end
  return { hw = 2, program = program }
end

local function extra(source, settings)
  settings = settingsOf(settings)
  if not settings.enabled then return nil end
  local spec = source
  -- if source is already a chip song def, skip
  if type(spec) == "table" and spec.chip then return nil end
  local program = leadProgram(spec)
  if not program then return nil end
  local subs = leadSubroutines(spec)
  local volume = math.max(1, math.min(12, math.floor((settings.extraVolume or 1.0) * 12)))
  local tempo = spec.tempo or 0x100
  local fast = tempo < 224
  local profile = settings.profile
  local key = nil
  if settings.keyAware ~= false then
    key = profileKey(profile) or detectKey(spec)
  end
  local dyn = settings.dynamicIntensity
  if profile and profile.dynamicIntensity ~= nil then
    dyn = profile.dynamicIntensity ~= false
  end
  local envelope = nil
  if dyn then envelope = buildIntensityEnvelope(spec) end
  local out = {}
  local function sideEnvelope(base, factor)
    if not envelope then return nil end
    local e = {}
    for i, p in ipairs(envelope) do
      local g = (p.g or 1.0) * (factor or 1.0)
      if base == "center" then
        -- bring center in only for active/climactic windows
        if (p.g or 1.0) < 0.55 then g = 0 end
      elseif base == "bassDown" then
        g = math.max(0.25, (p.g or 1.0) * (factor or 1.0))
      end
      e[i] = { t = p.t, g = g }
    end
    return e
  end

  local bass = bassProgram(spec)
  local defaults = {
    left = { degree = 2, duty = 1, gain = 1.0 },
    right = { degree = -3, duty = 1, gain = 0.95 },
    center = { degree = 5, duty = 2, gain = 0.9 },
    bassDown = { semitones = -12, duty = 1, gain = 0.85, program = bass },
  }
  local profileSides = type(profile) == "table" and type(profile.sides) == "table"
    and profile.sides or nil

  -- With no detected key, preserve the original octave/fifth fallbacks.
  local function fallbackInterval(degree)
    if degree < 0 then return -12 end
    if degree > 3 then return 7 end
    return 12
  end

  local function addSide(name, base)
    if name == "bassDown" and not base.program then return end
    local override = profileSides and profileSides[name] or nil
    if override and override.enabled == false then return end
    if name == "center" and fast and not (override and override.enabled == true) then
      return
    end

    local interval
    local voiceKey = name == "bassDown" and nil or key
    local shift = override and tonumber(override.octaveShift) or 0
    if override and override.semitones ~= nil then
      interval = (tonumber(override.semitones) or 0) + shift * 12
      voiceKey = nil
    elseif override and override.degree ~= nil then
      local degree = tonumber(override.degree) or 0
      if key then
        interval = { diatonic = true, degree = degree }
        if shift ~= 0 then interval.octaveShift = shift end
        voiceKey = key
      else
        interval = fallbackInterval(degree) + shift * 12
      end
    elseif base.semitones ~= nil then
      interval = base.semitones + shift * 12
    elseif key then
      interval = { diatonic = true, degree = base.degree }
      if shift ~= 0 then interval.octaveShift = shift end
    else
      interval = fallbackInterval(base.degree) + shift * 12
    end

    local duty = base.duty
    if override and override.duty ~= nil then duty = tonumber(override.duty) or duty end
    local gainFactor = override and tonumber(override.gain) or 1
    local voiceVolume = volume
    if name == "bassDown" then
      voiceVolume = math.max(1, math.min(12, math.floor(volume * 0.8 * gainFactor)))
    elseif gainFactor ~= 1 then
      voiceVolume = math.max(1, math.min(12, math.floor(volume * gainFactor)))
    end
    local envFactor = (base.gain or 1) * gainFactor

    local prog = base.program or program
    local sub = subs
    if name == "bassDown" then sub = nil end
    local s = { tempo = tempo,
      channels = { voiceSpec(prog, interval, voiceVolume, duty, sub, voiceKey) } }
    if prog ~= program then
      local follower = tempoFollowerChannel(program)
      if follower and #follower.program > 0 then
        -- Channel order matters: the follower must set engine.tempo before
        -- the voice channel reads it for this step.
        table.insert(s.channels, 1, follower)
      end
    end
    local env = sideEnvelope(name, envFactor)
    if env then s.intensityEnvelope = env end
    out[name] = s
  end

  addSide("left", defaults.left)
  addSide("right", defaults.right)
  addSide("center", defaults.center)
  addSide("bassDown", defaults.bassDown)
  return out
end

return {
  improve = improve,
  extra = extra,
  detectKey = detectKey,
  diatonicSemitoneDelta = diatonicSemitoneDelta,
  buildIntensityEnvelope = buildIntensityEnvelope,
  sampleEnvelope = sampleEnvelope,
}
