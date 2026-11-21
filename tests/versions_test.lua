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
assert(V.variantLabel("g2_improved") == "G2E")
assert(V.variantLabel({ id = "Music_MixCities1_firered" }) == "G3 Mix")
assert(V.variantLabel({ native = true, generation = 3 }) == "G3")

-- Host-native improved IDs have no source suffix; label from loaded game.
assert(V.variantKind("Music_ImprovedTitleScreen", 2) == "g2_improved")
assert(V.describe("Music_ImprovedTitleScreen", 2).label == "G2E")
assert(V.describe("Music_ImprovedTitleScreen", 1).label == "G1E")
assert(V.describe("Music_TitleScreen", 2).label == "G2")

-- RSE aliases normalise to the canonical FRLG label before mix lookup.
assert(V.canonicalGen3Label("MUS_RG_PALLET") == "MUS_PALLET")
assert(V.canonicalGen3Label("MUS_GSC_PEWTER") == "MUS_PEWTER")
assert(V.canonicalGen3Label("MUS_GSC_ROUTE38") == "MUS_ROUTE37")
assert(V.canonicalGen3Label("MUS_RG_NOPE") == "MUS_RG_NOPE")
assert(V.nameFor("MUS_RG_PALLET") == "Pallet Town")
assert(V.groupFor("MUS_GSC_PEWTER") == V.byLabel.MUS_PEWTER)
assert(table.concat(V.mixLabelsFor("MUS_PALLET", "firered"), ",") == "MUS_PALLET")
assert(table.concat(V.mixLabelsFor("MUS_PALLET", "emerald"), ",")
  == "MUS_RG_PALLET,MUS_PALLET")
assert(table.concat(V.mixLabelsFor("MUS_PEWTER", "ruby"), ",")
  == "MUS_PEWTER,MUS_GSC_PEWTER")
assert(table.concat(V.mixLabelsFor("MUS_GSC_ROUTE38", "emerald"), ",")
  == "MUS_RG_ROUTE37,MUS_ROUTE37,MUS_GSC_ROUTE38")
assert(V.byLabel.MUS_ROUTE37 and V.byLabel.MUS_ROUTE37.gen2 == "Music_Route37")
assert(V.byLabel.MUS_GSC_RADIO_TOWER_TAKEOVER
  and V.byLabel.MUS_GSC_RADIO_TOWER_TAKEOVER.gen2 == "Music_LakeOfRageRocketRadio")
assert(table.concat(V.mixLabelsFor("MUS_GSC_RADIO_TOWER_TAKEOVER", "ruby"), ",")
  == "MUS_GSC_RADIO_TOWER_TAKEOVER")
assert(V.mixAllowed(V.byLabel.MUS_GSC_RADIO_TOWER_TAKEOVER, 2)
  and not V.mixAllowed(V.byLabel.MUS_GSC_RADIO_TOWER_TAKEOVER, 1))

-- G3 Mix title exists on RBY but clashes with GSC title screen.
assert(not V.mixAllowed(nil, 2), "GBA-only labels skip Mix on Gen2")
assert(V.mixAllowed(V.byLabel.Music_TitleScreen, 1), "RBY keeps Mix title")
assert(not V.mixAllowed(V.byLabel.Music_TitleScreen, 2), "GSC skips Mix title")
assert(V.mixAllowed(V.byLabel.Music_PalletTown, 2), "mapped GSC songs keep Mix")
assert(V.mixAllowed(V.byLabel.Music_KantoGymBattle, 2), "GSC Kanto tracks keep Mix")

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
