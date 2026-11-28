-- Stadium 2 sequence names, cross-game aliases, and taxonomy.
-- Run: cd <mod> && luajit tests/n64_mapping_test.lua
package.path = "./?.lua;./tests/?.lua;" .. package.path
local map = dofile("n64_song_map.lua")
local versions = dofile("versions.lua")

local function index(label)
  local song = assert(map.mappedSongFor(label), "unmapped label: " .. tostring(label))
  return song.index
end

assert(index("SEQ_N64_00") == 0)
assert(index("SEQ_N64_0") == 0)
assert(index("N64:SEQ_N64_4") == 4)
assert(index("N64:SEQ_N64_41") == 0x29)
assert(index("Music_GymLeaderBattle") == 0x29)
assert(index("MUS_VS_GYM_LEADER") == 0x29)
assert(index("Music_Gym") == 0x2B)
assert(index("Music_FinalBattle") == 0x2C)
assert(index("Music_MeetRival") == 0x66)
assert(index("Music_RocketBattle") == 0x64)
assert(index("Music_OaksLab") == 0x2F)
assert(index("N64:Music_TitleScreen") == 0x4B)
assert(map.mappedSongFor("SEQ_N64_137") == nil)
assert(map.mappedSongFor("not-a-song") == nil)

assert(map.keyFor("Music_OaksLab") == "SEQ_N64_47")
assert(map.labelFor("SEQ_N64_75") == "SEQ_N64_75")
assert(map.nameForIndex(0x29) == "Gym Leader Battle")
assert(map.nameForIndex(0x42) == "Pokemon Select")
assert(map.nameForIndex(0x00) == "SEQ_N64_00")
local names = map.namesFor("SEQ_N64_41")
local found = false
for _, name in ipairs(names) do
  if name == "Music_GymLeaderBattle" then found = true end
end
assert(found)

assert(versions.variantKind("Music_N64MixTitleScreen_red") == "n64_mix")
assert(versions.variantKind({ id = "x", n64Mix = true }) == "n64_mix")
assert(versions.variantKind({ candidate = { n64Mix = true } }) == "n64_mix")
assert(versions.variantLabel("n64_mix") == "N64 Mix")
assert(select(2, versions.qualityRank("n64_mix"))
  > select(2, versions.qualityRank("g4_gb")))
local alt = false
for _, kind in ipairs(versions.ALTERNATIVE_KINDS) do
  if kind == "n64_mix" then alt = true end
end
assert(alt)

print("n64_mapping_test: ok")
