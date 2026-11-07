# G1R Music Improvement

AI Usage Disclosure. I am not a LUA dev and OpenCode was used to develop this addon.

## Overview

Music Improvement enhances the game's original Game Boy-style chiptune soundtrack, transforming the familiar melodies into fuller, richer arrangements while preserving the original musical identity.

Rather than replacing the original sound system with external instruments or prerecorded audio, the mod builds upon the game's existing chip-music synthesis engine. Original music is analysed, enhanced and reassembled into improved arrangements, with additional harmony layers generated dynamically from the original musical parts.

The result is a more immersive and layered soundtrack that retains the character of classic Game Boy music.
There are no large files to download as we generate and cache the additional channels on startup.

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
- Enhanced arrangements are generated and cached.
- Cached music can be regenerated through the mod options.

### 🎼 Music Testing
Includes a music testing/jukebox screen that allows available music tracks to be selected and played directly.

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
