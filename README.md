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
  <img src="https://img.shields.io/badge/version-0.1.0-6448d4" alt="Version 0.1.0">
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
`set_pan`, `set_pitch`) and stop (`stop`, `stop_all`). [`examples/play.esk`](examples/play.esk)
plays a WAV file or, given none, a chord it makes on the spot.

## Platforms

| Modules | macOS, Linux, Windows | iOS, Android, WebAssembly |
|---|---|---|
| `<audio/wav>`, `<audio/mixer>` | yes | yes |
| `<audio/device>` (and `<audio>`, which imports it) | yes | not yet |

`<audio/wav>` and `<audio/mixer>` are plain Eskiu and work on every target. Building
`<audio/device>` for a phone or for WebAssembly stops with an `#error`: SDL3 runs there, but
it is not checked yet.

## Install

The output module needs SDL3 (`brew install sdl3` on macOS, the SDL3 development package of
your Linux distribution or a build from source, the `SDL3-devel-*-mingw` archive on Windows).
Then, in an Eskiu package (Eskiu 0.12 or newer):

```bash
eskiuc add audio --git https://github.com/eskiu-lang/audio --rev v0.1.0
eskiuc build -L/opt/homebrew/lib       # the directory that holds libSDL3
```

## Modules

| Module | What it has |
|---|---|
| `<audio>` | the three modules below |
| `<audio/wav>` | `Sound`, `wav_load`, `wav_decode`, `wav_save`, `sound_new` |
| `<audio/mixer>` | `Mixer`, `mixer_new`, `play`, `stop`, `set_volume`, `set_pan`, `set_pitch`, `render`, `AudioPlay` |
| `<audio/device>` | `AudioDevice`, `audio_open`, `write`, `queued`, `pump`, `pause`, `resume`, `clear` (links SDL3) |

## Contributing

Bug reports are welcome; please include the program and the `eskiuc --version` output. The
tests run with `eskiuc test -L/opt/homebrew/lib`; the device test uses SDL's silent dummy
driver, so it needs no sound card. `tools/gen_test_audio.sh` regenerates the WAV files in
`tests/data` and ffmpeg's decoding of each, which the tests compare against.

## License

MIT. See [LICENSE](LICENSE).
