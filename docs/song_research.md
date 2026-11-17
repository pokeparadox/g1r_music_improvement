# Song research — guided Gen1/Gen2 enhancement

Research scope: every `Music_*` label in `songs_dump.txt` (144 unique).
Goal: steer the extra harmony layer with sourced key/mode/texture instead of one-size-fits-all transposition.
Fallback: labels with no usable source keep current `improve.lua` detection; no profile entry, no behavior change.

Sources used most:
- Nayuki transcription table (key + BPM for RGBY/GSC tracks): https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music
- Hooktheory theorytab pages (key, mode, mood): https://www.hooktheory.com/theorytab/artist/game-freak
- pret disassembly sources (`*.asm`) for exact note data: https://github.com/pret/pokered, https://github.com/pret/pokegold, https://github.com/pret/pokecrystal, https://github.com/pret/pokeyellow
- greenfieldcity texture notes: https://www.greenfieldcity.net/pokemon/music
- jasonyu battle analysis: https://jasonyu.me/pokemon-battle

`CONF` is source agreement. `TWEAK` maps to `song_profiles.lua` side overrides:
- `bright` — default diatonic thirds/sixths.
- `mellow` — quieter center voice.
- `spooky` / `battle` — disable center fifth; keep octaves/bass.
- `jingle` / `sparse` — quiet lead, no center voice, no bass octave.
- `drive` — tighter diatonic harmony, bass retained.

Shared labels with conflicting Gen1/Gen2 keys (`Music_Credits`, `Music_Gym`, `Music_IndigoPlateau`, `Music_TitleScreen`, `Music_GameCorner` partially) get **no key override**; profile carries only tweak/note. Exact-label lookup only; `Music_Lavender` (E minor) and `Music_LavenderTown` (C major) stay separate.

## Gen1 overworld

