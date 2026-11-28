-- Bounded reader for Pokemon Stadium 2 (USA) Zelda/EAD audio exposed through
-- the engine import facade.  No io/os: every byte comes from imports:read.
-- Tables are the fixed Zelda64 AudioTable headers in the USA ROM; sequence,
-- CTL and TBL payloads are uncompressed.

local M = {}

local IMPORT_ID = "n64_stadium2"
local CACHE_PATH = "stadium2_n64_index.lua"
local CACHE_VERSION = 1
local MAX_READ = 8 * 1024 * 1024
local MAX_ROM_SIZE = 512 * 1024 * 1024

local SEQ_TABLE, SEQ_DATA = 0x87020, 0x14D6660
local SEQ_FONT_TABLE = 0x878C0 -- right after the 137 sequence-table entries
local CTL_TABLE, CTL_DATA = 0x86960, 0x4AD450
local TBL_TABLE, TBL_DATA = 0x86F30, 0x50F7E0

local deps, byteOrder, parsed, attempted, currentStatus
local sampleCache = {}

local function freshStatus()
  return {
    available = false, filename = nil, size = nil, fingerprint = nil,
    sequenceCount = nil, bankCount = nil, sampleBankCount = nil, error = nil,
  }
end

local function u8(blob, off)
  if type(blob) ~= "string" or off < 0 or off >= #blob then return nil end
  return blob:byte(off + 1)
end

local function u16(blob, off)
  local a, b = u8(blob, off), u8(blob, off + 1)
  if not a or not b then return nil end
  return a * 256 + b
end

local function u32(blob, off)
  local a, b, c, d = u8(blob, off), u8(blob, off + 1), u8(blob, off + 2), u8(blob, off + 3)
  if not a or not b or not c or not d then return nil end
  return a * 16777216 + b * 65536 + c * 256 + d
end

local function i16(blob, off)
  local v = u16(blob, off)
  if not v then return nil end
  return v >= 0x8000 and v - 0x10000 or v
end

local function beFloat(blob, off)
  local w = u32(blob, off)
  if not w then return 0 end
  local sign = w >= 0x80000000 and -1 or 1
  local exp = math.floor(w / 0x800000) % 0x100
  local frac = w % 0x800000
  if exp == 0 then return sign * frac * 2 ^ -149 end
  if exp == 0xFF then return frac == 0 and sign * math.huge or 0/0 end
  return sign * (1 + frac / 0x800000) * 2 ^ (exp - 127)
end

local function pack16(v)
  local n = math.floor(v or 0) % 65536
  return string.char(n % 256, math.floor(n / 256) % 256)
end

