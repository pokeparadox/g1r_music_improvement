-- Music Improvement: swap vanilla Game Boy chip themes for improved,
-- in-engine-synthesized arrangements.  First-run enhancement is deferred
-- to the game loop so startup is not blocked; a confirmation dialog and a
-- progress window cover the cache build.

return function(mod)
  local ChipAsm = require("src.audio.ChipAsm")
  local okChipSynth, ChipSynth = pcall(require, "src.core.ChipSynth")
  local okChipAudio, ChipAudio = pcall(require, "src.core.ChipAudio")
  local okData, Data = pcall(require, "src.core.Data")
  local okMusic, Music = pcall(require, "src.core.Music")

  local function loadModFile(name)
    local source = mod:read(name)
    if not source then
      mod.log:error("%s missing from %s -- reinstall the mod", name, mod.path)
      return nil
    end
    local chunk, compileErr = load(source, "@" .. mod.path .. "/" .. name)
    if not chunk then
      mod.log:error("%s did not compile: %s", name, tostring(compileErr))
      return nil
    end
    local ok, result = pcall(chunk)
    if not ok then
      mod.log:error("%s failed to assemble: %s", name, tostring(result))
      return nil
    end
    return result
  end

  local improveModule = loadModFile("improve.lua")
  if not improveModule then return end
  local improve = function(src, settings) return improveModule.improve(src, settings) end
  local extraSpec = function(src, settings) return improveModule.extra(src, settings) end
  local serialize = loadModFile("serialize.lua")
  local extraAudioFactory = loadModFile("extra_audio.lua")
  local extraAudio = extraAudioFactory and extraAudioFactory()

  local function extraVolumeValue(v)
    if v == "low" then return 0.2 end
    if v == "high" then return 0.5 end
    return 0.35
  end
  local function currentSettings()
    return {
      enabled = mod.options:get("enabled") ~= false,
    }
  end

  local function translate(src, settings)
    local okImprove, improved = pcall(improve, src, settings)
    if not okImprove or type(improved) ~= "table" then
      mod.log:error("music_improvement: improve pass failed: %s", tostring(improved))
      return nil
    end
    local okSong, song = pcall(ChipAsm.song, improved)
    if not okSong or type(song) ~= "table" or type(song.chip) ~= "table" then
      mod.log:error("music_improvement: ChipAsm re-emit failed: %s", tostring(song))
      return nil
    end
    return song
  end

  -- ChipSynth exposes wave levels as multipliers; ChipAsm wants 0-3 codes.
  local function waveLevelCode(value)
    if value == 0 then return 0 end
    if value == 0.25 then return 3 end
    if value == 0.5 then return 2 end
    return 1
  end

  -- Convert an engine drum segment list (sample ticks) into ChipAsm drum rows
  -- (frames of 1-16 at 256 ticks each).
  local function drumRows(segments, frameTicks)
    frameTicks = frameTicks or 256
    local rows = {}
    for _, segment in ipairs(segments or {}) do
      local startSample = segment.startSample or 0
      local endSample = segment.endSample or startSample
      local frames = math.floor((endSample - startSample) / frameTicks + 0.5)
      if frames < 1 then frames = 1 end
      while frames > 0 do
        local chunk = math.min(frames, 16)
        rows[#rows + 1] = {
          len = chunk,
          volume = segment.volume or 0,
          fade = segment.fade or 0,
          parameter = segment.parameter or 0,
        }
        frames = frames - chunk
      end
    end
    if #rows == 0 then rows[1] = { len = 1, volume = 0 } end
    return rows
  end

  local extraDefs = {}
  local function registerTranslation(def, settings, id)
    id = id or "Music_PalletTown"
    if type(def) ~= "table" or type(def.address) ~= "number"
        or type(def.bank) ~= "number" then
      return nil
    end
    if not okChipSynth or type(ChipSynth) ~= "table"
        or type(ChipSynth.newEngine) ~= "function"
        or not okData or type(Data) ~= "table" then
      mod.log:error("music_improvement: ChipSynth/Data unavailable -- cannot translate %s", id)
      return nil
    end
    local engineType = def.engine
    if engineType == nil and Data.audio and Data.audio.gen2 == true then
      engineType = "gen2"
    end
    local okEngine, engine = pcall(ChipSynth.newEngine, Data, {
      address = def.address, bank = def.bank, engine = engineType,
    }, { allowLoops = true })
    if not okEngine or type(engine) ~= "table" or not engine.channels then
      mod.log:warn("music_improvement: ChipSynth.newEngine failed for %s: %s", id, tostring(engine))
      return nil
    end

    local function registerToPitch(channel, register, isWave)
      local freq = 131072 / (2048 - math.min(register or 0, 2047))
      if isWave then freq = freq * 0.5 end
      local probe = (channel.engine and channel.engine.channels[1]) or channel
      local bestN, bestO, bestErr = 0, 4, nil
      if probe then
        for n = 0, 11 do
          for o = 1, 8 do
            local r = probe:frequency(n, o)
            local f = 131072 / (2048 - math.min(r, 2047))
            if isWave then f = f * 0.5 end
            local err = math.abs(f - freq)
            if bestErr == nil or err < bestErr then
              bestErr = err
              bestN = n
              bestO = o
            end
          end
        end
      end
      return bestN, bestO, bestErr
    end

    local src = {
      tempo = engine.tempo or 0x100,
      channels = {},
      drums = {},
      waves = type(engine.waves) == "table" and #engine.waves > 0 and engine.waves or nil,
    }
  local drumIds = {}
  local ordered = {}
  for _, channel in ipairs(engine.channels) do ordered[#ordered + 1] = channel end
  table.sort(ordered, function(a, b) return (a.hardware or 1) < (b.hardware or 1) end)
  for _, channel in ipairs(ordered) do
    local hw = channel.hardware or 1
    if channel.noise then
      local program = {}
      local prevTime = 0
      local guard = 0
      local speed = channel.speed or 12
      local lastSpeed
      local tempo = engine.tempo or 0x100
      while true do
        if channel.ended then break end
        guard = guard + 1
        if guard > 4096 then break end
        local okEvent, event = pcall(function() return channel:nextEvent() end)
        if not okEvent or event == nil then break end
        local timeTicks = channel.timeTicks or 0
        local ticks = timeTicks - prevTime
        prevTime = timeTicks
        local length = math.floor(ticks / (speed * tempo) + 0.5)
        if length < 1 then length = 1 end
        speed = channel.speed or speed
        if speed ~= lastSpeed then
          program[#program + 1] = { notetype = { speed = speed } }
          lastSpeed = speed
        end
        if event.silence then
          program[#program + 1] = { rest = length }
        elseif event.noise then
          if event.drum then
            local drumId = drumIds[event.drum]
            if not drumId then
              drumId = #src.drums + 1
              if drumId > 255 then drumId = 255 end
              src.drums[drumId] = drumRows(event.drum, channel.frameTicks)
              drumIds[event.drum] = drumId
            end
            program[#program + 1] = { drum = drumId, len = length }
          else
            program[#program + 1] = {
              noiseNote = {
                len = length,
                volume = event.volume or 12,
                fade = event.fade or 0,
                parameter = event.noiseParameter or 0,
              },
            }
          end
        end
      end
      if #program > 0 then
        program[#program + 1] = { loop = { count = 0, to = 1 } }
        src.channels[#src.channels + 1] = { hw = hw, program = program }
      end
    else
      local program = {}
      local lastDuty, lastNotetypeKey, lastOctave, lastTempo =
        nil, nil, nil, nil
      local prevTime = 0
      local guard = 0
      while true do
        if channel.noise or channel.ended then break end
        guard = guard + 1
        if guard > 4096 then break end
        local okEvent, event = pcall(function() return channel:nextEvent() end)
        if not okEvent or event == nil then break end
        local timeTicks = channel.timeTicks or 0
        local ticks = timeTicks - prevTime
        prevTime = timeTicks
        local speed = channel.speed or 12
        local tempo = engine.tempo or 0x100
        local length = math.floor(ticks / (speed * tempo) + 0.5)
        if length < 1 then length = 1 end

        if tempo ~= lastTempo then
          program[#program + 1] = { tempo = tempo }
          lastTempo = tempo
        end
        if event.silence then
          program[#program + 1] = { rest = length }
        else
          local dutyVal = 2
          if type(event.duty) == "table" then dutyVal = event.duty[1] or 2 end
          dutyVal = tonumber(event.duty) or dutyVal
          dutyVal = math.max(0, math.min(3, dutyVal))
          if dutyVal ~= lastDuty then
            program[#program + 1] = { duty = dutyVal }
            lastDuty = dutyVal
          end
          if channel.wave then
            local level = waveLevelCode(event.waveLevel)
            local instrument = math.max(0, math.min(15, event.waveInstrument or 0))
            local key = "wave:" .. level .. ":" .. instrument
            if key ~= lastNotetypeKey then
              program[#program + 1] = {
                notetype = { speed = speed, waveLevel = level, waveInstrument = instrument },
              }
              lastNotetypeKey = key
            end
          elseif event.volume ~= nil or event.fade ~= nil then
            local key = tostring(event.volume) .. ":" .. tostring(event.fade)
            if key ~= lastNotetypeKey then
              program[#program + 1] = {
                notetype = { speed = speed, volume = event.volume or 12, fade = event.fade or 0 },
              }
              lastNotetypeKey = key
            end
          end
          local pitch, octave = registerToPitch(channel, event.register, channel.wave)
          if octave ~= lastOctave then
            program[#program + 1] = { octave = octave }
            lastOctave = octave
          end
          program[#program + 1] = { pitch = pitch, len = length }
        end
      end
      if #program > 0 then
        program[#program + 1] = { loop = { count = 0, to = 1 } }
        src.channels[#src.channels + 1] = { hw = hw, program = program }
      end
    end
  end
  local translated = translate(src, settings)
    if translated then
      -- ChipAsm emits Gen1 bytecode; without this Gold would decode the
      -- generated blob with its Gen2 decoder and misread every command.
      translated.generation = 1
      local extra = extraSpec(src, settings)
      if extra then
        local extraSong = {}
        for side, spec in pairs(extra) do
          local okSong, song = pcall(ChipAsm.song, spec)
          if okSong and type(song) == "table" and type(song.chip) == "table" then
            song.generation = 1
            extraSong[side] = song
          end
        end
        if next(extraSong) then
          translated.extra = extraSong
          extraDefs[id] = extraSong
        end
      end
    end
    return translated
  end

  mod.options:define({
    { key = "enabled", type = "toggle", label = "ENABLE IMPROVEMENTS", default = true,
      visible_if = { key = "__music_improvement_hidden", equals = true } },
    { key = "extra_mix", type = "number", label = "EXTRA HARMONY MIX",
      default = 7, min = 0, max = 7, step = 1 },
    { key = "extra_volume", type = "number", label = "EXTRA HARMONY MIX",
      default = 7, min = 0, max = 7, step = 1,
      visible_if = { key = "__music_improvement_hidden", equals = true } },
  })
  local baseOptionGet = mod.options.get
  mod.options.get = function(_, key)
    if key == "extra_mix" then
      local v = baseOptionGet(nil, "extra_volume")
      if v ~= nil then return v end
    elseif key == "extra_volume" then
      local v = baseOptionGet(nil, "extra_mix")
      if v ~= nil then return v end
    end
    return baseOptionGet(nil, key)
  end

  local settings = currentSettings()
  local improvedMap = {}
  local currentImproved = false
  local originalDefs = {}
  local queue = {}
  local total = 0
  local completed = 0
  local state = {
    confirmed = false,
    skipped = false,
    confirmPushed = false,
    progressPushed = false,
    progressInstance = nil,
    pending = false,
  }
  local readyGame

  local applyAll = true

  local function improvedIdFor(name)
    return "Music_Improved" .. tostring(name):gsub("^Music_", "")
  end

  local function settingsHash(s)
    return (mod.manifest.version or "0") .. "_" .. tostring(s.enabled)
  end

  local function cachePath(id, hash)
    local safeId = tostring(id):gsub("[^%w_]", "_")
    return "songs/" .. hash .. "_" .. safeId .. ".lua"
  end

  local cacheIndexPath = "songs/index.txt"
  local cacheIndexPaths = {}
  local cacheIndexSet = {}
  local cacheIndexReady = false

  local function isGeneratedCachePath(path)
    if type(path) ~= "string" or path:sub(1, 6) ~= "songs/"
        or path == cacheIndexPath then
      return false
    end
    local filename = path:sub(7)
    return filename ~= "" and not filename:find("[/\\]")
      and not filename:find("[%z\1-\31]")
      and filename:match("%.lua$") ~= nil
  end

  local function cacheFileExists(path)
    if type(mod.cache.info) ~= "function" then
      mod.log:error("music_improvement: cache info API unavailable for %s", path)
      return nil
    end
    local ok, info = pcall(mod.cache.info, mod.cache, path)
    if not ok then
      mod.log:error("music_improvement: cannot inspect cached file %s: %s",
        path, tostring(info))
      return nil
    end
    return info ~= nil and info ~= false
  end

  local function readCacheIndex()
    local exists = cacheFileExists(cacheIndexPath)
    if exists == nil then return nil end
    if not exists then return {}, {} end
    if type(mod.cache.read) ~= "function" then
      mod.log:error("music_improvement: cache read API unavailable for index")
      return nil
    end
    local ok, contents = pcall(mod.cache.read, mod.cache, cacheIndexPath)
    if not ok or type(contents) ~= "string" then
      mod.log:error("music_improvement: cannot read cache index%s",
        ok and "" or ": " .. tostring(contents))
      return nil
    end

    local paths, seen = {}, {}
    for path in contents:gmatch("[^\r\n]+") do
      if not isGeneratedCachePath(path) then
        mod.log:error("music_improvement: invalid path in cache index: %s", path)
        return nil
      end
      if not seen[path] then
        paths[#paths + 1] = path
        seen[path] = true
      end
    end
    return paths, seen
  end

  local function writeCacheIndex(paths)
    if type(mod.cache.write) ~= "function" then
      mod.log:error("music_improvement: cache write API unavailable for index")
      return false
    end
    local contents = #paths > 0 and (table.concat(paths, "\n") .. "\n") or ""
    local ok, result, writeErr = pcall(mod.cache.write, mod.cache, cacheIndexPath, contents)
    if not ok or result == false then
      mod.log:error("music_improvement: failed to write cache index%s",
        ok and ": " .. tostring(writeErr) or ": " .. tostring(result))
      return false
    end
    if cacheFileExists(cacheIndexPath) ~= true then
      mod.log:error("music_improvement: cache index is missing after write")
      return false
    end
    return true
  end

  local function indexGeneratedCachePath(path)
    if not isGeneratedCachePath(path) then
      mod.log:error("music_improvement: refusing to index invalid cache path %s",
        tostring(path))
      return false
    end
    if not cacheIndexReady then
      local paths, seen = readCacheIndex()
      if not paths then return false end
      cacheIndexPaths, cacheIndexSet = paths, seen
      cacheIndexReady = true
    end
    if cacheIndexSet[path] then return true end

    local updated = {}
    for _, indexedPath in ipairs(cacheIndexPaths) do
      updated[#updated + 1] = indexedPath
    end
    updated[#updated + 1] = path
    if not writeCacheIndex(updated) then return false end
    cacheIndexPaths = updated
    cacheIndexSet[path] = true
    return true
  end

  local function deleteCacheFile(path)
    local exists = cacheFileExists(path)
    if exists == nil then return false end
    if not exists then return true end
    if type(mod.cache.delete) ~= "function" then
      mod.log:error("music_improvement: cache delete API unavailable for %s", path)
      return false
    end
    local ok, result = pcall(mod.cache.delete, mod.cache, path)
    if not ok or result == false then
      mod.log:error("music_improvement: failed to delete cached file %s%s",
        path, ok and "" or ": " .. tostring(result))
      return false
    end
    exists = cacheFileExists(path)
    if exists ~= false then
      mod.log:error("music_improvement: cached file still exists after deletion: %s", path)
      return false
    end
    return true
  end

  do
    local paths, seen = readCacheIndex()
    if paths then
      cacheIndexPaths, cacheIndexSet = paths, seen
      cacheIndexReady = true
    end
  end

  local function loadCached(path)
    local bytes = mod.cache:read(path)
    if type(bytes) ~= "string" then return nil end
    local chunk = load(bytes)
    if not chunk then return nil end
    local ok, def = pcall(chunk)
    if ok and type(def) == "table" and type(def.chip) == "table" then
      return def
    end
    return nil
  end

  local function buildQueue(settings, force)
    queue = {}
    originalDefs = {}
    improvedMap = {}
    extraDefs = {}
    completed = 0
    total = 0
    state.skipped = false
    if settings.enabled == false then
      state.pending = false
      return
    end
    local ids = {}
    if okData and type(Data) == "table" and type(Data.audio) == "table"
        and type(Data.audio.songs) == "table" then
      for id in pairs(Data.audio.songs) do ids[#ids + 1] = id end
    end
    table.sort(ids)
    local hash = settingsHash(settings)
    for _, id in ipairs(ids) do
      if not tostring(id):match("^Music_Improved") then
        local def = Data.audio.songs[id]
        local shouldProcess = true
        if shouldProcess then
          originalDefs[id] = def
          local cachedDef = nil
          if not force then
            cachedDef = loadCached(cachePath(id, hash))
          end
          if cachedDef then
            indexGeneratedCachePath(cachePath(id, hash))
            local improvedId = improvedIdFor(id)
            local okReg = pcall(mod.content.music.register, mod.content.music, improvedId, cachedDef)
            if not okReg then
              pcall(mod.content.music.override, mod.content.music, improvedId, cachedDef)
            end
            improvedMap[id] = improvedId
            extraDefs[improvedId] = cachedDef.extra
            completed = completed + 1
          else
            queue[#queue + 1] = id
          end
          total = total + 1
        end
      end
    end
    state.pending = (#queue > 0)
  end

  buildQueue(settings, false)

  local function setModOption(game, key, value)
    local modId = mod.manifest.id
    local loader = game and game.mods
    if loader then
      loader.modOptions = loader.modOptions or {}
      loader.modOptions[modId] = loader.modOptions[modId] or {}
      loader.modOptions[modId][key] = value
    end
    local save = game and game.save
    if save and save.options then
      save.options.modOptions = save.options.modOptions or {}
      save.options.modOptions[modId] = save.options.modOptions[modId] or {}
      save.options.modOptions[modId][key] = value
      if game.state and type(game.state.persistOptions) == "function" then
        pcall(game.state.persistOptions, game.state)
      end
    end
  end

  local function clearSongCache()
    local indexedPaths, indexedSet = readCacheIndex()
    if not indexedPaths then return false end

    for _, path in ipairs(indexedPaths) do
      if not deleteCacheFile(path) then return false end
    end

    local ids = {}
    if okData and type(Data) == "table" and type(Data.audio) == "table"
        and type(Data.audio.songs) == "table" then
      for id in pairs(Data.audio.songs) do
        if not tostring(id):match("^Music_Improved") then
          ids[#ids + 1] = id
        end
      end
    end
    table.sort(ids)

    local legacyVersions = { "0.4.6", tostring(mod.manifest.version or "0") }
    local legacySeen = {}
    for _, version in ipairs(legacyVersions) do
      if not legacySeen[version] then
        legacySeen[version] = true
        for _, id in ipairs(ids) do
          local path = cachePath(id, version .. "_true")
          if not isGeneratedCachePath(path) then
            mod.log:error("music_improvement: refusing to delete invalid legacy cache path %s",
              path)
            return false
          end
          if not indexedSet[path] and not deleteCacheFile(path) then
            return false
          end
        end
      end
    end

    if not deleteCacheFile(cacheIndexPath) then return false end
    cacheIndexPaths, cacheIndexSet = {}, {}
    cacheIndexReady = true
    mod.log:info("music_improvement: cleared indexed generated song cache")
    return true
  end

  local startPreparation
  local function regenerateCache(game)
    if not clearSongCache() then
      mod.log:error("music_improvement: regeneration cancelled because old cache could not be cleared")
      return
    end
    settings = currentSettings()
    settings.enabled = true
    setModOption(game, "enabled", true)
    if state.progressInstance and game and game.stack then
      pcall(game.stack.pop, game.stack)
    end
    state.confirmed = true
    state.confirmPushed = true
    state.progressPushed = false
    state.progressInstance = nil
    buildQueue(settings, true)
    if startPreparation then startPreparation(game) end
  end

  local function prepareOne(game)
    if #queue == 0 then
      state.pending = false
      return
    end
    local id = table.remove(queue, 1)
    local okPrepare, prepareErr = pcall(function()
      local def = originalDefs[id]
      local translated
      if type(def) == "table" and type(def.address) == "number"
          and type(def.bank) == "number" then
        translated = registerTranslation(def, settings, id)
      else
        mod.log:warn("music_improvement: skipping %s (missing ROM address/bank)", tostring(id))
      end
      if translated then
        if translated.extra then
          extraDefs[id] = translated.extra
          extraDefs[improvedIdFor(id)] = translated.extra
        end
        local improvedId = improvedIdFor(id)
        local okReg = pcall(mod.content.music.register, mod.content.music, improvedId, translated)
        if not okReg then
          pcall(mod.content.music.override, mod.content.music, improvedId, translated)
        end
        improvedMap[id] = improvedId
        local hash = settingsHash(settings)
        if serialize then
          local okSer, bytes = pcall(serialize, translated)
          if okSer and type(bytes) == "string" then
            local path = cachePath(id, hash)
            if indexGeneratedCachePath(path) then
              local okWrite, result, writeErr =
                pcall(mod.cache.write, mod.cache, path, bytes)
              if not okWrite or result == false then
                mod.log:error("music_improvement: failed to write cached file %s%s",
                  path, okWrite and ": " .. tostring(writeErr)
                    or ": " .. tostring(result))
              elseif cacheFileExists(path) ~= true then
                mod.log:error("music_improvement: cached file is missing after write: %s",
                  path)
              end
            else
              mod.log:error("music_improvement: skipping unindexed cached file %s", path)
            end
          end
        end
      end
    end)
    if not okPrepare then
      mod.log:error("music_improvement: prepare failed for %s: %s", tostring(id), tostring(prepareErr))
    end
    completed = completed + 1
    mod.log:info("music_improvement: prepared %d/%d: %s", completed, total, id)
    if state.progressInstance then
      state.progressInstance.progress = completed
      state.progressInstance.total = total
    end
    if #queue == 0 then
      state.pending = false
      if state.progressInstance and game and game.stack then
        pcall(game.stack.pop, game.stack)
        state.progressInstance = nil
        state.progressPushed = false
      end
    end
  end

  local function prepareAll()
    while #queue > 0 do
      prepareOne(nil)
    end
    state.pending = false
  end

  mod.exports = mod.exports or {}
  mod.exports.prepareAll = prepareAll
  mod.exports.prepareMusic = prepareAll
  mod.exports.flush = prepareAll
  mod.exports.processQueue = prepareAll
  mod.exports.regenerateCache = regenerateCache

  -- confirmation + progress screens
  mod.content.screens:register("MusicImprovementConfirm", {
    new = function(game)
      local items = {
        { label = "YES", value = "yes" },
        { label = "NO", value = "no" },
      }
      return mod.ui.ListMenu.new(game, "ENHANCE MUSIC?", items, {
        onChoose = function(item)
          if item.value == "yes" then
            state.confirmed = true
            setModOption(game, "enabled", true)
          else
            state.skipped = true
            state.pending = false
          end
          if game and game.stack then pcall(game.stack.pop, game.stack) end
          state.confirmInstance = nil
          if state.confirmed and #queue > 0 then
            startPreparation(game)
          end
          return true
        end,
        onCancel = function()
          state.skipped = true
          state.pending = false
          state.confirmInstance = nil
        end,
      })
    end,
  })

  mod.content.screens:register("MusicImprovementProgress", {
    new = function(game)
      local inst = {
        game = game,
        progress = completed,
        total = total,
        isOpaque = true,
        update = function(self)
          prepareOne(game)
        end,
        draw = function(self)
          local G = love.graphics
          G.setColor(0, 0, 0, 1)
          G.rectangle("fill", 0, 0, G.getWidth(), G.getHeight())
          G.setColor(1, 1, 1, 1)
          G.print("Preparing music cache...", 10, 10)
          G.print(string.format("%d / %d", self.progress or 0, self.total or 0), 10, 30)
        end,
      }
      return inst
    end,
  })

  -- jukebox screen
  mod.content.screens:register("MusicImprovementJukebox", {
    new = function(game)
      local ids = {}
      for id in mod.content.music:each() do ids[#ids + 1] = id end
      table.sort(ids)
      local items = {}
      for _, id in ipairs(ids) do
        items[#items + 1] = { label = id:gsub("^Music_", ""), value = id }
      end
      local menu = mod.ui.ListMenu.new(game, "MUSIC TEST", items, {
        onChoose = function(item)
          require("src.core.Music").play(game.data, item.value, true,
            { reason = "direct" })
        end,
        onCancel = function()
          require("src.core.Music").stop()
        end,
      })
      if items[1] and mod.options:get("enabled") ~= false and not state.skipped then
        require("src.core.Music").play(game.data, items[1].value, true,
          { reason = "direct" })
      end
      return menu
    end,
  })

  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    -- Gold groups rows by a fixed set of built-in IDs; these aliases place
    -- the mod controls inside AUDIO rather than after Gold's root groups.
    local musicRows = {
      {
        id = "sound",
        musicImprovementId = "music_improvement_enabled",
        label = "MUSIC IMPROVEMENTS",
        value = function()
          return mod.options:get("enabled") ~= false and "ON" or "OFF"
        end,
        activate = function(g)
          local cur = mod.options:get("enabled") ~= false
          setModOption(g, "enabled", not cur)
        end,
      },

      {
        id = "musicVol",
        musicImprovementId = "music_improvement_jukebox",
        label = "MUSIC TEST",
        value = function()
          if state.pending then
            return string.format("PREPARING %d/%d", completed, total)
          end
          return "OPEN"
        end,
        activate = function(g)
          mod.ui.push(g, "MusicImprovementJukebox")
        end,
      },

      {
        id = "sfxVol",
        musicImprovementId = "music_improvement_regenerate",
        label = "REGEN MUSIC",
        value = function()
          if state.pending then
            return string.format("PREPARING %d/%d", completed, total)
          end
          return "PRESS A"
        end,
        activate = function(g) regenerateCache(g) end,
      },
    }
    if type(mod.ui.insertAfter) == "function" then
      local anchor = "SOUND"
      for _, row in ipairs(musicRows) do
        mod.ui.insertAfter(out, anchor, row)
        anchor = row.label
      end
    else
      for _, row in ipairs(musicRows) do out[#out + 1] = row end
    end
    return out
  end)

  mod.hooks:wrap("music.select", function(next, chosen, ctx)
    if mod.options:get("enabled") == false then
      return next(chosen, ctx)
    end
    if state.pending and not state.confirmed then
      return next(chosen, ctx)
    end
    if state.skipped then
      return next(chosen, ctx)
    end
    if not ctx or ctx.reason == "direct" then
      return next(chosen, ctx)
    end
    local improved = improvedMap[chosen]
    if improved then
      return next(improved, ctx)
    end
    return next(chosen, ctx)
  end)

  startPreparation = function(game)
    if #queue == 0 then
      state.pending = false
      return
    end
    if game and game.stack and not state.progressPushed then
      state.progressPushed = true
      state.progressInstance = mod.ui.push(game, "MusicImprovementProgress")
      if state.progressInstance then
        state.progressInstance.progress = completed
        state.progressInstance.total = total
      end
    end
  end

  -- realtime extra harmony stream
  local function applyChannelMix()
    if not okChipAudio or type(ChipAudio) ~= "table" then return end
    local enhancementActive = mod.options:get("enabled") ~= false
      and not state.skipped and (not state.pending or state.confirmed)
    local noiseVolume = enhancementActive and 1.5 or 1
    pcall(ChipAudio.setChannelVolumes, { 1, 1, 1, noiseVolume })
  end
  mod.events:on("music.started", function(payload)
    local song = payload and payload.song
    currentImproved = (type(song) == "string" and song:match("^Music_Improved") ~= nil)
    if extraAudio then
      pcall(extraAudio.stop)
      local extra = song and extraDefs[song]
      local enhancementActive = mod.options:get("enabled") ~= false
        and not state.skipped and (not state.pending or state.confirmed)
      if extra and enhancementActive then
        pcall(extraAudio.start, extra, Data)
      end
    end
    pcall(applyChannelMix)
  end)
  mod.events:on("music.stopped", function()
    currentImproved = false
    if extraAudio then pcall(extraAudio.stop) end
    pcall(applyChannelMix)
  end)

  mod.hooks:wrap("music.volume", function(next, vol, ctx)
    local out = next(vol, ctx)
    if extraAudio then
      pcall(extraAudio.setMusicVolume, tonumber(out) or vol)
    end
    return out
  end)

  -- The game does not expose a core.update hook. Wrap the live instance at
  -- game.ready for audio work, and wait for the first screen push before
  -- showing the opt-in prompt so it sits above Gold's boot/title screen.
  mod.events:on("screen.pushed", function()
    if readyGame and state.pending and not state.confirmed and not state.skipped
        and not state.confirmPushed and readyGame.stack then
      state.confirmPushed = true
      state.confirmInstance = mod.ui.push(readyGame, "MusicImprovementConfirm")
    end
  end)
  mod.events:on("game.ready", function(payload)
    local game = payload and (payload.game or payload)
    if type(game) ~= "table" then return end
    readyGame = game
    settings = currentSettings()
    buildQueue(settings, false)
    if type(game.update) ~= "function" or game._g1rMusicImprovementUpdateWrapped then
      return
    end
    local nextUpdate = game.update
    game._g1rMusicImprovementUpdateWrapped = true
    game.update = function(self, dt)
      if extraAudio then
        if mod.options:get("enabled") ~= false then
          pcall(extraAudio.setExtraMix, mod.options:get("extra_mix"))
          pcall(extraAudio.update)
        else
          pcall(extraAudio.stop)
        end
      end
      pcall(applyChannelMix)
      return nextUpdate(self, dt)
    end
  end)

  mod.log:info("music_improvement: %d cached, %d pending", completed, #queue)
end