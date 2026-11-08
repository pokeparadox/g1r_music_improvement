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
    lead = 8192,
    pendingBuffer = nil,
    pendingSamples = 0,
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
  end

  local function currentBaseSource()
    if okCA and type(ChipAudio.currentSource) == "function" then
      local ok, source = pcall(ChipAudio.currentSource)
      if ok then return source end
    end
    return nil
  end

  local function basePositionSamples(source)
    if not source or type(source.tell) ~= "function" then return nil end
    local ok, samples = pcall(source.tell, source, "samples")
    if ok and type(samples) == "number" and samples >= 0 then
      return samples
    end
    local okSeconds, seconds = pcall(source.tell, source)
    if okSeconds and type(seconds) == "number" and seconds >= 0 then
      return seconds * SAMPLE_RATE
    end
    return nil
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
    local src = nil
    local channels = 2
    local ok6, src6 = pcall(love.audio.newQueueableSource, ChipSynth.SAMPLE_RATE, 16, 6, 16)
    if ok6 and src6 then
      src = src6
      channels = 6
    else
      local ok2, src2 = pcall(love.audio.newQueueableSource, ChipSynth.SAMPLE_RATE, 16, 2, 16)
      if ok2 and src2 then
        src = src2
        channels = 2
      end
    end
    if not src then return end
    state.source = src
    state.channels = channels
    state.lpfState = 0
    state.lead = (looping == false) and 2048 or 8192
    local startedAt = clock()
    local baseSrc = currentBaseSource()
    local played = basePositionSamples(baseSrc)
    if played ~= nil then
      state.baseElapsed = played
    elseif type(basePlayClock) == "number" then
      state.baseElapsed = math.max(0, (startedAt - basePlayClock) * SAMPLE_RATE)
    else
      state.baseElapsed = 0
    end
    -- Align generated harmony to the base source's playback position when
    -- available; the clock estimate is only a fallback for new sources.
    local skip = math.floor(state.baseElapsed)
    for _, engine in pairs(state.engines) do
      local remaining = skip
      while remaining > 0 do
        local n = math.min(state.chunk, remaining)
        pcall(ChipSynth.soundData, engine, n, 1)
        remaining = remaining - n
      end
    end
    state.extraRendered = skip
    state.baseLastClock = startedAt
    local baseSrc = currentBaseSource()
    state.baseWasPlaying = isPlaying(baseSrc)
  end

  local function update()
    if not state.source then return end
    local now = clock()
    if state.baseWasPlaying then
      local elapsed = now - state.baseLastClock
      if elapsed > 0 then state.baseElapsed = state.baseElapsed + elapsed * SAMPLE_RATE end
    end
    state.baseLastClock = now
    local baseSrc = currentBaseSource()
    local basePlaying = isPlaying(baseSrc)
    if basePlaying and not isPlaying(state.source) then
      pcall(state.source.play, state.source)
    elseif (not basePlaying) and isPlaying(state.source) then
      pcall(state.source.pause, state.source)
    end
    state.baseWasPlaying = basePlaying

    if basePlaying then
      local target = state.baseElapsed + state.lead
      local guard = 0
      while state.extraRendered < target and guard < 64 do
        guard = guard + 1
        if not renderChunk() then break end
      end
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

  return {
    start = start,
    stop = stop,
    update = update,
    setExtraGain = setExtraGain,
    setSideEnabled = setSideEnabled,
    setMusicVolume = setMusicVolume,
  }
end
