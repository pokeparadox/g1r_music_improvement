-- Realtime extra harmony stream rendered alongside the base chip song.
return function()
  local okCS, ChipSynth = pcall(require, "src.core.ChipSynth")
  local okCA, ChipAudio = pcall(require, "src.core.ChipAudio")
  if not okCS or type(ChipSynth) ~= "table" then return nil end

  local SAMPLE_RATE = ChipSynth.SAMPLE_RATE or 44100
  local function clock()
    if love and love.timer and type(love.timer.getTime) == "function" then
      local ok, t = pcall(love.timer.getTime)
      if ok and type(t) == "number" then return t end
    end
    return os.clock()
  end

  local BUFFER_COUNT = 16
  local LEAD_LOOP = 8192
  local LEAD_ONCE = 2048
  local DRIFT_TOL = math.floor(SAMPLE_RATE * 0.12)
  local MAX_SKIP = math.floor(SAMPLE_RATE * 2)
  local MAX_RESYNCS = 3
  local RESYNC_WINDOW = 30

  local state = {
    engines = {},
    pcms = {},
    sampleReader = nil,
    envelopes = {},
    pans = {},
    gains = {},
    sideEnabled = { left = true, center = true, right = true },
    source = nil,
    extraGain = 0.35,
    musicVolume = 1.0,
    chunk = 512,
    lpfAlpha = 0.04,
    baseElapsed = 0,
    baseLastClock = 0,
    baseWasPlaying = false,
    extraRendered = 0,
    lead = LEAD_LOOP,
    bufferCount = BUFFER_COUNT,
    pendingBuffer = nil,
    pendingSamples = 0,
    baseVolumeRef = nil,
    fadeScale = 1,
    paused = false,
    resyncCount = 0,
    resyncSince = 0,
    givenUp = false,
    profile = "gb",
    maxEngines = nil,
  }

  local function engineKeys()
    local numeric = {}
    local named = {}
    local legacy = { left = true, center = true, right = true }
    local others = {}
    for key in pairs(state.engines) do
      if type(key) == "number" then
        numeric[#numeric + 1] = key
      elseif not legacy[key] then
        others[#others + 1] = key
      end
    end
    table.sort(numeric)
    table.sort(others)
    for _, key in ipairs(numeric) do named[#named + 1] = key end
    for _, key in ipairs({ "left", "center", "right" }) do
      if state.engines[key] then named[#named + 1] = key end
    end
    for _, key in ipairs(others) do named[#named + 1] = key end
    return named
  end

  local function songSides(song)
    local numeric = {}
    local named = {}
    local others = {}
    for side, sideSong in pairs(song) do
      if type(sideSong) == "table" and type(sideSong.chip) == "table" then
        if type(side) == "number" then
          numeric[#numeric + 1] = side
        elseif side ~= "left" and side ~= "center" and side ~= "right" then
          others[#others + 1] = side
        end
      end
    end
    table.sort(numeric)
    table.sort(others)
    for _, side in ipairs(numeric) do named[#named + 1] = side end
    for _, side in ipairs({ "left", "center", "right" }) do
      local sideSong = song[side]
      if type(sideSong) == "table" and type(sideSong.chip) == "table" then
        named[#named + 1] = side
      end
    end
    for _, side in ipairs(others) do named[#named + 1] = side end
    return named
  end

  local function sampleEnvelope(envelope, t)
    if type(envelope) ~= "table" or #envelope == 0 then return 1.0 end
    local g = envelope[1].g
    if g == nil then g = 1.0 end
    for i = 1, #envelope do
      local e = envelope[i]
      if (e.t or 0) <= t then
        g = e.g
        if g == nil then g = 1.0 end
      else
        break
      end
    end
    return g
  end

  -- ChipSynth advances 0.4 * M4A tempo seq ticks per second; convert those
  -- ticks to output samples so PCM voices stay locked to chip events.
  local MAX_PCM_VOICES = 16
  -- PCM is rendered on the same bus as the extra chip voices; full-level GBA
  -- samples mask the chip layer. Keep samples under the chip by default.
  -- ponytail: fixed ceiling, add a profile knob only if FR sample level needs tuning.
  local PCM_GAIN = 0.6

  local function pcmSample(data, frame)
    local index = frame * 2 + 1
    if index < 1 or index + 1 > #data then return 0 end
    local lo, hi = data:byte(index), data:byte(index + 1)
    local value = lo + hi * 256
    if value >= 32768 then value = value - 65536 end
    return value / 32768
  end

  local function pcmTickToSample(timeline, tick)
    local done, samples = 0, 0
    for i = 1, #timeline do
      local current = timeline[i]
      local nextTick = timeline[i + 1] and timeline[i + 1].tick or tick
      local untilTick = math.min(tick, nextTick)
      if untilTick > done then
        -- G4 PCM carries gb, the integer tempo byte actually used by the
        -- chip channel. Render on that grid or long tracks drift against the
        -- beeps. G3 scores have no gb and keep the exact score rate.
        if tonumber(current.gb) then
          samples = samples + (untilTick - done) * SAMPLE_RATE
            * math.max(1, current.gb) / 15360
        else
          samples = samples + (untilTick - done) * SAMPLE_RATE * 2.5
            / math.max(1, current.tempo or 300)
        end
        done = untilTick
      end
      if done >= tick then break end
    end
    return math.floor(samples + 0.5)
  end

  local function pcmSeek(pcm, pos)
    if not pcm then return end
    pcm.pos = pos
    pcm.active = {}
    pcm.cycle = 0
    local first = 1
    local target = pos
    if pcm.loopSamples and pcm.loopSamples > 0
        and pos >= (pcm.loopEndSamples or 0) then
      local start = pcm.loopStartSamples or 0
      pcm.cycle = math.floor((pos - start) / pcm.loopSamples)
      target = start + (pos - start) % pcm.loopSamples
      first = pcm.firstLoopEvent or 1
    end
    pcm.nextEvent = first
    for index = first, #pcm.events do
      if pcm.events[index].at >= target then pcm.nextEvent = index break end
    end
  end

  local function chipGainFor(songGain, gain, hasPcm)
    if not hasPcm then return gain end
    return math.min(1, gain * math.max(1, 0.8 / math.max(0.01, songGain)))
  end

  local function pcmPrepare(side, sideSong)
    local pcm = sideSong.pcm
    if type(pcm) ~= "table" or type(pcm.events) ~= "table" or #pcm.events == 0
        or type(state.sampleReader) ~= "function" then return nil end
    local timeline = type(pcm.tempoTimeline) == "table" and pcm.tempoTimeline
      or { { tick = 0, tempo = 300 } }
    if (timeline[1] or {}).tick ~= 0 then
      local copy = { { tick = 0, tempo = timeline[1].tempo or 300 } }
      for _, entry in ipairs(timeline) do copy[#copy + 1] = entry end
      timeline = copy
    end
    local events, samples = {}, {}
    for _, event in ipairs(pcm.events) do
      local gba = type(event.bank) == "table" and event.bank.gba
      local key = gba
        and ("gba:" .. tostring(event.bank.version) .. ":"
          .. tostring(event.bank.sampleId))
        or (tostring(event.bank) .. ":" .. tostring(event.archive) .. ":"
          .. tostring(event.wave))
      local sample = samples[key]
      if sample == nil then
        local readerDef = gba and event.bank or {
          waveArchiveID = event.archive, waveID_dutyCycle = event.wave,
        }
        local ok, resolved = pcall(state.sampleReader, event.bank, readerDef)
        if ok and type(resolved) == "table" and type(resolved.data) == "string"
            and #resolved.data >= 4 then
          sample = resolved
        else
          sample = false
        end
        samples[key] = sample
      end
      if sample then
        local at = pcmTickToSample(timeline, event.tick)
        local gateEnd = pcmTickToSample(timeline, event.tick + (event.gate or 1))
        events[#events + 1] = {
          at = at, gateSamples = math.max(1, gateEnd - at),
          key = tonumber(event.key) or 60, pitch = tonumber(event.pitch) or 60,
          rateHz = tonumber(event.rateHz),
          gainScale = math.max(0.1, tonumber(event.gainScale) or 1),
          vel = math.max(1, math.min(127, tonumber(event.vel) or 100)),
          volume = math.max(1, math.min(127, tonumber(event.volume) or 100)),
          pan = tonumber(event.pan) or 0x40,
          sample = sample,
        }
      end
    end
    if #events == 0 then return nil end
    table.sort(events, function(a, b) return a.at < b.at end)
    local built = {
      events = events, active = {}, pos = 0, nextEvent = 1, cycle = 0,
      looping = true,
    }
    local loopStartTick = tonumber(pcm.loopStartTick) or 0
    local loopEndTick = tonumber(pcm.loopEndTick)
      or tonumber(pcm.loopTick) or 0
    built.loopStartSamples = pcmTickToSample(timeline, loopStartTick)
    built.loopEndSamples = pcmTickToSample(timeline, loopEndTick)
    built.loopSamples = math.max(0,
      built.loopEndSamples - built.loopStartSamples)
    built.firstLoopEvent = 1
    if built.loopSamples > 0 then
      for index, event in ipairs(events) do
        if event.at >= built.loopStartSamples then
          built.firstLoopEvent = index
          break
        end
      end
    end
    pcmSeek(built, 0)
    return built
  end

  local function pcmRender(pcm, leftMix, rightMix, start, count, baseGain)
    if not pcm or #pcm.active == 0 and pcm.nextEvent > #pcm.events
        and pcm.loopSamples == 0 then return end
    local last = start + count
    while true do
      local event = pcm.events[pcm.nextEvent]
      if not event and pcm.loopSamples > 0 then
        pcm.cycle = pcm.cycle + 1
        pcm.nextEvent = pcm.firstLoopEvent or 1
        event = pcm.events[pcm.nextEvent]
      end
      if not event then break end
      local at = event.at + pcm.cycle * pcm.loopSamples
      if at > last then break end
      if at >= start and #pcm.active < MAX_PCM_VOICES then
        local data = event.sample.data
        local frames = math.floor(#data / 2)
        local rate = tonumber(event.sample.sampleRate) or SAMPLE_RATE
        if rate < 1000 then rate = SAMPLE_RATE end
        local loopStart = math.max(0, math.floor(tonumber(event.sample.loopStart) or 0))
        local loopEnd = math.floor(tonumber(event.sample.loopEnd) or frames - 1)
        if loopEnd > frames - 1 then loopEnd = frames - 1 end
        if loopStart > frames - 1 then loopStart = frames - 1 end
        local hasLoop = event.sample.loop and loopEnd > loopStart
        if not hasLoop then loopStart = 0 end
        local ratio = event.rateHz and event.rateHz > 0
          and event.rateHz / SAMPLE_RATE
          or (rate / SAMPLE_RATE * 2 ^ ((event.key - event.pitch) / 12))
        local pan = math.max(-1, math.min(1, (event.pan - 0x40) / 0x80))
        pcm.active[#pcm.active + 1] = {
          data = data, phase = 0, loopStart = loopStart,
          endFrame = hasLoop and loopEnd or frames - 1,
          loop = hasLoop and true or false,
          step = ratio, start = at,
          stop = at + event.gateSamples + math.floor(SAMPLE_RATE * 0.08),
          gateEnd = at + event.gateSamples,
          gain = baseGain * PCM_GAIN * event.gainScale
            * math.sqrt((event.vel / 127) * (event.volume / 127)),
          leftGain = 0.5 + 0.25 * (1 - pan),
          rightGain = 0.5 + 0.25 * (1 + pan),
        }
      end
      pcm.nextEvent = pcm.nextEvent + 1
    end
    for i = 0, count - 1 do
      local sampleIndex = start + i
      local mixedL, mixedR = 0, 0
      for v = #pcm.active, 1, -1 do
        local voice = pcm.active[v]
        if sampleIndex >= voice.stop or sampleIndex < pcm.pos then
          table.remove(pcm.active, v)
        elseif sampleIndex >= voice.start then
          local elapsed = (sampleIndex - voice.start) / SAMPLE_RATE
          local attack, decay, sustain = 0.006, 0.04, 0.65
          local env
          if elapsed < attack then
            env = elapsed / attack
          elseif elapsed < attack + decay then
            env = 1 - (1 - sustain) * (elapsed - attack) / decay
          elseif sampleIndex < voice.gateEnd then
            env = sustain
          else
            env = sustain * math.max(0, 1
              - (sampleIndex - voice.gateEnd) / (SAMPLE_RATE * 0.08))
          end
          local frame = math.floor(voice.phase)
          local value = pcmSample(voice.data, frame)
          local frac = voice.phase - frame
          if frac > 0 then
            value = value * (1 - frac) + pcmSample(voice.data, frame + 1) * frac
          end
          voice.phase = voice.phase + voice.step
          if voice.phase >= voice.endFrame then
            if voice.loop then
              voice.phase = voice.loopStart + (voice.phase - voice.endFrame)
            else
              voice.phase = voice.endFrame - 1
            end
          end
          local amplified = value * env * voice.gain
          mixedL = mixedL + amplified * voice.leftGain
          mixedR = mixedR + amplified * voice.rightGain
        end
      end
      leftMix[i] = leftMix[i] + mixedL
      rightMix[i] = rightMix[i] + mixedR
    end
    pcm.pos = last
  end

  local function isPlaying(src)
    if not src then return false end
    local ok, playing = pcall(src.isPlaying, src)
    return ok and playing
  end

  local function stop()
    if state.source then pcall(state.source.stop, state.source) end
    state.source = nil
    state.engines = {}
    state.pcms = {}
    state.envelopes = {}
    state.pans = {}
    state.gains = {}
    state.extraRendered = 0
    state.baseElapsed = 0
    state.baseLastClock = 0
    state.baseWasPlaying = false
    state.pendingBuffer = nil
    state.pendingSamples = 0
    state.paused = false
    state.resyncCount = 0
    state.resyncSince = 0
    state.givenUp = false
  end

  local function currentBaseSource()
    if okCA and type(ChipAudio.currentSource) == "function" then
      local ok, source = pcall(ChipAudio.currentSource)
      if ok then return source end
    end
    return nil
  end

  -- Queueable Source:tell() only reports the position inside the buffer that
  -- is playing right now, not the song cursor. Use the wall clock while the
  -- base source plays instead; its worker queue keeps running through stalls.

  -- Samples already consumed by the audio device. QueueableSource exposes
  -- free slots, not a play cursor, so derive it from what we queued.
  local function sourcePlayed()
    if not state.source then return state.extraRendered end
    local okFree, free = pcall(state.source.getFreeBufferCount, state.source)
    if not okFree or type(free) ~= "number" then return state.extraRendered end
    local capacity = state.bufferCount or BUFFER_COUNT
    local queued = math.max(0, math.min(capacity, capacity - free))
    return state.extraRendered - queued * state.chunk
  end

  local function queuePending()
    if not state.source or not state.pendingBuffer then return false end
    local okFree, free = pcall(state.source.getFreeBufferCount, state.source)
    if not okFree or type(free) ~= "number" or free < 1 then return false end
    local okQueue, result =
      pcall(state.source.queue, state.source, state.pendingBuffer)
    if not okQueue or result == false then return false end
    state.pendingBuffer = nil
    state.extraRendered = state.extraRendered + state.pendingSamples
    state.pendingSamples = 0
    return true
  end

  local function renderChunk()
    if not state.source then return false end
    if next(state.engines) == nil then return false end

    if state.pendingBuffer then return queuePending() end
    local okFree, free = pcall(state.source.getFreeBufferCount, state.source)
    if not okFree or type(free) ~= "number" or free < 1 then return false end

    local chunk = state.chunk
    local leftMix = {}
    local rightMix = {}
    for i = 0, chunk - 1 do leftMix[i] = 0; rightMix[i] = 0 end

    local chunkStart = state.extraRendered
    for index, side in ipairs(engineKeys()) do
      if state.maxEngines and index > state.maxEngines then break end
      local engine = state.engines[side]
      local env = state.envelopes and state.envelopes[side]
      local dynGain = sampleEnvelope(env, chunkStart / SAMPLE_RATE)
      if state.sideEnabled[side] == false then dynGain = 0 end
      local pan = state.pans[side] or 0
      local leftGain = 0.5 + 0.25 * (1 - pan)
      local rightGain = 0.5 + 0.25 * (1 + pan)
      local songGain = state.gains[side] or 1
      local gain = state.extraGain * state.musicVolume * dynGain * songGain
      -- Converter balance can push a PCM carrier's chip side down to gain
      -- 0.35.  Samples share this bus; keep the chip layer audible instead of
      -- letting DirectSound bury it.
      local chipGain = chipGainFor(songGain, gain, state.pcms[side] ~= nil)
      local okSd, sd = false, nil
      if engine then
        okSd, sd = pcall(ChipSynth.soundData, engine, chunk, 1)
      end
      if okSd and sd and dynGain > 0 then
        local ptr = nil
        if ChipSynth._int16Pointer then
          local okPtr, p = pcall(ChipSynth._int16Pointer, sd)
          if okPtr then ptr = p end
        end
        for i = 0, chunk - 1 do
          local sample = 0
          if ptr then
            sample = ptr[i] / 32767
          else
            local okSample, v = pcall(sd.getSample, sd, i)
            if okSample then sample = v or 0 end
          end
          leftMix[i] = leftMix[i] + sample * chipGain * leftGain
          rightMix[i] = rightMix[i] + sample * chipGain * rightGain
        end
      end
      local pcm = state.pcms[side]
      if pcm and dynGain > 0 then
        pcmRender(pcm, leftMix, rightMix, chunkStart, chunk, gain)
      end
    end

    local channels = state.channels or 2
    local out = ChipSynth.newBuffer(chunk, channels)
    local outPtr = nil
    if ChipSynth._int16Pointer then
      local okPtr, p = pcall(ChipSynth._int16Pointer, out)
      if okPtr then outPtr = p end
    end
    for i = 0, chunk - 1 do
      local fl = leftMix[i]
      local fr = rightMix[i]
      if fl > 1 then fl = 1 elseif fl < -1 then fl = -1 end
      if fr > 1 then fr = 1 elseif fr < -1 then fr = -1 end
      if channels >= 6 then
        local center = (fl + fr) * 0.5
        local rearL = fl * 0.9
        local rearR = fr * 0.9
        local lfeIn = (fl + fr) * 0.5
        state.lpfState = state.lpfState + state.lpfAlpha * (lfeIn - state.lpfState)
        local lfe = state.lpfState * 0.7
        if center > 1 then center = 1 elseif center < -1 then center = -1 end
        if rearL > 1 then rearL = 1 elseif rearL < -1 then rearL = -1 end
        if rearR > 1 then rearR = 1 elseif rearR < -1 then rearR = -1 end
        if lfe > 1 then lfe = 1 elseif lfe < -1 then lfe = -1 end
        if outPtr then
          outPtr[i * 6 + 0] = fl * 32767
          outPtr[i * 6 + 1] = fr * 32767
          outPtr[i * 6 + 2] = center * 32767
          outPtr[i * 6 + 3] = lfe * 32767
          outPtr[i * 6 + 4] = rearL * 32767
          outPtr[i * 6 + 5] = rearR * 32767
        else
          pcall(out.setSample, out, i, 1, fl)
          pcall(out.setSample, out, i, 2, fr)
          pcall(out.setSample, out, i, 3, center)
          pcall(out.setSample, out, i, 4, lfe)
          pcall(out.setSample, out, i, 5, rearL)
          pcall(out.setSample, out, i, 6, rearR)
        end
      else
        if outPtr then
          outPtr[i * 2] = fl * 32767
          outPtr[i * 2 + 1] = fr * 32767
        else
          pcall(out.setSample, out, i, 1, fl)
          pcall(out.setSample, out, i, 2, fr)
        end
      end
    end
    state.pendingBuffer = out
    state.pendingSamples = chunk
    return queuePending()
  end

  local function newExtraSource()
    local buffers = state.bufferCount or BUFFER_COUNT
    local ok6, src6 = pcall(love.audio.newQueueableSource,
                            ChipSynth.SAMPLE_RATE, 16, 6, buffers)
    if ok6 and src6 then return src6, 6 end
    local ok2, src2 = pcall(love.audio.newQueueableSource,
                            ChipSynth.SAMPLE_RATE, 16, 2, buffers)
    if ok2 and src2 then return src2, 2 end
    return nil, nil
  end

  local function discardSamples(samples)
    if samples <= 0 then return end
    local remaining = samples
    for _, engine in pairs(state.engines) do
      remaining = samples
      while remaining > 0 do
        local step = math.min(state.chunk, remaining)
        pcall(ChipSynth.soundData, engine, step, 1)
        remaining = remaining - step
      end
    end
    for _, pcm in pairs(state.pcms) do pcmSeek(pcm, state.extraRendered + samples) end
  end

  local function fillTo(target)
    local guard = 0
    while state.extraRendered < target and guard < 128 do
      guard = guard + 1
      if not renderChunk() then break end
    end
  end

  -- Rebuild the source at the base cursor after the harmony queue ran dry.
  -- Cannot rewind, so only a forward gap is repairable.
  local function resync(basePos)
    local gap = basePos - state.extraRendered
    if gap < 0 or gap > MAX_SKIP then return false end
    local now = clock()
    if now - state.resyncSince > RESYNC_WINDOW then
      state.resyncSince = now
      state.resyncCount = 0
    end
    state.resyncCount = state.resyncCount + 1
    if state.resyncCount > MAX_RESYNCS then return false end

    if state.source then pcall(state.source.stop, state.source) end
    state.source = nil
    state.pendingBuffer = nil
    state.pendingSamples = 0
    discardSamples(gap)
    state.extraRendered = basePos

    local src, channels = newExtraSource()
    if not src then return false end
    state.source = src
    state.channels = channels
    state.paused = false
    fillTo(basePos + state.lead)
    pcall(src.play, src)
    return true
  end

  local function start(song, data, basePlayClock, looping)
    stop()
    if type(song) ~= "table" then return end
    state.data = data
    state.envelopes = {}
    local sides = songSides(song)
    if state.maxEngines and #sides > state.maxEngines then
      while #sides > state.maxEngines do sides[#sides] = nil end
    end
    for _, side in ipairs(sides) do
      local sideSong = song[side]
      if type(sideSong) == "table" and type(sideSong.chip) == "table" then
        local ok, engine = pcall(ChipSynth.newEngine, data, sideSong, { allowLoops = true })
        if ok and type(engine) == "table" then
          state.engines[side] = engine
          local pan = tonumber(sideSong.pan)
          if not pan then
            pan = side == "left" and -0.6 or side == "right" and 0.6 or 0
          end
          state.pans[side] = math.max(-1, math.min(1, pan))
          state.gains[side] = math.max(0, math.min(1,
            tonumber(sideSong.gain) or 1))
          if type(sideSong.intensityEnvelope) == "table" then
            state.envelopes[side] = sideSong.intensityEnvelope
          end
          local pcm = pcmPrepare(side, sideSong)
          if pcm then state.pcms[side] = pcm end
        end
      end
    end
    if next(state.engines) == nil then return end
    state.bufferCount = BUFFER_COUNT
    local src, channels = newExtraSource()
    if not src then return end
    state.source = src
    state.channels = channels
    state.lpfState = 0
    state.lead = (looping == false) and LEAD_ONCE or LEAD_LOOP
    local startedAt = clock()
    if type(basePlayClock) == "number" then
      state.baseElapsed = math.max(0, (startedAt - basePlayClock) * SAMPLE_RATE)
    else
      state.baseElapsed = 0
    end
    local skip = math.floor(state.baseElapsed)
    discardSamples(skip)
    state.extraRendered = skip
    state.baseLastClock = startedAt
    local baseSrc = currentBaseSource()
    state.baseWasPlaying = isPlaying(baseSrc)
    -- Base is still buffering (threaded start): render the lead now so both
    -- sources can begin on the same sample, not one update later.
    if not state.baseWasPlaying then
      fillTo(skip + state.lead)
    end
  end

  local function update()
    if not state.source or state.givenUp then return end
    local now = clock()
    local baseSrc = currentBaseSource()
    local basePlaying = isPlaying(baseSrc)
    if basePlaying and state.baseWasPlaying then
      local elapsed = now - state.baseLastClock
      if elapsed > 0 then state.baseElapsed = state.baseElapsed + elapsed * SAMPLE_RATE end
    end
    state.baseLastClock = now
    state.baseWasPlaying = basePlaying
    -- Music.fadeOut ramps the base source volume directly, bypassing the
    -- music.volume hook. Follow that ratio so the harmony fades with it.
    if baseSrc and type(baseSrc.getVolume) == "function" then
      local okVol, baseVol = pcall(baseSrc.getVolume, baseSrc)
      if okVol and type(baseVol) == "number" and state.baseVolumeRef
          and state.baseVolumeRef > 0 then
        local scale = math.max(0, math.min(1, baseVol / state.baseVolumeRef))
        if scale ~= state.fadeScale then
          state.fadeScale = scale
          pcall(state.source.setVolume, state.source, scale)
        end
      end
    end

    local basePos = state.baseElapsed
    local drift = sourcePlayed() - basePos

    if state.paused then
      if not basePlaying then
        if isPlaying(state.source) then pcall(state.source.pause, state.source) end
        return
      end
      if (not drift) or drift <= 0 then
        state.paused = false
        pcall(state.source.play, state.source)
      else
        return
      end
    end

    if basePlaying and drift then
      if drift < -DRIFT_TOL then
        if not resync(basePos) then
          if state.source then pcall(state.source.stop, state.source) end
          state.givenUp = true
          return
        end
      elseif drift > DRIFT_TOL then
        pcall(state.source.pause, state.source)
        state.paused = true
        return
      end
    end

    if basePlaying then fillTo(state.baseElapsed + state.lead) end
    if basePlaying and not isPlaying(state.source) and not state.paused then
      pcall(state.source.play, state.source)
    elseif (not basePlaying) and isPlaying(state.source) then
      pcall(state.source.pause, state.source)
    end
  end

  local function setSideEnabled(side, v)
    if side ~= nil then state.sideEnabled[side] = (v ~= false) end
  end

  local function setExtraGain(v)
    local n = tonumber(v)
    if n then state.extraGain = math.max(0, math.min(1, n)) end
  end

  local function setExtraMix(v)
    local n = tonumber(v)
    if n then state.extraGain = math.max(0, math.min(1, n / 7)) end
  end

  local function setProfile(profile)
    state.profile = profile == "gba" and "gba" or "gb"
    state.maxEngines = state.profile == "gba" and 16 or nil
  end

  local function setSampleReader(fn)
    state.sampleReader = type(fn) == "function" and fn or nil
  end

  local function setMusicVolume(v)
    local n = tonumber(v)
    if n then state.musicVolume = math.max(0, n) end
  end

  -- Full (non-fading) base volume, captured from the music.volume hook.
  local function setBaseVolume(v)
    local n = tonumber(v)
    if n then state.baseVolumeRef = n end
  end

  local function isActive()
    return state.source ~= nil and not state.givenUp
  end

  return {
    start = start,
    stop = stop,
    update = update,
    isActive = isActive,
    setExtraGain = setExtraGain,
    setExtraMix = setExtraMix,
    setSideEnabled = setSideEnabled,
    setProfile = setProfile,
    setSampleReader = setSampleReader,
    setMusicVolume = setMusicVolume,
    setBaseVolume = setBaseVolume,
  }
end
