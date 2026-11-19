-- Cross-version song equivalents.  Gen1/Gen2 music is chip bytecode, so any
-- imported Gen1/Gen2 dataset can feed the same translation pipeline.  Gen3
-- entries only identify native GBA songs; GBA audio itself is never used as a
-- source here.

local M = {}

M.VERSIONS = {
  { id = "red", generation = 1 },
  { id = "blue", generation = 1 },
  { id = "yellow", generation = 1 },
  { id = "gold", generation = 2 },
  { id = "silver", generation = 2 },
  { id = "crystal", generation = 2 },
  { id = "firered", generation = 3 },
  { id = "leafgreen", generation = 3 },
  { id = "emerald", generation = 3 },
  { id = "ruby", generation = 3 },
  { id = "sapphire", generation = 3 },
}

M.BY_ID = {}
for _, entry in ipairs(M.VERSIONS) do M.BY_ID[entry.id] = entry end

-- One group per recognisable tune.  Labels must match the dataset registries.
-- `name` is the canonical display name used by toasts and the music test menu.
M.EQUIVALENTS = {
  { gen1 = "Music_Pokecenter", gen2 = "Music_PokemonCenter", gen3 = "MUS_POKE_CENTER",
    name = "Pokemon Center" },

  { gen1 = "Music_PalletTown", gen2 = "Music_PalletTown", gen3 = "MUS_PALLET",
    name = "Pallet Town" },
  { gen1 = "Music_Cities1", gen2 = "Music_ViridianCity", gen3 = "MUS_PEWTER",
    name = "Viridian City" },
  { gen1 = "Music_TitleScreen", gen3 = "MUS_TITLE", hosts = { "firered", "leafgreen" },
      hostSources = { firered = { "red" }, leafgreen = { "blue" } },
      name = "Title Screen" },
  { gen1 = "Music_IntroBattle", gen3 = "MUS_INTRO_FIGHT", hosts = { "firered", "leafgreen" },
      hostSources = { firered = { "red" }, leafgreen = { "blue" } }, oneshot = true,
      name = "Intro Battle" },
  { gen1 = "Music_Cities1", gen2 = "Music_ViridianCity", gen3 = "MUS_PEWTER",
    name = "Pewter City" },
  { gen1 = "Music_Celadon", gen2 = "Music_CeladonCity", gen3 = "MUS_CELADON",
    name = "Celadon City" },
  { gen1 = "Music_Vermilion", gen2 = "Music_VermilionCity", gen3 = "MUS_VERMILLION",
    name = "Vermilion City" },
  { gen1 = "Music_Lavender", gen2 = "Music_LavenderTown", gen3 = "MUS_LAVENDER",
    name = "Lavender Town" },
  { gen1 = "Music_Routes1", gen2 = "Music_Route1", gen3 = "MUS_ROUTE1",
    name = "Route 1" },
  { gen1 = "Music_Routes2", gen2 = "Music_Route2", gen3 = "MUS_ROUTE2",
    name = "Route 2" },
  { gen1 = "Music_Routes3", gen2 = "Music_Route3", gen3 = "MUS_ROUTE3",
    name = "Route 3" },
  { gen1 = "Music_Routes4", gen2 = "Music_Route12", name = "Route 12" },
  { gen1 = "Music_Gym", gen2 = "Music_Gym", gen3 = "MUS_GYM", name = "Gym" },
  { gen1 = "Music_GymLeaderBattle", gen2 = "Music_KantoGymBattle", gen3 = "MUS_VS_GYM_LEADER",
    name = "Gym Leader Battle" },
  { gen1 = "Music_TrainerBattle", gen2 = "Music_KantoTrainerBattle", gen3 = "MUS_VS_TRAINER",
    name = "Trainer Battle" },
  { gen1 = "Music_WildBattle", gen2 = "Music_KantoWildBattle", gen3 = "MUS_VS_WILD",
    name = "Wild Battle" },
  { gen1 = "Music_FinalBattle", gen2 = "Music_ChampionBattle", gen3 = "MUS_VS_CHAMPION",
    name = "Champion Battle" },
  { gen1 = "Music_MeetRival", gen2 = "Music_LookRival", gen3 = "MUS_ENCOUNTER_RIVAL",
    name = "Rival Encounter" },
  { gen1 = "Music_TrainerBattle", gen2 = "Music_RocketBattle", gen3 = "MUS_VS_TRAINER",
    name = "Team Rocket Battle" },
  { gen1 = "Music_MeetEvilTrainer", gen2 = "Music_LookRocket", gen3 = "MUS_ENCOUNTER_ROCKET",
    name = "Team Rocket Encounter" },
  { gen1 = "Music_Dungeon1", gen2 = "Music_MtMoon", gen3 = "MUS_MT_MOON",
    name = "Mt. Moon" },
  { gen1 = "Music_Dungeon2", gen2 = "Music_UnionCave", name = "Union Cave" },
  { gen1 = "Music_Dungeon3", gen2 = "Music_DarkCave", name = "Dark Cave" },
  { gen1 = "Music_IndigoPlateau", gen2 = "Music_IndigoPlateau", gen3 = "MUS_VICTORY_ROAD",
    name = "Indigo Plateau" },
  { gen1 = "Music_Surfing", gen2 = "Music_Surf", gen3 = "MUS_SURF", name = "Surfing" },
  { gen1 = "Music_BikeRiding", gen2 = "Music_Bicycle", gen3 = "MUS_CYCLING",
    name = "Bicycle" },
  { gen1 = "Music_Credits", gen2 = "Music_Credits", gen3 = "MUS_CREDITS",
    name = "Credits" },
  { gen1 = "Music_HallOfFame", gen2 = "Music_HallOfFame", gen3 = "MUS_HALL_OF_FAME",
    name = "Hall of Fame" },
  { gen1 = "Music_GameCorner", gen2 = "Music_GameCorner", gen3 = "MUS_GAME_CORNER",
    name = "Game Corner" },
  { gen1 = "Music_SSAnne", gen2 = "Music_SSAqua", gen3 = "MUS_SS_ANNE",
    name = "S.S. Anne" },
  { gen1 = "Music_PokemonTower", gen2 = "Music_TinTower", gen3 = "MUS_POKE_TOWER",
    name = "Pokemon Tower" },
  { gen1 = "Music_CinnabarMansion", gen3 = "MUS_POKE_MANSION",
    name = "Pokemon Mansion" },

  { gen1 = "Music_MeetProfOak", gen2 = "Music_ProfOak", gen3 = "MUS_OAK",
    name = "Professor Oak" },
  { gen1 = "Music_OaksLab", gen3 = "MUS_OAK_LAB", hosts = { "firered", "leafgreen" },
      hostSources = { firered = { "red", "blue", "yellow" }, leafgreen = { "red", "blue", "yellow" } },
      name = "Oak's Lab" },
  { gen1 = "Music_DefeatedGymLeader", gen2 = "Music_GymLeaderVictory", gen3 = "MUS_VICTORY_GYM_LEADER",
    name = "Gym Leader Victory" },
  { gen1 = "Music_DefeatedTrainer", gen2 = "Music_TrainerVictory", gen3 = "MUS_VICTORY_TRAINER",
    name = "Trainer Victory" },
  { gen1 = "Music_DefeatedWildMon", gen2 = "Music_WildPokemonVictory", gen3 = "MUS_VICTORY_WILD",
    name = "Wild Victory" },
  { gen1 = "Music_PkmnHealed", gen2 = "Music_HealPokemon", gen3 = "MUS_HEAL",
    name = "Pokemon Healed" },
  { gen1 = "Music_JigglypuffSong", gen2 = "Music_PokemonLullaby", gen3 = "MUS_JIGGLYPUFF",
    name = "Jigglypuff Song" },

  { gen1 = "Music_SafariZone", gen2 = "Music_NationalPark", gen3 = "MUS_SAFARI_ZONE",
    name = "Safari Zone" },
  { gen1 = "Music_SilphCo", gen3 = "MUS_SILPH", name = "Silph Co." },
  { gen2 = "Music_Evolution", gen3 = "MUS_EVOLUTION", name = "Evolution" },
}

