-- Plain Lua asserts for the bounded HGSS NDS/SDAT reader.
-- Run: cd <mod> && luajit tests/nds_import_test.lua
package.path = "./?.lua;" .. package.path
local nds = dofile("nds_import.lua")

local function eq(actual, expected, label)
  assert(actual == expected, string.format("%s: expected %s, got %s",
    label, tostring(expected), tostring(actual)))
end

local function p8(n) return string.char(n % 256) end
local function p16(n) return p8(n) .. p8(math.floor(n / 256) % 256) end
local function p32(n) return p16(n % 65536) .. p16(math.floor(n / 65536) % 65536) end
local function patch(s, off, bytes) return s:sub(1, off) .. bytes .. s:sub(off + #bytes + 1) end
local function align(n, a) return math.floor((n + a - 1) / a) * a end

-- One SSEQ with event data starting at 0x1C.
local events = string.char(0xFE, 0x01, 0x00, 0xFF)
local sseq = "SSEQ" .. p16(0xFEFF) .. p16(0x100) .. p32(0) .. p16(0x10) .. p16(1)
sseq = sseq .. "DATA" .. p32(0) .. p32(0x1C) .. events
sseq = patch(sseq, 8, p32(#sseq))
sseq = patch(sseq, 0x14, p32(#sseq - 0x10))

-- One SBNK with a single PCM note definition.
local note = p16(3) .. p16(2) .. string.char(60, 127, 100, 80, 90, 64)
local sbnk = "SBNK" .. p16(0xFEFF) .. p16(0x100) .. p32(0) .. p16(0x10) .. p16(1)
sbnk = sbnk .. "DATA" .. p32(0) .. string.rep("\0", 32) .. p32(1)
sbnk = sbnk .. string.char(1) .. p16(0x40) .. "\0"
sbnk = sbnk .. string.rep("\0", 0x40 - #sbnk) .. note
sbnk = patch(sbnk, 8, p32(#sbnk))
sbnk = patch(sbnk, 0x14, p32(#sbnk - 0x10))

-- Sample blocks: 12-byte SWAV info followed by raw samples.  Wave 3 wraps the
-- same info in a standalone SWAV header; wave 1 is IMA-ADPCM with a 4-byte state.
local function sampleBlock(waveType, loop, rate, loopOffset, loopLength, raw)
  return string.char(waveType, loop and 1 or 0) .. p16(rate) .. p16(0)
    .. p16(loopOffset) .. p32(loopLength) .. raw
end
local pcm8Raw = string.char(0x80, 0x81, 0x7F, 0x00)
local fillerRaw = string.char(0x80, 0x80, 0x80, 0x80)
local adpcmRaw = string.char(0, 0, 0, 0, 0x40, 0x88)
local standalone = "SWAV" .. p16(0xFEFF) .. p16(0x100) .. p32(0x24 + #pcm8Raw)
  .. p16(0x10) .. p16(1) .. "DATA" .. p32(0x14 + #pcm8Raw)
  .. sampleBlock(0, true, 32768, 1, 2, pcm8Raw)
local pairedBlocks = {
  sampleBlock(0, false, 8000, 0, 4, fillerRaw),
  sampleBlock(2, false, 44100, 0, 3, adpcmRaw),
  sampleBlock(0, false, 8000, 0, 4, fillerRaw),
  standalone,
}
local function buildSwar(blocks, explicitPairs)
  local entrySize = explicitPairs and 8 or 4
  local base = 0x3C + #blocks * entrySize
  local offsets, pos = {}, base
  for i, block in ipairs(blocks) do
    offsets[i] = pos
    pos = pos + #block
  end
  local swar = "SWAR" .. p16(0xFEFF) .. p16(0x100) .. p32(pos) .. p16(0x10) .. p16(1)
    .. "DATA" .. p32(pos - 0x10) .. string.rep("\0", 32) .. p32(#blocks)
  for i, off in ipairs(offsets) do
    swar = swar .. p32(off)
    if explicitPairs then swar = swar .. p32(offsets[i + 1] or pos) end
  end
  for _, block in ipairs(blocks) do swar = swar .. block end
  return patch(swar, 8, p32(#swar))
end
local swarPaired = buildSwar(pairedBlocks, true)
local swarReal = buildSwar({ sampleBlock(0, false, 11025, 0, 4, fillerRaw) }, false)

-- SYMB list 0 names the two direct SEQ records.
local names = { "MUS_TEST", "MUS_SFX" }
local nameBase = 0x28 + 4 + 2 * 4
local symb = "SYMB" .. p32(0) .. string.rep("\0", 32)
symb = symb .. p32(2) .. p32(nameBase) .. p32(nameBase + #names[1] + 1)
symb = symb .. names[1] .. "\0" .. names[2] .. "\0"
symb = patch(symb, 4, p32(#symb))
symb = patch(symb, 8, p32(0x28))

local function seqRecord(fileID, bank, player)
  return p16(fileID) .. p16(0) .. p16(bank)
    .. string.char(127, 64, 50, player) .. "\0\0"
end
local info = "INFO" .. p32(0) .. string.rep("\0", 32)
info = info .. p32(2) .. p32(0x34) .. p32(0x40)
info = info .. seqRecord(4, 0, 1) .. seqRecord(4, 0, 0)
info = info .. p32(0) -- SSAR part, empty
info = info .. p32(1) .. p32(0x58)
info = info .. p16(5) .. p16(0)
info = info .. p16(0) .. p16(1) .. p16(0) .. p16(0xFFFF)
info = info .. p32(2) .. p32(0x70) .. p32(0x74)
info = info .. p16(6) .. p16(0) .. p16(7) .. p16(0)
info = patch(info, 4, p32(#info))
info = patch(info, 8, p32(0x28))  -- SEQ part
info = patch(info, 12, p32(0x4C)) -- SSAR part
info = patch(info, 16, p32(0x50)) -- BANK part
info = patch(info, 20, p32(0x64)) -- SWAR part

local symbOff = 0x40
local infoOff = align(symbOff + #symb, 0x20)
local fatOff = align(infoOff + #info, 0x20)
local fatSize = 12 + 8 * 16
local fileOff = align(fatOff + fatSize, 0x20)
local sseqOff = align(fileOff + 12, 0x20)
local swarPairedOff = align(sseqOff + #sseq, 0x20)
local sbnkOff = align(swarPairedOff + #swarPaired, 0x20)
local swarRealOff = align(sbnkOff + #sbnk, 0x20)
local total = swarRealOff + #swarReal

local fat = "FAT " .. p32(0) .. p32(8)
for id = 0, 7 do
  if id == 4 then
    fat = fat .. p32(sseqOff) .. p32(#sseq) .. string.rep("\0", 8)
  elseif id == 5 then
    fat = fat .. p32(sbnkOff) .. p32(#sbnk) .. string.rep("\0", 8)
  elseif id == 6 then
    fat = fat .. p32(swarPairedOff) .. p32(#swarPaired) .. string.rep("\0", 8)
  elseif id == 7 then
    fat = fat .. p32(swarRealOff) .. p32(#swarReal) .. string.rep("\0", 8)
  else
    fat = fat .. string.rep("\0", 16)
  end
end
fat = patch(fat, 4, p32(#fat))

local sdat = string.rep("\0", total)
local function place(off, bytes)
  assert(off >= 0 and off + #bytes <= total, "placement out of range")
  sdat = sdat:sub(1, off) .. bytes .. sdat:sub(off + #bytes + 1)
end
place(symbOff, symb)
place(infoOff, info)
place(fatOff, fat)
place(fileOff, "FILE" .. p32(total - fileOff) .. p32(8))
place(sseqOff, sseq)
place(sbnkOff, sbnk)
place(swarPairedOff, swarPaired)
place(swarRealOff, swarReal)

local header = "SDAT" .. p16(0xFEFF) .. p16(0x100) .. p32(total) .. p16(0x40) .. p16(4)
header = header
  .. p32(symbOff) .. p32(#symb)
  .. p32(infoOff) .. p32(#info)
  .. p32(fatOff) .. p32(#fat)
  .. p32(fileOff) .. p32(total - fileOff)
  .. string.rep("\0", 16)
sdat = patch(sdat, 0, header)

-- ROM with SDAT well away from the preferred HGSS offset, to exercise scan.
local rom = string.rep("\0", 0x1000) .. sdat
local imports = {
  info = function(self, id)
    eq(id, "hgss_nds", "import id")
    return { filename = "roms/hgss.nds", size = #rom, md5 = "abc123" }
  end,
  read = function(self, id, offset, length)
    eq(id, "hgss_nds", "read id")
    assert(length <= 8 * 1024 * 1024, "read is bounded")
    if offset < 0 or offset + length > #rom then return nil end
    return rom:sub(offset + 1, offset + length)
  end,
}
local stored = {}
local cache = {
  write = function(self, path, bytes) stored[path] = bytes return true end,
  read = function(self, path) return stored[path] end,
  info = function(self, path) return stored[path] and { size = #stored[path] } or nil end,
}

nds.install({ imports = imports, cache = cache })
local ctx, err = nds.open()
assert(ctx, err)
local status = nds.status()
eq(status.available, true, "status available")
eq(status.filename, "hgss.nds", "status filename")
eq(status.size, #rom, "status size")
eq(status.fingerprint, "abc123", "status fingerprint")
eq(status.sdatOffset, 0x1000, "status sdat offset")
eq(status.sdatSize, total, "status sdat size")
eq(status.songCount, 1, "status song count")

local songs = nds.listSongs()
eq(#songs, 1, "filtered music songs")
eq(songs[1].name, "MUS_TEST", "song name")
eq(songs[1].index, 0, "song index")
eq(songs[1].bank, 0, "song bank")
eq(songs[1].player, 1, "song player")
eq(songs[1].source, "seq", "song source")
eq(songs[1].fileID, 4, "song file id")

local seq = nds.readSequence(songs[1])
assert(seq, "readSequence returned nil")
eq(seq.data:sub(1, 4), "SSEQ", "sequence data")
eq(seq.base, 0x1C, "sequence base")
eq(seq.start, 0x1C, "sequence start")
eq(seq.size, #sseq, "sequence size")
eq(seq.data:sub(seq.base + 1, seq.base + #events), events, "sequence events")

local bank = nds.readBank(0)
assert(bank, "readBank returned nil")
eq(bank.fileID, 5, "bank file id")
eq(bank.count, 1, "instrument count")
local inst = bank.instruments[1]
eq(inst.type, 1, "instrument type")
eq(inst.keyLow, 0, "instrument keyLow")
eq(inst.keyHigh, 127, "instrument keyHigh")
eq(inst.notes[1].waveID, 3, "note wave id")
eq(inst.notes[1].waveArchiveID, 2, "note wave archive")
eq(inst.notes[1].pitch, 60, "note pitch")
assert(nds.readBank(1) == nil, "invalid bank rejected")
assert(nds.readSequence({}) == nil, "invalid song rejected")

local swarRecord = ctx.swarRecords[1]
assert(swarRecord, "swar record")
eq(swarRecord.fileID, 6, "swar file id")
eq(swarRecord.index, 0, "swar index")
eq(swarRecord.sdatIndex, 1, "swar sdat index")
eq(swarRecord.sdatOffset, 0x1000, "swar sdat offset")
assert(swarRecord.sdatIndex == 1, "swar sdat resolved")
assert(ctx.swarRecords[2] and ctx.swarRecords[2].fileID == 7, "second swar record")
eq(bank.swarIDs[1], 0, "bank swar id")
eq(bank.swarIDs[2], 1, "bank second swar id")
eq(bank.swarIDs[3], 0, "bank note swar id")

local function sampleAt(data, i)
  local lo, hi = data:byte(i * 2 + 1), data:byte(i * 2 + 2)
  local v = lo + hi * 256
  return v >= 32768 and v - 65536 or v
end

local sample = nds.readSample(0, bank.notes[1])
assert(sample, "readSample returned nil")
eq(sample.bankID, 0, "sample bank id")
eq(sample.archiveID, 2, "sample archive id")
eq(sample.waveID, 3, "sample wave id")
eq(sample.format, 0, "sample format")
eq(sample.sampleRate, 32768, "sample rate")
eq(sample.loop, true, "sample loop")
eq(sample.loopStart, 1, "sample loop start")
eq(sample.loopEnd, 3, "sample loop end")
eq(sample.sourceSize, #pcm8Raw, "sample source size")
eq(#sample.data, #pcm8Raw * 2, "decoded sample size")
eq(sampleAt(sample.data, 0), 0, "pcm8 sample 0")
local aliasDef = {}
for k, v in pairs(bank.notes[1]) do aliasDef[k] = v end
aliasDef.waveID = nil
aliasDef.waveID_dutyCycle = 3
local aliasSample = nds.readSample(0, aliasDef)
assert(aliasSample and aliasSample.waveID == 3, "waveID_dutyCycle aliases waveID")
eq(sampleAt(sample.data, 1), 1, "pcm8 sample 1")
eq(sampleAt(sample.data, 2), -1, "pcm8 sample 2")
eq(sampleAt(sample.data, 3), -128, "pcm8 sample 3")
assert(nds.readSample(0, bank.notes[1]) == sample, "sample cache")

local adpcm = nds.readSample(0, { waveArchiveID = 2, waveID = 1 })
assert(adpcm, "adpcm sample returned nil")
eq(adpcm.format, 2, "adpcm format")
eq(adpcm.sampleRate, 44100, "adpcm sample rate")
eq(adpcm.loop, false, "adpcm loop")
eq(adpcm.loopStart, 0, "adpcm loop start")
eq(adpcm.loopEnd, 3, "adpcm loop end")
eq(adpcm.sourceSize, #adpcmRaw, "adpcm source size")
eq(#adpcm.data, 8, "decoded adpcm size")
eq(sampleAt(adpcm.data, 0), 0, "adpcm sample 0")
eq(sampleAt(adpcm.data, 1), 7, "adpcm sample 1")
eq(sampleAt(adpcm.data, 2), 6, "adpcm sample 2")
eq(sampleAt(adpcm.data, 3), 5, "adpcm sample 3")

local realLayout = nds.readSample(0, { waveArchiveID = 1, waveID = 0 })
assert(realLayout, "4-byte offset table sample returned nil")
eq(realLayout.sourceSize, #fillerRaw, "real layout source size")
local fallback = nds.readSample(0, { waveArchiveID = 3, waveID = 3 })
assert(fallback and fallback.data == sample.data, "missing archive falls back")
assert(nds.readSample(0, { waveArchiveID = 2, waveID = 99 }) == nil, "invalid wave rejected")
assert(nds.readSample(1, bank.notes[1]) == nil, "invalid bank sample rejected")
assert(nds.readSample(0, nil) == nil, "invalid note rejected")
local cachedSample = nds.readSample(0, { waveArchiveID = 2, waveID = 2 })
assert(cachedSample and cachedSample.sourceSize == #fillerRaw, "second paired wave")

-- Reopen must come from cache; only the cached SDAT header is revalidated.
local romRead = imports.read
imports.read = function(self, id, offset, length)
  if length == 0x40 then return romRead(self, id, offset, length) end
  error("cache miss on reopen")
end
local cached = nds.open()
assert(cached == ctx, "reopen returns cached ctx")
eq(nds.status().available, true, "cached status")
assert(cached.swarRecords and cached.swarRecords[1].fileID == 6, "cached swar record")

nds.install({ cache = cache })
local missing, reason = nds.open()
assert(missing == nil and reason == "missing", "no import reports missing")
eq(nds.status().available, false, "missing status")
assert(#nds.listSongs() == 0, "missing import has no songs")

print("nds_import_test OK")
