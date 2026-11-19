-- Gen3 host bridge: Game3 owns GBA playback through Audio.playSong, not the
-- Gen1/2 music.* hooks.  Keep native M4A untouched; when a cached Gen1/2 chip
-- variant exists, swap the BGM bus to ChipAudio for that song.

local Audio = require("src.core.game3.audio")
local Song = require("src.core.game3.song_ids")
local ChipAudio = require("src.core.ChipAudio")
local GameVersion = require("src.core.GameVersion")

local M = {}

function M.install(deps)
  if M.installed then return end
  M.installed = true

  local version = GameVersion.get()
  local originalPlay = Audio.playSong
  local originalPause = Audio.pauseBgm
  local originalResume = Audio.resumeBgm
  local originalStopped = Audio.isBgmStopped
  local originalUpdate = Audio.update
  local originalStopAll = Audio.stopAll
  local chip = { id = nil, nativeId = nil, record = nil, paused = false }
  local pending = nil   -- { nativeId, id, settings, candidates }
  local lastPick = {}

  local function nativeLabel(id)
    local ok, name = pcall(Song.nameOf, id, version)
    if ok and name then return name end
    return tostring(id)
  end

  -- Unconditional bus teardown.  Do not early-return on chip.id: a transition
  -- from native to native, chip to chip, or either direction must leave exactly
  -- one bus running.
  local function resetBus()
    pcall(ChipAudio.holdMusic, false)
    pcall(ChipAudio.stopMusic)
    pcall(deps.extraAudio.stop)
    pcall(originalPlay, nil)
    if Audio._outCh and Audio._outCh.clear then
      pcall(Audio._outCh.clear, Audio._outCh)
    end
    Audio._bgmEpoch = (Audio._bgmEpoch or 0) + 1
    Audio._bgmPaused = false
    Audio._fanfareActive = false
    Audio._fanfareFrames = 0
    Audio._fanfarePending = nil
    Audio._fanfareRestore = nil
    Audio._fanfareDeferred = nil
    Audio._fadeOut, Audio._fadeIn = nil, nil
    Audio._currentSong = nil
    chip.id, chip.nativeId, chip.record, chip.paused = nil, nil, nil, false
  end

  local function recordsFor(nativeId, settings)
    local records = {}
    for _, candidate in ipairs(deps.candidatesFor(nativeId, settings)) do
      for _, enabled in ipairs(deps.enabledListFor and deps.enabledListFor()
          or { true, false }) do
        if not candidate.mix or enabled then
          local rec = deps.loadVariant(nativeId, candidate, { enabled = enabled })
          if rec then records[#records + 1] = rec end
        end
      end
    end
    return records
  end

  local function startChip(id, nativeId, record)
    local mapSong = Audio._mapSong
    local info = Audio.songInfo(id) or {}
    Audio._mapSong = mapSong or id
    Audio._currentSong = {
      id = id,
      duration = info.duration,
      loop = info.loop ~= false,
      startedAt = os.clock(),
    }
    Audio._bgmGen = id
    Audio._bgmLocal = nil
    Audio._pendingBgm = nil
    Audio._bgmPaused = false
    Audio._fadeOut, Audio._fadeIn = nil, nil
    Audio._fanfareActive = false
    chip.id, chip.nativeId, chip.record, chip.paused = id, nativeId, record, false
    local ok, source = pcall(ChipAudio.playMusic, { audio = {} }, record.def, true)
    if not ok or not source then
      chip.id = nil
      Audio._currentSong = nil
      Audio._bgmGen = nil
      return false
    end
    pcall(source.setVolume, source, (tonumber(Audio._bgmVolume) or 1) * 0.45)
    pcall(deps.extraAudio.stop)
    if record.extra then
      pcall(deps.extraAudio.start, record.extra, { audio = {} }, nil, true)
    end
    if deps.toast then pcall(deps.toast, record) end
    return true
  end

  local function playNative(id, opts)
    resetBus()
    return originalPlay(id, opts)
  end

  function Audio.playSong(id, opts)
    opts = opts or {}
    -- Suppress music during the quest-log recap (B&W location recap).
    if deps.isQuestLog and deps.isQuestLog() then
      resetBus()
      pending = nil
      return true
    end
    local resolved = Audio.resolveSong(id)
    if resolved == nil or resolved == 0 or resolved == 0xFFFF then
      resetBus()
      pending = nil
      return originalPlay(id, opts)
    end
    local info = Audio.songInfo(resolved)
    local fanfares = Audio._pack and Audio._pack.index
      and Audio._pack.index.fanfares
    local isFanfare = opts.fanfare or (info and info.kind == "fanfare")
      or (fanfares and (fanfares[resolved]
        or fanfares[tostring(resolved)]))
    if isFanfare then
      if chip.id then pcall(ChipAudio.holdMusic, true) end
      return originalPlay(id, opts)
    end
    local nativeId = nativeLabel(resolved)
    -- Music test menu: force native playback or a specific cached variant.
    if opts.forceNative then
      pending = nil
      resetBus()
      if deps.toast then pcall(deps.toast, nativeId) end
      return originalPlay(id, opts)
    end
    if opts.forceVariant then
      local forced = opts.forceVariant
      local rec = forced.candidate and deps.loadVariant(nativeId, forced.candidate,
        { enabled = forced.improved, source = "gen1" })
      pending = nil
      if rec then
        resetBus()
        if startChip(resolved, nativeId, rec) then return true end
      end
      if deps.toast then pcall(deps.toast, nativeId) end
      return originalPlay(id, opts)
    end
    local settings = deps.currentSettings()
    if not settings.enabled then
      pending = nil
      if chip.id then resetBus() end
      if deps.toast then pcall(deps.toast, nativeLabel(resolved)) end
      return originalPlay(id, opts)
    end
    -- Same variant already playing: do nothing.
    if chip.id == resolved and chip.record and not opts.restart then
      return true
    end
    -- A deferred preparation is already in flight for this song.
    if pending and pending.id == resolved and not opts.restart then
      return true
    end
    local candidates = deps.candidatesFor(nativeId, settings)
    if #candidates == 0 then
      pending = nil
      if chip.id then resetBus() end
      if deps.debug then pcall(deps.debug, "no alt for " .. nativeId) end
      return originalPlay(id, opts)
    end
    local records = {}
    for _, rec in ipairs(recordsFor(nativeId, settings)) do
      -- Do not translate on the audio thread; uncached variants are prepared
      -- in the background (Audio.update) and used on the next playSong.
      records[#records + 1] = rec
    end
    local eligible = deps.versions.filterEnabled(records, settings.alt)
    if #eligible == 0 then
      pending = nil
      if chip.id then resetBus() end
      if deps.toast then pcall(deps.toast, nativeLabel(resolved)) end
      return originalPlay(id, opts)
    end
    local record
    if settings.shuffle then
      record = deps.versions.pick("shuffle_all", eligible, lastPick[nativeId])
    else
      record = deps.versions.sortByQuality(eligible, 3)[1]
    end
    if not record then
      pending = nil
      if chip.id then resetBus() end
      return originalPlay(id, opts)
    end
    if record.key then lastPick[nativeId] = record.key end
    resetBus()
    pending = nil
    if startChip(resolved, nativeId, record) then return true end
    if deps.debug then pcall(deps.debug, "start fail for " .. nativeId) end
    -- Missing variant: play native now and prepare in the background.
    pending = {
      nativeId = nativeId,
      id = resolved,
      settings = settings,
      candidates = candidates,
    }
    if chip.id then resetBus() end
    if deps.toast then pcall(deps.toast, nativeLabel(resolved)) end
    return originalPlay(id, opts)
  end

  function Audio.pauseBgm()
    if chip.id then
      chip.paused = true
      Audio._bgmPaused = true
      pcall(ChipAudio.holdMusic, true)
      return
    end
    return originalPause()
  end

  function Audio.resumeBgm()
    if chip.id then
      chip.paused = false
      Audio._bgmPaused = false
      pcall(ChipAudio.holdMusic, false)
      return
    end
    return originalResume()
  end

  function Audio.isBgmStopped()
    if chip.id then return chip.paused end
    return originalStopped()
  end

  function Audio.stopAll()
    resetBus()
    pending = nil
    return originalStopAll()
  end

  function Audio.update(dt)
    local result = originalUpdate(dt)
    if chip.id then
      pcall(ChipAudio.update)
      local gain = (tonumber(Audio._bgmVolume) or 1) * 0.45
      local source = ChipAudio.currentSource()
      if source then
        pcall(source.setVolume, source, gain)
      end
      pcall(deps.extraAudio.update)
      pcall(deps.extraAudio.setMusicVolume, gain)
      pcall(deps.extraAudio.setBaseVolume, gain)
    elseif pending then
      -- Deferred preparation: one per frame, then swap in the chip variant.
      if not pending.busy then
        pending.busy = true
        local ok = pcall(function()
          for _, candidate in ipairs(pending.candidates or {}) do
            for _, enabled in ipairs(deps.enabledListFor and deps.enabledListFor()
                or { true, false }) do
              if not candidate.mix or enabled then
                deps.ensureVariant(pending.nativeId, candidate, { enabled = enabled })
              end
            end
          end
        end)
        pending.busy = false
        -- Do not interrupt a song that is already playing; the prepared
        -- variant is now cached and will be used on the next playSong.
        pending = nil
      end
    end
    return result
  end

  M.chip = chip
  M.pending = function() return pending end
end

return M