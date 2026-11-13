-- Standalone: cd <mod> && luajit tests/versions_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local V = require("versions")
local available = { red = true, blue = true, gold = true, crystal = true, firered = true }

local function imported(version) return available[version] == true end
local function has(version, label)
  if not imported(version) then return false end
  if version == "red" or version == "blue" then
    return label == "Music_Pokecenter" or label == "Music_TitleScreen"
  end
  if version == "gold" or version == "crystal" then
    return label == "Music_PokemonCenter" or label == "Music_TitleScreen"
  end
  return false
end

local function labels(list)
  local out = {}
  for _, item in ipairs(list) do out[#out + 1] = item.version .. ":" .. item.label end
  table.sort(out)
  return table.concat(out, ",")
end

-- Gen1 host can source Gen2, and skips its own version.
assert(labels(V.candidates("Music_Pokecenter", 1, "red", has))
  == "blue:Music_Pokecenter,crystal:Music_PokemonCenter,gold:Music_PokemonCenter")

-- Gen2 host sees Gen1 too, still excluding itself.
assert(labels(V.candidates("Music_PokemonCenter", 2, "gold", has))
  == "blue:Music_Pokecenter,crystal:Music_PokemonCenter,red:Music_Pokecenter")

-- Gen3 native ids resolve through the same group; only chip sources surface.
assert(labels(V.candidates("MUS_POKE_CENTER", 3, "firered", has))
  == "blue:Music_Pokecenter,crystal:Music_PokemonCenter,gold:Music_PokemonCenter,red:Music_Pokecenter")

-- Missing imports disappear.
assert(#V.candidates("Music_Pokecenter", 1, "red", function() return false end) == 0)

-- Mode filters and deterministic shuffle.
local list = V.candidates("Music_Pokecenter", 1, "red", has)
local gen2 = V.pick("gen2", list, nil, function() return 1 end)
assert(gen2 and gen2.generation == 2)
local gen1 = V.pick("gen1", list, nil, function() return 1 end)
assert(gen1 and gen1.generation == 1)
assert(V.pick("native", list) == nil)
assert(V.pick("gen3", list) == nil)

local seq = 0
local function rng(n) seq = seq + 1; return (seq % n) + 1 end
local a = V.pick("shuffle", list, nil, rng)
local b = V.pick("shuffle", list, a.version .. ":" .. a.label, rng)
assert(b and (a.version .. ":" .. a.label) ~= (b.version .. ":" .. b.label))

print("versions ok")
