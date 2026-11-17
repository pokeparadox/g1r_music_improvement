-- Per-song enhancement profiles. Pure data; no engine dependencies.
--
-- Profiles never transpose the source song. They only steer the generated
-- harmony: key override (diatonic interval maths) and conservative side
-- overrides (interval, gain, duty, enable/disable). Labels missing here use
-- the existing automatic path in improve.lua.

local MAJOR = { 0, 2, 4, 5, 7, 9, 11 }
local MINOR = { 0, 2, 3, 5, 7, 8, 10 }
local PHRYGIAN = { 0, 1, 3, 5, 7, 8, 10 }
local IN_SCALE = { 0, 1, 5, 7, 8, 10 } -- F G♭ B♭ C D♭ E♭ relative to F

local MIXOLYDIAN = { 0, 2, 4, 5, 7, 9, 10 }
local DORIAN = { 0, 2, 3, 5, 7, 9, 10 }
local MODE_SCALES = {
  major = MAJOR,
  minor = MINOR,
  mixolydian = MIXOLYDIAN,
  dorian = DORIAN,
  phrygian = PHRYGIAN,
}

local SIDES = { left = true, right = true, center = true, bassDown = true }

local SPARSE = { left = { gain = 0.75 }, center = { enabled = false }, bassDown = { enabled = false } }
local JINGLE = { left = { gain = 0.7 }, center = { enabled = false }, bassDown = { enabled = false } }
local BATTLE = { center = { enabled = false } }
local MELLOW = { center = { gain = 0.75 }, bassDown = { gain = 0.8 } }

