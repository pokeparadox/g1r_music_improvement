-- Static SSEQ name -> version-independent song group for G4 Mix.  Keys are
-- the gen1/gen2 dataset ids from versions.EQUIVALENTS where one exists, so the
-- same HGSS score can back G4 Mix on RBY, GSC and GBA hosts; Gen3-only tunes
-- keep their MUS_ id as the key.  Names come from the SDAT symbol table of
-- the imported HGSS ROM (SEQ_GS_* and SEQ_GS_P_* are duplicate scores).

local M = {}

local GROUPS = {
  { key = "Music_TitleScreen", names = {
    "SEQ_GS_TITLE", "SEQ_GS_TITLE01", "SEQ_GS_P_TITLE", "SEQ_GS_P_TITLE01",
    "SEQ_TITLE00", "SEQ_TITLE01",
  } },
  { key = "Music_BikeRiding", names = {
    "SEQ_BICYCLE", "SEQ_GS_BICYCLE", "SEQ_GS_P_BICYCLE", "SEQ_PL_BICYCLE",
  } },
  { key = "Music_Surfing", names = {
    "SEQ_NAMINORI", "SEQ_GS_NAMINORI", "SEQ_GS_P_NAMINORI",
    "SEQ_GS_NAMINORI_PHC",
  } },
  { key = "Music_Gym", names = { "SEQ_GYM", "SEQ_GS_GYM", "SEQ_GS_P_GYM" } },
  { key = "Music_GameCorner", names = {
    "SEQ_BLD_GAME", "SEQ_GS_GAME", "SEQ_GS_P_GAME",
  } },
  { key = "Music_Pokecenter", names = { "SEQ_PC_01", "SEQ_PC_02" } },
  { key = "Music_WildBattle", names = {
    "SEQ_GS_VS_NORAPOKE", "SEQ_GS_VS_NORAPOKE_KANTO",
    "SEQ_GS_P_VS_NORAPOKE", "SEQ_GS_P_VS_NORAPOKE_KANTO", "SEQ_BA_POKE",
  } },
  { key = "Music_TrainerBattle", names = {
    "SEQ_GS_VS_TRAINER", "SEQ_GS_VS_TRAINER_KANTO",
    "SEQ_GS_P_VS_TRAINER", "SEQ_GS_P_VS_TRAINER_KANTO", "SEQ_BA_TRAIN",
  } },
  { key = "Music_FinalBattle", names = {
    "SEQ_GS_VS_CHAMP", "SEQ_GS_P_VS_CHAMP",
  } },
  { key = "MUS_VS_LEGEND", names = {
    "SEQ_GS_VS_SUICUNE", "SEQ_GS_VS_ENTEI", "SEQ_GS_VS_RAIKOU",
    "SEQ_GS_VS_HOUOU", "SEQ_GS_VS_LUGIA", "SEQ_GS_P_VS_SUICUNE",
    "SEQ_GS_P_VS_ENTEI", "SEQ_GS_P_VS_RAIKOU", "SEQ_GS_P_VS_HOUOU",
    "SEQ_GS_P_VS_LUGIA",
  } },
  { key = "Music_DefeatedWildMon", names = {
    "SEQ_GS_WIN1", "SEQ_GS_P_WIN1", "SEQ_WINPOKE",
  } },
  { key = "Music_DefeatedTrainer", names = {
    "SEQ_GS_WIN2", "SEQ_GS_P_WIN2", "SEQ_WINTRAIN",
  } },
  { key = "Music_DefeatedGymLeader", names = {
    "SEQ_GS_WIN3", "SEQ_GS_P_WIN3", "SEQ_WINTGYM",
  } },
  { key = "Music_Evolution", names = {
    "SEQ_GS_SHINKA", "SEQ_GS_P_SHINKA", "SEQ_SHINKA",
  } },
  { key = "MUS_EVOLVED", names = { "SEQ_ME_SHINKAOME" } },
  { key = "MUS_LEVEL_UP", names = { "SEQ_ME_LVUP" } },
  { key = "MUS_CAUGHT", names = { "SEQ_ME_POKEGET" } },
  { key = "MUS_OBTAIN_BADGE", names = { "SEQ_BADGE", "SEQ_ME_BADGE" } },
  { key = "MUS_OBTAIN_ITEM", names = { "SEQ_ME_ITEM" } },
  { key = "MUS_OBTAIN_KEY_ITEM", names = { "SEQ_ME_KEYITEM" } },
  { key = "Music_Credits", names = {
    "SEQ_GS_ENDING", "SEQ_GS_ENDING2", "SEQ_GS_P_ENDING", "SEQ_GS_P_ENDING2",
  } },
  { key = "Music_IndigoPlateau", names = {
    "SEQ_GS_D_CHAMPROAD", "SEQ_GS_CHAMPROAD", "SEQ_GS_P_D_CHAMPROAD",
    "SEQ_GS_P_CHAMPROAD", "SEQ_D_LEAGUE", "SEQ_D_CROAD",
  } },
  { key = "Music_SafariZone", names = {
    "SEQ_D_SAFARI", "SEQ_GS_SAFARI_ROAD", "SEQ_GS_SAFARI_HOUSE",
    "SEQ_GS_SAFARI_FIELD", "SEQ_GS_P_SAFARI_ROAD", "SEQ_GS_P_SAFARI_HOUSE",
    "SEQ_GS_P_SAFARI_FIELD",
  } },
  -- Placeholder used by the generic town family until a concrete GBA song id
  -- is assigned; harmless because G4 candidates require g3Mix.has as well.
  { key = "MUS_TOWN", names = { "SEQ_TOWN01_D", "SEQ_TOWN01_N" } },
}

M.BY_NAME = {}
M.BY_KEY = {}
for _, group in ipairs(GROUPS) do
  local list = M.BY_KEY[group.key]
  if not list then list = {}; M.BY_KEY[group.key] = list end
  for _, name in ipairs(group.names) do
    M.BY_NAME[name] = group.key
    list[#list + 1] = name
  end
end
-- Legacy name used by callers that only ever handled Gen3 labels.
M.BY_LABEL = M.BY_KEY

function M.keyFor(name)
  return type(name) == "string" and M.BY_NAME[name] or nil
end

-- Backwards-compatible alias for keyFor.
function M.labelFor(name)
  return M.keyFor(name)
end

function M.namesFor(key)
  if type(key) ~= "string" then return {} end
  local list = M.BY_KEY[key]
  if not list then return {} end
  local out = {}
  for _, name in ipairs(list) do out[#out + 1] = name end
  return out
end

function M.keys()
  local out = {}
  for key in pairs(M.BY_KEY) do out[#out + 1] = key end
  table.sort(out)
  return out
end

return M
