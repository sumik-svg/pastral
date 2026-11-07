Samples for tone1 live in this folder.

How to use your own samples:
1. Copy .wav files into this folder
2. Reopen the script on norns (the list is built at startup)
3. On the params screen, choose the file under "T1 sample"
4. Set "T1 source" to "sample"
5. Set "T1 base note" to the pitch the sample was recorded at
   (playback rate follows the melody from that reference)

The trailing note tag in a filename (e.g. "_D4") is the base
note tag: selecting the file sets the base note automatically.
Name your own files the same way (e.g. "mybell_E4.wav") and
they line up on their own. Mono and stereo both work.

Bundled samples:

University of Iowa Electronic Music Studios, "Musical
Instrument Samples" (freely published, no restrictions);
single notes sliced from their chromatic recordings and
pitch-verified:
- guitar_B3.wav - classical guitar, open B string (B3).
  Performer: Brian Penkrot; instrument: Raimundo 118
- cello_pizz_A3.wav - cello pizzicato (A3)
- flute_D4.wav - flute, non-vibrato (D4)
- piano_D4.wav - Steinway Model B (D4)

VSCO-2-CE by Versilian Studios (CC0):
- organ_C4.wav - pipe organ, quiet manual (C4)
- glock_G5.wav - glockenspiel. The source file is notated G4,
  but a glockenspiel sounds two octaves up, so the tag uses
  the sounding pitch G5
- harp_A4.wav - concert harp (A4)

VCSL by Versilian Studios (CC0):
- chimes_D4.wav - tubular bells (D4)
- wineglass_D#5.wav - rubbed wine glass, sustained. The
  source file is named D#4, but the measured fundamental is
  about 630 Hz (D#5), so the tag uses the sounding pitch
- psaltery_D4.wav - plucked psaltery (D4), a zither-family
  relative of the hammered dulcimer

tonejs-instruments (samples from public-domain sources,
CC BY 3.0):
- harmonium_C4.wav - harmonium (C4)

"sample rnd" mode (params: T1 source):
Each tone1 note picks one sample at random from the files
switched on under "T1 POOL" (one toggle per file, all on by
default). Pool settings are tied to filenames, so they never
shift onto other files when recordings are added. Each note
is an independent synth: a note always rings out to its full
release, the next note never cuts it off.

Recording (params: T1 rec):
"T1 rec" is a ready / REC toggle. Set it to REC to start
recording the audio input; set it back to ready to stop.
The take is saved into this folder as rec_<nn>_<Note>.wav,
selected automatically, and joins the rnd pool. Recording
stops on its own at about 11.5 seconds and the display
returns to ready. Set "T1 base note" to the pitch you are
going to record BEFORE recording - that pitch becomes the
take's note tag and playback reference. The feature is made
for a single note; whatever you play is treated as one
one-shot sample.