local function normalize(raw)
  if type(raw) ~= "string" then return nil end
  if byteOrder == "le32" then
    local out = {}
    for i = 1, #raw - 3, 4 do
      out[#out + 1] = raw:sub(i + 3, i + 3) .. raw:sub(i + 2, i + 2)
        .. raw:sub(i + 1, i + 1) .. raw:sub(i, i)
    end
    return table.concat(out)
  elseif byteOrder == "swap16" then
    local out = {}
    for i = 1, #raw - 1, 2 do out[#out + 1] = raw:sub(i + 1, i + 1) .. raw:sub(i, i) end
    return table.concat(out)
  end
  return raw
end

local function readRange(off, length)
  if not deps or not deps.imports then return nil end
  off, length = math.floor(tonumber(off) or -1), math.floor(tonumber(length) or 0)
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
  return normalize(table.concat(parts))
end

local function importInfo()
  if not deps or not deps.imports then return nil end
  local ok, info = pcall(function() return deps.imports:info(IMPORT_ID) end)
  if not ok then return nil end
  if type(info) == "string" then info = { filename = info } end
  if type(info) ~= "table" then return nil end
  local filename = info.filename or info.name or info.path or info.file
  if type(filename) == "string" then filename = filename:match("([^/\\]+)$") or filename end
  local size = tonumber(info.size or info.length or info.bytes)
  if not size or size < 0x1000 or size > MAX_ROM_SIZE then return nil end
  return {
    filename = filename, size = math.floor(size),
    fingerprint = info.fingerprint or info.md5 or info.hash or info.sha1,
  }
end

local function detectOrder()
  local raw = readRange(0, 4)
  if not raw or #raw < 4 then return nil end
  local a, b, c, d = raw:byte(1, 4)
  if a == 0x80 and b == 0x37 and c == 0x12 and d == 0x40 then return "be" end
  if a == 0x37 and b == 0x80 and c == 0x40 and d == 0x12 then return "swap16" end
  if a == 0x40 and b == 0x12 and c == 0x37 and d == 0x80 then return "le32" end
  return nil
end

local function readTable(tabOff, dataOff, prefix)
  local header = readRange(tabOff, 0x10)
  if not header or #header < 0x10 then return nil end
  local count = u16(header, 0)
  if not count or count < 1 or count > 512 then return nil end
  local raw = readRange(tabOff + 0x10, count * 0x10)
  if not raw or #raw < count * 0x10 then return nil end
  local entries = {}
  for i = 0, count - 1 do
    local p = i * 0x10
    local rel, size = u32(raw, p), u32(raw, p + 4)
    if not rel or not size or size == 0 then
      entries[i + 1] = { index = i, name = prefix .. i, offset = nil, size = 0 }
    else
      entries[i + 1] = {
        index = i, name = prefix .. i, offset = dataOff + rel, size = size,
        medium = u8(raw, p + 8), cache = u8(raw, p + 9),
        tbl1 = u8(raw, p + 0xA), tbl2 = u8(raw, p + 0xB),
        normal = u8(raw, p + 0xC), percussion = u8(raw, p + 0xD),
        sfx = u8(raw, p + 0xF),
      }
    end
  end
  return entries
end

local function readSequenceFont(count)
  local raw = readRange(SEQ_FONT_TABLE, count * 2)
  if not raw or #raw < count * 2 then return nil end
  local banks = {}
  for i = 0, count - 1 do
    local rel = u16(raw, i * 2)
    if rel and rel > 0 then
      local record = readRange(SEQ_FONT_TABLE + rel, 0x20)
      local used = record and u8(record, 0)
      if used and used > 0 and used < 0x20 and used + 1 <= #record then
        banks[i + 1] = u8(record, 1)
      end
    end
  end
  return banks
end

local function writeCache(info, data)
  if not deps or not deps.cache then return end
  local parts = {
    "return { version=", CACHE_VERSION, ", filename=", string.format("%q", info.filename or ""),
    ", size=", info.size, ", fingerprint=", string.format("%q", tostring(info.fingerprint or "")),
    ", sequences=", #data.sequences, ", banks=", #data.banks, ", sampleBanks=", #data.sampleBanks, "}\n",
  }
  pcall(function() deps.cache:write(CACHE_PATH, table.concat(parts)) end)
end

local function buildOpen()
  local info = importInfo()
  if not info then return nil, "N64 ROM import not available" end
  local savedOrder = byteOrder
  byteOrder = detectOrder()
  if not byteOrder then byteOrder = savedOrder or "be" end
  local sequences = readTable(SEQ_TABLE, SEQ_DATA, "SEQ_N64_")
  local sequenceBanks = sequences and readSequenceFont(#sequences)
  local banks = readTable(CTL_TABLE, CTL_DATA, "CTL_N64_")
  local sampleBanks = readTable(TBL_TABLE, TBL_DATA, "TBL_N64_")
  if not sequences or not sequenceBanks or not banks or not sampleBanks then
    return nil, "stadium2 audio tables not found"
  end
  local out = {
    info = info, sequences = sequences, sequenceBanks = sequenceBanks,
    banks = banks, sampleBanks = sampleBanks,
  }
  writeCache(info, out)
  currentStatus = {
    available = true, filename = info.filename, size = info.size,
    fingerprint = info.fingerprint, sequenceCount = #sequences,
    bankCount = #banks, sampleBankCount = #sampleBanks, error = nil,
  }
  return out
end

function M.install(ctx)
  deps = ctx or {}
  parsed, attempted, currentStatus, byteOrder = nil, false, nil, nil
  sampleCache = {}
end

local function open()
  if parsed then return parsed end
  if attempted then return nil, currentStatus and currentStatus.error or "unavailable" end
  attempted = true
  local ok, result, err = pcall(buildOpen)
  if ok and result then parsed = result else
    currentStatus = freshStatus()
    currentStatus.error = tostring(err or result or "unavailable")
  end
  return parsed, currentStatus and currentStatus.error
end

function M.status()
  open()
  local st = currentStatus or freshStatus()
  if parsed then
    st.available = true
    st.songCount = st.sequenceCount
  end
  return st
end

function M.available()
  local ok, st = pcall(M.status)
  return ok and st.available == true
end

function M.bankForSequence(song)
  local index = type(song) == "table" and song.index or tonumber(song)
  local data = open()
  return index and data and data.sequenceBanks[index + 1] or nil
end

function M.listSongs()
  local data = open()
  if not data then return {} end
  local out = {}
  for _, song in ipairs(data.sequences) do
    if song.offset and song.size >= 0x40 then out[#out + 1] = song end
  end
  return out
end

function M.readSequence(song)
  local index = type(song) == "table" and song.index or tonumber(song)
  local data = open()
  local entry = data and index and data.sequences[index + 1]
  if not entry or not entry.offset then return nil end
  local blob = readRange(entry.offset, entry.size)
  if not blob then return nil end
  return { data = blob, base = 0, start = 0, size = #blob, index = entry.index }
end

local function waveDescriptor(ctl, instOff, waveOff)
  if not waveOff or waveOff < 0 or waveOff + 0x10 > #ctl then return nil end
  local len = u32(ctl, waveOff)
  local base = u32(ctl, waveOff + 4)
  local loopOff = u32(ctl, waveOff + 8)
  local predOff = u32(ctl, waveOff + 0xC)
  if not len or not base or not predOff then return nil end
  len = len % 0x1000000
  if len < 0x10 or len > 0x200000 then return nil end
  local desc = {
    type = "vadpcm", length = len, base = base, sourceSize = math.floor(len / 9) * 9,
    sampleRate = 32000, predictorOffset = predOff, loopStart = 0, loopEnd = math.floor(len / 9) * 16,
  }
  if loopOff and loopOff > 0 and loopOff + 0x10 <= #ctl then
    local start, stop, count = u32(ctl, loopOff), u32(ctl, loopOff + 4), u32(ctl, loopOff + 8)
    if start and stop and count and count > 0 then
      desc.loopStart, desc.loopEnd = start, math.min(stop, desc.loopEnd)
    end
  end
  return desc
end

local function parseInstrument(ctl, entry, index)
  local rel = u32(ctl, 8 + index * 4)
  if not rel or rel == 0 then return nil end
  local off = rel
  if off + 0x20 > #ctl then return nil end
  local adsrOff = u32(ctl, off + 4)
  local waveOff = u32(ctl, off + 0x10)
  local prevOff = u32(ctl, off + 8)
  local secOff = u32(ctl, off + 0x18)
  local wave = waveDescriptor(ctl, off, waveOff)
    or waveDescriptor(ctl, off, secOff) or waveDescriptor(ctl, off, prevOff)
  if not wave then return nil end
  local def = {
    type = "vadpcm", bank = entry.index, waveID = index,
    waveArchiveID = entry.tbl1 or 0, keyBase = beFloat(ctl, off + 0x14),
    keyBasePrev = beFloat(ctl, off + 0xC), keyBaseSec = beFloat(ctl, off + 0x1C),
    pan = 0x40, gain = 0x7F, wave = wave,
  }
  if adsrOff and adsrOff + 0x10 <= #ctl then
    local adsr = {}
    for i = 0, 7 do adsr[#adsr + 1] = u16(ctl, adsrOff + i * 2) end
    def.adsr = adsr
  end
  return def
end

local function parseDrum(ctl, entry, index)
  local listOff = u32(ctl, 0)
  if not listOff or listOff + index * 4 + 4 > #ctl then return nil end
  local off = u32(ctl, listOff + index * 4)
  if not off or off == 0 or off + 0x10 > #ctl then return nil end
  local waveOff = u32(ctl, off + 4)
  if not waveOff or waveOff == 0 then return nil end
  local wave = waveDescriptor(ctl, off, waveOff)
  if not wave then return nil end
  local def = {
    type = "vadpcm", bank = entry.index, waveID = 0, drum = true,
    waveArchiveID = entry.tbl1 or 0, keyBase = beFloat(ctl, off + 8),
    pan = u8(ctl, off + 1) or 0x40, gain = 0x7F, wave = wave,
  }
  local adsrOff = u32(ctl, off + 0xC)
  if adsrOff and adsrOff + 0x10 <= #ctl then
    local adsr = {}
    for i = 0, 7 do adsr[#adsr + 1] = u16(ctl, adsrOff + i * 2) end
    def.adsr = adsr
  end
  return def
end

function M.readBank(bank)
  local index = type(bank) == "table" and bank.index or tonumber(bank)
  local data = open()
  local entry = data and index and data.banks[index + 1]
  if not entry or not entry.offset then return nil end
  local key = "bank:" .. index
  if sampleCache[key] then return sampleCache[key] end
  local ctl = readRange(entry.offset, entry.size)
  if not ctl then return nil end
  local defs = { drums = {} }
  for i = 0, (entry.normal or 0) - 1 do
    local def = parseInstrument(ctl, entry, i)
    if def then defs[i + 1] = def end
  end
  for i = 0, (entry.percussion or 0) - 1 do
    local def = parseDrum(ctl, entry, i)
    if def then defs.drums[i + 1] = def end
  end
  sampleCache[key] = defs
  return defs
end

-- Matches zeldaret/oot tools/audio/sampleconv/src/codec/vadpcm.c.
local function expandBook(book, order, npred)
  local pages = {}
  local n = 1
  for i = 1, npred do
    local rows = {}
    for k = 0, 7 do rows[k + 1] = {} end
    for j = 0, order - 1 do
      for k = 0, 7 do
        rows[k + 1][j + 1] = book[n] or 0
        n = n + 1
      end
    end
    for k = 1, 7 do
      rows[k + 1][order + 1] = rows[k][order]
    end
    rows[1][order + 1] = 2048
    for k = 1, 7 do
      for j = k, 7 do
        rows[j + 1][k + order + 1] = rows[j - k + 1][order + 1]
      end
    end
    pages[i] = rows
  end
  return pages
end

local function innerProduct(row, input, length)
  local sum = 0
  for i = 1, length do
    sum = sum + row[i] * input[i]
  end
  return math.floor(sum / 2048)
end

local function decodeVadpcm(blob, book, order, npred, outCount)
  local needed = 8 * order * npred
  if type(blob) ~= "string" or type(book) ~= "table" or #book < needed then return "" end
  local pages = expandBook(book, order, npred)
  local frames = math.min(math.floor(#blob / 9), math.ceil(outCount / 16))
  local state, out, produced = {}, {}, 0
  for i = 0, 15 do state[i] = 0 end
  for f = 0, frames - 1 do
    local p = f * 9
    local h = blob:byte(p + 1) or 0
    local scale = 2 ^ (math.floor(h / 16) % 16)
    local predictor = (h % 16) + 1
    if predictor > npred then predictor = 1 end
    local page = pages[predictor]
    local ix = {}
    for i = 0, 15 do
      local b = blob:byte(p + 2 + math.floor(i / 2)) or 0
      local nibble = (i % 2 == 0) and math.floor(b / 16) or (b % 16)
      if nibble >= 8 then nibble = nibble - 16 end
      ix[i] = nibble * scale
    end
    for half = 0, 1 do
      local input = {}
      for i = 0, order - 1 do
        input[i + 1] = state[(2 - half) * 8 - order + i]
      end
      for i = 0, 7 do
        local ind = half * 8 + i
        input[order + i + 1] = ix[ind]
        local v = innerProduct(page[i + 1], input, order + i) + ix[ind]
        state[ind] = v
        if v > 32767 then v = 32767 elseif v < -32768 then v = -32768 end
        out[#out + 1] = pack16(v)
        produced = produced + 1
        if produced >= outCount then return table.concat(out) end
      end
    end
  end
  return table.concat(out)
end

function M.readSample(bank, def)
  if type(def) ~= "table" or type(def.wave) ~= "table" then return nil end
  local wave = def.wave
  local data = open()
  if not data then return nil end
  local tblIndex = def.waveArchiveID or 0
  local tblEntry = data.sampleBanks[tblIndex + 1]
  if not tblEntry or not tblEntry.offset then return nil end
  local key = "sample:" .. tblIndex .. ":" .. (wave.base or 0) .. ":" .. (wave.length or 0)
  if sampleCache[key] then return sampleCache[key] end
  local ctlEntry = data.banks[(def.bank or 0) + 1]
  if not ctlEntry then return nil end
  local ctl = readRange(ctlEntry.offset, math.min(ctlEntry.size, 0x40000))
  if not ctl then return nil end
  local p = wave.predictorOffset
  if not p or p + 8 > #ctl then return nil end
  local order, npred = u32(ctl, p), u32(ctl, p + 4)
  if not order or not npred or order < 1 or order > 8
      or npred < 1 or npred > 16 then return nil end
  local used = 8 * order * npred
  if p + 8 + used * 2 > #ctl then return nil end
  local book = {}
  for i = 0, used - 1 do
    book[i + 1] = i16(ctl, p + 8 + i * 2) or 0
  end
  local blob = readRange(tblEntry.offset + wave.base, wave.sourceSize or wave.length)
  if not blob then return nil end
  local pcm = decodeVadpcm(blob, book, order, npred,
    wave.loopEnd or math.floor(wave.length / 9) * 16)
  local out = {
    data = pcm, sampleRate = wave.sampleRate or 32000,
    loop = wave.loopStart < wave.loopEnd, loopStart = wave.loopStart,
    loopEnd = wave.loopEnd, bank = def.bank, archiveID = tblIndex,
    waveID = def.waveID, format = "vadpcm", sourceSize = #blob,
  }
  sampleCache[key] = out
  return out
end

return M
