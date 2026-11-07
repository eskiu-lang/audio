<p align="center">
  <img src="https://raw.githubusercontent.com/eskiu-lang/eskiu/main/assets/logo.png" alt="Eskiu, a kitten with a ball of yarn" width="140">
</p>

<h2 align="center">audio</h2>
<p align="center">Sound for Eskiu: WAV files, a mixer and output through SDL3.</p>
<p align="center"><sub>Part of the <a href="https://github.com/eskiu-lang">Eskiu</a> project</sub></p>
<p align="center">
  <a href="https://eskiu-lang.org">eskiu-lang.org</a> &nbsp;&middot;&nbsp;
  <a href="#modules">Modules</a> &nbsp;&middot;&nbsp;
  <a href="CHANGELOG.md">Changelog</a> &nbsp;&middot;&nbsp;
  <a href="examples/">Examples</a> &nbsp;&middot;&nbsp;
  <a href="https://github.com/eskiu-lang/eskiu">The language</a>
</p>

<p align="center">
  <a href="https://github.com/eskiu-lang/audio/actions/workflows/ci.yml"><img src="https://github.com/eskiu-lang/audio/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/version-0.3.0-6448d4" alt="Version 0.3.0">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
</p>

---

`audio` plays sound from Eskiu programs: games, tools and apps. It reads WAV files in every
common encoding into float samples, mixes any number of them with volume, pan, pitch and
looping, and sends the mix to the default output device through SDL3.

- **WAV files.** 8, 16, 24 and 32-bit PCM, 32 and 64-bit float, IMA ADPCM and Microsoft
  ADPCM, mono to 5.1 and more, decoded exactly as ffmpeg decodes them; 16-bit or float
  output.
- **A mixer.** Voices with volume, pan, pitch (resampled with linear interpolation from any
  sample rate), loops and reverse, or streams that render themselves; buses, fades and
  crossfades; background music, fanfares and background sound as a game plays them. Its
  output depends only on the calls made to it, so it records offline exactly.
- **Output.** One call keeps the device fed from the mixer, from the program's main loop.
- **Pure Eskiu where it can be.** `<audio/wav>` and `<audio/mixer>` need nothing but the
  compiler; only `<audio/device>` links SDL3.

## Playing a sound

```eskiu
import <time>;
import <audio>;

Result<int, string> run() {
    Sound jump = wav_load("jump.wav")?;
    defer jump.free();
    AudioDevice out = audio_open(48000)?;
    defer out.close();
    Mixer mixer = mixer_new(out.rate);
    defer mixer.free();
    uint32 voice = mixer.play(&jump, AudioPlay{volume: 0.8, pan: -0.25});
    while (mixer.playing(voice)) {
        out.pump(&mixer, 50)?;      // keeps 50 ms of audio queued
        time_sleep_ms(10);
    }
    return Ok<int, string>(0);
}
```

`AudioPlay{}` plays at full volume, centered, once; `AudioPlay{loop: true, pitch: 1.5}` loops
it a fifth higher. A voice can change while it plays (`set_volume`,
`set_pan`, `set_pitch`), pause (`pause`, `resume`), move (`seek`, `position` in seconds) and
stop (`stop`, `stop_all`). `then` chains a sound after a voice's with no gap, for a song's intro
and its loop:

```eskiu
uint32 song = m.play(&intro, AudioPlay{});
m.then(song, &loop, true);    // the loop starts on the sample after the intro's last
```

[`examples/play.esk`](examples/play.esk) plays a WAV file or, given none, a chord it makes on
the spot.

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

## Platforms

| Modules | macOS, Linux, Windows | iOS, Android | WebAssembly |
|---|---|---|---|
| `<audio/wav>`, `<audio/mixer>` | yes | yes | yes |
| `<audio/device>` (and `<audio>`, which imports it) | SDL3 | yes, in an [eskiu-lang/ui](https://github.com/eskiu-lang/ui) app | not yet |

On a phone `<audio/device>` needs no SDL3: its native code (`native/`), which a ui app builds
in, plays through a RemoteIO audio unit on iOS and AAudio on Android (Android 8 or later,
loaded at run time). The calls are the same everywhere. `audio_open_with(rate, options)`
says how the output shares the device:

```eskiu
AudioDevice out = audio_open_with(48000, AudioOptions{mix_with_others: true, game: true})?;
```

| `AudioOptions` | Means |
|---|---|
| `mix_with_others` | other apps' sound goes on (iOS; on Android media always mixes) |
| `ignore_silent` | it plays with the iPhone's ringer switch on silent (otherwise the switch mutes it) |
| `game` | the stream is a game's (Android's usage and content type) |
| `buffer_ms` | the most that can be queued ahead on a phone (default 500) |

In a ui app, mix ahead once per display frame and pause in the background:

```eskiu
use_frame(playing.get(), void(Tick tick) { (void)out.pump(&mixer, 100); });
use_app_state(void(bool active) { if (active) { out.resume(); } else { out.pause(); } });
```

[`examples/ui`](examples/ui) plays a tone that way (`ui run ios`, or `android`). An Android
stream whose output goes away (headphones unplugged) opens again on the new one.

## Install

The output module needs SDL3 (`brew install sdl3` on macOS, the SDL3 development package of
your Linux distribution or a build from source, the `SDL3-devel-*-mingw` archive on Windows).
Then, in an Eskiu package (Eskiu 0.12 or newer):

```bash
eskiuc add audio --git https://github.com/eskiu-lang/audio --rev v0.3.0
eskiuc build -L/opt/homebrew/lib       # the directory that holds libSDL3
```

## Modules

| Module | What it has |
|---|---|
| `<audio>` | the modules below |
| `<audio/wav>` | `Sound`, `wav_load`, `wav_decode`, `wav_save`, `sound_new` |
| `<audio/decode>` | `sound_load`: WAV everywhere; MP3, AAC / M4A and FLAC (and Ogg Vorbis, Opus on Android) through the system's codecs on iOS and Android |
| `<audio/mixer>` | `Mixer`, `mixer_new`, `play`, `play_source`, `then`, `stop`, `pause`, `resume`, `seek`, `position`, `current`, `set_volume`, `set_pan`, `set_pitch`, `render`, `AudioPlay`, `AudioSource`; buses (`add_bus`, `set_bus`, `set_bus_volume`, `fade_bus`, `bus_volume`); fades (`fade`, `fade_in`, `fade_out`, `crossfade`, `fade_level`); roles (`use_bgm`, `stop_bgm`, `use_me`, `use_bgs`, `stop_bgs`, `bgm`, `me`, `bgs`); `set_mono`, `set_manual_clock`, `advance` |
| `<audio/device>` | `AudioDevice`, `audio_open`, `audio_open_with`, `AudioOptions`, `write`, `queued`, `pump`, `pause`, `resume`, `clear` (SDL3 on the desktop) |

In a ui app, a sound in the app's `assets/` loads by the path ui's `ui_asset_path` gives (in
the bundle on iOS, copied out of the APK on Android), and a remote one by the path of
`use_cached_file` or `ui_cached_file` once it is downloaded:

```eskiu
string path = ui_asset_path("music/battle.m4a");
Sound battle = sound_load(path)?;
free(path);
```

## Contributing

Bug reports are welcome; please include the program and the `eskiuc --version` output. The
tests run with `eskiuc test -L/opt/homebrew/lib`; the device test uses SDL's silent dummy
driver, so it needs no sound card. `tools/gen_test_audio.sh` regenerates the WAV files in
`tests/data` and ffmpeg's decoding of each, which the tests compare against.

## License

MIT. See [LICENSE](LICENSE).
