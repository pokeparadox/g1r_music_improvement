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
  }
end

-- Improvement pass, settings-gated. Returns a clone (unchanged) when disabled.
local function improve(source, settings)
  settings = settingsOf(settings)
  local improved = cloneSpec(source)
  if not settings.enabled then return improved end

  for _, channel in ipairs(improved.channels or {}) do
    if channel.program then
      for _, event in ipairs(channel.program) do
        if channel.hw == 1 and event.duty ~= nil then
          event.duty = math.max(event.duty, 2)
        end
        -- decoded engine events carry volume/fade at the top level (the
        -- interpreter folds the notetype opcode into the tone event); the
        -- authored DSL carries them under notetype -- accept both shapes.
        if channel.hw == 1 and event.notetype == nil and (event.volume or event.fade) then
          event.notetype = {
            speed = (event.notetype and event.notetype.speed) or 12,
            volume = event.volume or 12,
            fade = event.fade or 0,
          }
        end
        if channel.hw == 1 and event.notetype and event.notetype.volume then
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

local function transposeProgram(program, semitones)
  local out = {}
  local octave = 4
  for _, event in ipairs(program or {}) do
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
        local absolute = (evOct - 1) * 12 + pc + (semitones or 0)
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
      out[#out+1] = cloneEvent(event)
    end
  end
  return out
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

local function voiceSpec(program, semitones, volume, duty, subroutines)
  local subs = nil
  if type(subroutines) == "table" then
    subs = {}
    for name, sub in pairs(subroutines) do
      subs[name] = transposeProgram(sub, semitones)
    end
  end
  return {
    hw = 1,
    subroutines = subs,
    program = (function()
      local base = transposeProgram(program, semitones)
      -- ensure quiet instrument: inject notetype at start if missing
      local hasNoteType = false
      for _, ev in ipairs(base) do
        if ev.notetype then hasNoteType = true break end
      end
      if not hasNoteType then
        table.insert(base, 1, { notetype = { speed = 12, volume = volume, fade = 1 } })
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
        table.insert(base, 1, { duty = duty or 1 })
      end
      return base
    end)(),
  }
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
  local out = {}
  local function add(side, interval, duty)
    out[side] = { tempo = tempo, channels = { voiceSpec(program, interval, volume, duty, subs) } }
  end
  add("left", 12, 1)
  add("right", -12, 1)
  -- Add the fifth only for non-fast songs; this keeps fast arrangements clean.
  if not fast then
    add("center", 7, 2)
  end
  local bass = bassProgram(spec)
  if bass then
    local bassVolume = math.max(1, math.floor(volume * 0.8))
    -- bassDown uses a helper with bass program instead of lead
    out.bassDown = { tempo = tempo,
      channels = { (function()
        local base = transposeProgram(bass, -12)
        local hasNoteType = false
        for _, ev in ipairs(base) do if ev.notetype then hasNoteType = true break end end
        if not hasNoteType then
          table.insert(base, 1, { notetype = { speed = 12, volume = bassVolume, fade = 1 } })
        else
          for _, ev in ipairs(base) do
            if ev.notetype and ev.notetype.volume then
              ev.notetype.volume = math.min(ev.notetype.volume, bassVolume)
            end
          end
        end
        local hasDuty = false
        for _, ev in ipairs(base) do if ev.duty ~= nil then hasDuty = true break end end
        if not hasDuty then table.insert(base, 1, { duty = 1 }) end
        return { hw = 1, program = base }
      end)() } }
  end
  return out
end

return { improve = improve, extra = extra }
