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
  }

  local function isPlaying(src)
    if not src then return false end
    local ok, playing = pcall(src.isPlaying, src)
    return ok and playing
  end

  local function stop()
    if state.source then pcall(state.source.stop, state.source) end
    state.source = nil
    state.engines = {}
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

    for side, engine in pairs(state.engines) do
      if state.sideEnabled[side] == false then goto continue end
      local okSd, sd = pcall(ChipSynth.soundData, engine, chunk, 1)
      if okSd and sd then
        local ptr = nil
        if ChipSynth._int16Pointer then
          local okPtr, p = pcall(ChipSynth._int16Pointer, sd)
          if okPtr then ptr = p end
        end
        local gain = state.extraGain * state.musicVolume
        for i = 0, chunk - 1 do
          local sample = 0
          if ptr then
            sample = ptr[i] / 32767
          else
            local okSample, v = pcall(sd.getSample, sd, i)
            if okSample then sample = v or 0 end
          end
          if side == "left" then
            leftMix[i] = leftMix[i] + sample * gain * 0.8
            rightMix[i] = rightMix[i] + sample * gain * 0.6
          elseif side == "right" then
            rightMix[i] = rightMix[i] + sample * gain * 0.8
            leftMix[i] = leftMix[i] + sample * gain * 0.6
          else
            leftMix[i] = leftMix[i] + sample * gain * 0.5
            rightMix[i] = rightMix[i] + sample * gain * 0.5
          end
        end
      end
      ::continue::
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
    for side, sideSong in pairs(song) do
      if type(sideSong) == "table" and type(sideSong.chip) == "table" then
        local ok, engine = pcall(ChipSynth.newEngine, data, sideSong, { allowLoops = true })
        if ok and type(engine) == "table" then
          state.engines[side] = engine
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
    setSideEnabled = setSideEnabled,
    setMusicVolume = setMusicVolume,
    setBaseVolume = setBaseVolume,
  }
end
