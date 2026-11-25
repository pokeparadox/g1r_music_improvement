-- Bounded reader for a pre-extracted HGSS NDS ROM exposed by the engine's
-- import facade.  No io/os: every byte comes from imports:read(id, off, len).
-- Parses the ROM's SDAT (SYMB/INFO/FAT/FILE) and exposes BGM sequences/banks.

local M = {}

local IMPORT_ID = "hgss_nds"
local CACHE_PATH = "hgss_nds_index.lua"
local CACHE_VERSION = 4
local MAX_READ = 8 * 1024 * 1024
local SCAN_CHUNK = 1024 * 1024
local PREFERRED_SDAT = 0x6B3000
local PREFERRED_SDAT2 = 0x7094C00
local MAX_ROM_SIZE = 512 * 1024 * 1024

local deps
local parsed
local attempted
local currentStatus
local sampleCache = {}

local function freshStatus()
  return {
    available = false,
    filename = nil,
    size = nil,
    fingerprint = nil,
    sdatOffset = nil,
    sdatSize = nil,
    songCount = nil,
    error = nil,
  }
end

local function u8(blob, off)
  if type(blob) ~= "string" or off < 0 or off >= #blob then return nil end
  return blob:byte(off + 1)
end

local function u16(blob, off)
  local a = u8(blob, off)
  if not a then return nil end
  return a + (u8(blob, off + 1) or 0) * 256
end

local function u32(blob, off)
  local a = u8(blob, off)
  if not a then return nil end
  return a
    + (u8(blob, off + 1) or 0) * 256
    + (u8(blob, off + 2) or 0) * 65536
    + (u8(blob, off + 3) or 0) * 16777216
end

local function i32(blob, off)
  local v = u32(blob, off)
  if not v then return nil end
  return v >= 0x80000000 and v - 0x100000000 or v
end

local function i16(blob, off)
  local v = u16(blob, off)
  if not v then return nil end
  return v >= 0x8000 and v - 0x10000 or v
end

local function pack16(v)
  local n = math.floor(v or 0) % 65536
  return string.char(n % 256, math.floor(n / 256) % 256)
end

-- IMA-ADPCM step/index tables used by NDS SWAV ADPCM samples.
local ADPCM_STEPS = {
  7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
  34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
  157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658,
  724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024,
  3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
  15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
}
local ADPCM_INDEX = { -1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8 }

local function tag(blob, off)
  if type(blob) ~= "string" or off < 0 or off + 4 > #blob then return nil end
  return blob:sub(off + 1, off + 4)
end

