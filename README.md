<p align="center">
  <img src="https://raw.githubusercontent.com/eskiu-lang/eskiu/main/assets/logo.png" alt="Eskiu, a kitten with a ball of yarn" width="140">
</p>

<h2 align="center">audio</h2>
<p align="center">Sound for Eskiu: WAV and Ogg Vorbis files, a mixer and output through SDL3.</p>
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
  <img src="https://img.shields.io/badge/version-0.4.0-6448d4" alt="Version 0.4.0">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
</p>

---

`audio` plays sound from Eskiu programs: games, tools and apps. It reads WAV files in every
common encoding and Ogg Vorbis files into float samples, mixes any number of them with
volume, pan, pitch and looping, and sends the mix to the default output device through SDL3.

- **WAV files.** 8, 16, 24 and 32-bit PCM, 32 and 64-bit float, IMA ADPCM and Microsoft
  ADPCM, mono to 5.1 and more, decoded exactly as ffmpeg decodes them; 16-bit or float
  output.
- **Ogg Vorbis files.** Decoded whole, or streamed a block at a time for music, on every
  platform with no library; loop points from the file's `LOOPSTART` and `LOOPLENGTH`
  comments, and seeking exact to the frame. The same frame count as libvorbisfile and
  samples within 2^-20 of it.
- **A mixer.** Voices with volume, pan, pitch (resampled with linear interpolation from any
  sample rate), loops and reverse, or streams that render themselves; buses, fades and
  crossfades; background music, fanfares and background sound as a game plays them. Its
  output depends only on the calls made to it, so it records offline exactly.
- **Output.** One call keeps the device fed from the mixer, from the program's main loop.
- **Pure Eskiu where it can be.** `<audio/wav>`, `<audio/ogg>` and `<audio/mixer>` need
  nothing but the compiler; only `<audio/device>` links SDL3.

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

[`examples/play.esk`](examples/play.esk) plays a WAV or Ogg Vorbis file or, given none, a chord
it makes on the spot.

## Documentation

- [Music, fanfares and effects](docs/guide.md#music-fanfares-and-effects)
- [Ogg Vorbis files](docs/guide.md#ogg-vorbis-files)
- [Streams](docs/guide.md#streams)
- [Recording: offline mixing](docs/guide.md#recording-offline-mixing)
- [Platforms](docs/README.md#platforms)
- [Modules](docs/README.md#modules)
- [Contributing](docs/README.md#contributing)
- [API reference](docs/api.md): every public function and type

## Install

The output module needs SDL3 (`brew install sdl3` on macOS, the SDL3 development package of
your Linux distribution or a build from source, the `SDL3-devel-*-mingw` archive on Windows).
Then, in an Eskiu package (Eskiu 0.12 or newer):

```bash
eskiuc add audio --git https://github.com/eskiu-lang/audio --rev v0.4.0
eskiuc build -L/opt/homebrew/lib       # the directory that holds libSDL3
```

## License

MIT. See [LICENSE](LICENSE). The Ogg Vorbis decoder (`src/ogg.esk`) is a port of
[stb_vorbis](https://github.com/nothings/stb) by Sean Barrett and the stb_vorbis
contributors, which is in the public domain or under the MIT license, at your choice.