M.byLabel = {}
for _, group in ipairs(M.EQUIVALENTS) do
  for generation, label in pairs(group) do
    if (generation == "gen1" or generation == "gen2" or generation == "gen3")
        and not M.byLabel[label] then
      M.byLabel[label] = group
    end
  end
end

function M.groupFor(label)
  return M.byLabel[label]
end

function M.labelFor(group, generation)
  return group and group[generation] or nil
end

function M.pretty(label)
  label = tostring(label or "")
  label = label:gsub("^Music_", ""):gsub("^MUS_", "")
  label = label:gsub("_", " "):gsub("(%l)(%u)", "%1 %2")
  return label
end

-- Canonical name for a dataset label.  Falls back to the pretty-printed id.
function M.nameFor(label)
  local group = M.byLabel[label]
  if group then return group.name end
  label = tostring(label or "")
  if label:match("^MUS_") then
    local ok, Song = pcall(require, "src.core.game3.song_ids")
    if ok and type(Song) == "table" and Song.select and Song.nameOf then
      local previous = Song.current
      local name
      for _, version in ipairs({ "firered", "leafgreen", "emerald", "ruby", "sapphire" }) do
        if pcall(Song.select, version) then
          local id = Song.resolve(label)
          if id then
            name = Song.nameOf(id, version)
            if name then break end
          end
        end
      end
      if previous then pcall(Song.select, previous) end
      if name then return name end
    end
  end
  return M.pretty(label)
