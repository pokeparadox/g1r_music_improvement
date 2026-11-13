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
  local lastPick = {}

  local function nativeLabel(id)
    local ok, name = pcall(Song.nameOf, id, version)
    if ok and name then return name end
    return tostring(id)
  end

  local function stopChip()
    if not chip.id then return end
    pcall(ChipAudio.stopMusic)
    pcall(deps.extraAudio.stop)
    -- Drop the logical song too: a later native playSong for the same id
    -- would otherwise early-return on _currentSong and leave the bus silent.
    Audio._currentSong = nil
    Audio._bgmGen = nil
    Audio._bgmPaused = false
    chip.id, chip.nativeId, chip.record, chip.paused = nil, nil, nil, false
    chip.extraPending = nil
  end

  local function pickVariant(nativeId, settings)
    local candidates = deps.candidatesFor(nativeId, settings)
    if #candidates == 0 then return nil end
    local candidate = deps.versions.pick(settings.source, candidates, lastPick[nativeId])
    if not candidate then return nil end
    local record = deps.ensureVariant(nativeId, candidate, settings)
    if record then
      lastPick[nativeId] = candidate.version .. ":" .. candidate.label
    end
    return record
  end

  local function startChip(id, nativeId, record)
    local mapSong = Audio._mapSong
    local info = Audio.songInfo(id) or {}
    -- Stop the GBA stream, then put the logical map song back: map/battle
    -- restoration reads _mapSong and currentMapMusic().
    originalPlay(nil)
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
      return false
    end
    pcall(source.setVolume, source, tonumber(Audio._bgmVolume) or 1)
    pcall(deps.extraAudio.stop)
    -- Harmony waits for the base stream's first buffer so both start on the
    -- same frame, mirroring the Gen1/2 ChipAudio.update handshake.
    chip.extraPending = record.extra
    return true
  end

  function Audio.playSong(id, opts)
    opts = opts or {}
    local resolved = Audio.resolveSong(id)
    if resolved == nil or resolved == 0 or resolved == 0xFFFF then
      stopChip()
      return originalPlay(id, opts)
    end
    local info = Audio.songInfo(resolved)
    local fanfares = Audio._pack and Audio._pack.index
      and Audio._pack.index.fanfares
    local isFanfare = opts.fanfare or (info and info.kind == "fanfare")
      or (fanfares and (fanfares[resolved]
        or fanfares[tostring(resolved)]))
    if isFanfare then
      -- Keep chip state: the engine restores BGM through resumeBgm when the
      -- jingle ends, and our wrapper resumes the held chip stream there.
      if chip.id then pcall(ChipAudio.holdMusic, true) end
      return originalPlay(id, opts)
    end
    local settings = deps.currentSettings()
    if not settings.enabled or settings.source == "native" or settings.source == "gen3" then
      stopChip()
      return originalPlay(id, opts)
    end
    local nativeId = nativeLabel(resolved)
    if chip.id == resolved and not opts.restart then return true end
    local record = pickVariant(nativeId, settings)
    if not record then
      stopChip()
      return originalPlay(id, opts)
    end
    return startChip(resolved, nativeId, record) and true or originalPlay(id, opts)
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
    stopChip()
    return originalStopAll()
  end

  function Audio.update(dt)
    local result = originalUpdate(dt)
    if chip.id then
      pcall(ChipAudio.update)
      local gain = tonumber(Audio._bgmVolume) or 1
      local source = ChipAudio.currentSource()
      if source then
        pcall(source.setVolume, source, gain)
        if chip.extraPending then
          local okPlaying, playing = pcall(source.isPlaying, source)
          if okPlaying and playing then
            local extra = chip.extraPending
            chip.extraPending = nil
            pcall(deps.extraAudio.start, extra, { audio = {} }, os.clock(), true)
          end
        end
      end
      pcall(deps.extraAudio.setMusicVolume, gain)
      pcall(deps.extraAudio.setBaseVolume, gain)
    end
    return result
  end

  M.chip = chip
end

return M