local function cstring(blob, off)
  if type(blob) ~= "string" or off < 0 or off >= #blob then return nil end
  local stop = math.min(#blob, off + 255)
  local chunk = blob:sub(off + 1, stop)
  local z = chunk:find("\0", 1, true)
  if not z then return nil end
  return chunk:sub(1, z - 1)
end

local function readRange(off, length)
  if not deps or not deps.imports then return nil end
  off = math.floor(tonumber(off) or -1)
  length = math.floor(tonumber(length) or 0)
  if off < 0 or length < 0 then return nil end
  if length == 0 then return "" end
  local parts, got = {}, 0
  while got < length do
    local want = math.min(MAX_READ, length - got)
    local ok, chunk = pcall(function()
      return deps.imports:read(IMPORT_ID, off + got, want)
    end)
    if not ok or type(chunk) ~= "string" or #chunk ~= want then return nil end
    parts[#parts + 1] = chunk
    got = got + want
  end
  return table.concat(parts)
end

local function importInfo()
  if not deps or not deps.imports then return nil end
  local ok, info = pcall(function() return deps.imports:info(IMPORT_ID) end)
  if not ok then return nil end
  if type(info) == "string" then info = { filename = info } end
  if type(info) ~= "table" then return nil end
  local filename = info.filename or info.name or info.path or info.file
  if type(filename) == "string" then
    filename = filename:match("([^/\\]+)$") or filename
  else
    filename = nil
  end
  local size = tonumber(info.size or info.length or info.bytes)
  if not size or size < 0x1000 or size > MAX_ROM_SIZE then return nil end
  return {
    filename = filename,
    size = math.floor(size),
    fingerprint = info.fingerprint or info.md5 or info.hash or info.sha1 or info.checksum,
  }
end

local function parseSdatHeader(blob, romSize)
  if #blob < 0x40 or tag(blob, 0) ~= "SDAT" then return nil end
  local fileSize = u32(blob, 8)
  local headerSize = u16(blob, 12)
  local blockCount = u16(blob, 14)
  if not fileSize or fileSize <= 0x100 or fileSize > romSize then return nil end
  if headerSize ~= 0x40 or not blockCount or blockCount < 3 then return nil end
  local blocks = {}
  for i = 0, 3 do
    local off, size = u32(blob, 0x10 + i * 8), u32(blob, 0x14 + i * 8)
    if not off or not size or off < 0x40 or size < 8 then return nil end
    if off + size > fileSize then return nil end
    blocks[i + 1] = { offset = off, size = size }
  end
  return { fileSize = fileSize, blocks = blocks }
end

local function sdatAt(romOffset, romSize)
  local header = readRange(romOffset, 0x40)
  local info = header and parseSdatHeader(header, romSize)
  if not info then return nil end
  local blocks = info.blocks
  local expected = { "SYMB", "INFO", "FAT ", "FILE" }
  for i = 2, 4 do
    if tag(readRange(romOffset + blocks[i].offset, 4) or "", 0) ~= expected[i] then
      return nil
    end
  end
  if tag(readRange(romOffset + blocks[1].offset, 4) or "", 0) ~= "SYMB" then
    return nil
  end
  return info
end

local function findSdat(romSize)
  local found, seen = {}, {}
  local function tryOffset(off)
    if seen[off] or off + 0x40 > romSize then return end
    seen[off] = true
    local info = sdatAt(off, romSize)
    if info then found[#found + 1] = { offset = off, info = info } end
  end
  tryOffset(PREFERRED_SDAT)
  tryOffset(PREFERRED_SDAT2)
  if #found > 0 then return found end
  local base = 0
  while base < romSize do
    local length = math.min(SCAN_CHUNK + 3, romSize - base)
    local blob = readRange(base, length)
    if blob then
      local from = 1
      while true do
        local hit = blob:find("SDAT", from, true)
        if not hit then break end
        local off = base + hit - 1
        if off % 4 == 0 then tryOffset(off) end
        from = hit + 1
      end
    end
    base = base + SCAN_CHUNK
  end
  return #found > 0 and found or nil
end

local function infoParts(infoBlob)
  local offsets = {}
  for i = 0, 7 do offsets[i + 1] = u32(infoBlob, 8 + i * 4) end
  return offsets
end

local function partEntries(infoBlob, partOffsets, partIndex)
  local out = {}
  local base = partOffsets[partIndex + 1]
  if not base or base == 0 or base + 4 > #infoBlob then return out end
  local count = u32(infoBlob, base)
  if not count or count > 100000 then return out end
  if base + 4 + count * 4 > #infoBlob then return out end
  for i = 0, count - 1 do
    out[i + 1] = u32(infoBlob, base + 4 + i * 4) or 0
  end
  return out
end

local function symbolList(symbBlob, listOffset, withSubgroups)
  local out = {}
  if not listOffset or listOffset == 0 or listOffset + 4 > #symbBlob then return out end
  local count = u32(symbBlob, listOffset)
  if not count or count > 100000 then return out end
  local stride = withSubgroups and 8 or 4
  if listOffset + 4 + count * stride > #symbBlob then return out end
  for i = 0, count - 1 do
    local pos = listOffset + 4 + i * stride
    local nameOff = u32(symbBlob, pos) or 0
    local name = nameOff ~= 0 and cstring(symbBlob, nameOff) or nil
    if withSubgroups then
      local subOff = u32(symbBlob, pos + 4) or 0
      out[i + 1] = { name = name, subs = subOff ~= 0 and symbolList(symbBlob, subOff, false) or {} }
    else
      out[i + 1] = name
    end
  end
  return out
end

local function parseFat(fatBlob)
  local files = {}
  local count = u32(fatBlob, 8)
  if not count or count > 100000 then return files end
  if 12 + count * 16 > #fatBlob then return files end
  for i = 0, count - 1 do
    local pos = 12 + i * 16
    local off, size = u32(fatBlob, pos), u32(fatBlob, pos + 4)
    if off and size and off + size > 0 then
      files[i] = { offset = off, size = size }
    end
  end
  return files
end

local function parseSsars(fat, sdatOffset, entries)
  local out = {}
  for i, entry in ipairs(entries) do
    local file = fat[entry.fileID]
    local blob = file and readRange(sdatOffset + file.offset, file.size)
    local sequences = {}
    if blob and #blob >= 0x20 and tag(blob, 0) == "SSAR" and tag(blob, 0x10) == "DATA" then
      local dataOffset = u32(blob, 0x18)
      local count = u32(blob, 0x1C)
      if dataOffset and count and dataOffset <= #blob
          and 0x20 + count * 12 <= dataOffset and dataOffset >= 0x20 then
        for j = 0, count - 1 do
          local p = 0x20 + j * 12
          sequences[j + 1] = {
            firstEventOffset = i32(blob, p),
            bank = u16(blob, p + 4) or 0,
            volume = u8(blob, p + 6) or 0,
            channelPressure = u8(blob, p + 7) or 0,
            polyphonicPressure = u8(blob, p + 8) or 0,
            player = u8(blob, p + 9) or 0,
          }
        end
      end
    end
    out[i] = {
      index = i - 1,
      fileID = entry.fileID,
      sequences = sequences,
    }
  end
  return out
end

local function skippedName(name)
  if type(name) ~= "string" or name == "" then return true end
  local upper = name:upper()
  if upper:find("DUMMY", 1, true) or upper:find("SILENCE", 1, true) then return true end
  -- Every music symbol starts with SEQ_; only true SE records are effects.
  if upper:match("^SEQ_SE_") or upper:match("^SE_") or upper:find("_SE_", 1, true) then
    return true
  end
  return false
end

local function maxIndex(t)
  local n = 0
  for i in pairs(t) do
    if type(i) == "number" and i > n then n = i end
  end
  return n
end

local function buildSongs(seqs, ssars, seqNames, ssarNames)
  local songs = {}
  for i = 1, maxIndex(seqs) do
    local seq = seqs[i]
    if not seq then
      -- sparse SEQ records are normal; skip unused slots
    else
    local name = seqNames[i]
    if seq.player == 1 and not skippedName(name) then
      songs[#songs + 1] = {
        name = name,
        index = i - 1,
        bank = seq.bank,
        player = seq.player,
        source = "seq",
        fileID = seq.fileID,
      }
      end
    end
  end
  for i = 1, maxIndex(ssars) do
    local archive = ssars[i]
    if not archive then
      -- sparse SSAR records are normal
    else
    local symbol = ssarNames[i]
    if symbol then
      for j, seq in ipairs(archive.sequences) do
        if seq.player == 1 then
          local subs = symbol.subs or {}
          local name = subs[j] or (j == 1 and symbol.name or nil)
          if not skippedName(name) then
            songs[#songs + 1] = {
              name = name or string.format("SSAR_%d_%d", archive.index, j - 1),
              index = archive.index,
              bank = seq.bank,
              player = seq.player,
              source = "ssar",
              fileID = archive.fileID,
              subIndex = j - 1,
              firstEventOffset = seq.firstEventOffset,
            }
          end
        end
      end
    end
    end
  end
  return songs
end

local function dump(value)
  local kind = type(value)
  if kind == "nil" then return "nil" end
  if kind == "boolean" then return value and "true" or "false" end
  if kind == "number" then return tostring(value) end
  if kind == "string" then return string.format("%q", value) end
  if kind ~= "table" then return nil end
  local max, count = 0, 0
  for k, v in pairs(value) do
    count = count + 1
    if type(k) == "number" and k >= 1 and k == math.floor(k) and k > max then
      max = k
    end
  end
  local isArray = max > 0 and count == max
  local parts = {}
  if isArray then
    for i = 1, max do
      local item = dump(value[i])
      if not item then return nil end
      parts[#parts + 1] = item
    end
  else
    for k, v in pairs(value) do
      local key
      if type(k) == "string" and k:match("^[_%a][_%w]*$") then
        key = k
      elseif type(k) == "number" or type(k) == "string" then
        local literal = dump(k)
        if not literal then return nil end
        key = "[" .. literal .. "]"
      else
        return nil
      end
      local item = dump(v)
      if not item then return nil end
      parts[#parts + 1] = key .. " = " .. item
    end
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function writeCache(data)
  if not deps or not deps.cache then return end
  local text = dump(data)
  if not text then return end
  pcall(function() deps.cache:write(CACHE_PATH, "return " .. text .. "\n") end)
end

local function readCache(info)
  if not deps or not deps.cache or type(load) ~= "function" then return nil end
  local ok, bytes = pcall(function() return deps.cache:read(CACHE_PATH) end)
  if not ok or type(bytes) ~= "string" or #bytes < 10 then return nil end
  local okLoad, chunk = pcall(load, bytes, "=hgss_nds_index")
  if not okLoad or not chunk then return nil end
  local okRun, data = pcall(chunk)
  if not okRun or type(data) ~= "table" or data.version ~= CACHE_VERSION then return nil end
  if data.filename ~= info.filename or data.size ~= info.size then return nil end
  if info.fingerprint and data.fingerprint ~= info.fingerprint then return nil end
  if type(data.sdats) ~= "table" or #data.sdats == 0 then return nil end
  local candidates = {}
  for _, entry in ipairs(data.sdats) do
    if type(entry.offset) ~= "number" or type(entry.size) ~= "number" then return nil end
    local header = readRange(entry.offset, 0x40)
    local sdat = header and parseSdatHeader(header, info.size)
    if not sdat or sdat.fileSize ~= entry.size then return nil end
    candidates[#candidates + 1] = { offset = entry.offset, info = sdat }
  end
  return { fingerprint = data.fingerprint, candidates = candidates }
end

local function buildOpen()
  local info = importInfo()
  if not info then return nil, "missing" end

  local cached = readCache(info)
  local sdats = cached and cached.candidates or findSdat(info.size)
  if not sdats then
    currentStatus.filename = info.filename
    currentStatus.size = info.size
    currentStatus.error = "SDAT not found"
    return nil, currentStatus.error
  end

  local allSongs, allBanks, allSwarRecords, loaded = {}, {}, {}, {}
  for _, candidate in ipairs(sdats) do
    local sdatOffset, sdat = candidate.offset, candidate.info
    local blocks = sdat.blocks
    local symbBlob = readRange(sdatOffset + blocks[1].offset, blocks[1].size)
    local infoBlob = readRange(sdatOffset + blocks[2].offset, blocks[2].size)
    local fatBlob = readRange(sdatOffset + blocks[3].offset, blocks[3].size)
    if not symbBlob or not infoBlob or not fatBlob
        or tag(symbBlob, 0) ~= "SYMB" or tag(infoBlob, 0) ~= "INFO" then
      currentStatus.error = "invalid SDAT blocks"
      return nil, currentStatus.error
    end

    local partOffsets = infoParts(infoBlob)
    local seqRecords, ssarRecords, bankRecords, swarRecords = {}, {}, {}, {}
    for i, off in ipairs(partEntries(infoBlob, partOffsets, 0)) do
      if off > 0 then
        seqRecords[i] = {
          index = i - 1,
          fileID = u16(infoBlob, off) or 0,
          bank = u16(infoBlob, off + 4) or 0,
          volume = u8(infoBlob, off + 6) or 0,
          channelPressure = u8(infoBlob, off + 7) or 0,
          polyphonicPressure = u8(infoBlob, off + 8) or 0,
          -- 3H4B: playerID lives at +9, not +10.
          player = u8(infoBlob, off + 9) or 0,
        }
      end
    end
    for i, off in ipairs(partEntries(infoBlob, partOffsets, 1)) do
      if off > 0 then ssarRecords[i] = { index = i - 1, fileID = u16(infoBlob, off) or 0 } end
    end
    for i, off in ipairs(partEntries(infoBlob, partOffsets, 2)) do
      if off > 0 then
        local swarIDs = {}
        for k = 0, 3 do
          local v = u16(infoBlob, off + 4 + k * 2)
          if v and v >= 0x8000 then v = v - 0x10000 end
          swarIDs[k + 1] = v
        end
        bankRecords[i] = {
          index = i - 1, fileID = u16(infoBlob, off) or 0, swarIDs = swarIDs,
          sdatOffset = sdatOffset,
        }
      end
    end
    for i, off in ipairs(partEntries(infoBlob, partOffsets, 3)) do
      if off > 0 then
        swarRecords[i] = {
          index = i - 1,
          fileID = u16(infoBlob, off) or 0,
          sdatOffset = sdatOffset,
        }
      end
    end

    local symbOffsets = {}
    for i = 0, 7 do symbOffsets[i + 1] = u32(symbBlob, 8 + i * 4) end
    local seqNames = symbolList(symbBlob, symbOffsets[1], false)
    local ssarNames = symbolList(symbBlob, symbOffsets[2], true)

    local fat = parseFat(fatBlob)
    local ssars = parseSsars(fat, sdatOffset, ssarRecords)
    local songs = buildSongs(seqRecords, ssars, seqNames, ssarNames)
    local sdatIndex = #loaded + 1
    for _, song in ipairs(songs) do
      song.sdatOffset = sdatOffset
      song.sdatIndex = sdatIndex
      allSongs[#allSongs + 1] = song
    end
    for i, bank in pairs(bankRecords) do
      bank.sdatOffset = sdatOffset
      bank.sdatIndex = sdatIndex
      if not allBanks[i] then allBanks[i] = bank end
    end
    for i, swar in pairs(swarRecords) do
      swar.sdatOffset = sdatOffset
      swar.sdatIndex = sdatIndex
      if not allSwarRecords[i] then allSwarRecords[i] = swar end
    end
    loaded[#loaded + 1] = {
      sdatOffset = sdatOffset, sdatSize = sdat.fileSize, fat = fat,
      seqs = seqRecords, ssars = ssars, banks = bankRecords,
      swarRecords = swarRecords,
    }
  end

  local first = loaded[1]
  data = {
    version = CACHE_VERSION,
    filename = info.filename,
    size = info.size,
    fingerprint = cached and cached.fingerprint or info.fingerprint
      or string.format("%x-%x-%x", info.size, first.sdatOffset, first.sdatSize),
    sdatOffset = first.sdatOffset,
    sdatSize = first.sdatSize,
    sdats = loaded,
    banks = allBanks,
    swarRecords = allSwarRecords,
    fat = first.fat,
    songs = allSongs,
  }
  local cacheOffsets = {}
  for _, entry in ipairs(loaded) do
    cacheOffsets[#cacheOffsets + 1] = { offset = entry.sdatOffset, size = entry.sdatSize }
  end
  writeCache({ version = CACHE_VERSION, filename = info.filename, size = info.size,
    fingerprint = data.fingerprint, sdats = cacheOffsets })

  currentStatus.filename = info.filename
  currentStatus.size = info.size
  currentStatus.fingerprint = data.fingerprint
  currentStatus.sdatOffset = first.sdatOffset
  currentStatus.sdatSize = first.sdatSize
  currentStatus.songCount = #allSongs
  currentStatus.available = true
  currentStatus.error = nil
  return data
end

function M.install(ctx)
  deps = type(ctx) == "table" and ctx or nil
  parsed = nil
  attempted = false
  sampleCache = {}
  currentStatus = freshStatus()
  if deps and type(deps.imports) == "table" then
    local info = importInfo()
    if info then
      currentStatus.filename = info.filename
      currentStatus.size = info.size
      currentStatus.fingerprint = info.fingerprint
    end
  end
end

function M.open()
  if not deps or not deps.imports then return nil, "missing" end
  if parsed then return parsed end
  attempted = true
  local ok, result, err = pcall(buildOpen)
  if not ok then
    currentStatus.available = false
    currentStatus.error = "error: " .. tostring(result)
    return nil, currentStatus.error
  end
  if not result then
    currentStatus.available = false
    return nil, err
  end
  result.deps = deps
  parsed = result
  return parsed
end

function M.status()
  if not currentStatus then currentStatus = freshStatus() end
  if not attempted and deps and deps.imports then M.open() end
  local out = {}
  for k, v in pairs(currentStatus) do out[k] = v end
  return out
end

function M.listSongs()
  local ctx, err = M.open()
  if not ctx then return {} end
  local out = {}
  for i, song in ipairs(ctx.songs or {}) do out[i] = song end
  return out
end

local function fileBlob(ctx, fileID, sdatIndex, sdatOffset, fallbackFat)
  local fat = ctx.fat
  if type(sdatIndex) == "number" then
    local sd = ctx.sdats and ctx.sdats[sdatIndex]
    if sd and type(sd.fat) == "table" then fat = sd.fat end
  end
  sdatOffset = sdatOffset or ctx.sdatOffset
  local file = (fat and fat[fileID]) or (fallbackFat and fallbackFat[fileID])
  if not file then return nil end
  return readRange(sdatOffset + file.offset, file.size)
end

function M.readSequence(song)
  local ctx = M.open()
  if not ctx or type(song) ~= "table" then return nil, "invalid song" end
  local ok, result, err = pcall(function()
    local blob = fileBlob(ctx, song.fileID, song.sdatIndex, song.sdatOffset)
    if not blob then return nil, "file unavailable" end
    if song.source == "ssar" then
      if tag(blob, 0) ~= "SSAR" or tag(blob, 0x10) ~= "DATA" then
        return nil, "invalid SSAR"
      end
      local dataOffset = u32(blob, 0x18)
      local sub = song.subIndex or 0
      if not dataOffset or dataOffset > #blob or sub < 0 then return nil, "invalid SSAR" end
      local p = 0x20 + sub * 12
      if p + 10 > dataOffset then return nil, "invalid SSAR index" end
      local first = i32(blob, p)
      if not first or first < 0 then return nil, "no sequence" end
      local eventsData = blob:sub(dataOffset + 1)
      -- IDs inside SSAR events are relative to eventsData itself; `first` only
      -- says where this sub-song starts within that shared event blob.
      return { data = eventsData, base = 0, start = first, size = #eventsData }
    end
    if tag(blob, 0) ~= "SSEQ" or tag(blob, 0x10) ~= "DATA" then
      return nil, "invalid SSEQ"
    end
    local dataOffset = u32(blob, 0x18) or 0x1C
    if dataOffset < 0x10 or dataOffset > #blob then return nil, "invalid SSEQ" end
    return { data = blob, base = dataOffset, start = dataOffset, size = #blob }
  end)
  if not ok then return nil, "error: " .. tostring(result) end
  return result, err
end

local function note(fields)
  return {
    type = fields.type,
    keyLow = fields.keyLow,
    keyHigh = fields.keyHigh,
    waveID = fields.waveID,
    waveArchiveID = fields.waveArchiveID,
    pitch = fields.pitch,
    attack = fields.attack,
    decay = fields.decay,
    sustain = fields.sustain,
    release = fields.release,
    pan = fields.pan,
  }
end

local function readNote(blob, off, noteType, keyLow, keyHigh)
  if not noteType then
    noteType = u16(blob, off)
    off = off + 2
  end
  if not noteType or off < 0 or off + 10 > #blob then return nil end
  return note({
    type = noteType,
    keyLow = keyLow,
    keyHigh = keyHigh,
    waveID = u16(blob, off),
    waveArchiveID = u16(blob, off + 2),
    pitch = u8(blob, off + 4),
    attack = u8(blob, off + 5),
    decay = u8(blob, off + 6),
    sustain = u8(blob, off + 7),
    release = u8(blob, off + 8),
    pan = u8(blob, off + 9),
  })
end

local function parseInstruments(blob)
  local out = {}
  local count = u32(blob, 0x38)
  if not count or count > 100000 then return out end
  if 0x3C + count * 4 > #blob then return out end
  for i = 0, count - 1 do
    local p = 0x3C + i * 4
    local instType, instOff = u8(blob, p), u16(blob, p + 1)
    local inst = { index = i, type = instType or 0, notes = {} }
    if instType == 0 then
      inst.keyLow, inst.keyHigh = 0, 0
    elseif instType and instType < 16 then
      inst.keyLow, inst.keyHigh = 0, 127
      local n = instOff and readNote(blob, instOff, instType, 0, 127)
      if n then inst.notes[1] = n end
    elseif instType == 16 and instOff then
      local first, last = u8(blob, instOff), u8(blob, instOff + 1)
      if first and last and last >= first then
        inst.keyLow, inst.keyHigh = first, last
        for key = first, last do
          local n = readNote(blob, instOff + 2 + (key - first) * 12, nil, key, key)
          if n then inst.notes[#inst.notes + 1] = n end
        end
      end
    elseif instType == 17 and instOff then
      inst.keyLow, inst.keyHigh = 0, 127
      local low = 0
      for region = 0, 7 do
        local high = u8(blob, instOff + region)
        if not high or (high == 0 and region > 0) then break end
        local n = readNote(blob, instOff + 8 + region * 12, nil, low, high)
        if n then
          inst.notes[#inst.notes + 1] = n
          inst.keyHigh = high
        end
        low = high + 1
      end
    end
    out[i + 1] = inst
  end
  return out
end

function M.readBank(bankID)
  local ctx = M.open()
  if not ctx then return nil, "unavailable" end
  bankID = tonumber(bankID)
  if not bankID or bankID < 0 or bankID ~= math.floor(bankID) then
    return nil, "invalid bank"
  end
  local record = ctx.banks and ctx.banks[bankID + 1]
  if not record then return nil, "invalid bank" end
  local ok, result, err = pcall(function()
    local blob = fileBlob(ctx, record.fileID, record.sdatIndex, record.sdatOffset)
    if not blob or tag(blob, 0) ~= "SBNK" or tag(blob, 0x10) ~= "DATA" then
      return nil, "invalid SBNK"
    end
    local instruments = parseInstruments(blob)
    local notes = {}
    for _, inst in ipairs(instruments) do
      for _, n in ipairs(inst.notes) do notes[#notes + 1] = n end
    end
    return {
      bankID = bankID,
      fileID = record.fileID,
      data = blob,
      swarIDs = record.swarIDs,
      instruments = instruments,
      notes = notes,
      count = #instruments,
    }
  end)
  if not ok then return nil, "error: " .. tostring(result) end
  return result, err
end

-- SWAR wave offsets are four bytes per wave in real SDATs.  Some imports use
-- explicit (first, next) pairs; try both layouts, bounded by the SWAR file size.
local function swavRange(blob, count, waveID, fileSize)
  for _, stride in ipairs({ 4, 8 }) do
    local ranges, ok = {}, true
    for i = 0, count - 1 do
      local p = 0x3C + i * stride
      local first = u32(blob, p)
      local last = (i == count - 1) and fileSize or u32(blob, p + 4)
      if not first or not last or first < 0x3C + count * 4
        or last <= first or last > fileSize then
        ok = false
        break
      end
      ranges[i + 1] = { first = first, last = last }
    end
    if ok and ranges[waveID + 1] then return ranges[waveID + 1] end
  end
  return nil
end

local function decodeAdpcm(raw)
  if #raw < 4 then return nil end
  local predictor = i16(raw, 0) or 0
  local index = (u16(raw, 2) or 0) % 128
  if index > 88 then index = 88 end
  local out = {}
  for off = 4, #raw - 1 do
    local byte = u8(raw, off)
    for shift = 0, 4, 4 do
      local nibble = math.floor(byte / (2 ^ shift)) % 16
      local step = ADPCM_STEPS[index + 1]
      local diff = math.floor(step / 8)
      if nibble % 2 == 1 then diff = diff + math.floor(step / 4) end
      if math.floor(nibble / 2) % 2 == 1 then diff = diff + math.floor(step / 2) end
      if math.floor(nibble / 4) % 2 == 1 then diff = diff + step end
      if nibble >= 8 then predictor = predictor - diff else predictor = predictor + diff end
      if predictor > 32767 then predictor = 32767 elseif predictor < -32768 then predictor = -32768 end
      index = index + ADPCM_INDEX[(nibble % 8) + 1]
      if index < 0 then index = 0 elseif index > 88 then index = 88 end
      out[#out + 1] = pack16(predictor)
    end
  end
  return table.concat(out)
end

local function readSampleUncached(bankID, noteDef, archiveID, waveID)
  local ctx = M.open()
  if not ctx then return nil end
  local bank = ctx.banks and ctx.banks[bankID + 1]
  if not bank then return nil end
  local swarID = bank.swarIDs and bank.swarIDs[archiveID + 1]
  if not swarID or swarID < 0 then
    swarID = nil
    for _, id in ipairs(bank.swarIDs or {}) do
      if id and id >= 0 then swarID = id break end
    end
  end
  if not swarID then return nil end
  local record = ctx.swarRecords and ctx.swarRecords[swarID + 1]
  if not record or record.sdatIndex ~= bank.sdatIndex then return nil end
  local blob = fileBlob(ctx, record.fileID, record.sdatIndex, record.sdatOffset)
  if not blob or #blob < 0x40 or tag(blob, 0) ~= "SWAR" then return nil end
  if u16(blob, 4) ~= 0xFEFF or u16(blob, 6) ~= 0x100
    or u16(blob, 0x0C) ~= 0x10 or u16(blob, 0x0E) ~= 1
    or tag(blob, 0x10) ~= "DATA" then return nil end
  local fileSize = u32(blob, 8)
  local count = u32(blob, 0x38)
  if not fileSize or fileSize > #blob or not count or count < 1 or count > 4096
    or waveID >= count then return nil end
  local range = swavRange(blob, count, waveID, fileSize)
  if not range then return nil end

  local infoOff, samplesOff, limit = range.first, range.first + 0x0C, range.last
  if tag(blob, range.first) == "SWAV" then
    local subSize = u32(blob, range.first + 8)
    if not subSize or subSize < 0x24 or range.first + subSize > range.last
      or u16(blob, range.first + 6) ~= 0x100
      or u16(blob, range.first + 0x0C) ~= 0x10
      or u16(blob, range.first + 0x0E) ~= 1
      or tag(blob, range.first + 0x10) ~= "DATA" then return nil end
    infoOff = range.first + 0x18
    samplesOff = range.first + 0x24
    limit = range.first + subSize
  end
  if samplesOff > limit or limit > #blob or infoOff + 0x0C > limit then return nil end
  local format = u8(blob, infoOff)
  local loopFlag = u8(blob, infoOff + 1)
  local sampleRate = u16(blob, infoOff + 2)
  local loopOffset = u16(blob, infoOff + 6)
  local loopLength = u32(blob, infoOff + 8)
  if not format or format > 2 or not loopFlag or not sampleRate
    or not loopOffset or not loopLength then return nil end
  local raw = blob:sub(samplesOff + 1, limit)
  local data
  if format == 0 then
    local out = {}
    for i = 1, #raw do out[i] = pack16(raw:byte(i) - 128) end
    data = table.concat(out)
  elseif format == 1 then
    data = raw:sub(1, #raw - (#raw % 2))
  else
    data = decodeAdpcm(raw)
  end
  if not data then return nil end
  -- SWAV loop points are in 4-byte words. Convert to decoded sample frames:
  -- PCM8 4 frames/word, PCM16 2, ADPCM 8 minus the 4-byte header.
  local frames = math.floor(#data / 2)
  local wordFrames = format == 0 and 4 or (format == 1 and 2 or 8)
  local function loopFrame(word, upper)
    local value = word * wordFrames
    if format == 2 then value = value - 8 end
    if value < 0 then value = 0 end
    value = math.floor(value + 0.5)
    local limit = upper and frames or math.max(0, frames - 1)
    if value > limit then value = limit end
    return value
  end
  local loopStart = loopFrame(loopOffset, false)
  local loopEnd = loopFrame(loopOffset + loopLength, true)
  if loopEnd <= loopStart then loopEnd = math.min(frames, loopStart + 1) end
  return {
    bankID = bankID,
    archiveID = archiveID,
    waveID = waveID,
    format = format,
    sampleRate = sampleRate,
    loop = loopFlag ~= 0 and true or false,
    loopStart = loopStart,
    loopEnd = loopEnd,
    data = data,
    sourceSize = #raw,
  }
end

function M.readSample(bankID, noteDef)
  if type(noteDef) ~= "table" then return nil end
  bankID = tonumber(bankID)
  local archiveID = tonumber(noteDef.waveArchiveID or 0)
  local waveID = tonumber(noteDef.waveID or noteDef.waveID_dutyCycle or 0)
  if not bankID or bankID < 0 or bankID ~= math.floor(bankID)
    or not archiveID or archiveID < 0 or archiveID > 3 or archiveID ~= math.floor(archiveID)
    or not waveID or waveID < 0 or waveID ~= math.floor(waveID) then return nil end
  local key = bankID .. ":" .. archiveID .. ":" .. waveID
  if sampleCache[key] ~= nil then return sampleCache[key] or nil end
  local ok, result = pcall(readSampleUncached, bankID, noteDef, archiveID, waveID)
  sampleCache[key] = (ok and result) and result or false
  return sampleCache[key] or nil
end

return M