end

-- Describe a song id for the toast: { generation, name, kind }.
-- kind is "Improved"/"Stock" for chip variants, nil for base songs.
function M.describe(id, hostGeneration)
  local raw = tostring(id or "")
  local generation = hostGeneration or 1
  local kind, base, version = raw:match("^Music_(Improved)(.-)_([%w]+)$")
  if not kind then
    kind, base, version = raw:match("^Music_(Stock)(.-)_([%w]+)$")
  end
  if not kind then
    kind, base, version = raw:match("^Music_(Mix)(.-)_([%w]+)$")
  end
  if kind then
    local source = M.BY_ID[version]
    if source then generation = source.generation end
    local label = (kind == "Mix" and "MUS_" or "Music_") .. base
    local variant = kind == "Mix" and "g3_mix"
      or ("g" .. tostring(generation) .. (kind == "Improved" and "_improved" or ""))
    return {
      generation = generation,
      name = M.nameFor(label),
      kind = kind == "Improved" and "Improved"
        or kind == "Stock" and "Stock" or "Mix",
      mix = kind == "Mix",
      variant = variant,
      label = M.variantLabel(variant),
    }
  end
  local group = M.byLabel[raw]
  if group then
    return {
      generation = generation, name = group.name or M.pretty(raw),
      variant = "g" .. tostring(generation),
      label = M.variantLabel("g" .. tostring(generation)),
    }
  end
  return {
    generation = generation, name = M.pretty(raw),
    variant = "native", label = M.variantLabel("native"),
  }
end

-- `available(version, label)` filters to imported datasets that actually carry
-- the song.  Host version is excluded so "shuffle" never picks itself.
function M.candidates(label, hostGeneration, hostVersion, available, includeGen3)
  local group = M.byLabel[label]
  if not group then return {} end
  local out = {}
  local allowedSources = nil
  if group.hostSources and group.hostSources[hostVersion] then
    allowedSources = {}
    for _, v in ipairs(group.hostSources[hostVersion]) do allowedSources[v] = true end
  elseif group.sources then
    allowedSources = {}
    for _, v in ipairs(group.sources) do allowedSources[v] = true end
  end
  -- hosts restriction: group only applies on certain host versions
  if group.hosts then
    local ok = false
    for _, h in ipairs(group.hosts) do if h == hostVersion then ok = true break end end
    if not ok then return out end
  end
  for _, version in ipairs(M.VERSIONS) do
    local generation = "gen" .. tostring(version.generation)
    local candidateLabel = group[generation]
    if candidateLabel and version.id ~= hostVersion
        and (includeGen3 or generation == "gen1" or generation == "gen2") then
      if allowedSources and not allowedSources[version.id] then
        -- skip
      elseif not available or available(version.id, candidateLabel) then
        out[#out + 1] = {
          version = version.id,
          generation = version.generation,
          label = candidateLabel,
        }
      end
    end
  end
  return out
end