local entries = {
  -- Gen1 overworld -------------------------------------------------------
  {
    id = "bike_riding", labels = { "Music_BikeRiding" },
    key = { tonic = 0, mode = "major" },
    source = "https://hooktheory.com/theorytab/view/junichi-masuda/cycling---pokemon-red-blue-and-yellow-versions",
    confidence = "high", note = "C major / 134; rolling diatonic triads.",
  },
  {
    id = "celadon_rgby", labels = { "Music_Celadon" },
    key = { tonic = 7, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-celadon-city",
    confidence = "medium", note = "G major / D mixolydian / 134; keep chords light.",
  },
  {
    id = "cinnabar", labels = { "Music_Cinnabar" },
    key = { tonic = 7, mode = "major" },
    sides = MELLOW,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-cinnabar-island",
    confidence = "medium", note = "G major / 134; laid-back 12-bar loop.",
  },
  {
    id = "cinnabar_mansion", labels = { "Music_CinnabarMansion" },
    sides = SPARSE,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-pokemon-mansion",
    confidence = "high", note = "Atonal/erratic; channels loop at different lengths.",
  },
  {
    id = "cities1", labels = { "Music_Cities1" },
    key = { tonic = 4, mode = "major" },
    sides = SPARSE,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-viridian-pewter-saffron-city",
    confidence = "medium", note = "E major / F♯ minor / 134; dissonant overlaps.",
  },
  {
    id = "cities2", labels = { "Music_Cities2" },
    key = { tonic = 4, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-cerulean-fuchsia-city",
    confidence = "medium", note = "E major / 130.3; bright, pastoral.",
  },
  {
    id = "dungeon1", labels = { "Music_Dungeon1" },
    key = { tonic = 4, mode = "minor" },
    sides = BATTLE,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-rocket-hideout",
    confidence = "medium", note = "E minor / 134; scheming chromatic riff.",
  },
  {
    id = "dungeon2", labels = { "Music_Dungeon2" },
    key = { tonic = 4, mode = "minor" },
    sides = SPARSE,
    source = "https://hooktheory.com/theorytab/view/game-freak/viridian-forest-%28pokemon-red-blue-yellow%29",
    confidence = "high", note = "E minor pentatonic / 134; mysterious, leave space.",
  },
  {
    id = "dungeon3", labels = { "Music_Dungeon3" },
    sides = SPARSE,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-mt-moon",
    confidence = "high", note = "Augmented triads, odd meter; no diatonic key override.",
  },
  {
    id = "game_corner", labels = { "Music_GameCorner" },
    key = { tonic = 4, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-game-corner",
    confidence = "medium", note = "Gen1 E major / 160.8; Gen2 source reports F minor / 138 (low).",
  },
  {
    id = "gym_shared", labels = { "Music_Gym" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-gym",
    confidence = "medium", note = "Gen1 F major / 139.8 vs Gen2 G mixolydian / 123.7; no key override.",
  },
  {
    id = "indigo_shared", labels = { "Music_IndigoPlateau" },
    sides = BATTLE,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-indigo-plateau",
    confidence = "medium", note = "Gen1 D minor/F major vs Gen2 B♭ major/G minor; no key override.",
  },
  {
    id = "jigglypuff", labels = { "Music_JigglypuffSong" },
    key = { tonic = 4, mode = "major" },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokered/master/audio/music/jigglypuffsong.asm",
    confidence = "medium", note = "E major/mixolydian / 144; soft lullaby jingle.",
  },
  {
    id = "lavender_rgby", labels = { "Music_Lavender" },
    key = { tonic = 4, mode = "minor" },
    sides = BATTLE,
    source = "https://hooktheory.com/theorytab/view/nintendo/pokemon-red-and-blue---lavender-town",
    confidence = "high", note = "E minor / 126.9; ghostly, diminished color.",
  },
  {
    id = "meet_prof_oak_rgby", labels = { "Music_MeetProfOak" },
    key = { tonic = 4, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-professor-oak",
    confidence = "medium", note = "E major / 172.2; urgent, narrow range.",
  },
  {
    id = "museum_guy", labels = { "Music_MuseumGuy" },
    key = { tonic = 9, mode = "major" },
    sides = JINGLE,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-guide",
    confidence = "medium", note = "A major / 150.7; hurried comic intro.",
  },
  {
    id = "oaks_lab", labels = { "Music_OaksLab" },
    key = { tonic = 9, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-professor-oaks-laboratory",
    confidence = "medium", note = "A major / 137.8; inquisitive, active bass.",
  },
  {
    id = "pokecenter", labels = { "Music_Pokecenter" },
    key = { tonic = 2, mode = "major" },
    source = "https://hooktheory.com/theorytab/view/game-freak/pokemon-center---pokemon-red-and-blue",
    confidence = "high", note = "D major / 134; almost purely diatonic.",
  },
  {
    id = "pokemon_tower", labels = { "Music_PokemonTower" },
    key = { tonic = 4, mode = "minor" },
    sides = BATTLE,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-pokemon-tower",
    confidence = "medium", note = "G major / E minor / 126.9; haunted, sparse minor color.",
  },
  {
    id = "routes1", labels = { "Music_Routes1" },
    key = { tonic = 2, mode = "major" },
    source = "https://hooktheory.com/theorytab/view/nintendo/pokemon-route-1---1st-generation",
    confidence = "high", note = "D major / 126.9; bright, simple.",
  },
  {
    id = "routes2", labels = { "Music_Routes2" },
    key = { tonic = 0, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-route-3",
    confidence = "medium", note = "C major / 130.3; cheerful, busy.",
  },
  {
    id = "routes3", labels = { "Music_Routes3" },
    key = { tonic = 4, scale = MIXOLYDIAN },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-route-11",
    confidence = "medium", note = "E mixolydian / 130.3; ♭VII prominent.",
  },
  {
    id = "routes4", labels = { "Music_Routes4" },
    key = { tonic = 4, scale = MIXOLYDIAN },
    sides = JINGLE,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-route-24",
    confidence = "medium", note = "E mixolydian / 126.9; short 10-bar loop.",
  },
  {
    id = "safari_zone", labels = { "Music_SafariZone" },
    key = { tonic = 7, mode = "major" },
    sides = JINGLE,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-safari-zone",
    confidence = "medium", note = "G major / 146.2; tiny 2-bar loop.",
  },
  {
    id = "silph_co", labels = { "Music_SilphCo" },
    sides = SPARSE,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-silph-co",
    confidence = "high", note = "Semitone steps, no functional progression.",
  },
  {
    id = "ss_anne", labels = { "Music_SSAnne" },
    key = { tonic = 9, mode = "major" },
    source = "https://hooktheory.com/theorytab/view/game-freak/ss-anne---pokemon-red-and-blue",
    confidence = "high", note = "A major / 150.7; jaunty, overlapping lines.",
  },
  {
    id = "surfing", labels = { "Music_Surfing" },
    key = { tonic = 9, mode = "major" },
    sides = MELLOW,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-surfing",
    confidence = "medium", note = "A major / 120.6; flowing 6/8.",
  },
  {
    id = "title_shared", labels = { "Music_TitleScreen" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-title-screen",
    confidence = "medium", note = "Gen1 C major / 134 vs Gen2 G mixolydian / 144; no key override.",
  },
  {
    id = "vermilion_rgby", labels = { "Music_Vermilion" },
    key = { tonic = 9, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-rgby-vermilion-city",
    confidence = "medium", note = "F♯ minor / A major / 123.6; bouncy port.",
  },
  {
    id = "yellow_intro", labels = { "Music_YellowIntro" },
    key = { tonic = 4, mode = "major" },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokeyellow/master/audio/music/yellowintro.asm",
    confidence = "medium", note = "E major / 116; triumphant fanfare.",
  },

  -- Gen1 battles, endings, jingles ---------------------------------------
  {
    id = "credits_shared", labels = { "Music_Credits" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "medium", note = "Gen1 D major / 137.8; Gen2 C major / 138; no key override.",
  },
  {
    id = "defeated_gym_leader", labels = { "Music_DefeatedGymLeader" },
    key = { tonic = 2, mode = "major" },
    sides = JINGLE,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "high", note = "D major / 172.2; triumphant sting.",
  },
  {
    id = "defeated_trainer", labels = { "Music_DefeatedTrainer" },
    key = { tonic = 2, mode = "major" },
    sides = JINGLE,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "high", note = "D major / 172.2; jaunty sting.",
  },
  {
    id = "defeated_wild", labels = { "Music_DefeatedWildMon" },
    sides = JINGLE,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "high", note = "E major → F major / 172.2; no single key override.",
  },
  {
    id = "final_battle", labels = { "Music_FinalBattle" },
    key = { tonic = 9, mode = "minor" },
    sides = BATTLE,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "medium", note = "A minor / 172.3; intense.",
  },
  {
    id = "gb_printer", labels = { "Music_GBPrinter" },
    key = { tonic = 4, mode = "major" },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokeyellow/master/audio/music/printer.asm",
    confidence = "medium", note = "E major / 256; E-B drone, single channel.",
  },
  {
    id = "gym_leader_battle", labels = { "Music_GymLeaderBattle" },
    key = { tonic = 11, scale = MIXOLYDIAN },
    sides = BATTLE,
    source = "https://www.hooktheory.com/theorytab/view/junichi-masuda/pokemon-rgb-gym-leader-battle",
    confidence = "high", note = "B mixolydian / 185.5; A natural ♭VII.",
  },
  {
    id = "hall_of_fame", labels = { "Music_HallOfFame" },
    key = { tonic = 7, scale = MIXOLYDIAN },
    source = "https://raw.githubusercontent.com/pret/pokered/master/audio/music/halloffame.asm",
    confidence = "medium", note = "G mixolydian / 112; ceremonial, F natural.",
  },
  {
    id = "intro_battle", labels = { "Music_IntroBattle" },
    key = { tonic = 2, mode = "minor" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokered/master/audio/music/introbattle.asm",
    confidence = "medium", note = "D minor / 98; urgent.",
  },
  {
    id = "meet_evil_trainer", labels = { "Music_MeetEvilTrainer" },
    key = { tonic = 8, mode = "minor" },
    sides = BATTLE,
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "medium", note = "G♯ minor / 155.6; sinister.",
  },
  {
    id = "meet_female_trainer", labels = { "Music_MeetFemaleTrainer" },
    key = { tonic = 4, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "high", note = "E major / 155.6; cheerful.",
  },
  {
    id = "meet_jessie_james", labels = { "Music_MeetJessieJames" },
    key = { tonic = 10, mode = "minor" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokeyellow/master/audio/music/meetjessiejames.asm",
    confidence = "medium", note = "B♭ minor / 144; scheming.",
  },
  {
    id = "meet_male_trainer", labels = { "Music_MeetMaleTrainer" },
    key = { tonic = 4, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "medium", note = "E major / 172.2; brisk.",
  },
  {
    id = "meet_rival", labels = { "Music_MeetRival" },
    key = { tonic = 7, scale = MIXOLYDIAN },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "medium", note = "G mixolydian / 172.2; restless.",
  },
  {
    id = "pkmn_healed", labels = { "Music_PkmnHealed" },
    key = { tonic = 4, mode = "major" },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokered/master/audio/music/pkmnhealed.asm",
    confidence = "medium", note = "E major / 144; soothing sting.",
  },
  {
    id = "printer_gsc", labels = { "Music_Printer" },
    key = { tonic = 4, mode = "major" },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokegold/master/audio/music/printer.asm",
    confidence = "medium", note = "E major / 256; sparse single-channel drone.",
  },
  {
    id = "surfing_pikachu", labels = { "Music_SurfingPikachu" },
    key = { tonic = 4, mode = "major" },
    source = "https://raw.githubusercontent.com/pret/pokeyellow/master/audio/music/surfingpikachu.asm",
    confidence = "medium", note = "E major / 117; playful.",
  },
  {
    id = "trainer_battle", labels = { "Music_TrainerBattle" },
    key = { tonic = 11, mode = "minor" },
    sides = BATTLE,
    source = "https://www.hooktheory.com/theorytab/view/junichi-masuda/trainer-battle---pokemon-red-and-blue",
    confidence = "high", note = "B minor / 172.2; aggressive.",
  },
  {
    id = "wild_battle", labels = { "Music_WildBattle" },
    key = { tonic = 0, scale = MIXOLYDIAN },
    source = "https://www.hooktheory.com/theorytab/view/junichi-masuda/wild-pokemon-battle---pokemon-red-and-blue",
    confidence = "high", note = "C mixolydian / 185.5; frantic, ♭VII.",
  },

  -- Gen2 encounters, radio, misc -----------------------------------------
  {
    id = "lake_radio", labels = { "Music_LakeOfRageRocketRadio" },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lakeofragerocketradio.asm",
    confidence = "high", note = "Non-tonal G/F♯ interference; static, eerie.",
  },
  {
    id = "look_beauty", labels = { "Music_LookBeauty" },
    key = { tonic = 2, scale = MIXOLYDIAN },
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookbeauty.asm",
    confidence = "medium", note = "D mixolydian / 150; C natural over D pedal.",
  },
  {
    id = "look_hiker", labels = { "Music_LookHiker" },
    key = { tonic = 11, mode = "minor" },
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookhiker.asm",
    confidence = "medium", note = "B minor / 145.5; driving, gruff.",
  },
  {
    id = "look_kimono_girl", labels = { "Music_LookKimonoGirl" },
    key = { tonic = 4, scale = PHRYGIAN },
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookkimonogirl.asm",
    confidence = "medium", note = "E phrygian / 120; F natural ♭2.",
  },
  {
    id = "look_lass", labels = { "Music_LookLass" },
    key = { tonic = 4, mode = "major" },
    sides = MELLOW,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/looklass.asm",
    confidence = "medium", note = "E major / 145.5; dreamy, sweet.",
  },
  {
    id = "look_mystical_man", labels = { "Music_LookMysticalMan" },
    key = { tonic = 11, scale = DORIAN },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookmysticalman.asm",
    confidence = "medium", note = "B dorian / 141.2; mysterious, pulsing.",
  },
  {
    id = "look_officer", labels = { "Music_LookOfficer" },
    key = { tonic = 4, mode = "major" },
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookofficer.asm",
    confidence = "medium", note = "E major / 165.5; brisk, alert.",
  },
  {
    id = "look_pokemaniac", labels = { "Music_LookPokemaniac" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookpokemaniac.asm",
    confidence = "low", note = "C-D♯-F♯-A dim7 symmetry; unstable, no tonic.",
  },
  {
    id = "look_sage", labels = { "Music_LookSage" },
    key = { tonic = 9, mode = "minor" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/looksage.asm",
    confidence = "medium", note = "A minor / 133.3; calm, wise.",
  },
  {
    id = "look_youngster", labels = { "Music_LookYoungster" },
    key = { tonic = 7, scale = MIXOLYDIAN },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookyoungster.asm",
    confidence = "medium", note = "G mixolydian / 162.7; playful, ♭7.",
  },
  {
    id = "prof_oak_gsc", labels = { "Music_ProfOak" },
    key = { tonic = 4, mode = "major" },
    sides = MELLOW,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/profoak.asm",
    confidence = "high", note = "E major / 162.7; warm, inquisitive.",
  },
  {
    id = "rocket_theme", labels = { "Music_RocketTheme" },
    key = { tonic = 0, mode = "minor" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/rockettheme.asm",
    confidence = "medium", note = "C minor / 150; menacing, chromatic.",
  },
  {
    id = "ss_aqua", labels = { "Music_SSAqua" },
    key = { tonic = 7, mode = "major" },
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/ssaqua.asm",
    confidence = "medium", note = "G major / 164.1; bright, nautical.",
  },

  -- Gen2 overworld -------------------------------------------------------
  {
    id = "azalea", labels = { "Music_AzaleaTown" },
    key = { tonic = 1, mode = "major" },
    source = "https://www.hooktheory.com/theorytab/view/go-ichinose/azalea-town---pokemon-gold-and-silver",
    confidence = "high", note = "D♭ major / 121; graceful folk-dance feel.",
  },
  {
    id = "burned_tower", labels = { "Music_BurnedTower" },
    key = { tonic = 0, mode = "minor" },
    sides = { center = { gain = 0.7 }, bassDown = { gain = 0.8 } },
    source = "https://chordu.com/chords-tabs-pok%C3%A9mon-gold-and-silver-tin-tower-remix-id_6LYe5Yp1XM8",
    confidence = "low", note = "C minor / ~95; slow, melancholic Tin Tower variant.",
  },
  {
    id = "celadon_city_gsc", labels = { "Music_CeladonCity" },
    key = { tonic = 7, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "medium", note = "G major / 132.2; distinct from Gen1 arrangement.",
  },
  {
    id = "cherrygrove", labels = { "Music_CherrygroveCity" },
    key = { tonic = 5, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "medium", note = "F major / 126.9; light 12-bar loop.",
  },
  {
    id = "dancing_hall", labels = { "Music_DancingHall" },
    sides = { left = { gain = 0.8 }, right = { semitones = -12 }, center = { enabled = false }, bassDown = { enabled = false } },
    source = "https://greenfieldcity.net/pokemon/music",
    confidence = "none", note = "No key published; shakuhachi/koto texture, sparse.",
  },
  {
    id = "dark_cave", labels = { "Music_DarkCave" },
    key = { tonic = 0, scale = PHRYGIAN },
    sides = { center = { gain = 0.7 } },
    source = "https://www.hooktheory.com/theorytab/view/junichi-masuda/dark-cave-(gsc)",
    confidence = "medium", note = "C phrygian / 151; Hooktheory over nayuki B♭.",
  },
  {
    id = "ecruteak", labels = { "Music_EcruteakCity" },
    key = { tonic = 0, mode = "major" },
    sides = { center = { gain = 0.75 } },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "high", note = "C major / 98; slow, calm.",
  },
  {
    id = "elms_lab", labels = { "Music_ElmsLab" },
    key = { tonic = 5, mode = "major" },
    source = "https://chordify.net/es/chords/zeng-tian-shun-yi-yi-zhi-lai-gang-songs/pokemon-lab-chords",
    confidence = "low", note = "F major / 88; warm, simple.",
  },
  {
    id = "goldenrod", labels = { "Music_GoldenrodCity" },
    key = { tonic = 1, mode = "major" },
    source = "https://www.hooktheory.com/theorytab/view/junichi-masuda/goldenrod-city---pokemon-gold-and-silver-versions",
    confidence = "high", note = "D♭ major / 110; busy 16ths.",
  },
  {
    id = "lake_of_rage", labels = { "Music_LakeOfRage" },
    key = { tonic = 7, mode = "major" },
    source = "https://www.hooktheory.com/theorytab/view/junichi-masuda/route-42---pokemon-gold-and-silver",
    confidence = "high", note = "G major / D mixolydian / 133; Route 42 groove.",
  },
  {
    id = "lavender_gsc", labels = { "Music_LavenderTown" },
    key = { tonic = 0, mode = "major" },
    sides = { center = { enabled = false }, bassDown = { gain = 0.8 } },
    source = "https://www.hooktheory.com/theorytab/view/junichi-masuda-and-go-ichinose/lavender-town---pokemon-gold-and-silver",
    confidence = "high", note = "C major / 119; eerie diminished 7ths; not Gen1 G major.",
  },
  {
    id = "magnet_train", labels = { "Music_MagnetTrain" },
    sides = { left = { gain = 0.7 }, center = { enabled = false }, bassDown = { enabled = false } },
    source = "https://archive.org/details/pkmn-gsc-soundtrack",
    confidence = "none", note = "~8s jingle; no harmonic key published.",
  },
  {
    id = "mom", labels = { "Music_Mom" },
    sides = { left = { gain = 0.7 }, center = { enabled = false }, bassDown = { enabled = false } },
    source = "https://songdata.io/album/5Da3cKHb8GGsRVA4U91Bd6/Pokemon-Gold-Silver-Crystal-Chiptune-Renditions-by-Bitmaster",
    confidence = "none", note = "Short jingle; no key published.",
  },
  {
    id = "mt_moon_gsc", labels = { "Music_MtMoon" },
    sides = { center = { enabled = false } },
    source = "https://bulbapedia.bulbagarden.net/wiki/List_of_overworld_music_themes",
    confidence = "none", note = "Rock Tunnel theme in GSC; modal cave, no key source.",
  },
  {
    id = "mt_moon_square", labels = { "Music_MtMoonSquare" },
    sides = { center = { gain = 0.75 } },
    source = "https://songdata.io/album/5Da3cKHb8GGsRVA4U91Bd6/Pokemon-Gold-Silver-Crystal-Chiptune-Renditions-by-Bitmaster",
    confidence = "none", note = "Short, quirky; cover database suggests F♯ minor / 119 (unverified).",
  },
  {
    id = "national_park", labels = { "Music_NationalPark" },
    key = { tonic = 1, mode = "major" },
    sides = { center = { gain = 0.75 } },
    source = "https://www.hooktheory.com/theorytab/view/junichi-masuda/pokemon-gold-and-silver---national-park",
    confidence = "high", note = "D♭ major / 101; melancholy, pensive.",
  },
  {
    id = "new_bark", labels = { "Music_NewBarkTown" },
    key = { tonic = 2, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "high", note = "D major / 103.1; gentle, three registers.",
  },
  {
    id = "pallet", labels = { "Music_PalletTown" },
    key = { tonic = 7, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "high", note = "G major; Gen1 120.6 bright, GSC 102.6 slower/mellow.",
  },
  {
    id = "rocket_hq", labels = { "Music_RocketHideout" },
    sides = { center = { enabled = false } },
    source = "https://archive.org/details/pkmn-gsc-soundtrack",
    confidence = "none", note = "Dark, stealthy; no reliable key source.",
  },
  {
    id = "route12_gsc", labels = { "Music_Route12" },
    key = { tonic = 4, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "medium", note = "E major / 130.4; same key/tempo as Gen1 Route 11.",
  },
  {
    id = "route1_gsc", labels = { "Music_Route1" },
    key = { tonic = 2, mode = "major" },
    sides = { center = { enabled = false }, bassDown = { gain = 0.8 } },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "medium", note = "D major / 104.9; only route theme without percussion.",
  },
  {
    id = "route26", labels = { "Music_Route26" },
    key = { tonic = 1, mode = "major" },
    source = "https://www.hooktheory.com/theorytab/view/go-ichinose/route-26---pokemon-gold-and-silver",
    confidence = "high", note = "D♭ major / 128; smooth 6/8.",
  },
  {
    id = "route29", labels = { "Music_Route29" },
    key = { tonic = 0, mode = "major" },
    source = "https://www.hooktheory.com/theorytab/view/junichi-masuda/route-29---pokemon-gold-and-silver-versions",
    confidence = "high", note = "C major / 132; bright, rolling.",
  },
  {
    id = "route2_gsc", labels = { "Music_Route2" },
    key = { tonic = 0, mode = "major" },
    sides = { center = { gain = 0.75 } },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "medium", note = "C major / 127.8; forest/modal feel.",
  },
  {
    id = "route30", labels = { "Music_Route30" },
    key = { tonic = 0, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "medium", note = "C major / 134; also Prof Oak speech theme.",
  },
  {
    id = "route36_37", labels = { "Music_Route36", "Music_Route37" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "medium", note = "B♭ major → G major key change / 134; no single key override.",
  },
  {
    id = "route3_gsc", labels = { "Music_Route3" },
    key = { tonic = 9, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "medium", note = "A major / 120.6; 16th-note lead.",
  },
  {
    id = "ruins_interior", labels = { "Music_RuinsOfAlphInterior" },
    sides = { center = { enabled = false } },
    source = "https://greenfieldcity.net/pokemon/music",
    confidence = "none", note = "Atonal/polymeter; avoid strict tonal third/fifth.",
  },
  {
    id = "ruins_radio", labels = { "Music_RuinsOfAlphRadio" },
    sides = { left = { gain = 0.7 }, center = { enabled = false }, bassDown = { enabled = false } },
    source = "https://bulbapedia.bulbagarden.net/wiki/Radio",
    confidence = "none", note = "Eerie Unown/noise cue; no tonal key.",
  },
  {
    id = "sprout_tower", labels = { "Music_SproutTower" },
    key = { tonic = 5, scale = PHRYGIAN },
    sides = { center = { enabled = false } },
    source = "https://www.hooktheory.com/theorytab/view/junichi-masuda/sprout-tower",
    confidence = "high", note = "F phrygian / 110; Japanese In scale, avoid Western 3rds.",
  },
  {
    id = "tin_tower", labels = { "Music_TinTower" },
    key = { tonic = 0, mode = "minor" },
    sides = { center = { gain = 0.75 } },
    source = "https://chordu.com/chords-tabs-pok%C3%A9mon-gold-and-silver-tin-tower-remix-id_6LYe5Yp1XM8",
    confidence = "low", note = "C minor / ~95; sacred, solemn.",
  },
  {
    id = "union_cave", labels = { "Music_UnionCave" },
    sides = { center = { enabled = false } },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "none", note = "4/4 + 5/4 polymeter, detuned; key N/A.",
  },
  {
    id = "vermilion_gsc", labels = { "Music_VermilionCity" },
    key = { tonic = 9, mode = "major" },
    sides = { center = { gain = 0.75 } },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "medium", note = "A major / 109.6; slow feel, no percussion.",
  },
  {
    id = "violet_city", labels = { "Music_VioletCity" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "medium", note = "B major → D major key change / 117.6; no single key override.",
  },
  {
    id = "viridian_gsc", labels = { "Music_ViridianCity" },
    key = { tonic = 2, mode = "major" },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music",
    confidence = "medium", note = "D major / 122.9; Pewter city theme.",
  },

  -- Gen2 battles, events, systems ----------------------------------------
  -- Keys below derived from pret/pokecrystal .asm note histograms; margin
  -- noted where close. Shared-label tracks keep their existing profile.
  {
    id = "after_the_rival_fight", labels = { "Music_AfterTheRivalFight" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/aftertherivalfight.asm",
    confidence = "low", note = "G♯ minor region ambiguous; intro loops to LookRival.",
  },
  {
    id = "battle_tower_lobby", labels = { "Music_BattleTowerLobby" },
    key = { tonic = 4, mode = "major" },
    sides = { center = { gain = 0.75 } },
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/battletowerlobby.asm",
    confidence = "medium", note = "E major / 152; strong histogram margin.",
  },
  {
    id = "battle_tower_theme", labels = { "Music_BattleTowerTheme" },
    key = { tonic = 5, mode = "major" },
    sides = BATTLE,
    source = "https://www.hooktheory.com/theorytab/view/morikazu-aoki/battle-tower---pokemon-crystal-version",
    confidence = "high", note = "F major / 138; 94% diatonic, crystal-only.",
  },
  {
    id = "bicycle_gsc", labels = { "Music_Bicycle" },
    key = { tonic = 7, mode = "major" },
    sides = { center = { gain = 0.75 } },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-gsc-bicycle",
    confidence = "medium", note = "G major / 137.8; rolling triads.",
  },
  {
    id = "buenas_password", labels = { "Music_BuenasPassword" },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/buenaspassword.asm",
    confidence = "low", note = "G♯ minor region ambiguous; radio jingle.",
  },
  {
    id = "bug_catching_contest", labels = { "Music_BugCatchingContest" },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/bugcatchingcontest.asm",
    confidence = "low", note = "A/E ambiguous; remix of Gen1 Bicycle.",
  },
  {
    id = "champion_battle", labels = { "Music_ChampionBattle" },
    key = { tonic = 3, mode = "minor" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/championbattle.asm",
    confidence = "medium", note = "E♭ minor / 98; slow, heavy.",
  },
  {
    id = "clair", labels = { "Music_Clair" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/clair.asm",
    confidence = "low", note = "D♯/G♯ minor close race; no key override.",
  },
  {
    id = "contest_results", labels = { "Music_ContestResults" },
    key = { tonic = 7, mode = "major" },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/contestresults.asm",
    confidence = "medium", note = "G major / 144; short celebratory loop.",
  },
  {
    id = "crystal_opening", labels = { "Music_CrystalOpening" },
    key = { tonic = 6, mode = "minor" },
    source = "https://www.hooktheory.com/theorytab/view/junichi-masuda/opening-movie---pokemon-crystal-version",
    confidence = "high", note = "F♯ minor / 136; 90% diatonic, crystal-only intro.",
  },
  {
    id = "evolution", labels = { "Music_Evolution" },
    key = { tonic = 7, mode = "major" },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/evolution.asm",
    confidence = "medium", note = "G major / 132; strong ascending fanfare.",
  },
  {
    id = "gold_silver_opening2", labels = { "Music_GoldSilverOpening2" },
    sides = MELLOW,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/goldsilveropening2.asm",
    confidence = "low", note = "D minor candidate but close race; no key override.",
  },
  {
    id = "gold_silver_opening", labels = { "Music_GoldSilverOpening" },
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/goldsilveropening.asm",
    confidence = "low", note = "Sources disagree (C minor vs E♭ major); no key override.",
  },
  {
    id = "heal_pokemon", labels = { "Music_HealPokemon" },
    key = { tonic = 4, mode = "major" },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/healpokemon.asm",
    confidence = "medium", note = "E major / 144; strong histogram margin, short sting.",
  },
  {
    id = "johto_gym_battle", labels = { "Music_JohtoGymBattle" },
    key = { tonic = 2, mode = "minor" },
    sides = BATTLE,
    source = "https://www.hooktheory.com/theorytab/view/junichi-masuda/pokemon-gold-and-silver---gym-leader-battle-theme",
    confidence = "high", note = "D minor / 191; 72% diatonic, tense.",
  },
  {
    id = "johto_trainer_battle", labels = { "Music_JohtoTrainerBattle" },
    key = { tonic = 3, mode = "major" },
    sides = BATTLE,
    source = "https://www.hooktheory.com/theorytab/view/junichi-masuda/vs-johto-trainer",
    confidence = "high", note = "E♭ major / 188 (asm 102); crisp counterpoint.",
  },
  {
    id = "johto_wild_battle", labels = { "Music_JohtoWildBattle" },
    key = { tonic = 7, mode = "major" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/johtowildbattle.asm",
    confidence = "high", note = "G major / 104; Hooktheory 182 BPM.",
  },
  {
    id = "johto_wild_battle_night", labels = { "Music_JohtoWildBattleNight" },
    key = { tonic = 7, mode = "major" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/johtowildbattlenight.asm",
    confidence = "medium", note = "G major / 107; loops JohtoWildBattle body.",
  },
  {
    id = "kanto_gym_battle", labels = { "Music_KantoGymBattle" },
    key = { tonic = 3, mode = "minor" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/kantogymbattle.asm",
    confidence = "medium", note = "D♯ minor / 101; reuses Johto Gym material.",
  },
  {
    id = "kanto_trainer_battle", labels = { "Music_KantoTrainerBattle" },
    key = { tonic = 3, mode = "major" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/kantotrainerbattle.asm",
    confidence = "medium", note = "E♭ major / 114; crisp, distinct from Johto Trainer.",
  },
  {
    id = "kanto_wild_battle", labels = { "Music_KantoWildBattle" },
    key = { tonic = 0, mode = "major" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/kantowildbattle.asm",
    confidence = "medium", note = "C major / 112; GSC arrangement with passing chromatics.",
  },
  {
    id = "look_rocket", labels = { "Music_LookRocket" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookrocket.asm",
    confidence = "low", note = "Suspicious/atenal encounter; no reliable key override.",
  },
  {
    id = "main_menu", labels = { "Music_MainMenu" },
    sides = { center = { gain = 0.75 } },
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/mainmenu.asm",
    confidence = "low", note = "B/G♯ minor close race; no key override.",
  },
  {
    id = "mobile_adapter", labels = { "Music_MobileAdapter" },
    key = { tonic = 2, mode = "major" },
    sides = { center = { gain = 0.75 } },
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/mobileadapter.asm",
    confidence = "medium", note = "D major / 132; clean dial-up motif.",
  },
  {
    id = "mobile_adapter_menu", labels = { "Music_MobileAdapterMenu" },
    key = { tonic = 4, mode = "major" },
    sides = { center = { gain = 0.75 } },
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/mobileadaptermenu.asm",
    confidence = "medium", note = "E major / 168; bright UI loop.",
  },
  {
    id = "mobile_center", labels = { "Music_MobileCenter" },
    key = { tonic = 0, mode = "major" },
    sides = { center = { gain = 0.75 } },
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/mobilecenter.asm",
    confidence = "medium", note = "C major / 160; strong histogram margin.",
  },
  {
    id = "poke_flute_channel", labels = { "Music_PokeFluteChannel" },
    key = { tonic = 0, mode = "major" },
    sides = SPARSE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/pokeflutechannel.asm",
    confidence = "medium", note = "C major / 240; airy, mostly melody + drone.",
  },
  {
    id = "pokemon_center_gsc", labels = { "Music_PokemonCenter" },
    key = { tonic = 2, mode = "major" },
    sides = { center = { gain = 0.75 } },
    source = "https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-gsc-pokemon-center",
    confidence = "medium", note = "D major / 126.9; distinct Gen2 arrangement.",
  },
  {
    id = "pokemon_channel", labels = { "Music_PokemonChannel" },
    key = { tonic = 7, mode = "major" },
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/pokemonchannel.asm",
    confidence = "medium", note = "G major / 128; calm TV theme.",
  },
  {
    id = "pokemon_lullaby", labels = { "Music_PokemonLullaby" },
    sides = MELLOW,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/pokemonlullaby.asm",
    confidence = "low", note = "C major candidate but close race; no key override.",
  },
  {
    id = "pokemon_march", labels = { "Music_PokemonMarch" },
    key = { tonic = 3, mode = "major" },
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/pokemonmarch.asm",
    confidence = "medium", note = "E♭ major / 144; strong marching answer phrases.",
  },
  {
    id = "post_credits", labels = { "Music_PostCredits" },
    key = { tonic = 0, mode = "major" },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/postcredits.asm",
    confidence = "medium", note = "C major / 271; fast epilogue.",
  },
  {
    id = "prof_oaks_talk", labels = { "Music_ProfOaksPokemonTalk" },
    key = { tonic = 11, mode = "major" },
    sides = MELLOW,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/profoakspokemontalk.asm",
    confidence = "medium", note = "B major / 164; mellow dialogue bed.",
  },
  {
    id = "rival_battle_gsc", labels = { "Music_RivalBattle" },
    key = { tonic = 3, mode = "minor" },
    sides = BATTLE,
    source = "https://www.hooktheory.com/theorytab/view/junichi-masuda/rival-battle---pokemon-gold-and-silver",
    confidence = "high", note = "D♯ minor / 190; smooth, moody, tight harmony.",
  },
  {
    id = "rocket_battle_gsc", labels = { "Music_RocketBattle" },
    key = { tonic = 9, scale = PHRYGIAN },
    sides = BATTLE,
    source = "https://www.hooktheory.com/theorytab/view/junichi-masuda/team-rocket-battle---pokemon-gold-and-silver",
    confidence = "high", note = "A phrygian / 188; ♭2 color, sinister.",
  },
  {
    id = "successful_capture", labels = { "Music_SuccessfulCapture" },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/successfulcapture.asm",
    confidence = "medium", note = "Jumps to WildPokemonVictory body; key reports conflict, no override.",
  },
  {
    id = "suicune_battle", labels = { "Music_SuicuneBattle" },
    key = { tonic = 9, mode = "minor" },
    sides = BATTLE,
    source = "https://www.hooktheory.com/theorytab/view/junichi-masuda/suicune-battle---pokemon-crystal-version",
    confidence = "high", note = "A minor / 190; ceremonial battle, isus4 color.",
  },
  {
    id = "surf_gsc", labels = { "Music_Surf" },
    key = { tonic = 3, mode = "major" },
    sides = MELLOW,
    source = "https://www.hooktheory.com/theorytab/view/game-freak/surf---pokemon-gold-and-silver",
    confidence = "high", note = "E♭ major / 177 (asm 108); flowing 3/4.",
  },
  {
    id = "wild_pokemon_victory", labels = { "Music_WildPokemonVictory" },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/wildpokemonvictory.asm",
    confidence = "medium", note = "Shares body with SuccessfulCapture; key reports conflict, no override.",
  },

  -- Previously unfiled Gen2 overworld / victory cues ---------------------
  {
    id = "lighthouse_gsc", labels = { "Music_Lighthouse" },
    key = { tonic = 1, mode = "minor" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lighthouse.asm",
    confidence = "medium", note = "C♯ minor / 144; B and A♯ inflections.",
  },
  {
    id = "look_rival", labels = { "Music_LookRival" },
    key = { tonic = 5, mode = "minor" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookrival.asm",
    confidence = "medium", note = "F minor / 112; relative minor of AfterTheRivalFight.",
  },
  {
    id = "show_me_around", labels = { "Music_ShowMeAround" },
    key = { tonic = 4, mode = "major" },
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/showmearound.asm",
    confidence = "low", note = "E major / 144; mixolydian D natural common.",
  },
  {
    id = "trainer_victory", labels = { "Music_TrainerVictory" },
    key = { tonic = 9, mode = "major" },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/trainervictory.asm",
    confidence = "medium", note = "A major / 120; bright victory sting.",
  },
  {
    id = "dragons_den", labels = { "Music_DragonsDen" },
    key = { tonic = 1, mode = "minor" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/dragonsden.asm",
    confidence = "low", note = "C♯ minor / 144; drone-heavy, ancient feel.",
  },
  {
    id = "gym_leader_victory", labels = { "Music_GymLeaderVictory" },
    key = { tonic = 2, mode = "major" },
    sides = JINGLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/gymleadervictory.asm",
    confidence = "medium", note = "D major / 116; triumphant fanfare.",
  },
  {
    id = "victory_road_gsc", labels = { "Music_VictoryRoad" },
    key = { tonic = 4, mode = "major" },
    sides = BATTLE,
    source = "https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/victoryroad.asm",
    confidence = "low", note = "E major / 144; mixed-mode cave theme.",
  },
}

local byLabel = {}
for _, entry in ipairs(entries) do
  for _, label in ipairs(entry.labels) do byLabel[label] = entry end
end

local function forLabel(label)
  return byLabel[label]
end

local function validate()
  local seen = {}
  for _, entry in ipairs(entries) do
    assert(type(entry.id) == "string" and entry.id ~= "", "profile id required")
    assert(not seen[entry.id], "duplicate profile id: " .. entry.id)
    seen[entry.id] = true
    assert(type(entry.labels) == "table" and #entry.labels > 0,
      "profile " .. entry.id .. " needs labels")
    for _, label in ipairs(entry.labels) do
      assert(type(label) == "string" and label:match("^Music_"),
        "bad label in profile " .. entry.id)
      assert(byLabel[label] == entry, "label index mismatch for " .. label)
    end
    if entry.key then
      local tonic = tonumber(entry.key.tonic)
      assert(tonic and tonic >= 0 and tonic <= 11 and tonic == math.floor(tonic),
        "tonic must be 0..11 in profile " .. entry.id)
      local scale = entry.key.scale or MODE_SCALES[entry.key.mode]
      assert(type(scale) == "table" and #scale >= 3,
        "key needs a known mode or scale in profile " .. entry.id)
      for _, degree in ipairs(scale) do
        assert(tonumber(degree) and degree >= 0 and degree <= 11,
          "scale degrees must be 0..11 in profile " .. entry.id)
      end
    end
    if entry.sides then
      for name, side in pairs(entry.sides) do
        assert(SIDES[name], "unknown side " .. tostring(name) .. " in profile " .. entry.id)
        assert(type(side) == "table", "side " .. name .. " must be a table in " .. entry.id)
        if side.degree ~= nil then assert(tonumber(side.degree), "bad degree in " .. entry.id) end
        if side.semitones ~= nil then assert(tonumber(side.semitones), "bad semitones in " .. entry.id) end
      end
    end
    assert(type(entry.source) == "string" and entry.source ~= "",
      "source required in profile " .. entry.id)
    assert(type(entry.confidence) == "string", "confidence required in profile " .. entry.id)
  end
  return true
end

return {
  entries = entries,
  byLabel = byLabel,
  forLabel = forLabel,
  validate = validate,
}
