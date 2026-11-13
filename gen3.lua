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
  local chip = { id = nil, nativeId = nil, record = nil, paused = false,
                 extraPending = nil }
  local pending = nil   -- { nativeId, id, settings, candidate }
  local lastPick = {}
  local chosen = {}     -- nativeId -> { source=..., candidate=... }

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
    chip.extraPending = nil
  end

  local function candidateFor(nativeId, settings)
    -- Shuffle must roll again for every fresh playSong, so do not reuse a
    -- cached pick in that mode.
    if settings.source ~= "shuffle" then
      local cached = chosen[nativeId]
      if cached and cached.source == settings.source then
        return cached.candidate
      end
    end
    local candidates = deps.candidatesFor(nativeId, settings)
    if #candidates == 0 then
      chosen[nativeId] = nil
      return nil
    end
    local candidate = deps.versions.pick(settings.source, candidates,
      lastPick[nativeId])
    if candidate then
      chosen[nativeId] = { source = settings.source, candidate = candidate }
      lastPick[nativeId] = candidate.version .. ":" .. candidate.label
    else
      chosen[nativeId] = nil
    end
    return candidate
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
    pcall(source.setVolume, source, (tonumber(Audio._bgmVolume) or 1) * 0.3)
    pcall(deps.extraAudio.stop)
    chip.extraPending = record.extra
    if deps.toast then
      local gen = record.generation and ("G" .. record.generation) or "G1"
      pcall(deps.toast, gen, record.label)
    end
    return true
  end

  local function playNative(id, opts)
    resetBus()
    return originalPlay(id, opts)
  end

  function Audio.playSong(id, opts)
    opts = opts or {}
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
    local settings = deps.currentSettings()
    if not settings.enabled or settings.source == "native"
        or settings.source == "gen3" then
      pending = nil
      if chip.id then resetBus() end
      if deps.toast then
        pcall(deps.toast, "G3", nativeLabel(resolved))
      end
      return originalPlay(id, opts)
    end
    local nativeId = nativeLabel(resolved)
    -- Same variant already playing: do nothing.
    if chip.id == resolved and chip.record and not opts.restart then
      return true
    end
    -- A deferred preparation is already in flight for this song.
    if pending and pending.id == resolved and not opts.restart then
      return true
    end
    local candidate = candidateFor(nativeId, settings)
    if not candidate then
      pending = nil
      if chip.id then resetBus() end
      if deps.toast then
        pcall(deps.toast, "G3", nativeLabel(resolved))
      end
      return originalPlay(id, opts)
    end
    local enabledList = deps.enabledListFor
      and deps.enabledListFor(settings.source, settings.enabled)
      or { settings.enabled ~= false }
    local records = {}
    for _, enabled in ipairs(enabledList) do
      local s2 = { enabled = enabled, source = settings.source }
      local rec = deps.loadVariant(nativeId, candidate, s2)
      if not rec then
        rec = deps.ensureVariant(nativeId, candidate, s2)
      end
      if rec then records[#records + 1] = rec end
    end
    -- Filter by shuffle mode.
    local eligible = {}
    for _, rec in ipairs(records) do
      local improved = tostring(rec.id):match("^Music_Improved") ~= nil
      local stock = tostring(rec.id):match("^Music_Stock") ~= nil
      if settings.source == "shuffle_improved" and improved then
        eligible[#eligible + 1] = rec
      elseif settings.source == "shuffle_stock" and stock then
        eligible[#eligible + 1] = rec
      else
        eligible[#eligible + 1] = rec
      end
    end
    local record = nil
    if #eligible > 0 then
      local picked = deps.versions.pick(settings.source, eligible,
        lastPick[nativeId])
      if picked then
        record = picked
        lastPick[nativeId] = picked.key
      else
        record = eligible[1]
      end
    end
    if record then
      resetBus()
      pending = nil
      local ok = startChip(resolved, nativeId, record)
      if not ok then
        return originalPlay(id, opts)
      end
      return true
    end
    -- Missing variant: play native now and prepare in the background.
    pending = {
      nativeId = nativeId,
      id = resolved,
      settings = settings,
      candidate = candidate,
    }
    if chip.id then resetBus() end
    if deps.toast then
      pcall(deps.toast, "G3", nativeLabel(resolved))
    end
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
        if chip.extraPending then
          local okPlaying, playing = pcall(source.isPlaying, source)
          if okPlaying and playing then
            local extra = chip.extraPending
            chip.extraPending = nil
            pcall(deps.extraAudio.start, extra, { audio = {} },
              os.clock(), true)
          end
        end
      end
      pcall(deps.extraAudio.setMusicVolume, gain)
      pcall(deps.extraAudio.setBaseVolume, gain)
    elseif pending then
      -- Deferred preparation: one per frame, then swap in the chip variant.
      if not pending.busy then
        pending.busy = true
        local ok = pcall(function()
          local enabledList = deps.enabledListFor
            and deps.enabledListFor(pending.settings.source, pending.settings.enabled)
            or { pending.settings.enabled ~= false }
          for _, enabled in ipairs(enabledList) do
            local s2 = { enabled = enabled, source = pending.settings.source }
            deps.ensureVariant(pending.nativeId, pending.candidate, s2)
          end
        end)
        pending.busy = false
        -- Do not interrupt a song that is already playing; the prepared
        -- variant is now cached and will be used on the next playSong.
        if ok and record then
          pending = nil
        else
          pending = nil
        end
      end
    end
    return result
  end

  M.chip = chip
  M.pending = function() return pending end
end

return M