-- Keep only records matching the shuffle mode's variant kind.  Other modes
-- (shuffle_all, gen1, gen2, ...) pass everything through.
function M.eligible(mode, records)
  local out = {}
  for _, rec in ipairs(records or {}) do
    local id = tostring(rec.id or "")
    local keep = true
    if mode == "shuffle_improved" then
      keep = id:match("^Music_Improved") ~= nil
    elseif mode == "shuffle_stock" then
      keep = id:match("^Music_Stock") ~= nil
    elseif mode == "shuffle_mix" then
      keep = id:match("^Music_Mix") ~= nil
    end
    if keep then out[#out + 1] = rec end
  end
  return out
end

function M.generationForMode(mode)
  if mode == "gen1" then return 1 end
  if mode == "gen2" then return 2 end
  return nil
end

-- Deterministic when `rng` is supplied (tests); otherwise avoid repeating the
-- previous pick for this native song when more than one candidate exists.
-- Variant taxonomy shared by menu, toast and settings.  IDs stay unchanged;
-- "guided" is the existing Music_Improved translation using song profiles.
M.VARIANT_KINDS = {
  { key = "g1", label = "G1" },
  { key = "g1_improved", label = "G1 (Improved)" },
  { key = "g2", label = "G2" },
  { key = "g2_improved", label = "G2 (Improved)" },
  { key = "g3", label = "G3" },
  { key = "g3_mix", label = "G3 (Mix)" },
}
M.MENU_KINDS = M.VARIANT_KINDS
M.ALTERNATIVE_KINDS = { "g1", "g1_improved", "g2", "g2_improved", "g3_mix" }

local VARIANT_LABELS = {}
for _, item in ipairs(M.VARIANT_KINDS) do VARIANT_LABELS[item.key] = item.label end
-- Legacy names from the previous taxonomy; keep old saves/options readable.
for key, label in pairs({
  native = "G1", g1_stock = "G1", g1_guided = "G1 (Improved)",
  g2_stock = "G2", g2_guided = "G2 (Improved)",
}) do VARIANT_LABELS[key] = label end

function M.variantKind(value)
  if type(value) == "string" then
    if VARIANT_LABELS[value] and not tostring(value):match("^Music_") then
      return value
    end
    value = { id = value }
  end
  if type(value) ~= "table" then return "g1" end
  local id = tostring(value.id or "")
  if value.mix or (value.candidate and value.candidate.mix)
      or id:match("^Music_Mix") then
    return "g3_mix"
  end
  -- Variant IDs end in their source version.  Trust that over the host
  -- generation stored on the record: a Gold track heard in Red is still G2.
  local generation
  local version = id:match("_([%w]+)$")
  local source = version and M.BY_ID[version]
  if source then generation = source.generation end
  if not generation then
    version = value.version or (value.candidate and value.candidate.version)
    source = version and M.BY_ID[version]
    generation = source and source.generation
  end
  if not generation then generation = value.generation
      or (value.candidate and value.candidate.generation) end
  generation = tonumber(generation) or 1
  if generation > 3 then generation = 3 end
  local improved = value.improved
  if improved == nil then improved = id:match("^Music_Improved") ~= nil end
  return "g" .. generation .. (improved and "_improved" or "")
end

function M.variantLabel(value)
  local key = type(value) == "string" and value or M.variantKind(value)
  if VARIANT_LABELS[key] then return VARIANT_LABELS[key] end
  return VARIANT_LABELS[M.variantKind(value)] or string.upper(tostring(key))
end

-- Lower rank is higher perceived quality; host generation wins ties.
-- Menu order stays origin-first; shuffle-off preference still puts mixes first.
function M.qualityRank(kind, hostGeneration)
  local canonical = M.variantKind(kind)
  -- Native G3 is the real arrangement; G3 Mix is the backport approximation.
  if canonical == "g3" then return 0, tonumber(hostGeneration) == 3 and 0 or 1 end
  if canonical == "g3_mix" then return 1, 0 end
  local generation = tonumber(tostring(canonical):match("^g(%d)")) or 1
  local tier = tostring(canonical):match("improved") and 2 or 3
  return tier, generation == tonumber(hostGeneration) and 0 or 1
end

function M.sortByQuality(records, hostGeneration)
  local out = {}
  for _, record in ipairs(records or {}) do out[#out + 1] = record end
  table.sort(out, function(a, b)
    local ak, bk = M.variantKind(a), M.variantKind(b)
    local at, ah = M.qualityRank(ak, hostGeneration)
    local bt, bh = M.qualityRank(bk, hostGeneration)
    if at ~= bt then return at < bt end
    if ah ~= bh then return ah < bh end
    return ak < bk
  end)
  return out
end

function M.filterEnabled(records, enabled)
  local out = {}
  for _, record in ipairs(records or {}) do
    local kind = M.variantKind(record)
    if not enabled or enabled[kind] ~= false then out[#out + 1] = record end
  end
  return out
end

function M.pick(mode, candidates, lastKey, rng)
  if mode == "native" or mode == "gen3" then return nil end
  local generation = M.generationForMode(mode)
  local usable = {}
  for _, candidate in ipairs(candidates or {}) do
    if not generation or candidate.generation == generation then
      usable[#usable + 1] = candidate
    end
  end
  if #usable == 0 then return nil end
  local index
  if #usable == 1 then
    index = 1
  else
    local random = rng or math.random
    index = random(#usable)
    if lastKey then
      for attempt = 1, 4 do
        local key = usable[index].key
          or (usable[index].version .. ":" .. usable[index].label)
        if key ~= lastKey then break end
        index = random(#usable)
      end
    end
  end
  return usable[index]
end

return M
