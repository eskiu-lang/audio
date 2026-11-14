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

## Ogg Vorbis files

`<audio/ogg>` decodes Ogg Vorbis in Eskiu, with no library, on every platform the package
builds for (WebAssembly included). A short sound decodes whole into a `Sound`; music streams,
a block at a time as the mixer asks for it:

```eskiu
Sound jump = ogg_load("se/jump.ogg")?;            // or sound_load, which goes by the name
defer jump.free();
m.play(&jump, AudioPlay{bus: AUDIO_BUS_SFX});

OggStream town = ogg_stream("bgm/town.ogg", m.rate, true)?;   // at the mixer's rate, looping
defer town.free();
m.use_bgm(m.play_source(&town, AudioPlay{bus: AUDIO_BUS_MUSIC}), 500);
```

A file in memory (from an archive or a download) opens with `ogg_decode(bytes, len)` or
`ogg_open_memory(bytes, len)`; `sound_decode(bytes, len)` takes WAV or Ogg Vorbis bytes and
tells them apart by their first bytes.

**Loop points.** A file's `LOOPSTART` and `LOOPLENGTH` comments (or `LOOPSTART` and
`LOOPEND`), in frames, are its loop points (the convention RPG Maker started). A looping stream plays the file once to the loop end, then from the loop start to
the loop end again and again; without loop points it loops the whole file. `ogg_load` copies
them to the `Sound`'s `loop_start` and `loop_end`, and a looping voice of that sound wraps the
same way. A `Sound` from anywhere else can be given loop points by setting those two fields.

**Seeking.** `OggStream.seek(seconds)` and `OggVorbis.seek(frame)` land on the exact frame:
the frames read after a seek are the ones a decode from the start gives there, and a seek
decodes at most two packets. `position()` says where a stream is, in seconds of the file.

**Rates and channels.** A stream renders at the rate it was opened with, resampling the file
with linear interpolation as a voice does; at the file's own rate its frames pass through
unchanged. A mono file plays on both sides, and a file with more than two channels plays its
first two.

**Accuracy.** The decoder follows the Vorbis I specification and stb_vorbis. Against
libvorbisfile, the reference decoder, it gives the same number of frames (the encoder's
padding cut from the start and the end) and samples within 2^-20 (`tests/ogg.esk` checks
files from libvorbis and from ffmpeg's encoder). It reads every Vorbis I stream with floor 1,
which is what encoders write; the obsolete floor 0 is refused. Decoding reads no clock and
calls no system codec, so a file gives the same samples on every run.

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

The same struct shape adapts a decoder or a synthesizer; `OggStream` is one already.

## Sound in space

A voice can sit at a point around a listener (ViroReact's `ViroSpatialSound`) or be a
first-order ambisonic recording around it (`ViroSoundField`). The listener is the camera:
set it each frame from the camera's position and rotation.

```eskiu
uint32 bird = m.play_at(&chirp, AudioPlay{loop: true}, AudioVec3{2.0, 1.0, -3.0});
m.set_rolloff(bird, AUDIO_ROLLOFF_LOGARITHMIC, 1.0, 20.0);
uint32 forest = m.play_field(&ambix, AudioPlay{loop: true}, AudioQuat{0.0, 0.0, 0.0, 1.0});
...each frame:
m.set_listener_pose(AudioVec3{cam.x, cam.y, cam.z}, AudioQuat{q.x, q.y, q.z, q.w});
m.set_position(bird, AudioVec3{x, y, z});
```

The axes are ViroReact's: x right, y up, and the listener looks along -z before its
rotation. `Mixer_set_listener` takes a forward and an up direction instead of a rotation.

A positioned sound's channels are mixed to one, panned with equal power by how far to the
listener's right or left it is, and faded by its rolloff model, with the curves of Resonance
Audio (the engine ViroReact plays spatial sound through):

| Model | Gain at distance d |
|---|---|
| `AUDIO_ROLLOFF_NONE` (default) | 1 |
| `AUDIO_ROLLOFF_LINEAR` | (max - d) / (max - min) |
| `AUDIO_ROLLOFF_LOGARITHMIC` | 1 / (d - min + 1), shifted down so it reaches 0 at max |

A distance under min (and under 1, whatever min is) plays at full volume, and past max the
sound is silent. `audio_rolloff_gain` returns the curve's value.

A sound field has four channels in AmbiX order (W, Y, Z, X: y to the left, z up, x ahead).
The mixer decodes it to two cardioid microphones pointing to the listener's ears, so it
turns as the listener turns; `Mixer_set_field_rotation` turns the field itself.

ViroReact renders spatial sound binaurally (head-related filters for headphones, height and
front or back) and can add room reverb. This mixer pans in stereo, so a sound ahead and one
behind sound alike, and has no rooms.

## Recording: offline mixing

The mixer never reads a clock. What it renders depends only on the calls made to it and the
frame counts asked for: the same calls give the same bytes on every run, and a render of 4096
frames gives the same samples as the same frames rendered 1 or 7 at a time (the tests check
both). So a game can record a video's soundtrack with no device, frame by frame, and write it
with `wav_save`. An `OggStream` keeps the guarantee: it decodes the same frames for the same
calls.

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
