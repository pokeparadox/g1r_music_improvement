-- Plain Lua asserts for music_menu navigation.
-- Run: cd <mod> && luajit tests/music_menu_test.lua
package.path = "./?.lua;" .. package.path
local versions = dofile("versions.lua")
local menu = dofile("music_menu.lua")

local function eq(actual, expected, label)
  assert(actual == expected, string.format("%s: expected %s, got %s",
    label, tostring(expected), tostring(actual)))
end

local d = versions.describe("Music_ImprovedPokecenter_gold", 1)
eq(d.generation, 2, "variant generation")
eq(d.name, "Pokemon Center", "variant name")
eq(d.variant, "g2_improved", "guided variant")
eq(d.label, "G2 (Improved)", "guided label")

d = versions.describe("Music_StockPokemonCenter_red", 2)
eq(d.variant, "g1", "stock variant")
eq(d.label, "G1", "stock label")

d = versions.describe("Music_MixCities1_firered", 1)
eq(d.variant, "g3_mix", "mix variant")
eq(d.label, "G3 (Mix)", "mix label")

d = versions.describe("MUS_OAK_LAB", 3)
eq(d.generation, 3, "native generation")
eq(d.kind, nil, "native has no kind")
eq(d.label, "G3", "native label")

-- Fixed origin order; LEFT/RIGHT cycles only present variants.
local entry = {
  name = "Pallet Town",
  nativeId = "Music_PalletTown",
  variants = {
    { mix = true, version = "firered", generation = 3, id = "M3" },
    { version = "gold", generation = 2, improved = true, id = "I2" },
    { native = true, generation = 1 },
    { version = "gold", generation = 2, improved = false, id = "S2" },
    { version = "red", generation = 1, improved = false, id = "S1" },
    { version = "red", generation = 1, improved = true, id = "I1" },
    { native = true, generation = 3, id = "N3" },
  },
}
eq(menu.rightText(entry.variants[1]), "G3 (Mix)", "mix label")
eq(menu.rightText(entry.variants[2]), "G2 (Improved)", "g2 guided label")
eq(menu.rightText(entry.variants[3]), "G1", "g1 stock label")
eq(menu.rightText(entry.variants[4]), "G2", "g2 stock label")
eq(menu.rightText(entry.variants[5]), "G1", "g1 stock label dup")
eq(menu.rightText(entry.variants[6]), "G1 (Improved)", "g1 guided label")

local keys = menu.versionKeys(entry)
eq(#keys, 6, "version slots")
eq(table.concat(keys, ","), "g1,g1_improved,g2,g2_improved,g3,g3_mix", "menu order")

eq(menu.select(entry, "g3_mix").id, "M3", "mix slot")
eq(menu.select(entry, "g1").native, true, "native slot")
eq(menu.cycle(entry, "g1", 1).id, "I1", "cycle forward")
eq(menu.cycle(entry, "g3_mix", 1).native, true, "cycle wraps forward")
eq(menu.cycle(entry, "g1", -1).id, "M3", "cycle wraps back")
eq(menu.title(), "MUSIC TEST", "title")

print("music_menu ok")
