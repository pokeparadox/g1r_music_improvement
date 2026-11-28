-- Pokémon Stadium 2 (U) sequence names and cross-game aliases.
-- Sequence indices are raw AudioSeq table indices.  Names come from HCS
-- miniusf savestates/tags cross-checked against ROM audio; ambiguous ones are
-- marked below but kept usable.

local M = {}

local COUNT = 137

local NAMES = {
  [0x28] = "Gym/Beta Battle", [0x29] = "Gym Leader Battle",
  [0x2A] = "Lance Battle", [0x2B] = "Kanto Leader Battle",
  [0x2C] = "Elite 4 Battle", [0x2D] = "Little Cup Final Battle",
  [0x2E] = "Earl's Pokemon Academy", [0x2F] = "Prof. Oak's Lab",
  [0x30] = "Little Cup Battle", [0x31] = "Little Cup Battle 2",
  [0x32] = "Poke Cup Final Battle 2", [0x33] = "Ash Battle (Red)",
  [0x34] = "Gutsy Golbat", [0x35] = "Challenge Cup Battle",
  [0x36] = "Poke Cup Battle 2", [0x37] = "Prime Cup Battle",
  [0x38] = "Poke Cup Final Battle", [0x39] = "Clear Cut Begin",
  [0x3A] = "Clear Cut End", [0x3B] = "Academy Quiz",
  [0x3C] = "Pichu's Power Plant", [0x3D] = "Little Cup Final Battle 2",
  [0x3E] = "Poke Cup Battle", [0x3F] = "Challenge Cup Final Battle 2",
  [0x40] = "Event Battle Theme", [0x41] = "Academy Battle",
  [0x42] = "Pokemon Select", [0x43] = "Battle Preparation",
  [0x44] = "Quiz Introduction", [0x45] = "Streaming Stampede",
  [0x46] = "Select the Winner", [0x47] = "Beep (drum)",
  [0x48] = "Topsy-Turvy", [0x49] = "Rampage Rollout",
  [0x4A] = "Barrier Ball", [0x4B] = "Title Screen",
  [0x4C] = "White City (menu)", [0x4D] = "Battle End",
  [0x4E] = "Victory!", [0x4F] = "Versus Theme",
  [0x50] = "My Room", [0x51] = "Options Menu",
  [0x52] = "Challenge Cup Final Battle", [0x53] = "Prime Cup Final Battle",
  [0x54] = "Egg Emergency", [0x55] = "Tumbling Togepi",
  [0x56] = "Furret's Frolic", [0x57] = "Evolution",
  [0x58] = "Evolution Complete", [0x59] = "Trade Complete",
  [0x5A] = "Stadium", [0x5B] = "Delibird's Delivery",
  [0x5C] = "Champion Whistle", [0x5D] = "Eager Eevee",
  [0x5E] = "Minigame Won", [0x5F] = "Minigame Lost",
  [0x60] = "Minigame Champion", [0x61] = "Challenge Cup Battle 2",
  [0x62] = "Prime Cup Battle 2", [0x63] = "Rival Battle",
  [0x64] = "Team Rocket's Battle", [0x65] = "Johto Castle",
  [0x66] = "Rival Theme", [0x67] = "Free Battle",
  [0x68] = "Beta Theme", [0x69] = "Demonstration Battle",
  [0x6A] = "Prime Cup Final Battle 2", [0x6B] = "Mystery Gift",
  [0x6C] = "Team Rocket's Castle", [0x6D] = "Cup Victory",
  [0x6E] = "Kanto Castle", [0x6F] = "Minigames",
  [0x70] = "Single Minigame Won", [0x71] = "Earl's Test Pass",
  [0x72] = "Earl's Test Fail", [0x73] = "Quiz",
  [0x74] = "Minigame Championship", [0x75] = "Defeated!",
  [0x76] = "Minigame Champion Prize", [0x77] = "Minigame Complete",
  [0x7A] = "Clear!", [0x7B] = "Lance's Theme",
  [0x7C] = "Elite 4 Battle 2", [0x7D] = "Relearning Move",
  [0x7E] = "Move Relearned!", [0x7F] = "Castle Clear",
  [0x80] = "Got A Rare Pokemon!", [0x81] = "Gym/Beta Battle",
  [0x82] = "Lance's Theme", [0x83] = "Lance Defeated",
  [0x84] = "Lance's Theme", [0x85] = "Relearn TM",
  [0x86] = "Castle Clear (short)",
  [0x87] = "Stadium Cup Final - Winner Fanfare", [0x88] = "Rival Defeated",
}

-- Cross-game labels that should resolve to a Stadium 2 arrangement.  Only
-- high-confidence matches are listed; the rest stay as generic SEQ_N64_XX.
local ALIASES = {
  [0x29] = { "Music_GymLeaderBattle", "Music_KantoGymBattle", "MUS_VS_GYM_LEADER" },
  [0x2B] = { "Music_Gym", "MUS_GYM" },
  [0x2C] = { "Music_FinalBattle", "Music_ChampionBattle", "MUS_VS_CHAMPION" },
  [0x63] = { "Music_MeetRival", "Music_LookRival", "MUS_ENCOUNTER_RIVAL" },
  [0x64] = { "Music_RocketBattle" },
  [0x66] = { "Music_MeetRival", "Music_LookRival", "MUS_ENCOUNTER_RIVAL" },
  [0x2F] = { "Music_MeetProfOak", "Music_ProfOak", "MUS_OAK",
    "Music_OaksLab", "MUS_OAK_LAB" },
  [0x4B] = { "Music_TitleScreen", "MUS_TITLE" },
}

local function keyForIndex(index)
  return string.format("SEQ_N64_%02d", index)
end

M.COUNT = COUNT
M.NAMES = NAMES
M.ALIASES = ALIASES
M.BY_KEY = {}
M.BY_NAME = {}
M.BY_INDEX = {}
M.BY_LABEL = M.BY_KEY

for index = 0, COUNT - 1 do
  local key = keyForIndex(index)
  local names = { key }
  if NAMES[index] then names[#names + 1] = NAMES[index] end
  for _, alias in ipairs(ALIASES[index] or {}) do names[#names + 1] = alias end
  M.BY_KEY[key] = names
  M.BY_INDEX[index] = key
  for _, name in ipairs(names) do M.BY_NAME[name] = key end
  -- n64_import names raw sequences without zero padding; accept both forms.
  M.BY_NAME[string.format("SEQ_N64_%d", index)] = key
end

function M.keyFor(name)
  if type(name) ~= "string" then return nil end
  return M.BY_NAME[name] or M.BY_NAME[tostring(tonumber(name))]
end

function M.labelFor(name)
  return M.keyFor(name)
end

function M.namesFor(key, mode)
  if type(key) ~= "string" then return {} end
  return M.BY_KEY[key] or {}
end

function M.keys()
  local out = {}
  for key in pairs(M.BY_KEY) do out[#out + 1] = key end
  table.sort(out)
  return out
end

function M.nameForIndex(index)
  local value = tonumber(index)
  if not value then return nil end
  return NAMES[value] or keyForIndex(value)
end

function M.mappedSongFor(label, mode)
  local name = tostring(label or ""):gsub("^N64:", "")
  local key = M.BY_NAME[name]
  if not key then return nil end
  local index = tonumber(key:match("^SEQ_N64_(%d+)$"))
  if not index or index < 0 or index >= COUNT then return nil end
  return {
    name = key, label = name, key = key, index = index, bank = 0,
    display = NAMES[index],
  }
end

function M.available()
  return true
end

return M
