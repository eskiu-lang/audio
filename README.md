<p align="center">
  <img src="https://raw.githubusercontent.com/eskiu-lang/eskiu/main/assets/logo.png" alt="Eskiu, a kitten with a ball of yarn" width="140">
</p>

<h2 align="center">audio</h2>
<p align="center">Sound for Eskiu: WAV files, a mixer and output through SDL3.</p>
<p align="center"><sub>Part of the <a href="https://github.com/eskiu-lang">Eskiu</a> project</sub></p>
<p align="center">
  <a href="https://eskiu-lang.org">eskiu-lang.org</a> &nbsp;&middot;&nbsp;
  <a href="#modules">Modules</a> &nbsp;&middot;&nbsp;
  <a href="examples/">Examples</a> &nbsp;&middot;&nbsp;
  <a href="https://github.com/eskiu-lang/eskiu">The language</a>
</p>

<p align="center">
  <a href="https://github.com/eskiu-lang/audio/actions/workflows/ci.yml"><img src="https://github.com/eskiu-lang/audio/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/version-0.2.0-6448d4" alt="Version 0.2.0">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
</p>

---

`audio` plays sound from Eskiu programs: games, tools and apps. It reads WAV files in every
common encoding into float samples, mixes any number of them with volume, pan, pitch and
looping, and sends the mix to the default output device through SDL3.

- **WAV files.** 8, 16, 24 and 32-bit PCM, 32 and 64-bit float, IMA ADPCM and Microsoft
  ADPCM, mono to 5.1 and more, decoded exactly as ffmpeg decodes them; 16-bit or float
  output.
- **A mixer.** Voices with volume, equal-power pan, pitch (resampled with linear
  interpolation from any sample rate) and loops, rendered into a stereo float stream.
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
eskiuc add audio --git https://github.com/eskiu-lang/audio --rev v0.2.0
eskiuc build -L/opt/homebrew/lib       # the directory that holds libSDL3
```

## Modules

| Module | What it has |
|---|---|
| `<audio>` | the modules below |
| `<audio/wav>` | `Sound`, `wav_load`, `wav_decode`, `wav_save`, `sound_new` |
| `<audio/decode>` | `sound_load`: WAV everywhere; MP3, AAC / M4A and FLAC (and Ogg Vorbis, Opus on Android) through the system's codecs on iOS and Android |
| `<audio/mixer>` | `Mixer`, `mixer_new`, `play`, `then`, `stop`, `pause`, `resume`, `seek`, `position`, `current`, `set_volume`, `set_pan`, `set_pitch`, `render`, `AudioPlay` |
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
