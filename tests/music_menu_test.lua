-- Plain Lua asserts for versions.describe and music_menu navigation.
-- Run: cd <mod> && luajit tests/music_menu_test.lua
package.path = "./?.lua;" .. package.path
local versions = dofile("versions.lua")
local menu = dofile("music_menu.lua")

local function eq(actual, expected, label)
  assert(actual == expected, string.format("%s: expected %s, got %s",
    label, tostring(expected), tostring(actual)))
end

-- describe: variants use the source version's generation and canonical name.
local d = versions.describe("Music_ImprovedPokecenter_gold", 1)
eq(d.generation, 2, "variant generation")
eq(d.name, "Pokemon Center", "variant name")
eq(d.kind, "Improved", "variant kind")

d = versions.describe("Music_StockPokemonCenter_red", 2)
eq(d.generation, 1, "stock generation")
eq(d.name, "Pokemon Center", "stock name")
eq(d.kind, "Stock", "stock kind")

-- plain ids keep the host generation but use the canonical group name.
d = versions.describe("MUS_OAK_LAB", 3)
eq(d.generation, 3, "native generation")
eq(d.name, "Oak's Lab", "native name")
eq(d.kind, nil, "native has no kind")

d = versions.describe("Music_Cities1", 1)
eq(d.generation, 1, "host generation")
eq(d.name, "Viridian City", "group name")

-- music_menu: native first, then STK/IMP per generation, wrapping.
local entry = {
  name = "Pallet Town",
  nativeId = "Music_PalletTown",
  variants = {
    { native = true, generation = 1 },
    { version = "gold", generation = 2, improved = false, id = "S2" },
    { version = "gold", generation = 2, improved = true, id = "I2" },
    { version = "crystal", generation = 2, improved = true, id = "I3" },
  },
}
eq(menu.rightText(entry.variants[1]), "G1", "native label")
eq(menu.rightText(entry.variants[2]), "G2 STK", "stock label")
eq(menu.rightText(entry.variants[3]), "G2 IMP", "improved label")
eq(#menu.versionKeys(entry), 3, "version slots")

eq(menu.select(entry, "", true).native, true, "native slot")
eq(menu.select(entry, "gold", true).id, "I2", "improved pick")
eq(menu.select(entry, "gold", false).id, "S2", "stock pick")
eq(menu.select(entry, "crystal", false).id, "I3", "fallback other kind")

eq(menu.cycle(entry, "", 1, true).version, "gold", "cycle forward")
eq(menu.cycle(entry, "", -1, true).version, "crystal", "cycle wraps back")
eq(menu.cycle(entry, "crystal", 1, true).native, true, "cycle wraps forward")
eq(menu.title(true), "MUSIC TEST [IMP]", "improved title")
eq(menu.title(false), "MUSIC TEST [STK]", "stock title")

print("music_menu ok")
