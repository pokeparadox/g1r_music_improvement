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
M.EQUIVALENTS = {
  { gen1 = "Music_Pokecenter", gen2 = "Music_PokemonCenter", gen3 = "MUS_POKE_CENTER" },
  { gen1 = "Music_TitleScreen", gen2 = "Music_TitleScreen", gen3 = "MUS_TITLE" },
  { gen1 = "Music_PalletTown", gen2 = "Music_PalletTown", gen3 = "MUS_PALLET" },
  { gen1 = "Music_Cities1", gen2 = "Music_ViridianCity", gen3 = "MUS_VIRIDIAN" },
  { gen1 = "Music_Celadon", gen2 = "Music_CeladonCity", gen3 = "MUS_CELADON" },
  { gen1 = "Music_Vermilion", gen2 = "Music_VermilionCity", gen3 = "MUS_VERMILLION" },
  { gen1 = "Music_Lavender", gen2 = "Music_LavenderTown", gen3 = "MUS_LAVENDER" },
  { gen1 = "Music_Routes1", gen2 = "Music_Route1", gen3 = "MUS_ROUTE1" },
  { gen1 = "Music_Routes2", gen2 = "Music_Route2", gen3 = "MUS_ROUTE2" },
  { gen1 = "Music_Routes3", gen2 = "Music_Route3", gen3 = "MUS_ROUTE3" },
  { gen1 = "Music_Routes4", gen2 = "Music_Route12" },
  { gen1 = "Music_Gym", gen2 = "Music_Gym", gen3 = "MUS_GYM" },
  { gen1 = "Music_GymLeaderBattle", gen2 = "Music_KantoGymBattle", gen3 = "MUS_VS_GYM_LEADER" },
  { gen1 = "Music_TrainerBattle", gen2 = "Music_KantoTrainerBattle", gen3 = "MUS_VS_TRAINER" },
  { gen1 = "Music_WildBattle", gen2 = "Music_KantoWildBattle", gen3 = "MUS_VS_WILD" },
  { gen1 = "Music_FinalBattle", gen2 = "Music_ChampionBattle", gen3 = "MUS_VS_CHAMPION" },
  { gen1 = "Music_MeetRival", gen2 = "Music_RivalBattle", gen3 = "MUS_ENCOUNTER_RIVAL" },
  { gen1 = "Music_MeetEvilTrainer", gen2 = "Music_RocketBattle" },
  { gen1 = "Music_Dungeon1", gen2 = "Music_MtMoon", gen3 = "MUS_MT_MOON" },
  { gen1 = "Music_Dungeon2", gen2 = "Music_UnionCave" },
  { gen1 = "Music_Dungeon3", gen2 = "Music_DarkCave" },
  { gen1 = "Music_IndigoPlateau", gen2 = "Music_IndigoPlateau", gen3 = "MUS_VICTORY_ROAD" },
  { gen1 = "Music_Surfing", gen2 = "Music_Surf", gen3 = "MUS_SURF" },
  { gen1 = "Music_BikeRiding", gen2 = "Music_Bicycle", gen3 = "MUS_CYCLING" },
  { gen1 = "Music_Credits", gen2 = "Music_Credits", gen3 = "MUS_CREDITS" },
  { gen1 = "Music_HallOfFame", gen2 = "Music_HallOfFame", gen3 = "MUS_HALL_OF_FAME" },
  { gen1 = "Music_GameCorner", gen2 = "Music_GameCorner", gen3 = "MUS_GAME_CORNER" },
  { gen1 = "Music_SSAnne", gen2 = "Music_SSAqua", gen3 = "MUS_SS_ANNE" },
  { gen1 = "Music_PokemonTower", gen2 = "Music_TinTower", gen3 = "MUS_POKE_TOWER" },
  { gen1 = "Music_CinnabarMansion", gen3 = "MUS_POKE_MANSION" },
  { gen1 = "Music_OaksLab", gen2 = "Music_ElmsLab", gen3 = "MUS_OAK_LAB" },
  { gen1 = "Music_MeetProfOak", gen2 = "Music_ProfOak", gen3 = "MUS_OAK" },
  { gen1 = "Music_DefeatedGymLeader", gen2 = "Music_GymLeaderVictory", gen3 = "MUS_VICTORY_GYM_LEADER" },
  { gen1 = "Music_DefeatedTrainer", gen2 = "Music_TrainerVictory", gen3 = "MUS_VICTORY_TRAINER" },
  { gen1 = "Music_DefeatedWildMon", gen2 = "Music_WildPokemonVictory", gen3 = "MUS_VICTORY_WILD" },
  { gen1 = "Music_PkmnHealed", gen2 = "Music_HealPokemon", gen3 = "MUS_HEAL" },
  { gen1 = "Music_JigglypuffSong", gen2 = "Music_PokemonLullaby", gen3 = "MUS_JIGGLYPUFF" },
  { gen1 = "Music_IntroBattle", gen2 = "Music_GoldSilverOpening", gen3 = "MUS_INTRO_FIGHT" },
  { gen1 = "Music_SafariZone", gen2 = "Music_NationalPark", gen3 = "MUS_SAFARI_ZONE" },
  { gen1 = "Music_SilphCo", gen3 = "MUS_SILPH" },
  { gen2 = "Music_Evolution", gen3 = "MUS_EVOLUTION" },
}

M.byLabel = {}
for _, group in ipairs(M.EQUIVALENTS) do
  for generation, label in pairs(group) do
    if generation ~= "gen1" and generation ~= "gen2" and generation ~= "gen3" then
      error("versions: bad generation key " .. tostring(generation))
    end
    M.byLabel[label] = group
  end
end

function M.groupFor(label)
  return M.byLabel[label]
end

function M.labelFor(group, generation)
  return group and group[generation] or nil
end

-- `available(version, label)` filters to imported datasets that actually carry
-- the song.  Host version is excluded so "shuffle" never picks itself.
function M.candidates(label, hostGeneration, hostVersion, available)
  local group = M.byLabel[label]
  if not group then return {} end
  local out = {}
  for _, version in ipairs(M.VERSIONS) do
    local generation = "gen" .. tostring(version.generation)
    local candidateLabel = group[generation]
    if candidateLabel and version.id ~= hostVersion
        and (generation == "gen1" or generation == "gen2") then
      if not available or available(version.id, candidateLabel) then
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

function M.generationForMode(mode)
  if mode == "gen1" then return 1 end
  if mode == "gen2" then return 2 end
  return nil
end

-- Deterministic when `rng` is supplied (tests); otherwise avoid repeating the
-- previous pick for this native song when more than one candidate exists.
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
        local key = usable[index].version .. ":" .. usable[index].label
        if key ~= lastKey then break end
        index = random(#usable)
      end
    end
  end
  return usable[index]
end

return M
