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
  local profiles = loadModFile("song_profiles.lua")
  if not profiles then return end
  local musicMenu = loadModFile("music_menu.lua")
  if musicMenu and musicMenu.setVersions then musicMenu.setVersions(versions) end
  local omniUi = loadModFile("omni_ui.lua")
  if omniUi and omniUi.install then pcall(omniUi.install) end
  local function omniActive() return omniUi ~= nil and omniUi.isActive() == true end
  local g3Mix = loadModFile("g3_mix.lua")
  local g3SongIds = loadModFile("g3_song_ids.lua")
  if g3Mix and g3Mix.setSongIds and g3SongIds then
    g3Mix.setSongIds(g3SongIds)
  end
  local ndsImport = loadModFile("nds_import.lua")
  local g4SongMap = loadModFile("g4_song_map.lua")
  local g4Mix = loadModFile("g4_mix.lua")
  local function isG4VariantId(id)
    id = tostring(id or "")
    return id:match("^Music_G4Mix") ~= nil or id:match("^Music_G4GB") ~= nil
  end
  local sourceFor, sourceHasSong
  if ndsImport and ndsImport.install then
    pcall(ndsImport.install, { imports = mod.imports, cache = mod.cache })
  end
  if g4Mix and g4Mix.install then
    pcall(g4Mix.install, {
      g3Mix = g3Mix, nds = ndsImport, songMap = g4SongMap, cache = mod.cache,
      versions = versions,
      available = function(version, label)
        return sourceFor and sourceHasSong and
          sourceHasSong(sourceFor(version), label) or false
      end,
    })
  end
  local mixCandidatesFor
  local g4CandidatesFor
  local gen3Ui
  local openGen3Sources
  local improve = function(src, settings) return improveModule.improve(src, settings) end
  local extraSpec = function(src, settings, id)
    local profile = id and profiles.forLabel(id) or nil
    if not profile then return improveModule.extra(src, settings) end
    local copy = {}
    for k, v in pairs(settings or {}) do copy[k] = v end
    copy.profile = profile
    return improveModule.extra(src, copy)
  end
  local serialize = loadModFile("serialize.lua")
  local extraAudioFactory = loadModFile("extra_audio.lua")
  local extraAudio = extraAudioFactory and extraAudioFactory()
  local gbaExtraAudio = extraAudioFactory and extraAudioFactory()
  local function readNdsSample(bank, def)
    if not ndsImport or not ndsImport.readSample then return nil end
    local ok, sample = pcall(ndsImport.readSample, bank, def)
    if ok then return sample end
  end
  if gbaExtraAudio and gbaExtraAudio.setProfile then
    pcall(gbaExtraAudio.setProfile, "gba")
  end
  for _, audio in ipairs({ extraAudio, gbaExtraAudio }) do
    if audio and audio.setSampleReader then
      pcall(audio.setSampleReader, readNdsSample)
    end
  end

  local function extraVolumeValue(v)
    if v == "low" then return 0.2 end
    if v == "high" then return 0.5 end
    return 0.35
  end
  -- Gen3 host games have no loader on game.mods, so setModOption cannot update
  -- mod.options:get live.  Keep session overrides for every option write.
  local optionOverrides = {}
  local function optionValue(key)
    local value = optionOverrides[key]
    if value ~= nil then return value end
    return mod.options:get(key)
  end
  local function optionBool(key, default)
    local value = optionValue(key)
    if value == nil then return default end
    if value == false then return false end
    return tostring(value) ~= "0" and tostring(value) ~= "false"
  end

  local function currentSettings()
    return {
      enabled = optionBool("enabled", true),
      shuffle = optionBool("shuffle", true),
      alt = {
        g1 = optionBool("alt_g1_stock", true),
        g1_improved = optionBool("alt_g1_guided", true),
        g2 = optionBool("alt_g2_stock", true),
        g2_improved = optionBool("alt_g2_guided", true),
        g3 = optionBool("alt_g3_native", true),
        g3_mix = optionBool("alt_g3_mix", true),
        g4_mix = optionBool("alt_g4_mix", true),
        g4_gb = optionBool("alt_g4_gb", true),
      },
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
  local function registerSpec(def, settings, id, extra)
    local translated = translate(def, settings)
    if not translated then return nil end
    translated.generation = 1
    if extra then
      local extraSong = {}
      for side, spec in pairs(extra) do
        local okSong, song = pcall(ChipAsm.song, spec)
        if okSong and type(song) == "table" and type(song.chip) == "table" then
          song.generation = 1
          if spec.pan then song.pan = spec.pan end
          if spec.gain then song.gain = spec.gain end
          if spec.pcm then song.pcm = spec.pcm end
          extraSong[side] = song
        end
      end
      if next(extraSong) then
        translated.extra = extraSong
        extraDefs[id] = extraSong
      end
    end
    return translated
  end

  local function registerTranslation(def, settings, id, sourceData, extraKey)
    id = id or "Music_PalletTown"
    local oneshot = (versions and versions.groupFor and
      (versions.groupFor(id) or {}).oneshot == true)
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
      local sourceTarget, loopTo = resolveLoop(program,
        eventProgramIndices, channel, decode, id, hw, def.address)
      if #program > 0 then
        local srcChannel = { hw = hw, program = program }
        if sourceTarget then
          if not oneshot then program[#program + 1] = { loop = { count = 0, to = loopTo or 1 } } end
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
      local sourceTarget, loopTo = resolveLoop(program,
        eventProgramIndices, channel, decode, id, hw, def.address)
      if #program > 0 then
        local srcChannel = { hw = hw, program = program }
        if sourceTarget then
          if not oneshot then program[#program + 1] = { loop = { count = 0, to = loopTo or 1 } } end
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
        if (not oneshot) and entry.srcChannel and entry.srcChannel.program then
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
      local extra = extraSpec(src, settings, id)
      if extra then
        local extraSong = {}
        for side, spec in pairs(extra) do
          local okSong, song = pcall(ChipAsm.song, spec)
          if okSong and type(song) == "table" and type(song.chip) == "table" then
            song.generation = 1
            if type(spec) == "table" and spec.intensityEnvelope then
              song.intensityEnvelope = spec.intensityEnvelope
            end
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
    { key = "source", type = "choice", label = "MUSIC VERSION", default = "shuffle_all",
      visible_if = { key = "__music_improvement_hidden", equals = true },
      choices = {
        { "NATIVE", "native" },
        { "SHUF ALL", "shuffle_all" },
        { "SHUF IMP", "shuffle_improved" },
        { "SHUF STK", "shuffle_stock" },
        { "SHUF MIX", "shuffle_mix" },
        { "GEN 1", "gen1" }, { "GEN 2", "gen2" },
      } },
    { key = "shuffle", type = "toggle", label = "MUSIC SHUFFLE", default = true,
      visible_if = { key = "__music_improvement_hidden", equals = true } },
    { key = "alt_g1_stock", type = "toggle", label = "G1", default = true,
      visible_if = { key = "__music_improvement_hidden", equals = true } },
    { key = "alt_g1_guided", type = "toggle", label = "G1E", default = true,
      visible_if = { key = "__music_improvement_hidden", equals = true } },
    { key = "alt_g2_stock", type = "toggle", label = "G2", default = true,
      visible_if = { key = "__music_improvement_hidden", equals = true } },
    { key = "alt_g2_guided", type = "toggle", label = "G2E", default = true,
      visible_if = { key = "__music_improvement_hidden", equals = true } },
    { key = "alt_g3_mix", type = "toggle", label = "G3 Mix", default = true,
      visible_if = { key = "__music_improvement_hidden", equals = true } },
    { key = "alt_g4_mix", type = "toggle", label = "G4 Mix", default = true,
      visible_if = { key = "__music_improvement_hidden", equals = true } },
    { key = "alt_g4_gb", type = "toggle", label = "G4 (GB)", default = true,
      visible_if = { key = "__music_improvement_hidden", equals = true } },
    { key = "alt_g3_native", type = "toggle", label = "G3", default = true,
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
  local stagedImprovedMap = {}
  local variantMap = {}
  local variantByKey = {}
  local recordById = {}
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

  local toast = { text = nil, until_ = 0 }
  local hostGeneration
  -- Toast format: <Canonical Name> — <G1 STOCK|G1 GUIDED|...|NATIVE>
  local function showToast(value)
    local generation = hostGeneration()
    local record = type(value) == "table" and value or recordById[value]
    local info
    if record then
      info = {
        name = record.name or versions.nameFor(record.label or ""),
        variant = versions.variantKind(record, generation),
      }
    else
      info = versions.describe(value, generation)
    end
    local label = info.label or versions.variantLabel(info.variant or "native")
    toast.text = string.format("%s — %s", tostring(info.name or "Music"), label)
    toast.until_ = os.clock() + 2.5
  end
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
    local alt = s.alt or {}
    return (mod.manifest.version or "0") .. "_" .. tostring(s.enabled)
      .. "_" .. tostring(s.shuffle)
      .. "_" .. table.concat({
        alt.g1 and "1" or "0", alt.g1_improved and "1" or "0",
        alt.g2 and "1" or "0", alt.g2_improved and "1" or "0",
        alt.g3 and "1" or "0", alt.g3_mix and "1" or "0",
      }, "_")
  end

  -- Base songs are cached per host version: Red/Blue/Yellow and every Gen2
  -- game reuse song IDs but can have different source bytecode.  Variants are
  -- keyed by source version instead: their translation does not depend on the
  -- host, so every host shares the same file.
  local function cacheGameId(game)
    local version = game and game.save and game.save.version
    if type(version) ~= "string" or version == "" then
      version = okGameVersion and GameVersion and GameVersion.get and GameVersion.get()
    end
    version = tostring(version or "unknown"):lower():gsub("[^%w_]", "_")
    return version ~= "" and version or "unknown"
  end

  local activeCacheGame = cacheGameId(nil)

  -- Toast labels follow the loaded game, not GameVersion.get(), which can be
  -- stale on hosts that swap save files without reselecting the global game.
  hostGeneration = function()
    local ids = {
      readyGame and cacheGameId(readyGame),
      activeCacheGame,
      okGameVersion and GameVersion and GameVersion.get and GameVersion.get(),
    }
    if okGameVersion and GameVersion and GameVersion.generation then
      for _, id in ipairs(ids) do
        if id and id ~= "" and id ~= "unknown" then
          local ok, generation = pcall(GameVersion.generation, id)
          if ok and generation then return generation end
        end
      end
    end
    return 1
  end

  local cacheAliases = {}

  local function contentHash(bytes)
    local h = 5381
    for i = 1, #bytes do
      h = (h * 33 + bytes:byte(i)) % 4294967296
    end
    return string.format("%08x", h)
  end

  local function contentCachePath(bytes)
    local version = tostring(mod.manifest.version or "0")
    local h = contentHash(bytes .. version)
    return "songs/c_" .. version .. "_" .. h .. "_" .. tostring(#bytes) .. ".lua"
  end

  local function resolveCachePath(id)
    return cacheAliases[id]
  end

  -- A dataset view is a detached, data-only copy.  Build the same synthetic
  -- audio table ChipSynth expects from it; translated chip defs need no source
  -- bytes at playback time, but the initial decode does.
  sourceFor = function(version)
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

  sourceHasSong = function(source, label)
    if not source then return false end
    local music = source.view.content.music
    if type(music.has) == "function" then
      local ok, has = pcall(music.has, music, label)
      return ok and has == true
    end
    local ok, def = pcall(music.get, music, label)
    return ok and def ~= nil
  end

  local function variantIdFor(nativeId, version, enabled, candidate)
    local isG4 = candidate and (candidate.g4Mix or candidate.g4Gb)
    local rawName = isG4 and type(candidate.label) == "string"
      and candidate.label:match("^G4:(.+)$") or nil
    local source = rawName or nativeId
    local suffix = tostring(source):gsub("^Music_", ""):gsub("^MUS_", "")
      :gsub("[^%w_]", "_")
    local base = candidate and candidate.g4Gb and "Music_G4GB"
      or candidate and candidate.g4Mix and "Music_G4Mix"
      or candidate and candidate.mix and "Music_Mix"
      or enabled and "Music_Improved" or "Music_Stock"
    return base .. suffix .. "_" .. tostring(version)
  end

  -- Prepare both guided and stock for every game; toggles only gate playback.
  local function enabledListFor()
    return { true, false }
  end

  local function variantKeyFor(nativeId, candidate, enabled)
    local kind = candidate.g4Gb and "B" or (candidate.g4Mix and "G"
      or (candidate.mix and "M" or (enabled and "I" or "S")))
    return tostring(nativeId or "") .. "|" .. tostring(candidate.version)
      .. ":" .. tostring(candidate.label) .. ":" .. kind
  end

  local function rememberVariant(nativeId, candidate, def, improvedId, enabled)
    if enabled == nil then enabled = improvedId:match("^Music_Improved") ~= nil end
    local key = variantKeyFor(nativeId, candidate, enabled)
    local record = {
      key = key,
      id = improvedId,
      def = def,
      extra = extraDefs[improvedId],
      version = candidate.version,
      label = candidate.label,
      candidate = candidate,
      name = versions.nameFor(candidate.label),
      generation = candidate.generation,
      improved = enabled,
      mix = candidate.mix == true,
      g4Mix = candidate.g4Mix == true,
      g4Gb = candidate.g4Gb == true,
    }
    variantByKey[key] = record
    recordById[improvedId] = record
    local list = variantMap[nativeId]
    if not list then list = {}; variantMap[nativeId] = list end
    for index = #list, 1, -1 do
      if list[index].key == key then table.remove(list, index) end
    end
    list[#list + 1] = record
    return record
  end

  local candidateCache = {}
  local function candidatesFor(nativeId, s)
    if s.native then return {} end
    local cacheKey = tostring(nativeId) .. "|" .. settingsHash(s) .. "|" .. tostring(activeCacheGame)
    if candidateCache[cacheKey] then return candidateCache[cacheKey] end
    local hostGeneration = 1
    if okGameVersion and GameVersion and GameVersion.generation then
      hostGeneration = GameVersion.generation(activeCacheGame) or hostGeneration
    end
    local list = {}
    local rawName = tostring(nativeId):match("^_(.+)$")
    if rawName and g4Mix and g4Mix.available and g4Mix.available() then
      for _, mode in ipairs({ "pcm", "chip" }) do
        list[#list + 1] = {
          version = activeCacheGame, generation = hostGeneration,
          label = "G4:" .. rawName,
          g4Mix = mode == "pcm", g4Gb = mode == "chip",
        }
      end
      candidateCache[cacheKey] = list
      return list
    end
    local all = versions.candidates(nativeId, hostGeneration, activeCacheGame,
      function(version, label) return sourceHasSong(sourceFor(version), label) end, true)
    for _, candidate in ipairs(all) do
      -- G3 native playback only exists on a Gen3 host.  G3 Mix is added
      -- separately and stays available everywhere.
      local generation = candidate.generation
        or (versions.BY_ID[candidate.version] and versions.BY_ID[candidate.version].generation)
      if not generation or generation < 3 or hostGeneration >= 3 then
        list[#list + 1] = candidate
      end
    end
    local canonical = versions.canonicalGen3Label(nativeId)
    local group = versions.byLabel[canonical]
    local label = group and group.gen3
      or (tostring(canonical):match("^MUS_") and canonical or nil)
    if g4CandidatesFor and group and versions.mixAllowed(group, hostGeneration) then
      for _, candidate in ipairs(g4CandidatesFor(nativeId, hostGeneration, group)) do
        list[#list + 1] = candidate
      end
    end
    if mixCandidatesFor and label and versions.mixAllowed(group, hostGeneration) then
      for _, candidate in ipairs(mixCandidatesFor(label)) do
        list[#list + 1] = candidate
      end
    end
    candidateCache[cacheKey] = list
    return list
  end

  local loadCached

  local function loadVariant(nativeId, candidate, s)
    if not candidate then return nil end
    local enabled = (s and s.enabled ~= false)
    local key = variantKeyFor(nativeId, candidate, enabled)
    local existing = variantByKey[key]
    if existing and existing.def then return existing end
    local improvedId = variantIdFor(nativeId, candidate.version, enabled, candidate)
    local path = resolveCachePath(improvedId)
    local cached = path and loadCached(path)
    if cached then
      registerImprovedId(improvedId, cached)
      extraDefs[improvedId] = cached.extra
      local record = rememberVariant(nativeId, candidate, cached, improvedId, enabled)
      if record then record.cachePath = path end
      return record
    end
    return nil
  end

  -- One index for every generated file: base songs are host-scoped, variants
  -- are shared across hosts.  Per-game indexes from older builds are merged
  -- and removed by migrateCacheIndex.
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

  local function deleteCacheFile(path, quiet)
    local exists = cacheFileExists(path)
    if exists == nil then return false end
    if not exists then return true end
    if type(mod.cache.delete) ~= "function" then
      if not quiet then
        mod.log:error("music_improvement: cache delete API unavailable for %s", path)
      end
      return false
    end
    local ok, result = pcall(mod.cache.delete, mod.cache, path)
    if not ok or result == false then
      if not quiet then
        mod.log:error("music_improvement: failed to delete cached file %s%s",
          path, ok and "" or ": " .. tostring(result))
      end
      return false
    end
    exists = cacheFileExists(path)
    if exists ~= false then
      if not quiet then
        mod.log:error("music_improvement: cached file still exists after deletion: %s", path)
      end
      return false
    end
    return true
  end

  local function migrateCacheIndex()
    local paths, seen = readCacheIndex()
    if not paths then return end
    local changed = false

    local function addPath(path)
      if isGeneratedCachePath(path) and not seen[path] then
        paths[#paths + 1] = path
        seen[path] = true
        changed = true
      end
    end

    -- Older builds kept one index per host game; merge them.
    for _, entry in ipairs((versions and versions.VERSIONS) or {}) do
      local legacy = "songs/" .. tostring(entry.id) .. "_index.txt"
      if cacheFileExists(legacy) then
        local ok, contents = pcall(mod.cache.read, mod.cache, legacy)
        if ok and type(contents) == "string" then
          for path in contents:gmatch("[^\r\n]+") do addPath(path) end
        end
        deleteCacheFile(legacy, true)
      end
    end

    -- Drop files from other manifest versions and host-prefixed variants
    -- (variants now live in the shared v_<source>_ namespace).  If the
    -- filesystem cannot delete (headless test overlays), keep the entries and
    -- stop trying; playback ignores files whose hash does not match.
    local kept = {}
    local pruneOk = true
    for _, path in ipairs(paths) do
      local keep = path == "songs/aliases.lua"
        or path:match("^songs/c_[%w%.]+_[0-9a-f]+_[0-9]+%.lua$") ~= nil
      if keep then
        kept[#kept + 1] = path
      elseif pruneOk then
        if deleteCacheFile(path, true) then
          changed = true
        else
          pruneOk = false
          kept[#kept + 1] = path
        end
      else
        kept[#kept + 1] = path
      end
    end

    cacheIndexPaths, cacheIndexSet = kept, {}
    for _, path in ipairs(kept) do cacheIndexSet[path] = true end
    cacheIndexReady = true
    if changed then writeCacheIndex(kept) end
  end

  migrateCacheIndex()

  do
    local aliasPath = "songs/aliases.lua"
    if cacheFileExists(aliasPath) then
      local ok, bytes = pcall(mod.cache.read, mod.cache, aliasPath)
      if ok and type(bytes) == "string" then
        local fn = load(bytes)
        if fn then
          local okRun, result = pcall(fn)
          if okRun and type(result) == "table" then cacheAliases = result end
        end
      end
    end
  end

  loadCached = function(path)
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
    local list = variantMap[nativeId]
    if not list or #list == 0 then return nil end
    local eligible = versions.filterEnabled(list, s.alt)
    if #eligible == 0 then return nil end
    local picked
    if s.shuffle then
      picked = versions.pick("shuffle_all", eligible, lastVariant[nativeId])
    else
      picked = versions.sortByQuality(eligible, hostGeneration())[1]
    end
    if not picked then return nil end
    lastVariant[nativeId] = picked.key
    return picked.id
  end

  mixCandidatesFor = function(label)
    local out = {}
    for _, entry in ipairs(versions.VERSIONS) do
      if entry.generation == 3 then
        for _, candidateLabel in ipairs(versions.mixLabelsFor(label, entry.id)) do
          if g3Mix.has(entry.id, candidateLabel) then
            out[#out + 1] = {
              version = entry.id, generation = 3, label = candidateLabel, mix = true,
            }
            break
          end
        end
      end
    end
    return out
  end

  g4CandidatesFor = function(nativeId, hostGeneration, group)
    local out, seen = {}, {}
    if not g4Mix or not g4Mix.available or not g4Mix.available() then return out end
    local key = group and (group.gen3 or group.gen2 or group.gen1) or nativeId
    local function add(version, generation, label)
      for _, mode in ipairs({ "pcm", "chip" }) do
        local dedupe = tostring(version) .. ":" .. tostring(label) .. ":" .. mode
        if seen[dedupe] then
          -- keep going
        else
          seen[dedupe] = true
          out[#out + 1] = {
            version = version, generation = generation, label = label, mode = mode,
            g4Mix = mode == "pcm", g4Gb = mode == "chip",
          }
        end
      end
    end
    for _, entry in ipairs(versions.VERSIONS) do
      local generation = entry.generation
        or (versions.BY_ID[entry.id] and versions.BY_ID[entry.id].generation)
      if generation == 3 then
        for _, candidateLabel in ipairs(versions.mixLabelsFor(key, entry.id)) do
          if g3Mix.has(entry.id, candidateLabel)
              and g4Mix.has(entry.id, candidateLabel, "pcm") then
            add(entry.id, 3, candidateLabel)
            break
          end
        end
      elseif generation == hostGeneration then
        local candidateLabel = group and group["gen" .. generation]
        if candidateLabel and g4Mix.has(entry.id, candidateLabel, "pcm") then
          add(entry.id, generation, candidateLabel)
        end
      end
    end
    return out
  end

  local mixSongListCache
  local function mixSongList()
    if mixSongListCache then return mixSongListCache end
    local seen, labels = {}, {}
    for _, entry in ipairs(versions.VERSIONS) do
      if entry.generation == 3 then
        for _, raw in ipairs(g3Mix.songList(entry.id)) do
          local label = versions.canonicalGen3Label(raw)
          if not seen[label] then seen[label] = true labels[#labels + 1] = label end
        end
      end
    end
    table.sort(labels, function(a, b)
      return versions.nameFor(a):lower() < versions.nameFor(b):lower()
    end)
    mixSongListCache = labels
    return labels
  end

  local function buildQueue(settings, force, game)
    local gameId = cacheGameId(game)
    if activeCacheGame ~= gameId then
      activeCacheGame = gameId
    end
    queue = {}
    originalDefs = {}
    improvedMap = {}
    stagedImprovedMap = {}
    variantMap = {}
    variantByKey = {}
    recordById = {}
    lastVariant = {}
    sourceCache = {}
    extraDefs = {}
    candidateCache = {}
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
    local hostGeneration = 1
    if okGameVersion and GameVersion and GameVersion.generation then
      hostGeneration = GameVersion.generation(activeCacheGame) or hostGeneration
    end
    -- Keep variant ids separate.  Raw G4 entries are appended below; `ids`
    -- must stay native songs for the data.audio.songs lookup in this loop.
    local variantIds = {}
    for _, id in ipairs(ids) do variantIds[#variantIds + 1] = id end
    if hostGeneration == 3 then
      -- Gen3 data has no audio.songs; enumerate the host's song table instead.
      variantIds = {}
      local okSong, Song = pcall(require, "src.core.game3.song_ids")
      if okSong and Song and Song.forVersion then
        local okSongs, songs = pcall(Song.forVersion, activeCacheGame)
        if okSongs and type(songs) == "table" then
          for label in pairs(songs) do
            if tostring(label):match("^MUS_") and versions.byLabel[label] then
              variantIds[#variantIds + 1] = label
            end
          end
        end
      end
      table.sort(variantIds)
    end
    if g4Mix and g4Mix.available and g4Mix.available() and g4Mix.songList then
      local rawSeen = {}
      for _, id in ipairs(variantIds) do rawSeen[id] = true end
      for _, label in ipairs(g4Mix.songList()) do
        local rawName = label:match("^G4:(.+)$")
        if rawName then
          local nativeId = "_" .. rawName:gsub("[^%w]", "_")
          if not rawSeen[nativeId] then
            rawSeen[nativeId] = true
            variantIds[#variantIds + 1] = nativeId
          end
        end
      end
      table.sort(variantIds)
    end
    local hash = settingsHash(settings)
    for _, id in ipairs(ids) do
      if not tostring(id):match("^Music_Improved")
          and not tostring(id):match("^Music_Stock")
          and not tostring(id):match("^Music_Mix")
          and not isG4VariantId(id) then
        local def = isSongData(data) and data.audio.songs[id] or nil
        local shouldProcess = true
        if shouldProcess then
          originalDefs[id] = def
          local cachedDef = nil
          if not force then
            local path = resolveCachePath(id)
            cachedDef = (not force and path) and loadCached(path) or nil
          end
          if settings.enabled ~= false then
            if cachedDef then
              local path = resolveCachePath(id)
              if path then indexGeneratedCachePath(path) end
              local improvedId = registerImproved(id, cachedDef)
              stagedImprovedMap[id] = improvedId
              extraDefs[improvedId] = cachedDef.extra
            else
              queue[#queue + 1] = id
            end
          end
        end
      end
    end
    if mixSongList then
      -- Attach each GBA label to its host-native ID.  Queueing the raw MUS_
      -- label would file Mix records under that key, where playback (which
      -- asks for Music_<Name>) could never find them.
      local mixNative = {}
      local variantSeen = {}
      for _, id in ipairs(variantIds) do variantSeen[id] = true end
      for _, id in ipairs(ids) do
        local group = versions.byLabel[id]
        if group and group.gen3 then mixNative[group.gen3] = id end
      end
      for _, label in ipairs(mixSongList()) do
        local canonical = versions.canonicalGen3Label(label)
        local nativeId = mixNative[canonical]
          or (tostring(canonical):match("^MUS_") and canonical or nil)
        if nativeId and versions.mixAllowed(versions.byLabel[canonical], hostGeneration)
          and not variantSeen[nativeId] then
          variantSeen[nativeId] = true
          variantIds[#variantIds + 1] = nativeId
        end
      end
    end
    do
      local enabledList = enabledListFor()
      for _, id in ipairs(variantIds) do
        if not tostring(id):match("^Music_Improved")
            and not tostring(id):match("^Music_Stock")
            and not tostring(id):match("^Music_Mix")
              and not isG4VariantId(id) then
          for _, candidate in ipairs(candidatesFor(id, settings)) do
            for _, enabled in ipairs(enabledList) do
              if (not candidate.mix and not candidate.g4Mix
                  and not candidate.g4Gb) or enabled then
                local s2 = { enabled = enabled }
                local record = loadVariant(id, candidate, s2)
                if record then
                  local path = resolveCachePath(record.id)
                  if path then indexGeneratedCachePath(path) end
                  extraDefs[record.id] = record.extra
                else
                  local key = tostring(id) .. "|" .. variantKeyFor(id, candidate, enabled)
                  if not queuedVariant[key] then
                    queuedVariant[key] = true
                    queue[#queue + 1] = {
                      kind = "variant",
                      nativeId = id,
                      improvedId = variantIdFor(id, candidate.version, enabled, candidate),
                      version = candidate.version,
                      label = candidate.label,
                      generation = candidate.generation,
                      enabled = enabled,
                      mix = candidate.mix == true,
                      g4Mix = candidate.g4Mix == true,
      g4Gb = candidate.g4Gb == true,
                    }
                  end
                end
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
    optionOverrides[key] = value
  end

  local function clearSongCache()
    local indexedPaths = readCacheIndex()
    if not indexedPaths then return false end

    for _, path in ipairs(indexedPaths) do
      if not deleteCacheFile(path) then return false end
    end

    cacheAliases = {}
    cacheIndexPaths, cacheIndexSet = {}, {}
    cacheIndexReady = true
    if not writeCacheIndex({}) then return false end
    mod.log:info("music_improvement: cleared generated song cache")
    return true
  end

  local startPreparation
  local openGen3Progress
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
    local path = contentCachePath(bytes)
    if cacheFileExists(path) ~= true then
      if not indexGeneratedCachePath(path) then
        mod.log:error("music_improvement: skipping unindexed cached file %s", path)
        return
      end
      local okWrite, result, writeErr = pcall(mod.cache.write, mod.cache, path, bytes)
      if not okWrite or result == false then
        mod.log:error("music_improvement: failed to write cached file %s%s", path,
          okWrite and ": " .. tostring(writeErr) or ": " .. tostring(result))
        return
      elseif cacheFileExists(path) ~= true then
        mod.log:error("music_improvement: cached file is missing after write: %s", path)
        return
      end
    end
    -- Alias this song id to the content-addressed file.
    if cacheAliases[cacheId] ~= path then
      cacheAliases[cacheId] = path
      local aliasBytes = serialize(cacheAliases)
      if type(aliasBytes) == "string" then
        local aliasPath = "songs/aliases.lua"
        if indexGeneratedCachePath(aliasPath) then
          pcall(mod.cache.write, mod.cache, aliasPath, aliasBytes)
        end
      end
    end
    return
  end

  local function prepareVariant(entry, s)
    s = s or settings
    local enabled = entry.enabled
    if enabled == nil then enabled = s.enabled ~= false end
    local ss = { enabled = enabled }
    local translated
    if entry.mix then
      local converted = g3Mix.convert(entry.version, entry.label)
      if not converted then
        mod.log:warn("music_improvement: no G3 mix data for %s (%s)",
          tostring(entry.label), tostring(entry.version))
        return nil
      end
      translated = registerSpec(converted.def, ss, entry.improvedId, converted.extra)
    elseif entry.g4Mix or entry.g4Gb then
      local mode = entry.g4Gb and "chip" or "pcm"
      local converted = g4Mix and g4Mix.convert and
        g4Mix.convert(entry.version, entry.label, mode)
      if not converted then
        mod.log:warn("music_improvement: no G4 data for %s (%s)",
          tostring(entry.label), tostring(entry.version))
        return nil
      end
      translated = registerSpec(converted.def, ss, entry.improvedId, converted.extra)
    else
      local source = sourceFor(entry.version)
      local def = source and source.view.content.music:get(entry.label)
      translated = registerTranslation(def, ss, entry.label,
        source and source.data, entry.improvedId)
    end
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
    local record = rememberVariant(entry.nativeId, entry, translated, entry.improvedId, enabled)
    writeCached(entry.improvedId, translated)
    if record then record.cachePath = resolveCachePath(entry.improvedId) end
    return record
  end

  local function ensureVariant(nativeId, candidate, s)
    local enabled = (s and s.enabled ~= false)
    local record = loadVariant(nativeId, candidate, s)
    if record then return record end
    return prepareVariant({
      kind = "variant",
      nativeId = nativeId,
      improvedId = variantIdFor(nativeId, candidate.version, enabled, candidate),
      version = candidate.version,
      label = candidate.label,
      generation = candidate.generation,
      enabled = enabled,
      mix = candidate.mix == true,
      g4Mix = candidate.g4Mix == true,
      g4Gb = candidate.g4Gb == true,
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
      if state.progressInstance then
        if game and game.stack then
          pcall(game.stack.pop, game.stack)
        else
          local ui = gen3Ui()
          if ui and type(ui.close) == "function" then pcall(ui.close) end
        end
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
      local menu = mod.ui.ListMenu.new(game, "ENHANCE MUSIC?", items, {
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
      menu.g1rMusicScreen = "confirm"
      return menu
    end,
  })

  mod.content.screens:register("MusicImprovementProgress", {
    new = function(game)
      local inst = {
        game = game,
        g1rMusicScreen = "progress",
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
      if not seen[id] and not tostring(id):match("^Music_Mix")
          and not isG4VariantId(id) then
        seen[id] = true; ids[#ids + 1] = id
      end
    end
    local songs = game and game.data and game.data.audio
      and game.data.audio.songs
    if type(songs) == "table" then
      for id in pairs(songs) do
        if not seen[id] and not tostring(id):match("^Music_Mix")
            and not isG4VariantId(id) then
          seen[id] = true; ids[#ids + 1] = id
        end
      end
    end
    table.sort(ids)
    return ids
  end
  mod.exports.musicIds = musicIds

  -- Forward declarations: the jukebox registration and rows hook run before
  -- the helpers below are defined, but their closures execute later.
  local hostIsGen3, openGen3Jukebox, gen3SongIds
  local musicTestEntries, musicTestItems, musicTestPlay

  -- jukebox screen
  mod.content.screens:register("MusicImprovementJukebox", {
    new = function(game)
      local items = musicTestItems(musicTestEntries(game))
      local menu = mod.ui.ListMenu.new(game, musicMenu.title(), items, {
        onChoose = function(item) musicTestPlay(game, item) end,
        onCancel = function()
          require("src.core.Music").stop()
        end,
        footer = omniActive() and "L/R VARIANT\nA PLAY  B BACK"
          or "LEFT/RIGHT VARIANT\nA PLAY B BACK",
        rows = omniActive() and 16 or 6,
      })
      menu.g1rMusicScreen = "jukebox"
      local baseUpdate = menu.update
      menu.update = function(self, dt)
        local input = self.game and self.game.input
        local item = self.items[self.index]
        if input and item and item.entry then
          if input:wasPressed("left") or input:wasPressed("l")
              or input:wasPressed("right") or input:wasPressed("r") then
            local dir = (input:wasPressed("left") or input:wasPressed("l")) and -1 or 1
            local variant = musicMenu.cycle(item.entry, item.versionKey, dir)
            if variant then
              item.variant = variant
              item.versionKey = musicMenu.versionKey(variant)
              item.right = musicMenu.rightText(variant)
              musicTestPlay(game, item)
            end
            return
          end
        end
        return baseUpdate(self, dt)
      end
      if items[1] then musicTestPlay(game, items[1]) end
      return menu
    end,
  })

  local sourceKeys = {
    { "shuffle", "SHUFFLE" },
    { "alt_g1_stock", "G1" },
    { "alt_g1_guided", "G1E" },
    { "alt_g2_stock", "G2" },
    { "alt_g2_guided", "G2E" },
    { "alt_g3_mix", "G3 MIX" },
    { "alt_g4_mix", "G4 MIX" },
    { "alt_g4_gb", "G4 GB" },
    { "alt_g3_native", "G3" },
  }
  local function sourceRight(game, key)
    if key == "alt_g3_native" and not hostIsGen3(game) then return "N/A" end
    if (key == "alt_g4_mix" or key == "alt_g4_gb")
        and (not g4Mix or not g4Mix.available or not g4Mix.available()) then
      return "N/A"
    end
    local value = optionValue(key)
    local off = value == false or tostring(value) == "0"
    -- FRLG font has no bracket glyphs; YES/NO render on every host.
    return off and "NO" or "YES"
  end
  local function sourceItems(game)
    local items = {}
    for _, spec in ipairs(sourceKeys) do
      items[#items + 1] = {
        label = spec[2], right = sourceRight(game, spec[1]), entry = spec[1],
      }
    end
    return items
  end
  local function toggleSource(game, key)
    if key == "alt_g3_native" and not hostIsGen3(game) then return false end
    if (key == "alt_g4_mix" or key == "alt_g4_gb")
        and (not g4Mix or not g4Mix.available or not g4Mix.available()) then
      return false
    end
    local now = optionValue(key)
    local off = now == false or tostring(now) == "0"
    setModOption(game, key, off and "1" or "0")
    return true
  end
  mod.content.screens:register("MusicImprovementSources", {
    new = function(game)
      local menu = mod.ui.ListMenu.new(game, "MUSIC SOURCES", sourceItems(game), {
        onChoose = function() end,
        onCancel = function() end,
        footer = "A TOGGLE\nB DONE",
        rows = omniActive() and 16 or 5,
      })
      menu.g1rMusicScreen = "sources"
      local baseUpdate = menu.update
      menu.update = function(self, dt)
        local input = self.game and self.game.input
        if input and input:wasPressed("a") then
          local item = self.items[self.index]
          if item and item.entry and toggleSource(game, item.entry) then
            self.items = sourceItems(game)
          end
          return
        end
        return baseUpdate(self, dt)
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
          local game = (type(g) == "table" and g.game) or g or readyGame
          local cur = mod.options:get("enabled") ~= false
          setModOption(game, "enabled", not cur)
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
          local game = (type(g) == "table" and g.game) or g or readyGame
          if hostIsGen3(game) then
            openGen3Jukebox(game)
          else
            mod.ui.push(g, "MusicImprovementJukebox")
          end
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
        activate = function(g) regenerateCache((type(g) == "table" and g.game) or g) end,
      },

      {
        -- Gold groups options by id; use an AUDIO member so NDS IMPORT shows
        -- on the same page as other music controls.
        id = "sfxVol",
        musicImprovementId = "music_improvement_nds_import",
        label = "NDS IMPORT",
        value = function()
          local st = ndsImport and ndsImport.status and ndsImport.status() or {}
          if not st.available then return "MISSING" end
          return string.format("READY %d", st.songCount or 0)
        end,
        activate = function(g)
          local game = (type(g) == "table" and g.game) or g or readyGame
          local st = ndsImport and ndsImport.status and ndsImport.status()
          if not st or not st.available then return end
          if g4Mix and g4Mix.refresh then pcall(g4Mix.refresh) end
          regenerateCache(game)
        end,
      },

      {
        id = "musicVol",
        musicImprovementId = "music_improvement_sources",
        label = "MUSIC SOURCES",
        value = function() return "OPEN" end,
        activate = function(g)
          local game = (type(g) == "table" and g.game) or g or readyGame
          if hostIsGen3(game) then
            openGen3Sources(game)
          else
            mod.ui.push(game, "MusicImprovementSources")
          end
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

  local function selectVariantFor(song)
    local settings = currentSettings()
    if not settings.enabled or type(song) ~= "string" then return nil end
    local improved = chooseVariant(song)
    if not improved then
      local fallback = improvedMap[song]
      local record = fallback and recordById[fallback]
      local kind = record and versions.variantKind(record)
        or (fallback and versions.variantKind(fallback))
      if fallback and (not kind or settings.alt[kind] ~= false) then
        improved = fallback
      end
    end
    return improved
  end

  -- playOnce only arms its map-theme restore when the label it passed in
  -- became the current song.  The select hook below rewrites that label, so
  -- the jingle plays but the map theme never comes back.  Give core the
  -- improved label up front instead.
  if okMusic and type(Music.playOnce) == "function" then
    local corePlayOnce = Music.playOnce
    Music.playOnce = function(data, song)
      local improved = selectVariantFor(song)
      if improved and not state.skipped then song = improved end
      return corePlayOnce(data, song)
    end
  end

  -- Gen1/Gen2 cue the same native battle id twice (pre-wipe and battle enter).
  -- Shuffle would otherwise pick a different variant on the second cue, so core
  -- sees a new label and restarts playback. Reuse the choice while it is still
  -- the current song; any real stop/change clears it.
  local lastCueNative
  local lastCueVariant

  mod.hooks:wrap("music.select", function(next, chosen, ctx)
    if mod.options:get("enabled") == false
        and (mod.options:get("source") or "native") == "native" then
      return next(chosen, ctx)
    end
    if state.pending and not state.confirmed then
      return next(chosen, ctx)
    end
    if state.skipped and (mod.options:get("source") or "native") == "native" then
      return next(chosen, ctx)
    end
    -- Core uses "direct" for calls with no context too (title, intro, menus),
    -- so only the jukebox opts out of enhancement explicitly.
    if not ctx or ctx.reason == "jukebox" then
      return next(chosen, ctx)
    end
    if lastCueVariant and chosen == lastCueNative and currentSong == lastCueVariant then
      return next(lastCueVariant, ctx)
    end
    local improved = selectVariantFor(chosen)
    if improved then
      lastCueNative, lastCueVariant = chosen, improved
      return next(improved, ctx)
    end
    lastCueNative, lastCueVariant = nil, nil
    return next(chosen, ctx)
  end)

  startPreparation = function(game)
    if #queue == 0 then
      state.pending = false
      return
    end
    if state.progressPushed then return end
    if game and game.stack then
      state.progressPushed = true
      state.progressInstance = mod.ui.push(game, "MusicImprovementProgress")
    elseif openGen3Progress then
      state.progressPushed = true
      state.progressInstance = openGen3Progress(game)
    end
    if state.progressInstance then
      state.progressInstance.progress = completed
      state.progressInstance.total = total
    end
  end

  -- Gen3 has no game.stack; its option rows and startup prompt go through
  -- gen3_ui.lua (the game3 modal stack) instead of mod.ui.push.
  local gen3UiModule
  gen3Ui = function()
    if gen3UiModule == nil then
      gen3UiModule = loadModFile("gen3_ui.lua") or false
    end
    return gen3UiModule or nil
  end

  openGen3Progress = function(game)
    local ui = gen3Ui()
    if not ui or type(ui.openProgress) ~= "function" then return nil end
    return ui.openProgress(game)
  end

  hostIsGen3 = function(game)
    if not (okGameVersion and GameVersion and GameVersion.generation) then
      return false
    end
    local ids = {
      cacheGameId(game or readyGame),
      activeCacheGame,
      okGameVersion and GameVersion.get and GameVersion.get() or nil,
    }
    for _, id in ipairs(ids) do
      if type(id) == "string" and id ~= "" and id ~= "unknown" then
        local ok, generation = pcall(GameVersion.generation, id)
        if ok and generation == 3 then return true end
      end
    end
    return false
  end

  gen3SongIds = function(game)
    local ids = {}
    local okSong, Song = pcall(require, "src.core.game3.song_ids")
    if not okSong or type(Song) ~= "table" or not Song.forVersion then
      return ids
    end
    local okSongs, songs = pcall(Song.forVersion,
      cacheGameId(game or readyGame))
    if not okSongs or type(songs) ~= "table" then return ids end
    for label in pairs(songs) do
      if tostring(label):match("^MUS_") then
        ids[#ids + 1] = label
      end
    end
    table.sort(ids)
    return ids
  end

  local gen3Audio
  local function audio3()
    if gen3Audio == nil then
      local ok, module = pcall(require, "src.core.game3.audio")
      gen3Audio = (ok and type(module) == "table") and module or false
    end
    return gen3Audio or nil
  end

  local function gen3SongId(label, game)
    local okSong, Song = pcall(require, "src.core.game3.song_ids")
    if not okSong or type(Song) ~= "table" or not Song.forVersion then
      return nil
    end
    local okSongs, songs = pcall(Song.forVersion,
      cacheGameId(game or readyGame))
    if okSongs and type(songs) == "table" then return songs[label] end
    return nil
  end

  -- Music test entries: mapped groups first, then unmapped native songs.
  musicTestEntries = function(game)
    local hostVersion = cacheGameId(game or readyGame)
    local hostGen = 1
    if okGameVersion and GameVersion and GameVersion.generation then
      hostGen = GameVersion.generation(hostVersion) or hostGen
    end
    local entries, seen = {}, {}
    local function baseImprovedVariant(id, generation)
      local baseId = improvedIdFor(id)
      local songs = game and game.data and game.data.audio
        and game.data.audio.songs
      if improvedMap[id] == baseId
          or stagedImprovedMap[id] == baseId
          or (type(songs) == "table" and songs[baseId] ~= nil) then
        return {
          id = baseId,
          improved = true,
          generation = generation,
          base = true,
        }
      end
      return nil
    end
    local function add(entry)
      if seen[entry.nativeId] then return end
      seen[entry.nativeId] = true
      local rank = {}
      for index, item in ipairs(versions.MENU_KINDS) do rank[item.key] = index end
      table.sort(entry.variants, function(a, b)
        local ak, bk = versions.variantKind(a), versions.variantKind(b)
        local ar, br = rank[ak] or 99, rank[bk] or 99
        if ar ~= br then return ar < br end
        return tostring(a.version or "") < tostring(b.version or "")
      end)
      entries[#entries + 1] = entry
    end
    for _, group in ipairs(versions.EQUIVALENTS) do
      local label = group["gen" .. hostGen]
      local allowed = true
      if group.hosts then
        allowed = false
        for _, host in ipairs(group.hosts) do
          if host == hostVersion then allowed = true break end
        end
      end
      if label and allowed then
        local variants = { { native = true, generation = hostGen, improved = false } }
        local base = baseImprovedVariant(label, hostGen)
        if base then variants[#variants + 1] = base end
        local records = {}
        for _, record in ipairs(variantMap[label] or {}) do
          records[#records + 1] = record
        end
        table.sort(records, function(a, b)
          if a.generation ~= b.generation then
            return a.generation < b.generation
          end
          if a.version ~= b.version then
            return tostring(a.version) < tostring(b.version)
          end
          return (not a.improved) and b.improved or false
        end)
        local seenContent = {}
        for _, record in ipairs(records) do
          if not (hostGen ~= 3 and record.generation == 3
              and not record.mix and not record.g4Mix and not record.g4Gb) then
            local contentKey = record.cachePath or record.id
            if contentKey and seenContent[contentKey] then
              -- Skip an identical translation already represented by another version.
            else
              if contentKey then seenContent[contentKey] = true end
              variants[#variants + 1] = {
                candidate = record.candidate,
                improved = record.improved,
                mix = record.mix,
                g4Mix = record.g4Mix,
                g4Gb = record.g4Gb,
                generation = record.generation,
                version = record.version,
                id = record.id,
              }
            end
          end
        end
        add({
          name = group.name or versions.pretty(label),
          nativeId = label,
          variants = variants,
        })
      end
    end
    local natives = hostGen == 3 and gen3SongIds(game) or musicIds(game)
    for _, id in ipairs(natives) do
      if not versions.byLabel[id]
          and not tostring(id):match("^Music_Improved")
          and not tostring(id):match("^Music_Stock")
          and not isG4VariantId(id) then
        local variants = { { native = true, generation = hostGen, improved = false } }
        local base = baseImprovedVariant(id, hostGen)
        if base then variants[#variants + 1] = base end
        add({
          name = versions.pretty(id),
          nativeId = id,
          variants = variants,
        })
      end
    end
    for _, label in ipairs(mixSongList()) do
      local canonical = versions.canonicalGen3Label(label)
      local group = versions.byLabel[canonical]
      local nativeId = (group and group["gen" .. hostGen]) or canonical
      if versions.mixAllowed(group, hostGen) and not seen[nativeId] then
        local variants = {}
        for _, record in ipairs(variantMap[nativeId] or {}) do
          if record.mix and record.id then
            variants[#variants + 1] = {
              candidate = record.candidate,
              mix = true, improved = true,
              generation = 3, version = record.version, id = record.id,
            }
          end
        end
        if #variants == 0 then
          for _, candidate in ipairs(mixCandidatesFor(canonical)) do
            variants[#variants + 1] = {
              candidate = candidate, mix = true, improved = true,
              generation = 3, version = candidate.version,
            }
          end
        end
        if #variants > 0 then
          add({
            name = versions.nameFor(label),
            nativeId = nativeId,
            variants = variants,
          })
        end
      end
    end
    if g4Mix and g4Mix.available and g4Mix.available() and g4Mix.songList then
      local g4Seen = {}
      local songIds = hostGen == 3 and gen3SongIds(game) or nil
      local carrierId = songIds and next(songIds) and songIds[next(songIds)] or nil
      for _, label in ipairs(g4Mix.songList()) do
        local rawName = label:match("^G4:(.+)$")
        if rawName then
          local nativeId = "_" .. rawName:gsub("[^%w]", "_")
          if not g4Seen[nativeId] then
            local candidate = {
              version = activeCacheGame, generation = hostGen,
              label = label, g4Mix = true,
            }
            local variants = {}
            for _, record in ipairs(variantMap[nativeId] or {}) do
              if (record.g4Mix or record.g4Gb) and record.id then
                variants[#variants + 1] = {
                  candidate = record.candidate,
                  g4Mix = record.g4Mix == true, g4Gb = record.g4Gb == true,
                  improved = true,
                  generation = record.generation or hostGen,
                  version = record.version, id = record.id,
                }
              end
            end
            if #variants == 0 then
              variants[1] = {
                candidate = candidate, g4Mix = true, improved = true,
                generation = hostGen, version = activeCacheGame,
              }
              local chipCandidate = {}
              for k, v in pairs(candidate) do chipCandidate[k] = v end
              chipCandidate.g4Mix, chipCandidate.g4Gb = nil, true
              variants[2] = {
                candidate = chipCandidate, g4Gb = true, improved = true,
                generation = hostGen, version = activeCacheGame,
              }
            end
            g4Seen[nativeId] = true
            add({
              name = rawName .. " (G4)",
              nativeId = nativeId, playId = carrierId,
              variants = variants,
            })
          end
        else
        local canonical = versions.canonicalGen3Label(label)
        local group = versions.byLabel[canonical]
        local nativeId = (group and group["gen" .. hostGen]) or canonical
        if versions.mixAllowed(group, hostGen) and not g4Seen[nativeId] then
          local variants = {}
          for _, record in ipairs(variantMap[nativeId] or {}) do
            if (record.g4Mix or record.g4Gb) and record.id then
              variants[#variants + 1] = {
                candidate = record.candidate,
                g4Mix = record.g4Mix == true, g4Gb = record.g4Gb == true,
                improved = true,
                generation = record.generation or 3,
                version = record.version, id = record.id,
              }
            end
          end
          if #variants == 0 then
            for _, candidate in ipairs(g4CandidatesFor(nativeId, hostGen, group)) do
              variants[#variants + 1] = {
                candidate = candidate,
                g4Mix = candidate.g4Mix == true, g4Gb = candidate.g4Gb == true,
                improved = true,
                generation = candidate.generation or 3,
                version = candidate.version,
              }
            end
          end
          if #variants > 0 then
            g4Seen[nativeId] = true
            add({
              name = versions.nameFor(label) .. " (G4)",
              nativeId = nativeId,
              variants = variants,
            })
          end
        end
        end
      end
    end
    table.sort(entries, function(a, b)
      return a.name:lower() < b.name:lower()
    end)
    return entries
  end

  musicTestItems = function(entries)
    local items = {}
    for _, entry in ipairs(entries) do
      local initialKey = entry.variants[1] and musicMenu.versionKey(entry.variants[1]) or ""
      local variant = musicMenu.select(entry, initialKey)
        or entry.variants[1]
      items[#items + 1] = {
        label = entry.name,
        entry = entry,
        variant = variant,
        versionKey = musicMenu.versionKey(variant),
        right = musicMenu.rightText(variant),
      }
    end
    return items
  end

  musicTestPlay = function(game, item)
    if not (item and item.entry and item.variant) then return end
    local entry, variant = item.entry, item.variant
    if hostIsGen3(game) then
      local A = audio3()
      local numeric = gen3SongId(entry.playId or entry.nativeId, game)
      if not (A and A.playSong and numeric) then return end
      if variant.native then
        pcall(A.playSong, numeric, { forceNative = true })
      else
        pcall(A.playSong, numeric, {
          forceVariant = {
            candidate = variant.candidate, improved = variant.improved,
            nativeId = entry.nativeId,
          },
        })
      end
      return
    end
    local id = variant.id or entry.nativeId
    local target = okMusic and Music or require("src.core.Music")
    pcall(target.play, game.data, id, true, { reason = "jukebox" })
  end

  openGen3Sources = function(game)
    local ui = gen3Ui()
    if not ui then return false end
    local items = sourceItems(game)
    return ui.openList(game, {
      screenKind = "sources",
      title = "MUSIC SOURCES",
      items = items,
      visible = omniActive() and 16 or nil,
      stayOpen = true,
      hint = { "A TOGGLE  B BACK" },
      onChoose = function(item)
        if item and item.entry and toggleSource(game, item.entry) then
          item.right = sourceRight(game, item.entry)
        end
      end,
      onCancel = function() end,
    })
  end

  openGen3Jukebox = function(game)
    local ui = gen3Ui()
    if not ui then return false end
    local items = musicTestItems(musicTestEntries(game))
    if #items == 0 then
      items[1] = { label = "(NO SONGS)" }
    end
    local menu
    menu = ui.openList(game, {
      screenKind = "jukebox",
      title = musicMenu.title(),
      items = items,
      visible = omniActive() and 16 or nil,
      stayOpen = true,
      hint = omniActive()
        and { "L/R VARIANT", "A PLAY  B BACK" }
        or { "LEFT/RIGHT VARIANT", "A PLAY  B BACK" },
      onChoose = function(item) musicTestPlay(game, item) end,
      onCycle = function(item, dir)
        local variant = musicMenu.cycle(item.entry, item.versionKey, dir)
        if variant then
          item.variant = variant
          item.versionKey = musicMenu.versionKey(variant)
          item.right = musicMenu.rightText(variant)
          musicTestPlay(game, item)
        end
      end,
      onCancel = function()
        local A = audio3()
        if A and A.stopAll then pcall(A.stopAll) end
      end,
    })
    if menu and items[1] and items[1].entry then
      musicTestPlay(game, items[1])
    end
    return menu
  end

  local function openGen3Confirm(game)
    local ui = gen3Ui()
    if not ui then return false end
    return ui.openList(game, {
      screenKind = "confirm",
      title = "ENHANCE MUSIC?",
      items = { { label = "YES", value = true }, { label = "NO", value = false } },
      onChoose = function(item)
        if item.value then
          state.confirmed = true
          setModOption(game, "enabled", true)
          if #queue > 0 then startPreparation(game) end
        else
          state.skipped = true
          state.pending = false
        end
      end,
      onCancel = function()
        state.skipped = true
        state.pending = false
      end,
    })
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
    pcall(ChipAudio.setChannelVolumes, { 1, 1, 1, 1 })
  end
  mod.events:on("music.started", function(payload)
    local song = payload and payload.song
    currentSong = song
    if song ~= lastCueVariant then
      lastCueNative, lastCueVariant = nil, nil
    end
    currentReason = payload and payload.reason
    currentImproved = (type(song) == "string" and song:match("^Music_Improved") ~= nil)
    suppressExtra = false
    cpuEma = 0
    cpuOverSince = nil
    if extraAudio then
      pcall(extraAudio.stop)
      local extra = song and extraDefs[song]
      local enhancementActive = (mod.options:get("enabled") ~= false
          or currentReason == "jukebox")
        and not state.skipped and not suppressExtra
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
    if song then showToast(song) end
  end)
  mod.events:on("music.stopped", function()
    currentImproved = false
    lastCueNative, lastCueVariant = nil, nil
    currentSong = nil
    currentReason = nil
    pendingExtra = nil
    if extraAudio then pcall(extraAudio.stop) end
    if gbaExtraAudio then pcall(gbaExtraAudio.stop) end
    pcall(applyChannelMix)
  end)

  mod.hooks:wrap("music.volume", function(next, vol, ctx)
    local out = next(vol, ctx)
    if extraAudio then
      pcall(extraAudio.setMusicVolume, tonumber(out) or vol)
      pcall(extraAudio.setBaseVolume, tonumber(out) or vol)
    end
    if gbaExtraAudio then
      pcall(gbaExtraAudio.setMusicVolume, tonumber(out) or vol)
      pcall(gbaExtraAudio.setBaseVolume, tonumber(out) or vol)
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
  mod.hooks:wrap("render.hud", function(next, game, viewport)
    if type(next) == "function" then pcall(next, game, viewport) end
    if not toast.text or (toast.until_ or 0) < os.clock() then return end
    local w, h = viewport and viewport.width, viewport and viewport.height
    if omniUi and omniActive() and omniUi.drawToast then
      local ok, drawn = pcall(omniUi.drawToast, toast.text, w, h)
      if ok and drawn then return end
    end
    if type(love) ~= "table" or type(love.graphics) ~= "table" then return end
    w = w or love.graphics.getWidth()
    h = h or love.graphics.getHeight()
    local x, y = 8, 8
    love.graphics.push("all")
    local font = love.graphics.getFont()
    local textWidth = font and font:getWidth(toast.text) or (#toast.text * 6)
    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.rectangle("fill", x, y, textWidth + 12, 20)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(toast.text, x + 6, y + 4)
    love.graphics.pop()
  end, 101)

  mod.events:on("game.ready", function(payload)
    local game = payload and (payload.game or payload)
    if type(game) ~= "table" then return end
    readyGame = game
    settings = currentSettings()
    buildQueue(settings, false, game)
    -- One-line boot trace: makes "G3 Mix missing" diagnosable without a debugger.
    pcall(function()
      local mixVersions = g3Mix.availableVersions(versions)
      local first = mixVersions[1]
      local songCount = first and #g3Mix.songList(first) or 0
      local candidateCount = #mixCandidatesFor("MUS_PALLET")
      local queued, records = 0, 0
      for _, entry in ipairs(queue) do
        if entry.kind == "variant" and entry.mix then queued = queued + 1 end
      end
      for _, list in pairs(variantMap) do
        for _, record in ipairs(list) do
          if record.mix then records = records + 1 end
        end
      end
      local dataPath = g3Mix.lastPath and first
        and g3Mix.lastPath[first .. ":index.lua"] or "none"
      mod.log:info(
        "[g1r_music_improvement] g3 mix: versions=%d songs=%d candidates=%d queued=%d records=%d data=%s host3=%s cache=%s pending=%s queue=%d error=%s",
        #mixVersions, songCount, candidateCount, queued, records, dataPath,
        tostring(hostIsGen3(game)), activeCacheGame, tostring(state.pending),
        #queue, tostring(g3Mix.lastError or "-"))
    end)
    local generation = hostIsGen3(game) and 3 or 1
    if generation == 3 then
      local host = loadModFile("gen3.lua")
      if host and type(host.install) == "function" then
        local extra = gbaExtraAudio or extraAudio or {
          start = function() end, stop = function() end,
          setMusicVolume = function() end, setBaseVolume = function() end,
          update = function() end, setExtraMix = function() end,
        }
        host.install({
          versions = versions,
          currentSettings = currentSettings,
          candidatesFor = candidatesFor,
          ensureVariant = ensureVariant,
          loadVariant = loadVariant,
          enabledListFor = enabledListFor,
          extraAudio = extra,
          toast = showToast,
          debug = function(message)
            pcall(mod.log.info, mod.log, "gen3: %s", tostring(message))
          end,
          isQuestLog = function() return readyGame ~= nil and readyGame.phase == "quest_log" end,
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
          and not state.confirmPushed then
        if self.stack then
          state.confirmPushed = true
          state.confirmInstance = mod.ui.push(self, "MusicImprovementConfirm")
        elseif hostIsGen3(self) and self.phase == "field" then
          -- FireRed boots into intro/title/recap first; its modal cannot take
          -- input until the field owns it, so wait for that phase.
          state.confirmPushed = true
          openGen3Confirm(self)
        end
      end
      local result = nextUpdate(self, dt)
      if state.pending and state.confirmed and not state.skipped then prepareOne(self) end
      frameGuard(dt)
      -- Base audio starts inside nextUpdate (Music.update -> ChipAudio.update).
      -- Start harmony after it, in the same frame, instead of one frame late.
      if gbaExtraAudio and hostIsGen3(self) then
        pcall(gbaExtraAudio.setExtraMix, mod.options:get("extra_mix"))
      end
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