# Guide

Using `<audio>` past the first sound in the [README](../README.md). Every function and type is in the [API reference](api.md).

## Music, fanfares and effects

Every voice plays on a bus. The mixer starts with `AUDIO_BUS_MASTER` and, inside it,
`AUDIO_BUS_MUSIC` and `AUDIO_BUS_SFX`; `add_bus(parent)` adds more. A voice's gain is its
volume, times its fade, times the volume of its bus and of every bus that holds it, so the
settings menu's three sliders are three calls:

```eskiu
m.set_bus_volume(AUDIO_BUS_MASTER, 0.8);
m.set_bus_volume(AUDIO_BUS_MUSIC, 0.6);
m.set_bus_volume(AUDIO_BUS_SFX, 1.0);
```

Fades move a gain in a straight line over a time in milliseconds: `fade_in(id, ms)`,
`fade_out(id, ms)` (which stops the voice at silence), `fade(id, gain, ms)`,
`crossfade(from, to, ms)` (the two gains add up to 1 all the way) and `fade_bus(bus, volume, ms)`.

Three roles take a voice that is already playing and give it a game's behavior:

```eskiu
AudioPlay music = AudioPlay{loop: true, balance: true, bus: AUDIO_BUS_MUSIC};
m.use_bgm(m.play(&town, music), 0);          // background music
m.use_bgm(m.play(&battle, music), 500);      // crossfades from the town theme over 500 ms
m.use_me(m.play(&victory, AudioPlay{balance: true, bus: AUDIO_BUS_MUSIC}));
                                             // the fanfare pauses the battle music, which
                                             // resumes on the frame after the fanfare ends
m.use_bgs(m.play(&rain, AudioPlay{loop: true, bus: AUDIO_BUS_SFX, volume: 0.4}));
m.stop_bgm(1000);                            // fades out over a second
```

`bgm()`, `me()` and `bgs()` say which voice has each role (0 for none). A cry plays at a speed
and backwards with `AudioPlay{pitch: 1.3, reverse: true}` (pitch is the speed, as on a tape),
and `set_mono(true)` sends the average of both channels to both sides.

`AudioPlay{balance: true}` pans as a stereo balance: centered, both channels play at full
volume. Without it pan is equal power, which suits a mono sound but plays a centered stereo
sound 3 dB lower.

## Streams

A voice can play anything that renders itself, through the `AudioSource` interface:

```eskiu
interface AudioSource {
    int64 render(*float out, int64 frames);   // stereo, interleaved, at the mixer's rate
    bool done();
}
```

`m.play_source(&src, AudioPlay{...})` plays one with the voice calls (volume, pan as a balance,
pause, stop, fades, buses and roles). The mixer asks it for 512 frames at a time and stops the
voice once `done()` is true and those frames are played; a short block from a source that is
not done plays silence for the rest. The source must live while it plays.

`audio` does not depend on the [`nds`](https://github.com/eskiu-lang/nds) package; a program
that uses both plugs an SDAT sequence in with a struct of its own:

```eskiu
import <nds/sdat>;
import <audio/mixer>;

struct SeqSource {
    SdatPlayer player;
    int64 render(*float out, int64 frames) { return self.player.render_f32(out, frames); }
    bool done() { return self.player.is_done(); }
}

Mixer m = mixer_new(SDAT_RATE);              // the sequencer renders at 48 kHz
SeqSource seq = SeqSource{player: SdatPlayer_open(&sdat, 0, true)?};
m.use_bgm(m.play_source(&seq, AudioPlay{bus: AUDIO_BUS_MUSIC}), 500);
```

The same struct shape adapts a decoder or a synthesizer.

## Recording: offline mixing

The mixer never reads a clock. What it renders depends only on the calls made to it and the
frame counts asked for: the same calls give the same bytes on every run, and a render of 4096
frames gives the same samples as the same frames rendered 1 or 7 at a time (the tests check
both). So a game can record a video's soundtrack with no device, frame by frame, and write it
with `wav_save`.

By default the timers (fades, the end of a fanfare) run on the rendered frames, sample by
sample. A recorder that steps a video clock can run them on that clock instead:

```eskiu
m.set_manual_clock(true);
for (f in 0..frames) {
    game_step(1.0 / 60.0);       // the game makes its audio calls
    m.advance(1.0 / 60.0);       // fades move, a fanfare that ended resumes the music
    m.render(&pcm[f * 1600], 800);
}
```

With the manual clock a render mixes at the gains the last `advance` left, and the music after
a fanfare resumes at the next `advance`, as Tallgrass's `OfflineAudio` does.