| Labels | Title | Key | BPM | Mood / texture | CONF | TWEAK | Source |
|---|---|---|---|---|---|---|---|
| `Music_BikeRiding` | Cycling | C major | 134 | rolling diatonic triads | high | drive | [Hooktheory](https://hooktheory.com/theorytab/view/junichi-masuda/cycling---pokemon-red-blue-and-yellow-versions) |
| `Music_Celadon` | Celadon City | G major / D mixolydian | 134 | bright, upbeat | medium | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Cinnabar` | Cinnabar Island | G major | 134 | laid-back 12-bar loop | medium | mellow | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_CinnabarMansion` | Pokémon Mansion | atonal | 134 | erratic, unfinished loops | high | sparse | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Cities1` | Viridian / Pewter / Saffron | E major / F♯ minor | 134 | dissonant overlaps | medium | sparse | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Cities2` | Cerulean / Fuchsia | E major | 130.3 | bright, pastoral | medium | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Dungeon1` | Rocket Hideout | E minor | 134 | scheming chromatic riff | medium | spooky | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Dungeon2` | Viridian Forest | E minor pentatonic | 134 | mysterious, airy | high | sparse | [Hooktheory](https://hooktheory.com/theorytab/view/game-freak/viridian-forest-%28pokemon-red-blue-yellow%29) |
| `Music_Dungeon3` | Mt. Moon | no functional key | 134 | augmented triads, odd meter | high | spooky | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_GameCorner` | Game Corner | E major (G1) / F minor (G2) | 160.8 / 138 | frantic arcade | medium | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Gym` | Gym | F major (G1) / G mixolydian (G2) | 139.8 / 123.7 | playful | medium | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_IndigoPlateau` | Indigo Plateau | D minor / F major (G1), B♭ major / G minor (G2) | 146.1 | determined | medium | battle | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_JigglypuffSong` | Jigglypuff's Song | E major / mixolydian | 144 | soft lullaby | medium | jingle | [pokered](https://raw.githubusercontent.com/pret/pokered/master/audio/music/jigglypuffsong.asm) |
| `Music_Lavender` | Lavender Town | E minor | 126.9 | ghostly, diminished | high | spooky | [Hooktheory](https://hooktheory.com/theorytab/view/nintendo/pokemon-red-and-blue---lavender-town) |
| `Music_MeetProfOak` | Professor Oak | E major | 172.2 | urgent, narrow range | medium | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_MuseumGuy` | Museum Guy / Guide | A major | 150.7 | hurried comic intro | medium | jingle | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_OaksLab` | Professor Oak's Lab | A major | 137.8 | inquisitive, active bass | medium | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Pokecenter` | Pokémon Center | D major | 134 | near-pure diatonic | high | bright | [Hooktheory](https://hooktheory.com/theorytab/view/game-freak/pokemon-center---pokemon-red-and-blue) |
| `Music_PokemonTower` | Pokémon Tower | G major / E minor | 126.9 | haunted, sparse | medium | spooky | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Routes1` | Route 1 / 25 | D major | 126.9 | bright, simple | high | bright | [Hooktheory](https://hooktheory.com/theorytab/view/nintendo/pokemon-route-1---1st-generation) |
| `Music_Routes2` | Routes 3 / 9 / 16 | C major | 130.3 | cheerful, busy | medium | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Routes3` | Routes 11 / 14 | E mixolydian | 130.3 | ♭VII color | medium | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Routes4` | Route 24 | E mixolydian | 126.9 | short 10-bar loop | medium | jingle | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_SafariZone` | Safari Zone | G major | 146.2 | tiny 2-bar loop | medium | jingle | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_SilphCo` | Silph Co. | no functional key | 134 | semitone steps, tense | high | sparse | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_SSAnne` | S.S. Anne | A major | 150.7 | jaunty, overlapping lines | high | bright | [Hooktheory](https://hooktheory.com/theorytab/view/game-freak/ss-anne---pokemon-red-and-blue) |
| `Music_Surfing` | Surfing | A major | 120.6 | flowing 6/8 | medium | mellow | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_TitleScreen` | Title | C major (G1) / G mixolydian (G2) | 134 / 144 | heroic | medium | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Vermilion` | Vermilion City | F♯ minor / A major | 123.6 | bouncy port | medium | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_YellowIntro` | Yellow intro | E major | 116 | triumphant fanfare | medium | jingle | [pokeyellow](https://raw.githubusercontent.com/pret/pokeyellow/master/audio/music/yellowintro.asm) |

## Gen1 battles / endings / jingles

| Labels | Title | Key | BPM | Mood / texture | CONF | TWEAK | Source |
|---|---|---|---|---|---|---|---|
| `Music_Credits` | Credits | D major (G1) / C major (G2) | 137.8 / 138 | triumphant | medium | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_DefeatedGymLeader` | Gym Leader defeated | D major | 172.2 | fanfare | high | jingle | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_DefeatedTrainer` | Trainer defeated | D major | 172.2 | jaunty sting | high | jingle | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_DefeatedWildMon` | Wild Pokémon defeated | E major → F major | 172.2 | short sting | high | jingle | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_FinalBattle` | Final battle | A minor | 172.3 | intense | medium | battle | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_GBPrinter` | GB Printer | E major | 256 | single-channel drone | medium | sparse | [pokeyellow](https://raw.githubusercontent.com/pret/pokeyellow/master/audio/music/printer.asm) |
| `Music_GymLeaderBattle` | Gym Leader battle | B mixolydian | 185.5 | driving, A natural ♭VII | high | battle | [Hooktheory](https://www.hooktheory.com/theorytab/view/junichi-masuda/pokemon-rgb-gym-leader-battle) |
| `Music_HallOfFame` | Hall of Fame | G mixolydian | 112 | ceremonial, F natural | medium | bright | [pokered](https://raw.githubusercontent.com/pret/pokered/master/audio/music/halloffame.asm) |
| `Music_IntroBattle` | Intro battle | D minor | 98 | urgent | medium | battle | [pokered](https://raw.githubusercontent.com/pret/pokered/master/audio/music/introbattle.asm) |
| `Music_MeetEvilTrainer` | Evil trainer | G♯ minor | 155.6 | sinister | medium | spooky | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_MeetFemaleTrainer` | Female trainer | E major | 155.6 | cheerful | high | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_MeetJessieJames` | Jessie & James | B♭ minor | 144 | scheming | medium | spooky | [pokeyellow](https://raw.githubusercontent.com/pret/pokeyellow/master/audio/music/meetjessiejames.asm) |
| `Music_MeetMaleTrainer` | Male trainer | E major | 172.2 | brisk | medium | drive | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_MeetRival` | Rival encounter | G mixolydian | 172.2 | restless | medium | drive | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_PkmnHealed` | Pokémon healed | E major | 144 | soothing sting | medium | jingle | [pokered](https://raw.githubusercontent.com/pret/pokered/master/audio/music/pkmnhealed.asm) |
| `Music_Printer` | Printer (GSC) | E major | 256 | sparse single-channel drone | medium | sparse | [pokegold](https://raw.githubusercontent.com/pret/pokegold/master/audio/music/printer.asm) |
| `Music_SurfingPikachu` | Surfing Pikachu | E major | 117 | playful | medium | bright | [pokeyellow](https://raw.githubusercontent.com/pret/pokeyellow/master/audio/music/surfingpikachu.asm) |
| `Music_TrainerBattle` | Trainer battle | B minor | 172.2 | aggressive | high | battle | [Hooktheory](https://www.hooktheory.com/theorytab/view/junichi-masuda/trainer-battle---pokemon-red-and-blue) |
| `Music_WildBattle` | Wild battle | C mixolydian | 185.5 | frantic, ♭VII | high | drive | [Hooktheory](https://www.hooktheory.com/theorytab/view/junichi-masuda/wild-pokemon-battle---pokemon-red-and-blue) |

## Gen2 overworld

Full per-label detail (40 tracks) recorded in journal entry `20261117-205156-482`; summary below.

| Labels | Title | Key | BPM | Mood / texture | CONF | TWEAK | Source |
|---|---|---|---|---|---|---|---|
| `Music_Azalea` | Azalea Town | D♭ major | 121 | bright, rustic | high | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_BurnedTower` | Burned Tower | C minor | 95 | eerie, low | low | spooky | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_CeladonCity` | Celadon City (GSC) | G major | 132.2 | bright, driving | medium | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Cherrygrove` | Cherrygrove City | F major | 126.9 | gentle, bright | medium | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_DancingHall` | Dance Hall | no key | — | sparse, percussive | high | sparse | [pokegold](https://raw.githubusercontent.com/pret/pokegold/master/audio/music/dancinghall.asm) |
| `Music_DarkCave` | Dark Cave | C phrygian | 151 | dark, urgent | medium | spooky | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Ecruteak` | Ecruteak City | C major | 98 | mellow, traditional | high | mellow | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_ElmsLab` | Elm's Lab | F major | 88 | bright, curious | low | bright | [pokegold](https://raw.githubusercontent.com/pret/pokegold/master/audio/music/elmslab.asm) |
| `Music_Goldenrod` | Goldenrod City | D♭ major | 110 | busy, driving | high | drive | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_LakeOfRage` | Lake of Rage | G major / D mixolydian | 133 | driving, mysterious | high | drive | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_LavenderTown` | Lavender Town (GSC) | C major | 119 | spooky, sparse | high | spooky | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_NationalPark` | National Park | D♭ major | 101 | mellow, pastoral | high | mellow | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_NewBark` | New Bark Town | D major | 103.1 | bright, hopeful | high | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_PalletTown` | Pallet Town (GSC) | G major | 102.6 | mellow, home | high | mellow | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Route12` | Route 12 | E major | 130.4 | driving, open | medium | drive | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Route1` | Route 1 (GSC) | D major | 104.9 | sparse, simple | medium | sparse | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Route26` | Route 26 | D♭ major | 128 | bright, journey | high | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Route29` | Route 29 | C major | 132 | energetic | high | drive | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Route2` | Route 2 (GSC) | C major | 127.8 | mellow, walking | medium | mellow | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Route30` | Route 30 | C major | 134 | bright, simple | medium | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Route36` / `Music_Route37` | Routes 36 / 37 | B♭ major → G major | — | modulating, driving | medium | drive | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Route3` | Route 3 (GSC) | A major | 120.6 | driving, sunny | medium | drive | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Route38` | Route 38 | E major | 134 | bright, rolling | high | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Route42` | Route 42 | G major | 134 | bright, rolling | high | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_SproutTower` | Sprout Tower | F phrygian | 110 | spooky, zen | high | spooky | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_TinTower` | Tin Tower | C minor | 95 | mellow, sacred | low | mellow | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Vermilion` | Vermilion City (GSC) | A major | 109.6 | mellow, port | medium | mellow | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Violet` | Violet City | B major → D major | — | modulating, bright | medium | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Viridian` | Viridian City (GSC) | D major | 122.9 | bright, walking | medium | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_Bicycle` | Cycling (GSC) | G major / C major | 134 | rolling | medium | drive | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_DragonsDen` | Dragon's Den | C♯ minor | 144 | drone-heavy, ancient | low | battle | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/dragonsden.asm) |
| `Music_Lighthouse` | Lighthouse | C♯ minor | 144 | storm, tense | medium | battle | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lighthouse.asm) |
| `Music_MagnetTrain` | Magnet Train | no reliable key | — | mechanical | low | fallback | — |
| `Music_MtMoon` | Mt. Moon (GSC) | no reliable key | — | cave | low | fallback | — |
| `Music_MtMoonSquare` | Mt. Moon Square | no reliable key | — | outdoors | low | fallback | — |
| `Music_RocketHideout` | Rocket Hideout (GSC) | no reliable key | — | tense | low | fallback | — |
| `Music_RuinsOfAlphInterior` | Ruins of Alph (inside) | no reliable key | — | ancient | low | fallback | — |
| `Music_RuinsOfAlphRadio` | Ruins of Alph (radio) | no reliable key | — | cryptic | low | fallback | — |
| `Music_ShowMeAround` | Show Me Around | E major | 144 | demo, mixolydian color | low | bright | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/showmearound.asm) |
| `Music_UnionCave` | Union Cave | no reliable key | — | cave | low | fallback | — |
| `Music_VictoryRoad` | Victory Road (GSC) | E major | 144 | rocky, mixed-mode | low | battle | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/victoryroad.asm) |

## Gen2 battles / events

Keys chosen from the authoritative research pass. Hooktheory and Nayuki take priority over histogram derivation when available. Shared labels keep no key override; unresearched or close-race tracks stay fallback.

| Label | Title | Key | BPM | Mood / texture | CONF | TWEAK | Source |
|---|---|---|---|---|---|---|---|
| `Music_AfterTheRivalFight` | After the Rival Fight | no override | 112 | tense, bittersweet | low | battle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/aftertherivalfight.asm) |
| `Music_BattleTowerLobby` | Battle Tower Lobby | E major | 152 | bright, brisk | medium | bright | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/battletowerlobby.asm) |
| `Music_BattleTowerTheme` | Battle Tower | F major | 138 | smooth, bright, competitive | high | battle | [source](https://www.hooktheory.com/theorytab/view/morikazu-aoki/battle-tower---pokemon-crystal-version) |
| `Music_Bicycle` | Bicycle (GSC) | G major | 137.8 | rolling, cheerful | medium | bright | [source](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-gsc-bicycle) |
| `Music_BuenasPassword` | Buenas Password | no override | 136 | quirky, secretive | low | jingle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/buenaspassword.asm) |
| `Music_BugCatchingContest` | Bug Catching Contest | no override | 144 | playful, light | low | jingle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/bugcatchingcontest.asm) |
| `Music_ChampionBattle` | Champion Battle | E♭ minor | 98 | slow, heavy, dramatic | medium | battle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/championbattle.asm) |
| `Music_Clair` | Clair | no override | 136 | mysterious, tense | low | battle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/clair.asm) |
| `Music_ContestResults` | Contest Results | G major | 144 | celebratory, bright | medium | jingle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/contestresults.asm) |
| `Music_Credits` | Ending (GSC) | no override (Gen1 D major) | 138 | bright, reflective | medium | bright | [source](https://www.hooktheory.com/theorytab/view/go-ichinose/ending---pokemon-gold-and-silver) |
| `Music_CrystalOpening` | Opening Movie (Crystal) | F♯ minor | 136 | smooth, moody | high | mellow | [source](https://www.hooktheory.com/theorytab/view/junichi-masuda/opening-movie---pokemon-crystal-version) |
| `Music_Evolution` | Evolution | G major | 132 | ascending, wondrous | medium | jingle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/evolution.asm) |
| `Music_GoldSilverOpening2` | Gold/Silver Opening 2 | no override | 92 | slow, melancholic | low | mellow | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/goldsilveropening2.asm) |
| `Music_GoldSilverOpening` | Gold/Silver Opening | no override | 168 | driving, fanfare | low | drive | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/goldsilveropening.asm) |
| `Music_Gym` | Gym (GSC) | no override (Gen1 F major) | 123.7 | mellow, focused | medium | bright | [source](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-gsc-gym) |
| `Music_HallOfFame` | Hall of Fame (GSC) | no override (Gen1 G mixolydian) | 112 | ceremonial, bright | medium | bright | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/halloffame.asm) |
| `Music_HealPokemon` | Heal Pokemon | E major | 144 | bright, soothing | medium | jingle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/healpokemon.asm) |
| `Music_JohtoGymBattle` | Gym Leader Battle (GSC) | D minor | 191 | tense, complex, moody | high | battle | [source](https://www.hooktheory.com/theorytab/view/junichi-masuda/pokemon-gold-and-silver---gym-leader-battle-theme) |
| `Music_JohtoTrainerBattle` | Vs Johto Trainer | E♭ major | 188 | unexpected, upbeat, bright | high | battle | [source](https://www.hooktheory.com/theorytab/view/junichi-masuda/vs-johto-trainer) |
| `Music_JohtoWildBattle` | Wild Pokemon Battle (Johto) | G major | 182 | complex, upbeat, bright | high | battle | [source](https://www.hooktheory.com/theorytab/view/junichi-masuda/wild-pokemon-battle---pokemon-gold-and-silver) |
| `Music_JohtoWildBattleNight` | Wild Pokemon Battle (Night) | G major | 179.4 | tense, darker | medium | battle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/johtowildbattlenight.asm) |
| `Music_KantoGymBattle` | Kanto Gym Leader Battle | E♭ minor | 101 | tense, urgent | medium | battle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/kantogymbattle.asm) |
| `Music_KantoTrainerBattle` | Kanto Trainer Battle | E♭ major | 114 | brisk, crisp | medium | battle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/kantotrainerbattle.asm) |
| `Music_KantoWildBattle` | Kanto Wild Battle | C major | 112 | frantic, urgent | medium | battle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/kantowildbattle.asm) |
| `Music_LookRocket` | Look Rocket | no override | 123 | suspicious, stealthy | low | battle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookrocket.asm) |
| `Music_MainMenu` | Main Menu | no override | 160 | urgent, busy | low | bright | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/mainmenu.asm) |
| `Music_MobileAdapter` | Mobile Adapter | D major | 132 | clean, dial-up motif | medium | bright | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/mobileadapter.asm) |
| `Music_MobileAdapterMenu` | Mobile Adapter Menu | E major | 168 | bright, UI-like | medium | bright | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/mobileadaptermenu.asm) |
| `Music_MobileCenter` | Mobile Center | C major | 160 | bright, clean | medium | bright | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/mobilecenter.asm) |
| `Music_PokeFluteChannel` | Poké Flute Channel | C major | 240 | airy, sparse | medium | sparse | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/pokeflutechannel.asm) |
| `Music_PokemonCenter` | Pokemon Center (GSC) | D major | 126.9 | warm, diatonic | medium | bright | [source](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music#pokemon-gsc-pokemon-center) |
| `Music_PokemonChannel` | Pokemon Channel | G major | 128 | calm, friendly | medium | mellow | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/pokemonchannel.asm) |
| `Music_PokemonLullaby` | Pokemon Lullaby | no override | 224 | gentle, sleepy | low | mellow | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/pokemonlullaby.asm) |
| `Music_PokemonMarch` | Pokemon March | E♭ major | 144 | marching, playful | medium | drive | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/pokemonmarch.asm) |
| `Music_PostCredits` | Post Credits | C major | 271 | fast, epilogue | medium | jingle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/postcredits.asm) |
| `Music_ProfOaksPokemonTalk` | Prof Oak’s Pokémon Talk | B major | 164 | mellow, inquisitive | medium | mellow | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/profoakspokemontalk.asm) |
| `Music_RivalBattle` | Rival Battle (GSC) | D♯ minor | 190 | smooth, moody, upbeat | high | battle | [source](https://www.hooktheory.com/theorytab/view/junichi-masuda/rival-battle---pokemon-gold-and-silver) |
| `Music_RocketBattle` | Team Rocket Battle | A phrygian | 188 | sinister, tense | high | battle | [source](https://www.hooktheory.com/theorytab/view/junichi-masuda/team-rocket-battle---pokemon-gold-and-silver) |
| `Music_SuccessfulCapture` | Successful Capture | no override | 126 | triumphant, bright | medium | jingle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/successfulcapture.asm) |
| `Music_SuicuneBattle` | Suicune Battle | A minor | 190 | upbeat, moody | high | battle | [source](https://www.hooktheory.com/theorytab/view/junichi-masuda/suicune-battle---pokemon-crystal-version) |
| `Music_Surf` | Surf (GSC) | E♭ major | 177 | tense, complex, bright | high | mellow | [source](https://www.hooktheory.com/theorytab/view/game-freak/surf---pokemon-gold-and-silver) |
| `Music_TitleScreen` | Title Screen (GSC) | no override (Gen1 C major) | 144 | smooth, upbeat, unexpected | high | bright | [source](https://www.hooktheory.com/theorytab/view/junichi-masuda/title-screen---pokemon-gold-and-silver-versions) |
| `Music_WildPokemonVictory` | Wild Pokémon Victory | no override | 126 | triumphant, brief | medium | jingle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/wildpokemonvictory.asm) |
| `Music_LookRival` | Look Rival | F minor | 112 | relative minor of above | medium | battle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookrival.asm) |
| `Music_GymLeaderVictory` | Gym Leader Victory | D major | 116 | triumphant fanfare | medium | jingle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/gymleadervictory.asm) |
| `Music_TrainerVictory` | Trainer Victory | A major | 120 | bright sting | medium | jingle | [source](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/trainervictory.asm) |

## Encounters / radio / misc

| Labels | Title | Key | BPM | Mood / texture | CONF | TWEAK | Source |
|---|---|---|---|---|---|---|---|
| `Music_LakeOfRageRocketRadio` | Rocket Radio | non-tonal G/F♯ interference | — | static, eerie | high | sparse | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lakeofragerocketradio.asm) |
| `Music_LookBeauty` | Look Beauty | D mixolydian | 150 | C natural over D pedal | medium | bright | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookbeauty.asm) |
| `Music_LookHiker` | Look Hiker | B minor | 145.5 | gruff, driving | medium | drive | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookhiker.asm) |
| `Music_LookKimonoGirl` | Look Kimono Girl | E phrygian | 120 | ♭2 color | medium | bright | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookkimonogirl.asm) |
| `Music_LookLass` | Look Lass | E major | 145.5 | dreamy, sweet | medium | mellow | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/looklass.asm) |
| `Music_LookMysticalMan` | Look Mystical Man | B dorian | 141.2 | mysterious, pulsing | medium | spooky | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookmysticalman.asm) |
| `Music_LookOfficer` | Look Officer | E major | 165.5 | brisk, alert | medium | drive | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookofficer.asm) |
| `Music_LookPokemaniac` | Look Pokemaniac | dim7 symmetry | — | unstable | low | spooky | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookpokemaniac.asm) |
| `Music_LookSage` | Look Sage | A minor | 133.3 | calm, wise | medium | sparse | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/looksage.asm) |
| `Music_LookYoungster` | Look Youngster | G mixolydian | 162.7 | playful, ♭7 | medium | jingle | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/lookyoungster.asm) |
| `Music_ProfOak` | Professor Oak (GSC) | E major | 162.7 | warm, inquisitive | high | mellow | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/profoak.asm) |
| `Music_RocketTheme` | Rocket Theme | C minor | 150 | menacing, chromatic | medium | battle | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/rockettheme.asm) |
| `Music_SSAnne` | S.S. Anne (GSC) | A major | 150.7 | jaunty | high | bright | [Nayuki](https://www.nayuki.io/page/transcription-of-pokemon-game-boy-music) |
| `Music_SSAqua` | S.S. Aqua | G major | 164.1 | bright, nautical | medium | bright | [pokecrystal](https://raw.githubusercontent.com/pret/pokecrystal/master/audio/music/ssaqua.asm) |
