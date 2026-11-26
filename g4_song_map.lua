-- Static SSEQ name -> version-independent song group for G4 Mix/GB.  Keys are
-- the gen1/gen2 dataset ids from versions.EQUIVALENTS where one exists, so the
-- same HGSS score can back G4 Mix on RBY, GSC and GBA hosts; Gen3-only tunes
-- keep their MUS_ id as the key.  Names come from the SDAT symbol table of
-- the imported HGSS ROM.  SEQ_GS_* are normal/PCM arrangements; SEQ_GS_P_*
-- are the PSG-only GB Sounds arrangements used by G4 GB.

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
  -- Kanto towns still named in the GSC dataset; HGSS GB Sounds scores.
  { key = "Music_PalletTown", names = {
    "SEQ_TOWN05_N", "SEQ_TOWN05_D",
    "SEQ_GS_T_MASARA", "SEQ_GS_P_T_MASARA",
  } },
  { key = "Music_Cities1", names = {
    "SEQ_CITY07_N", "SEQ_CITY07_D",
    "SEQ_GS_C_TOKIWA", "SEQ_GS_P_C_TOKIWA",
  } },
  { key = "Music_Vermilion", names = {
    "SEQ_CITY09_N", "SEQ_CITY09_D",
    "SEQ_GS_C_KUCHIBA", "SEQ_GS_P_C_KUCHIBA",
  } },
  { key = "Music_Celadon", names = {
    "SEQ_CITY10_N", "SEQ_CITY10_D",
    "SEQ_GS_C_TAMAMUSHI", "SEQ_GS_P_C_TAMAMUSHI",
  } },
  { key = "Music_Lavender", names = {
    "SEQ_TOWN07_N", "SEQ_TOWN07_D",
    "SEQ_GS_T_CHION", "SEQ_GS_P_T_CHION",
  } },
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

  -- Johto GB Sounds scores, named after their Japanese locations. These are
  -- the HGSS arrangements equivalent to the GSC dataset tunes.
  { key = "Music_NewBarkTown", names = {
    "SEQ_TOWN01_N", "SEQ_TOWN01_D",
    "SEQ_GS_T_WAKABA", "SEQ_GS_P_T_WAKABA",
  } },
  { key = "Music_CherrygroveCity", names = {
    "SEQ_CITY01_N", "SEQ_CITY01_D",
    "SEQ_GS_C_YOSHINO", "SEQ_GS_P_C_YOSHINO",
  } },
  { key = "Music_VioletCity", names = {
    "SEQ_CITY02_N", "SEQ_CITY02_D",
    "SEQ_GS_C_KIKYOU", "SEQ_GS_P_C_KIKYOU",
  } },
  { key = "Music_AzaleaTown", names = {
    "SEQ_TOWN02_N", "SEQ_TOWN02_D",
    "SEQ_GS_T_HIWADA", "SEQ_GS_P_T_HIWADA",
  } },
  { key = "Music_GoldenrodCity", names = {
    "SEQ_CITY03_N", "SEQ_CITY03_D",
    "SEQ_GS_C_KOGANE", "SEQ_GS_P_C_KOGANE",
  } },
  { key = "Music_EcruteakCity", names = {
    "SEQ_CITY04_N", "SEQ_CITY04_D",
    "SEQ_GS_C_ENJU", "SEQ_GS_P_C_ENJU",
  } },
  { key = "Music_Route26", names = {
    "SEQ_GS_R_1_26", "SEQ_GS_P_R_1_26",
  } },
  { key = "Music_Route29", names = {
    "SEQ_ROAD_A_N", "SEQ_ROAD_A_D",
    "SEQ_GS_R_1_29", "SEQ_GS_P_R_1_29",
  } },
  { key = "Music_Route30", names = {
    "SEQ_ROAD_A_N", "SEQ_ROAD_A_D",
    "SEQ_GS_R_1_30", "SEQ_GS_P_R_1_30",
  } },
}

-- Most GB Sounds sequences mirror a normal SEQ_GS_* name with P_ inserted.
-- Derive those aliases so every imported P sequence resolves to its mapped
-- key without hand-maintaining all 82 names.
local function addDerivedGbNames(names)
  local count = #names
  for i = 1, count do
    local name = names[i]
    local suffix = name:match("^SEQ_GS_(.+)$")
    if suffix and not name:match("^SEQ_GS_P_") then
      local derived = "SEQ_GS_P_" .. suffix
      local seen = false
      for _, existing in ipairs(names) do
        if existing == derived then seen = true break end
      end
      if not seen then names[#names + 1] = derived end
    end
  end
end

M.BY_NAME = {}
M.BY_KEY = {}
for _, group in ipairs(GROUPS) do
  addDerivedGbNames(group.names)
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

-- HGSS has two arrangements for most songs: normal DS BGM and GB Sounds.
-- Non-P SEQ_GS_* scores are PCM-heavy DS arrangements; SEQ_GS_P_* are the
-- PSG-only GB Sounds arrangements.  G4 Mix uses normal DS, G4 GB uses P.
function M.namesFor(key, mode)
  if type(key) ~= "string" then return {} end
  local list = M.BY_KEY[key]
  if not list then return {} end
  local first, second, third = {}, {}, {}
  local wantGb = mode == "chip"
  local wantPcm = mode == "pcm"
  for _, name in ipairs(list) do
    local p = type(name) == "string" and name:match("^SEQ_GS_P_") ~= nil
    local gs = type(name) == "string" and name:match("^SEQ_GS_") ~= nil
    local tier = third
    if wantGb then
      tier = p and first or (gs and second or third)
    elseif wantPcm then
      tier = (not gs) and first or ((gs and not p) and second or third)
    end
    tier[#tier + 1] = name
  end
  local out = {}
  for _, tier in ipairs({ first, second, third }) do
    for _, name in ipairs(tier) do out[#out + 1] = name end
  end
  if #out > 0 then return out end
  return list
end

function M.keys()
  local out = {}
  for key in pairs(M.BY_KEY) do out[#out + 1] = key end
  table.sort(out)
  return out
end

return M
