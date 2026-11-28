-- Minimal Pokémon Stadium 2 ROM facade for N64 import/mix tests.
package.path = "./?.lua;./tests/?.lua;" .. package.path

local M = {}

local SEQ_TABLE, SEQ_FONT_TABLE, CTL_TABLE, TBL_TABLE = 0x87020, 0x878C0, 0x86960, 0x86F30
local SEQ_DATA, CTL_DATA, TBL_DATA = 0x14D6660, 0x4AD450, 0x50F7E0

local function p16(n)
  n = n % 0x10000
  return string.char(math.floor(n / 256), n % 256)
end

local function p32(n)
  n = math.floor(n) % 0x100000000
  return string.char(math.floor(n / 0x1000000) % 256,
    math.floor(n / 0x10000) % 256, math.floor(n / 256) % 256, n % 256)
end

local function patch(s, off, bytes)
  return s:sub(1, off) .. bytes .. s:sub(off + #bytes + 1)
end

local function tableBlob(count, size, normal, tbl1)
  local header = p16(count) .. string.rep("\0", 14)
  local entry = p32(0) .. p32(size)
    .. string.char(0, 0, tbl1 or 0, 0, normal or 0, 0, 0, 0)
  return header .. entry
end

local ctl = string.rep("\0", 0x200)
ctl = patch(ctl, 8, p32(0x40)) -- instrument 0
ctl = patch(ctl, 0x40, p32(0x80) .. p32(0x80) .. p32(0x60) .. p32(0))
ctl = patch(ctl, 0x54, p32(0x3F800000)) -- keyBase = 1.0 -> MIDI 60
ctl = patch(ctl, 0x60, p32(0x12) .. p32(0) .. p32(0) .. p32(0x100))
ctl = patch(ctl, 0x80, string.rep(p16(32768), 8))
ctl = patch(ctl, 0x100, p32(1) .. p32(8) .. string.rep("\0", 0x80))

local seq = string.rep("\0", 0x40)
seq = patch(seq, 0, string.char(0xDD, 0x78, 0x90, 0x00, 0x07))
seq = patch(seq, 7, string.char(0xC4, 0x88, 0x00, 0x0B, 0x6D, 0x30, 0x7F, 0xFF))

local chunks = {}
local function place(off, bytes) chunks[#chunks + 1] = { off = off, data = bytes } end
place(0, string.char(0x80, 0x37, 0x12, 0x40))
place(SEQ_TABLE, tableBlob(1, #seq, 0, 0))
place(SEQ_FONT_TABLE, p16(0x100))
place(SEQ_FONT_TABLE + 0x100, string.char(1, 0))
place(CTL_TABLE, tableBlob(1, #ctl, 1, 0))
place(TBL_TABLE, tableBlob(1, 9, 0, 0))
place(SEQ_DATA, seq)
place(CTL_DATA, ctl)
place(TBL_DATA, string.rep("\0", 9))

function M.imports()
  return {
    read = function(_, id, off, length)
      assert(id == "n64_stadium2", "unexpected import id: " .. tostring(id))
      local out, pos = {}, 0
      while pos < length do
        local here, take = off + pos, nil
        for _, chunk in ipairs(chunks) do
          if here >= chunk.off and here < chunk.off + #chunk.data then
            take = math.min(chunk.off + #chunk.data - here, length - pos)
            out[#out + 1] = chunk.data:sub(here - chunk.off + 1, here - chunk.off + take)
            break
          end
        end
        if not take then
          take = length - pos
          out[#out + 1] = string.rep("\0", take)
        end
        pos = pos + take
      end
      return table.concat(out)
    end,
    info = function(_, id)
      assert(id == "n64_stadium2")
      return { filename = "stadium2.z64", size = 0x15000000,
        md5 = "1561c75d11cedf356a8ddb1a4a5f9d5d" }
    end,
  }
end

function M.cache()
  return { write = function() end }
end

return M
