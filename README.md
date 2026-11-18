# G1R Music Improvement

AI Usage Disclosure. I am not a LUA dev and OpenCode was used to develop this addon.

## Overview

Music Improvement enhances the game's original Game Boy-style chiptune soundtrack, transforming the familiar melodies into fuller, richer arrangements while preserving the original musical identity.
It supports both Gen1 and Gen2 chip-music engine formats.

Rather than replacing the original sound system with external instruments or prerecorded audio, the mod builds upon the game's existing chip-music synthesis engine. Original music is analysed, enhanced and reassembled into improved arrangements, with additional harmony layers generated dynamically from the original musical parts.

The result is a more immersive and layered soundtrack that retains the character of classic Game Boy music.
There are no large files to download as we generate and cache the additional channels on startup.

## Demo
[Gold Demo](https://youtu.be/C1w4JDoufZg)

## Features

### 🎵 Enhanced Original Music
- Reworks the original music arrangements rather than replacing them with unrelated compositions.
- Preserves the original melodies, timing and musical structure wherever possible.
- Improves the square-wave instrument voicing to produce a fuller, more prominent sound.
- Retains the distinctive character of the original chiptune soundtrack.

### 🎹 Additional Harmony Layers
The mod generates additional musical parts based on the original song's note sequences:

- **Upper harmony:** Adds a voice one octave above the original lead melody.
- **Lower harmony:** Adds a voice one octave below the original lead melody.
- **Fifth harmony:** Adds an additional voice a perfect fifth above the melody in suitable, slower arrangements.
- **Bass reinforcement:** Creates a lower-register layer derived from the original bass or supporting instrument part.

These additional voices are mixed together with the original music to create a fuller, more harmonically layered sound.
Faster tracks automatically omit the fifth harmony to help keep busy arrangements clear.
The added harmonies are applied as a stero mix with 80%/60% stereo bleed

### 🧭 Guided Song Profiles
Harmony choices are guided per song by researched key, mode and texture (see `docs/song_research.md`).
Profiles only steer diatonic harmony pitches and voice density; the original melody, tempo and note data are never transposed.
Songs without reliable research fall back to the automatic key detection and default harmony rules.

### 🎚️ Independent Harmony Mixing
- Additional harmony audio is mixed independently of the original music.
- Adjustable harmony volume allows the extra voices to be balanced against the original soundtrack.
- Harmony playback follows the original music's playback state.
- The mixer supports stereo output and can use six-channel (5.1) audio output when supported by the system.
- Additional voices use the game's own chip synthesis engine.

### ⚙️ Native Audio Synthesis
- No external soundfonts required.
- No prerecorded music or instrument samples.
- No additional audio synthesis backend.
- Music continues to use the game's existing ChipAsm, ChipSynth and ChipAudio systems.

This keeps the enhanced soundtrack consistent with the game's original audio architecture.

### 💾 Music Preparation and Caching
- On first launch, choose whether to generate the enhanced music cache; choosing **NO** skips enhanced playback.
- Enhanced arrangements are generated and cached after choosing **YES**.
- The Options menu exposes the enhancement toggle, Music Test, and cache regeneration inside Audio options.
- Cached music can be regenerated through the mod options; regeneration removes only indexed generated files and known legacy song-cache filenames.

### 🎼 Music Testing
Includes a music testing/jukebox screen that allows available music tracks to be selected and played directly.

- Lists each unique song once, with its available source generations.
- **Left/Right** cycles the source **generation** of the selected song.
- **Select** toggles between **Improved** and **Stock** arrangements for that generation.
- **A** plays the selected arrangement; **B** exits.
- Control hints are shown at the bottom of the screen (including on Gen3).
- Toasts announce playback as `G<n> <Canonical Name> (Improved|Stock)`.

### 🔀 Cross-Version Sourcing
- Any Gen1 or Gen2 song can be sourced from another Gen1/Gen2 version (red, blue, yellow, gold, silver, crystal) for its improved arrangement.
- Shuffle modes: `shuffle_all`, `shuffle_improved`, `shuffle_stock`, `gen1`, `gen2`; each song change rolls a new source version.

### 🎮 Gen3 (FRLG) Support
- Gen3 audio is native-only (GBA) but can make use of Gen1/Gen2 chip arrangements.
- Chip audio plays at 45% volume on Gen3 to try and match the level of the native audio.
- Music test and the startup enhancement prompt use a Gen3 stack modal with hints.
- `G3 MIX` variants backport FRLG/LeafGreen song data to the expanded chip format; all M4A tracks become extra engines (no 4-channel limit).
- `SHUF MIX` plays only mixes; `SHUF ALL` adds them to normal shuffle. `G3 MIX SONGS` toggles individual songs via checkbox; toasts read `G3 <Name> (Mix)`.

### 💾 Cache Consolidation
- Base songs are cached per host version; improved variants are shared across hosts by source version.
- Cache files are content-addressed by hash, with a single `songs/index.txt` and `songs/aliases.lua`.
- Legacy per-game indexes are merged and pruned on load; identical translations are deduplicated.

## Compared to the Original Soundtrack

| Feature | Original Game Music | Music Improvement |
|---|---|---|
| Original melodies | Yes | Preserved |
| Original chip synthesis | Yes | Yes |
| Enhanced instrument voicing | Original | Improved |
| Upper harmony | No additional mod layer | Added |
| Lower harmony | No additional mod layer | Added |
| Fifth harmony | No additional mod layer | Added selectively |
| Additional bass layer | Original bass arrangement | Reinforced |
| Independent harmony volume | No mod control | Adjustable |
| Stereo harmony mixing | Original audio only | Additional stereo mix |
| Six-channel harmony output | Original audio only | Supported where available |

## Design Philosophy

The aim of Music Improvement is not to change what makes the original soundtrack memorable.

Instead, it builds upon the limitations and characteristics of classic Game Boy-style music, introducing additional musical depth without losing the recognisable melodies, rhythms and sound of the original compositions.

Think of it as an enhanced arrangement of the original soundtrack rather than a complete replacement.

**The original music, with more depth, more harmony and a fuller sound.**
