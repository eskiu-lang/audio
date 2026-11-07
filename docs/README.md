# audio documentation

Guides and reference for audio. The [README](../README.md) has the overview.

<!-- pages -->
- [Guide](guide.md)
- [API reference](api.md): every public function and type
<!-- /pages -->

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

[`examples/ui`](../examples/ui) plays a tone that way (`ui run ios`, or `android`). An Android
stream whose output goes away (headphones unplugged) opens again on the new one.

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
