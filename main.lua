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
  local okGameVersion, GameVersion = pcall(require, "src.core.GameVersion")

  -- Gen1 keeps its music in the src.core.Data singleton; Gen2 builds the
  -- dataset in Game2.data and never fills Data.audio.  Prefer whichever
  -- table actually carries songs, and let game.ready promote the live one.
  local liveData
  local function isSongData(data)
    return type(data) == "table" and type(data.audio) == "table"
      and type(data.audio.songs) == "table"
  end
  local function musicData()
    if isSongData(liveData) then return liveData end
    if isSongData(Data) then return Data end
    return liveData or Data
  end
  if isSongData(Data) then liveData = Data end

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
  local versions = loadModFile("versions.lua")
  if not versions then return end
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
      source = mod.options:get("source") or "native",
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

  -- Convert engine sample positions into ChipAsm drum rows (frames of 1-16).
  local TICKS_PER_SECOND = 15360
  local function drumRows(segments, frameTicks, sampleRate)
    frameTicks = frameTicks or 256
    sampleRate = sampleRate or 44100
    local rows = {}
    for _, segment in ipairs(segments or {}) do
      local startSample = segment.startSample or 0
      local endSample = segment.endSample or startSample
      local durationTicks = (endSample - startSample)
        * TICKS_PER_SECOND / sampleRate
      local frames = math.floor(durationTicks / frameTicks + 0.5)
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
  local function registerTranslation(def, settings, id, sourceData, extraKey)
    id = id or "Music_PalletTown"
    if type(def) ~= "table" or type(def.address) ~= "number"
        or type(def.bank) ~= "number" then
      return nil
    end
    local data = sourceData or musicData()
    if not okChipSynth or type(ChipSynth) ~= "table"
        or type(ChipSynth.newEngine) ~= "function"
        or type(data) ~= "table" then
      mod.log:error("music_improvement: ChipSynth/Data unavailable -- cannot translate %s", id)
      return nil
    end
    local engineType = def.engine
    if engineType == nil and data.audio and data.audio.gen2 == true then
      engineType = "gen2"
    end
    local okEngine, engine = pcall(ChipSynth.newEngine, data, {
      address = def.address, bank = def.bank, engine = engineType,
      generation = def.generation,
    }, { allowLoops = false })
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

    local function stoppedLoopTarget(channel)
      if not channel.ended or type(channel.address) ~= "number"
          or type(channel.byte) ~= "function"
          or type(channel.word) ~= "function" or channel.address < 4 then
        return nil
      end
      local endAddress = channel.address
      channel.address = endAddress - 4
      local opcode = channel:byte()
      local count = channel:byte()
      local target = channel:word()
      channel.address = endAddress
      local loopOpcode = engine.generation == 2 and 0xFD or 0xFE
      if opcode == loopOpcode and count == 0 then return target end
      return nil
    end

    local src = {
      tempo = engine.tempo or 0x100,
      channels = {},
      drums = {},
      waves = type(engine.waves) == "table" and #engine.waves > 0 and engine.waves or nil,
    }
    -- Gen2 tempo is a shared engine register.  Channel 1 owns the song's
    -- tempo commands, so record them as a timeline and replay that same
    -- timeline while decoding the other channels.  Without it, a channel with
    -- no tempo commands is decoded at whatever tempo the previous channel
    -- happened to leave behind (the Gold intro changes 256 -> 168 after two
    -- notes, so both the stale and reset-to-initial variants drift).
    local tempoTimeline = { { tick = 0, tempo = src.tempo } }
    local function tempoAt(tick)
      local value = tempoTimeline[1].tempo
      for _, entry in ipairs(tempoTimeline) do
        if entry.tick <= tick then value = entry.tempo else break end
      end
      return value
    end
    local function recordTempo(tick, tempo)
      local last = tempoTimeline[#tempoTimeline]
      if last and last.tempo == tempo then return end
      if last and last.tick == tick then
        last.tempo = tempo
        return
      end
      tempoTimeline[#tempoTimeline + 1] = { tick = tick, tempo = tempo }
    end
    -- Gen2 note length comes from note_type (channel.noteLength); speed is a
    -- Gen1 field and stays 12 on Gold channels.
    local function eventSpeed(channel)
      if engine.generation == 2 then
        return math.max(1, channel.noteLength or 1)
      end
      return channel.speed or 12
    end
    -- Some songs loop into another song's stream (e.g. Gold's
    -- Music_AfterTheRivalFight loops into Music_LookRival). Continue decoding
    -- at the foreign target with the live channel state until the target is
    -- mapped into this program.
    local function resolveLoop(program, indices, channel, decode, id, hw,
        songAddress)
      local sourceTarget = stoppedLoopTarget(channel)
      local seen = {}
      for _ = 1, 8 do
        if not sourceTarget or indices[sourceTarget] or seen[sourceTarget]
            or not songAddress or sourceTarget >= songAddress then
          break
        end
        seen[sourceTarget] = true
        channel.ended = false
        channel.address = sourceTarget
        decode()
        sourceTarget = stoppedLoopTarget(channel)
      end
      local loopTo = sourceTarget and indices[sourceTarget]
      if sourceTarget and not loopTo then
        mod.log:warn(
          "music_improvement: couldn't map loop target %04X for %s channel %d",
          sourceTarget, id, hw)
      end
      return sourceTarget, loopTo
    end
    local noLoop = {}
    local drumIds = {}
  local ordered = {}
  for _, channel in ipairs(engine.channels) do ordered[#ordered + 1] = channel end
  table.sort(ordered, function(a, b) return (a.hardware or 1) < (b.hardware or 1) end)
  for _, channel in ipairs(ordered) do
    -- Channel 1 defines the tempo timeline; every other channel is decoded
    -- against it (see tempoTimeline above).
    engine.tempo = src.tempo
    local hw = channel.hardware or 1
    local eventProgramIndices = {}
    -- Loop targets often point into the middle of a decoded command group
    -- (e.g. at a note_type or octave byte). Record every byte address a
    -- decode step reads so such targets map to that step's program index
    -- instead of falling back to the start of the intro.
    local stepIndex = 0
    local readByte = channel.byte
    if type(readByte) == "function" then
      channel.byte = function(self)
        local address = self.address
        if type(address) == "number" then
          eventProgramIndices[address] = stepIndex
        end
        return readByte(self)
      end
    end
    if channel.noise then
      local program = {}
      local emittedTicks = 0
      local guard = 0
      local lastSpeed
      local lastTempo = src.tempo
      local decode
      decode = function()
        while true do
          if channel.ended then break end
          guard = guard + 1
          if guard > 4096 then break end
          if hw ~= 1 then
            engine.tempo = tempoAt(channel.timeTicks or 0)
          end
          local sourceAddress = channel.address
          stepIndex = #program + 1
          local okEvent, event = pcall(function() return channel:nextEvent() end)
          if not okEvent or event == nil then break end
          if type(sourceAddress) == "number" then
            eventProgramIndices[sourceAddress] = #program + 1
          end
          local timeTicks = channel.timeTicks or 0
          local speed = eventSpeed(channel)
          local tempo = engine.tempo or 0x100
          local length = math.floor((timeTicks - emittedTicks) / (speed * tempo) + 0.5)
          if length < 1 then length = 1 end
          local eventStartTicks = emittedTicks
          emittedTicks = emittedTicks + length * speed * tempo
          if tempo ~= lastTempo then
            if hw == 1 then
              recordTempo(eventStartTicks, tempo)
              program[#program + 1] = { tempo = tempo }
            end
            lastTempo = tempo
          end
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
                src.drums[drumId] = drumRows(
                  event.drum, channel.frameTicks, ChipSynth.SAMPLE_RATE)
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
      end
      decode()
      if #program > 0 then
        local sourceTarget, loopTo = resolveLoop(program,
          eventProgramIndices, channel, decode, id, hw, def.address)
        local srcChannel = { hw = hw, program = program }
        if sourceTarget then
          program[#program + 1] = { loop = { count = 0, to = loopTo or 1 } }
        else
          noLoop[#noLoop + 1] = { srcChannel = srcChannel,
            tempo = lastTempo or engine.tempo or 0x100 }
        end
        if #program > 0 then
          src.channels[#src.channels + 1] = srcChannel
        end
      end
      channel.byte = readByte
    else
      local program = {}
      local lastDuty, lastNotetypeKey, lastOctave, lastTempo =
        nil, nil, nil, src.tempo
      local emittedTicks = 0
      local guard = 0
      local decode
      decode = function()
        while true do
          if channel.noise or channel.ended then break end
          guard = guard + 1
          if guard > 4096 then break end
          if hw ~= 1 then
            engine.tempo = tempoAt(channel.timeTicks or 0)
          end
          local sourceAddress = channel.address
          stepIndex = #program + 1
          local okEvent, event = pcall(function() return channel:nextEvent() end)
          if not okEvent or event == nil then break end
          if type(sourceAddress) == "number" then
            eventProgramIndices[sourceAddress] = #program + 1
          end
          local timeTicks = channel.timeTicks or 0
          local speed = eventSpeed(channel)
          local tempo = engine.tempo or 0x100
          local length = math.floor((timeTicks - emittedTicks) / (speed * tempo) + 0.5)
          if length < 1 then length = 1 end
          local eventStartTicks = emittedTicks
          emittedTicks = emittedTicks + length * speed * tempo

          if tempo ~= lastTempo then
            if hw == 1 then
              recordTempo(eventStartTicks, tempo)
              program[#program + 1] = { tempo = tempo }
            end
            lastTempo = tempo
          end
          local notetype, notetypeKey
          if channel.wave then
            local level = waveLevelCode(event.waveLevel or channel.waveLevel)
            local instrument = math.max(0,
              math.min(15, event.waveInstrument or channel.waveInstrument or 0))
            notetypeKey = table.concat({
              "wave", tostring(speed), tostring(level), tostring(instrument),
            }, ":")
            notetype = {
              speed = speed,
              waveLevel = level,
              waveInstrument = instrument,
            }
          else
            local volume = event.volume
            if volume == nil then volume = channel.volume end
            local fade = event.fade
            if fade == nil then fade = channel.fade end
            volume = volume or 12
            fade = fade or 0
            notetypeKey = table.concat({
              "square", tostring(speed), tostring(volume), tostring(fade),
            }, ":")
            notetype = { speed = speed, volume = volume, fade = fade }
          end
          if notetypeKey ~= lastNotetypeKey then
            program[#program + 1] = { notetype = notetype }
            lastNotetypeKey = notetypeKey
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
            local pitch, octave = registerToPitch(channel, event.register, channel.wave)
            if octave ~= lastOctave then
              program[#program + 1] = { octave = octave }
              lastOctave = octave
            end
            program[#program + 1] = { pitch = pitch, len = length }
          end
        end
      end
      decode()
      if #program > 0 then
        local sourceTarget, loopTo = resolveLoop(program,
          eventProgramIndices, channel, decode, id, hw, def.address)
        local srcChannel = { hw = hw, program = program }
        if sourceTarget then
          program[#program + 1] = { loop = { count = 0, to = loopTo or 1 } }
        else
          noLoop[#noLoop + 1] = { srcChannel = srcChannel,
            tempo = lastTempo or engine.tempo or 0x100 }
        end
        if #program > 0 then
          src.channels[#src.channels + 1] = srcChannel
        end
      end
      channel.byte = readByte
    end
  end
  -- Pad no-source-loop channels to the longest generated playback duration so
  -- the whole song restarts in sync.  Measuring the first translation (rather
  -- than trusting per-event emittedTicks) avoids Gen2 frame-carry drift.
  if #noLoop > 0 then
    local firstTranslated = translate(src, settings)
    if firstTranslated and firstTranslated.chip and firstTranslated.chip.channels then
      local durations = {}
      local measureEngine = ChipSynth.newEngine({ audio = {} }, firstTranslated,
        { allowLoops = false })
      for i, channel in ipairs(measureEngine.channels) do
        local n=0
        while true do
          local e = channel:nextEvent()
          if not e then break end
          n=n+1
          if n>1000000 then break end
        end
        durations[i] = channel.timeTicks or 0
      end
      local maxDur = 0
      for _, entry in ipairs(noLoop) do
        for i, channel in ipairs(src.channels) do
          if channel == entry.srcChannel then
            entry._index = i
            if (durations[i] or 0) > maxDur then maxDur = durations[i] end
          end
        end
      end
      for _, entry in ipairs(noLoop) do
        local duration = entry._index and durations[entry._index] or 0
        local tempo = entry.tempo or 0x100
        local pad = maxDur - duration
        if id:match("GoldSilverOpening") then
        end
        if id:match("GoldSilverOpening") then
        end
        if pad > 0 and tempo > 0 and entry.srcChannel
            and entry.srcChannel.program then
          local units = math.floor(pad / tempo + 0.5)
          if id:match("GoldSilverOpening") then
          end
          if units > 0 then
            entry.srcChannel.program[#entry.srcChannel.program + 1] =
              { notetype = { speed = 1 } }
            while units > 0 do
              local chunk = math.min(16, units)
              entry.srcChannel.program[#entry.srcChannel.program + 1] =
                { rest = chunk }
              units = units - chunk
            end
          end
        end
        if entry.srcChannel and entry.srcChannel.program then
          entry.srcChannel.program[#entry.srcChannel.program + 1] =
            { loop = { count = 0, to = 1 } }
        end
      end
    end
  end
  if id:match("GoldSilverOpening") then
  end
  if id:match("GoldSilverOpening") then
    local p = src.channels[2] and src.channels[2].program
    if p then
      for i = math.max(1, #p - 6), #p do
        local e = p[i]
        io.stderr:write(string.format(" %s", e.loop and ("loop" .. tostring(e.loop.to)) or e.rest and ("rest" .. tostring(e.rest)) or "ev"))
      end
    end
    io.stderr:write("\n")
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
          extraDefs[extraKey or id] = extraSong
        end
      end
    end
    return translated
  end

  mod.options:define({
    { key = "enabled", type = "toggle", label = "ENABLE IMPROVEMENTS", default = true,
      visible_if = { key = "__music_improvement_hidden", equals = true } },
    { key = "source", type = "choice", label = "MUSIC VERSION", default = "native",
      choices = {
        { "NATIVE", "native" }, { "SHUFFLE", "shuffle" },
        { "GEN 1", "gen1" }, { "GEN 2", "gen2" },
      } },
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
  local stagedImprovedMap = {}
  local variantMap = {}
  local variantByKey = {}
  local lastVariant = {}
  local sourceCache = {}
  local currentImproved = false
  local currentSong
  local currentReason
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

  -- Content registries freeze at the loader's merge boundary.  Songs built
  -- after that (first cache fill, regeneration) must still reach the live
  -- Data table or every mapped cue resolves to a missing def.
  local function registerImprovedId(improvedId, def)
    local okReg = pcall(mod.content.music.register, mod.content.music, improvedId, def)
    if not okReg then
      pcall(mod.content.music.override, mod.content.music, improvedId, def)
    end
    -- after the merge boundary both registry writes raise, so keep the live
    -- table authoritative for playback and the music test list.
    local data = musicData()
    if isSongData(data) then
      data.audio.songs[improvedId] = def
    end
    return improvedId
  end

  local function registerImproved(id, def)
    return registerImprovedId(improvedIdFor(id), def)
  end

  local function settingsHash(s)
    return (mod.manifest.version or "0") .. "_" .. tostring(s.enabled)
  end

  -- Caches must never cross game versions: Red/Blue/Yellow and every Gen2
  -- game reuse song IDs but can have different source bytecode.
  local function cacheGameId(game)
    local version = game and game.save and game.save.version
    if type(version) ~= "string" or version == "" then
      version = okGameVersion and GameVersion and GameVersion.get and GameVersion.get()
    end
    version = tostring(version or "unknown"):lower():gsub("[^%w_]", "_")
    return version ~= "" and version or "unknown"
  end

  local activeCacheGame = cacheGameId(nil)

  local function cachePath(id, hash)
    local safeId = tostring(id):gsub("[^%w_]", "_")
    return "songs/" .. activeCacheGame .. "_" .. hash .. "_" .. safeId .. ".lua"
  end

  -- A dataset view is a detached, data-only copy.  Build the same synthetic
  -- audio table ChipSynth expects from it; translated chip defs need no source
  -- bytes at playback time, but the initial decode does.
  local function sourceFor(version)
    if sourceCache[version] ~= nil then return sourceCache[version] or nil end
    sourceCache[version] = false
    if not mod.datasets or type(mod.datasets.open) ~= "function" then return nil end
    local ok, view = pcall(mod.datasets.open, mod.datasets, version)
    if not ok or type(view) ~= "table" then return nil end
    local okAudio, audio = pcall(function() return view.content.audio end)
    local okMusic, music = pcall(function() return view.content.music end)
    if not okAudio or not audio or not okMusic or not music then return nil end
    local okGet, programFile = pcall(audio.get, audio, "programFile")
    if not okGet or not programFile then return nil end
    local okPath, programPath = pcall(view.assets.path, view.assets, programFile)
    if not okPath or not programPath then return nil end
    local data = {
      audio = {
        generation = view.generation,
        gen2 = view.generation == 2,
        programFile = programPath,
        bankOrder = audio:get("bankOrder"),
        waveBanks = audio:get("waveBanks"),
      },
    }
    if view.generation == 1 then
      data.audio.noiseHeaders = audio:get("noiseHeaders")
    else
      data.audio.drumkits = audio:get("drumkits")
    end
    local source = { view = view, data = data }
    sourceCache[version] = source
    return source
  end

  local function sourceHasSong(source, label)
    if not source then return false end
    local music = source.view.content.music
    if type(music.has) == "function" then
      local ok, has = pcall(music.has, music, label)
      return ok and has == true
    end
    local ok, def = pcall(music.get, music, label)
    return ok and def ~= nil
  end

  local function variantIdFor(nativeId, version)
    local suffix = tostring(nativeId):gsub("^Music_", ""):gsub("^MUS_", "")
    return "Music_Improved" .. suffix .. "_" .. tostring(version)
  end

  local function variantKeyFor(candidate)
    return tostring(candidate.version) .. ":" .. tostring(candidate.label)
  end

  local function rememberVariant(nativeId, candidate, def, improvedId)
    local key = variantKeyFor(candidate)
    local record = {
      key = key,
      id = improvedId,
      def = def,
      extra = extraDefs[improvedId],
      version = candidate.version,
      label = candidate.label,
      generation = candidate.generation,
    }
    variantByKey[key] = record
    local list = variantMap[nativeId]
    if not list then list = {}; variantMap[nativeId] = list end
    for index = #list, 1, -1 do
      if list[index].key == key then table.remove(list, index) end
    end
    list[#list + 1] = record
    return record
  end

  local function candidatesFor(nativeId, s)
    if not s.enabled or s.source == "native" then return {} end
    local hostGeneration = 1
    if okGameVersion and GameVersion and GameVersion.generation then
      hostGeneration = GameVersion.generation(activeCacheGame) or hostGeneration
    end
    local list = versions.candidates(nativeId, hostGeneration, activeCacheGame,
      function(version, label) return sourceHasSong(sourceFor(version), label) end)
    local wanted = versions.generationForMode(s.source)
    if not wanted then return list end
    local filtered = {}
    for _, candidate in ipairs(list) do
      if candidate.generation == wanted then filtered[#filtered + 1] = candidate end
    end
    return filtered
  end

  local function loadVariant(nativeId, candidate, s)
    if not candidate then return nil end
    local key = variantKeyFor(candidate)
    local existing = variantByKey[key]
    if existing and existing.def then return existing end
    local improvedId = variantIdFor(nativeId, candidate.version)
    local cached = loadCached(cachePath(improvedId, settingsHash(s)))
    if cached then
      registerImprovedId(improvedId, cached)
      extraDefs[improvedId] = cached.extra
      return rememberVariant(nativeId, candidate, cached, improvedId)
    end
    return nil
  end

  local function cacheIndexFor(gameId)
    return "songs/" .. gameId .. "_index.txt"
  end

  local cacheIndexPath = cacheIndexFor(activeCacheGame)
  local cacheIndexPaths = {}
  local cacheIndexSet = {}
  local cacheIndexReady = false

  local function isGeneratedCachePath(path)
    local prefix = "songs/" .. activeCacheGame .. "_"
    if type(path) ~= "string" or path:sub(1, #prefix) ~= prefix
        or path == cacheIndexPath then
      return false
    end
    local filename = path:sub(#prefix + 1)
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
      local data = musicData()
      if type(data) ~= "table" or type(data.audio) ~= "table" then data = { audio = {} } end
      local valid, engine = pcall(ChipSynth.newEngine, data, def, { allowLoops = true })
      if valid and type(engine) == "table" then return def end
      mod.log:warn("music_improvement: invalid cached song %s: %s", path, tostring(engine))
    end
    return nil
  end

  local function publishImprovedMap()
    improvedMap = stagedImprovedMap
    local song = currentSong
    if not song or tostring(song):match("^Music_Improved")
        or currentReason == "jukebox" or state.skipped
        or mod.options:get("enabled") == false
        or not okMusic or not okData then
      return
    end
    if not improvedMap[song] then return end
    local loop = currentReason ~= "once" and currentReason ~= "victory" or false
    pcall(Music.play, musicData(), song, loop, { reason = currentReason or "map" })
  end

  local function chooseVariant(nativeId)
    local s = currentSettings()
    if not s.enabled or s.source == "native" then return nil end
    local list = variantMap[nativeId]
    if not list or #list == 0 then return nil end
    local picked = versions.pick(s.source, list, lastVariant[nativeId])
    if not picked then return nil end
    lastVariant[nativeId] = picked.key
    return picked.id
  end

  local function buildQueue(settings, force, game)
    local gameId = cacheGameId(game)
    if activeCacheGame ~= gameId then
      activeCacheGame = gameId
      cacheIndexPath = cacheIndexFor(gameId)
      cacheIndexPaths, cacheIndexSet = {}, {}
      cacheIndexReady = false
    end
    queue = {}
    originalDefs = {}
    improvedMap = {}
    stagedImprovedMap = {}
    variantMap = {}
    variantByKey = {}
    lastVariant = {}
    extraDefs = {}
    completed = 0
    total = 0
    local queuedVariant = {}
    state.skipped = false
    if settings.enabled == false then
      state.pending = false
      return
    end
    local ids = {}
    local data = (game and game.data) or musicData()
    if isSongData(data) then
      if data ~= liveData then liveData = data end
      for id in pairs(data.audio.songs) do ids[#ids + 1] = id end
    end
    table.sort(ids)
    local hash = settingsHash(settings)
    for _, id in ipairs(ids) do
      if not tostring(id):match("^Music_Improved") then
        local def = data.audio.songs[id]
        local shouldProcess = true
        if shouldProcess then
          originalDefs[id] = def
          local cachedDef = nil
          if not force then
            cachedDef = loadCached(cachePath(id, hash))
          end
          if cachedDef then
            indexGeneratedCachePath(cachePath(id, hash))
            local improvedId = registerImproved(id, cachedDef)
            stagedImprovedMap[id] = improvedId
            extraDefs[improvedId] = cachedDef.extra
          else
            queue[#queue + 1] = id
          end
        end
      end
    end
    if settings.source ~= "native" then
      for _, id in ipairs(ids) do
        if not tostring(id):match("^Music_Improved") and originalDefs[id] then
          for _, candidate in ipairs(candidatesFor(id, settings)) do
            local record = loadVariant(id, candidate, settings)
            if record then
              indexGeneratedCachePath(cachePath(record.id, hash))
              extraDefs[record.id] = record.extra
            else
              local key = tostring(id) .. "|" .. variantKeyFor(candidate)
              if not queuedVariant[key] then
                queuedVariant[key] = true
                queue[#queue + 1] = {
                  kind = "variant",
                  nativeId = id,
                  improvedId = variantIdFor(id, candidate.version),
                  version = candidate.version,
                  label = candidate.label,
                  generation = candidate.generation,
                }
              end
            end
          end
        end
      end
    end
    total = #queue
    state.pending = total > 0
    if not state.pending then publishImprovedMap() end
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
    buildQueue(settings, true, game)
    if startPreparation then startPreparation(game) end
  end

  local function writeCached(cacheId, def)
    if not serialize then return end
    local okSer, bytes = pcall(serialize, def)
    if not okSer or type(bytes) ~= "string" then return end
    local path = cachePath(cacheId, settingsHash(settings))
    if not indexGeneratedCachePath(path) then
      mod.log:error("music_improvement: skipping unindexed cached file %s", path)
      return
    end
    local okWrite, result, writeErr = pcall(mod.cache.write, mod.cache, path, bytes)
    if not okWrite or result == false then
      mod.log:error("music_improvement: failed to write cached file %s%s", path,
        okWrite and ": " .. tostring(writeErr) or ": " .. tostring(result))
    elseif cacheFileExists(path) ~= true then
      mod.log:error("music_improvement: cached file is missing after write: %s", path)
    end
  end

  local function prepareVariant(entry, s)
    s = s or settings
    local source = sourceFor(entry.version)
    local def = source and source.view.content.music:get(entry.label)
    local translated = registerTranslation(def, s, entry.label,
      source and source.data, entry.improvedId)
    if not translated then return nil end
    local data = musicData()
    if type(data) ~= "table" or type(data.audio) ~= "table" then data = { audio = {} } end
    local okDef, defErr = pcall(ChipSynth.newEngine, data, translated,
      { allowLoops = true })
    if not okDef or type(defErr) ~= "table" then
      mod.log:warn("music_improvement: generated variant invalid for %s: %s",
        tostring(entry.label), tostring(defErr))
      return nil
    end
    extraDefs[entry.improvedId] = translated.extra
    registerImprovedId(entry.improvedId, translated)
    local record = rememberVariant(entry.nativeId, entry, translated, entry.improvedId)
    writeCached(entry.improvedId, translated)
    return record
  end

  local function ensureVariant(nativeId, candidate, s)
    local record = loadVariant(nativeId, candidate, s)
    if record then return record end
    return prepareVariant({
      kind = "variant",
      nativeId = nativeId,
      improvedId = variantIdFor(nativeId, candidate.version),
      version = candidate.version,
      label = candidate.label,
      generation = candidate.generation,
    }, s)
  end

  local function prepareOne(game)
    if #queue == 0 then
      state.pending = false
      return
    end
    local entry = table.remove(queue, 1)
    local variant = type(entry) == "table" and entry or nil
    local id = variant and variant.nativeId or entry
    local okPrepare, prepareErr = pcall(function()
      if variant then
        prepareVariant(variant, settings)
      else
        local def = originalDefs[id]
        local translated
        if type(def) == "table" and type(def.address) == "number"
            and type(def.bank) == "number" then
          translated = registerTranslation(def, settings, id)
        else
          mod.log:warn("music_improvement: skipping %s (missing ROM address/bank)", tostring(id))
        end
        if translated then
          local data = musicData()
          if type(data) ~= "table" or type(data.audio) ~= "table" then data = { audio = {} } end
          local okDef, defErr = pcall(ChipSynth.newEngine, data, translated,
            { allowLoops = true })
          if not okDef or type(defErr) ~= "table" then
            mod.log:warn("music_improvement: generated song invalid for %s: %s",
              tostring(id), tostring(defErr))
            translated = nil
          end
        end
        if translated then
          if translated.extra then
            extraDefs[id] = translated.extra
            extraDefs[improvedIdFor(id)] = translated.extra
          end
          local improvedId = registerImproved(id, translated)
          stagedImprovedMap[id] = improvedId
          writeCached(id, translated)
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
      publishImprovedMap()
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
    publishImprovedMap()
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

  -- Registrations made after the merge boundary are not in the frozen
  -- registry snapshot the test harness exposes, so merge both views.
  local function musicIds(game)
    local ids, seen = {}, {}
    for id in mod.content.music:each() do
      if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    local songs = game and game.data and game.data.audio
      and game.data.audio.songs
    if type(songs) == "table" then
      for id in pairs(songs) do
        if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
      end
    end
    table.sort(ids)
    return ids
  end
  mod.exports.musicIds = musicIds

  -- jukebox screen
  mod.content.screens:register("MusicImprovementJukebox", {
    new = function(game)
      local ids = musicIds(game)
      local items = {}
      for _, id in ipairs(ids) do
        items[#items + 1] = { label = id:gsub("^Music_", ""), value = id }
      end
      local menu = mod.ui.ListMenu.new(game, "MUSIC TEST", items, {
        onChoose = function(item)
          require("src.core.Music").play(game.data, item.value, true,
            { reason = "jukebox" })
        end,
        onCancel = function()
          require("src.core.Music").stop()
        end,
      })
      if items[1] and mod.options:get("enabled") ~= false and not state.skipped then
        require("src.core.Music").play(game.data, items[1].value, true,
          { reason = "jukebox" })
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

      {
        id = "sfxVol",
        musicImprovementId = "music_improvement_source",
        label = "MUSIC VERSION",
        value = function()
          local source = mod.options:get("source") or "native"
          return ({ native = "NATIVE", shuffle = "SHUFFLE",
            gen1 = "GEN 1", gen2 = "GEN 2" })[source] or "NATIVE"
        end,
        activate = function(g)
          local modes = { "native", "shuffle", "gen1", "gen2" }
          local cur = mod.options:get("source") or "native"
          local index = 1
          for i, mode in ipairs(modes) do if mode == cur then index = i break end end
          setModOption(g, "source", modes[index % #modes + 1])
          buildQueue(currentSettings(), false, readyGame or g)
          startPreparation(readyGame or g)
        end,
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

  -- playOnce only arms its map-theme restore when the label it passed in
  -- became the current song.  The select hook below rewrites that label, so
  -- the jingle plays but the map theme never comes back.  Give core the
  -- improved label up front instead.
  if okMusic and type(Music.playOnce) == "function" then
    local corePlayOnce = Music.playOnce
    Music.playOnce = function(data, song)
      local improved = type(song) == "string"
        and (improvedMap[song] or chooseVariant(song)) or nil
      if improved and mod.options:get("enabled") ~= false
          and not state.skipped then
        song = improved
      end
      return corePlayOnce(data, song)
    end
  end

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
    -- Core uses "direct" for calls with no context too (title, intro, menus),
    -- so only the jukebox opts out of enhancement explicitly.
    if not ctx or ctx.reason == "jukebox" then
      return next(chosen, ctx)
    end
    local improved = improvedMap[chosen] or chooseVariant(chosen)
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

  -- Prepare harmony while the threaded base source buffers, so both start
  -- from sample zero. Fallback paths still wait for the base to play.
  local pendingExtra
  local pendingLooping = true
  local suppressExtra = false
  local cpuEma = 0
  local cpuOverSince = nil
  local guardIgnoreUntil = 0
  local function g1rClock()
    if love and love.timer and type(love.timer.getTime) == "function" then
      local ok, t = pcall(love.timer.getTime)
      if ok and type(t) == "number" then return t end
    end
    return os.clock()
  end

  -- A long main-thread stall (voxel cache encode/storage, GPU upload, GC)
  -- drains the harmony queue faster than it can be repaired. Stop the extra
  -- voices for this song instead of drifting; music.started retries them.
  local function frameGuard(dt)
    if not extraAudio or not extraAudio.isActive() then return end
    if type(dt) ~= "number" or dt <= 0 then return end
    local now = g1rClock()
    if now < guardIgnoreUntil then return end
    cpuEma = cpuEma * 0.9 + dt * 0.1
    local over = dt > 0.5 or cpuEma > 0.035
    if over then
      cpuOverSince = cpuOverSince or now
    else
      cpuOverSince = nil
    end
    if over and (dt > 0.5 or now - cpuOverSince >= 1.0) then
      suppressExtra = true
      cpuOverSince = nil
      pcall(extraAudio.stop)
      mod.log:info("music_improvement: harmony paused until next song (%.0fms frame)",
                   dt * 1000)
    end
  end

  -- Base audio starts inside ChipAudio.update, before game.update returns.
  -- Start harmony in that same call so both streams begin at the same sample
  -- instead of one frame late.
  if okChipAudio and type(ChipAudio) == "table"
      and type(ChipAudio.update) == "function"
      and not ChipAudio._g1rUpdateWrapped then
    ChipAudio._g1rUpdateWrapped = true
    local baseChipUpdate = ChipAudio.update
    ChipAudio.update = function(...)
      local awaitingBefore = false
      if type(ChipAudio.awaitingFirstBuffer) == "function" then
        local ok, value = pcall(ChipAudio.awaitingFirstBuffer)
        if ok then awaitingBefore = value == true end
      end
      local result = baseChipUpdate(...)
      if pendingExtra and awaitingBefore
          and type(ChipAudio.awaitingFirstBuffer) == "function" then
        local ok, value = pcall(ChipAudio.awaitingFirstBuffer)
        if ok and value ~= true then
          -- updateThreaded starts the base Source during baseChipUpdate.
          -- start() already pre-rendered harmony while the base buffered.
          pendingExtra = nil
          if extraAudio then
            pcall(extraAudio.update)
          end
        end
      end
      return result
    end
  end

  local function applyChannelMix()
    if not okChipAudio or type(ChipAudio) ~= "table" then return end
    local enhancementActive = mod.options:get("enabled") ~= false
      and not state.skipped and (not state.pending or state.confirmed)
    pcall(ChipAudio.setChannelVolumes, { 1, 1, 1, 1 })
  end
  mod.events:on("music.started", function(payload)
    local song = payload and payload.song
    currentSong = song
    currentReason = payload and payload.reason
    currentImproved = (type(song) == "string" and song:match("^Music_Improved") ~= nil)
    suppressExtra = false
    cpuEma = 0
    cpuOverSince = nil
    if extraAudio then
      pcall(extraAudio.stop)
      local extra = song and extraDefs[song]
      local enhancementActive = mod.options:get("enabled") ~= false
        and not state.skipped and not state.pending and not suppressExtra
      if extra and enhancementActive then
        pendingLooping = currentReason ~= "once"
        guardIgnoreUntil = g1rClock() + 2
        local basePlaying = false
        if okChipAudio and type(ChipAudio.currentSource) == "function" then
          local okSource, source = pcall(ChipAudio.currentSource)
          if okSource and source then
            local okPlay, playing = pcall(source.isPlaying, source)
            if okPlay then basePlaying = playing == true end
          end
        end
        if basePlaying then
          pcall(extraAudio.start, extra, musicData(), g1rClock(), currentReason ~= "once")
          pcall(extraAudio.update)
        else
          pendingExtra = extra
          -- Base source is still buffering. Build and pre-render harmony now
          -- so it can start with the base instead of one update later.
          pcall(extraAudio.start, extra, musicData(), nil, pendingLooping)
        end
      else
        pendingExtra = nil
      end
    end
    pcall(applyChannelMix)
  end)
  mod.events:on("music.stopped", function()
    currentImproved = false
    currentSong = nil
    currentReason = nil
    pendingExtra = nil
    if extraAudio then pcall(extraAudio.stop) end
    pcall(applyChannelMix)
  end)

  mod.hooks:wrap("music.volume", function(next, vol, ctx)
    local out = next(vol, ctx)
    if extraAudio then
      pcall(extraAudio.setMusicVolume, tonumber(out) or vol)
      pcall(extraAudio.setBaseVolume, tonumber(out) or vol)
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
    buildQueue(settings, false, game)
    local generation = okGameVersion and GameVersion and GameVersion.generation
      and GameVersion.generation(cacheGameId(game)) or 1
    if generation == 3 then
      local host = loadModFile("gen3.lua")
      if host and type(host.install) == "function" then
        local extra = extraAudio or {
          start = function() end, stop = function() end,
          setMusicVolume = function() end, setBaseVolume = function() end,
        }
        host.install({
          versions = versions,
          currentSettings = currentSettings,
          candidatesFor = candidatesFor,
          ensureVariant = ensureVariant,
          extraAudio = extra,
        })
      end
    end
    if type(game.update) ~= "function" or game._g1rMusicImprovementUpdateWrapped then
      return
    end
    local nextUpdate = game.update
    game._g1rMusicImprovementUpdateWrapped = true
    game.update = function(self, dt)
      pcall(applyChannelMix)
      if state.pending and not state.confirmed and not state.skipped
          and not state.confirmPushed and self.stack then
        state.confirmPushed = true
        state.confirmInstance = mod.ui.push(self, "MusicImprovementConfirm")
      end
      local result = nextUpdate(self, dt)
      frameGuard(dt)
      -- Base audio starts inside nextUpdate (Music.update -> ChipAudio.update).
      -- Start harmony after it, in the same frame, instead of one frame late.
      if extraAudio then
        if suppressExtra then
          pendingExtra = nil
          if extraAudio.isActive() then pcall(extraAudio.stop) end
        elseif mod.options:get("enabled") ~= false then
          pcall(extraAudio.setExtraMix, mod.options:get("extra_mix"))
          if pendingExtra and okChipAudio and type(ChipAudio.currentSource) == "function" then
            local okSource, source = pcall(ChipAudio.currentSource)
            local okPlaying, playing = okSource and source and pcall(source.isPlaying, source)
            if okPlaying and playing then
              pendingExtra = nil
            end
          end
          pcall(extraAudio.update)
        else
          pendingExtra = nil
          pcall(extraAudio.stop)
        end
      end
      return result
    end
  end)

  mod.log:info("music_improvement: %d songs pending", #queue)
end