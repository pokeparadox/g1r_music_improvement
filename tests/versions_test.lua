-- Plain Lua asserts for version equivalence/candidate selection.
-- Run: cd <mod> && luajit tests/versions_test.lua
package.path = "./?.lua;" .. package.path
local V = dofile("versions.lua")

local recs = {
  { id = "Music_ImprovedCities1_red" },
  { id = "Music_ImprovedCities1_gold" },
  { id = "Music_StockCities1_red" },
  { id = nil },
}
assert(#V.eligible("shuffle_improved", recs) == 2)
assert(V.eligible("shuffle_improved", recs)[1].id == "Music_ImprovedCities1_red")
assert(#V.eligible("shuffle_stock", recs) == 1)
assert(V.eligible("shuffle_stock", recs)[1].id == "Music_StockCities1_red")
assert(#V.eligible("shuffle_all", recs) == 4)
assert(#V.eligible("gen1", recs) == 4)
assert(#V.eligible("shuffle_improved", nil) == 0)

-- Canonical kinds and labels for toasts/menu/settings.
assert(V.variantKind({ id = "Music_ImprovedCities1_gold", generation = 2 }) == "g2_improved")
-- Source comes from the ID suffix, never from the host generation.
assert(V.variantKind({ id = "Music_ImprovedCities1_gold", generation = 1 }) == "g2_improved")
assert(V.variantKind({ generation = 1, version = "gold" }) == "g2")
assert(V.variantKind({ generation = 1, candidate = { version = "firered" }, mix = true }) == "g3_mix")
assert(V.variantKind({ id = "Music_StockCities1_red", generation = 1 }) == "g1")
assert(V.variantKind({ id = "MUS_CITIES1", generation = 3, native = true }) == "g3")
assert(V.variantKind("Music_MixCities1_firered") == "g3_mix")
assert(V.variantLabel("g1") == "G1")
assert(V.variantLabel("g2_improved") == "G2+")
assert(V.variantLabel({ id = "Music_MixCities1_firered" }) == "G3 Mix")
assert(V.variantLabel({ native = true, generation = 3 }) == "G3")

local d = V.describe("Music_MixCities1_firered", 1)
assert(d.generation == 3 and d.kind == "Mix" and d.mix)
assert(d.variant == "g3_mix" and d.label == "G3 Mix")
assert(d.name == V.nameFor("MUS_Cities1"))

d = V.describe("MUS_OAK_LAB", 3)
assert(d.variant == "g3" and d.label == "G3")

-- Shuffle OFF quality order: G3 Mix, improved (host first), stock (host first).
local pool = {
  { id = "Music_StockCities1_red", generation = 1, improved = false },
  { id = "Music_StockCities1_gold", generation = 2, improved = false },
  { id = "Music_ImprovedCities1_red", generation = 1, improved = true },
  { id = "Music_ImprovedCities1_gold", generation = 2, improved = true },
  { id = "Music_MixCities1_firered", mix = true },
}
local ranked = V.sortByQuality(pool, 1)
assert(ranked[1].id == "Music_MixCities1_firered")
-- Native G3 is the real arrangement; Mix is the backported approximation.
assert(V.sortByQuality({
  { id = "Music_MixCities1_firered", mix = true },
  { id = "MUS_CITIES1", native = true, generation = 3 },
}, 3)[1].id == "MUS_CITIES1")
assert(ranked[2].id == "Music_ImprovedCities1_red")
assert(ranked[3].id == "Music_ImprovedCities1_gold")
assert(ranked[4].id == "Music_StockCities1_red")
assert(ranked[5].id == "Music_StockCities1_gold")

local enabled = V.filterEnabled(pool, {
  g1 = false, g1_improved = false, g3_mix = false,
  g2_improved = true, g2 = true,
})
assert(#enabled == 2)
assert(V.sortByQuality(enabled, 1)[1].id == "Music_ImprovedCities1_gold")

print("versions ok")
