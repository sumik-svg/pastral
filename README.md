# pastoral

by [sumik-svg](https://github.com/sumik-svg)

A semi-automatic generative pastoral piece for [monome norns](https://monome.org/docs/norns/).

A plucked voice (tone1), a church bell (tone2), a fiddle with layered harmonies, wind, and a granular cloud that keeps resampling the last 2.5 seconds of the piece itself. It loads stopped; start it, and it plays on its own — you steer it with three encoders, a few key gestures, and the parameters.

The script folder is named **pastral** (see Installation).

## Voices

- **tone1** — a pluck synth, or your own `.wav` samples: one selected file, or a random pick per note from a sample pool. Random octave jumps can be dialled in.
- **tone2** — a church bell with bright, sparkling partials, tolling on a slow cycle.
- **fiddle** — a bowed string voice that enters on its own and gathers up to five harmony layers around itself.
- **wind** — filtered noise underneath everything; it also breathes into how often tone1 speaks.
- **granular cloud** — the dry + reverb signal is recorded into a 2.5 s circular buffer and re-scattered as grains (forward, reversed, octave and fifth rates), with overlap compensation so the cloud never clips.

The screen draws what the piece is doing: a shoreline sand pattern that moves with the tone value, wind streamlines, the fiddle's strings of light, ripples for each attack, and the granular mosaic.

## Requirements

- monome norns (developed and tested on a norns shield)
- After installing or updating, run `;restart` in maiden once, so the SuperCollider engine builds.

## Installation

In maiden's command line (the `>>` prompt at the bottom of the maiden web interface), run:

```
;install https://github.com/sumik-svg/pastral
```

Then run `;restart` once, so the SuperCollider engine builds.

Manual install: download this repository and put its contents in `~/dust/code/` in a folder named exactly **`pastral`**, so the layout is:

```
~/dust/code/pastral/pastral.lua
~/dust/code/pastral/lib/Engine_Pastoral.sc
~/dust/code/pastral/audio/...
```

The folder name matters: the script looks for its samples in `pastral/audio/`.

## Controls

This script uses **K1 as a hold modifier**:

| Input | Action |
|---|---|
| K1 + K2 | play / stop (the script loads stopped) |
| K1 + K3 | toggle rhythmic mode (tone1 locks to a pulse) |
| K1 + E2 | grain size |
| K1 + E3 | grain mix |
| K2 | join the fiddle harmony |
| K3 | strike the bell |
| E1 | tone (master brightness, 150 Hz – 16.5 kHz) |
| E2 | wind amount |
| E3 | shimmer |

While stopped, the generative voices stay silent but K2 / K3 one-shots still sound, so you can test the bell and the strings.

## Parameters

- **PASTORAL LEVELS** — T1 vol, T2 vol, T2 bright, Wind vol.
- **T1** — T1 source (`synth` / `sample` / `sample rnd`), T1 sample (file), T1 base note, T1 oct rnd + T1 oct mode (random octave jumps: +1, +1/+2, −1/+1), T1 rec (record the audio input — see Samples).
- **T1 POOL** — one on/off toggle per sample file, used by `sample rnd`.
- **LFO** — slowly wobbles tone and wind around their knob values (on by default); rate and per-target depths. The background animation follows the LFO too.
- **RHYTHM** — T2 rate (how often the bell tolls).
- **MUSIC** — Mode, Scale, Root, Turing mut, Reseed (see below).

## Modes and scales

The note tables are built from **Root** (MIDI note 36–72, default D3) and **Scale** — the fiddle, the harmonies and the bell all follow automatically.

Scales: dorian (default), major, minor, major pentatonic, minor pentatonic, lydian, mixolydian, hirajoshi, whole tone.

**Mode** chooses how tone1 picks its next note:

- **meadow** — free random choice from the scale. The original behaviour.
- **walk** — drifts up and down the scale from the previous note, with occasional leaps. Points become a line.
- **turing** — a 12-note loop (after the Turing Machine idea) that repeats while mutating: each step, as the loop passes it, has a **Turing mut** % chance of being replaced. At 0% the loop is exact; small values give you "the same, but slowly different".
- **motif** — a short generated phrase, repeated through a series of transpositions, with an occasional variation of its last note.

**Reseed** re-rolls the walk's starting point, the turing loop and the motif.

With the defaults (mode = meadow, scale = dorian, root = D3) the generated tables are exactly the original fixed ones — the classic sound of this script is preserved note for note. Everything else is variation on top of it: mode × scale × root × samples.

## Samples

Eleven samples are bundled in `audio/` (guitar, cello pizzicato, flute, piano, pipe organ, glockenspiel, harp, tubular bells, wine glass, psaltery, harmonium). Sources and licences are listed in [audio/README.txt](audio/README.txt) — most are CC0 or freely published; the harmonium is CC BY 3.0.

Your own samples:

1. Drop `.wav` files into `audio/` and reopen the script (the list is built at startup).
2. If the filename ends with a note tag (e.g. `mybell_E4.wav`), selecting it sets **T1 base note** automatically. Playback rate follows the melody from that reference pitch.
3. In `sample rnd` mode, switch files in or out of the pool under **T1 POOL**. Every note is an independent synth and always rings out to its full release — the next note never cuts the previous one.

Recording your own, live:

1. Set **T1 base note** to the pitch you are about to play.
2. Set **T1 rec** to `REC`, play a single note, then set it back to `ready`. (It stops on its own at ~11.5 s.)
3. The take is saved as `audio/rec_<nn>_<Note>.wav`, selected automatically, and joins the pool.

## Notes

- The sample list is built when the script loads — reopen the script after adding files.
- Saved parameter sets from earlier versions keep working: parameter ids have not changed since v15.0 (display names were shortened in v15.8).
- The engine logs sample loads and recording start/stop (frames, path) to maiden's sc console, which helps if a file fails to load.

## Changelog

- **v15.15** — MUSIC section: selectable note-choice modes (meadow / walk / turing / motif), 9 scales and a root note; note tables are now generated from root + scale (defaults reproduce the original tables exactly). Reseed trigger.
- **v15.14** — hardening: the tone1 sample path can no longer silence tone1 (errors fall back to the synth pluck); pool membership cached instead of looked up per note.
- **v15.13** — T1 rec reworked into a visible ready/REC control with double-toggle protection; sample-list rebuild after recording fixed; pool settings tied to filenames; engine load/rec diagnostics.
- **v15.12** — fixed the wind continuing after switching scripts (engine `free` now frees the persistent synths); `sample rnd` mode with a 64-slot buffer pool (notes always ring out fully); random octave option for tone1.
- **v15.11** — five more bundled samples: harp, tubular bells, wine glass, psaltery, harmonium.
- **v15.10** — bundled pipe organ and glockenspiel samples.
- **v15.9** — background redesigned as a shoreline / wet-sand pattern.
- **v15.8** — shorter parameter display names; brighter, clearer bell.
- **v15.7** — background animation follows the LFO; much wider E1 tone range; wind follows tone.
- **v15.6** — fixed the engine failing to load since v15.3 (a stereo SynthDef build error).
- **v15.5** — more bundled samples; filename note tags set the base note; audio-input recording.
- **v15.4** — first bundled sample (classical guitar B3).
- **v15.3** — loads stopped, K1+K2 play/stop; tone1 / tone2 naming; tone1 sample playback.
- **v15.2** — LFO for tone and wind (params, on by default); wider granular range.
- **v15.1** — granular overlap compensation in the engine; bell brightness wired through.
- **v15.0** — the original release.

## About

pastoral was written by [sumik-svg](https://github.com/sumik-svg). The 15.x series adds fixes and extensions on top of the original release: sample playback and recording, a sample pool, generative modes and scales, and a long list of refinements, all tested on hardware.

## License

MIT — see [LICENSE](LICENSE). The bundled samples keep their own licences, listed in [audio/README.txt](audio/README.txt).
