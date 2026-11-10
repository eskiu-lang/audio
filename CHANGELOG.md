# Changelog

All notable changes to this package are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [0.4.0] - 2026-11-10

### Added

- `<audio/ogg>`: an Ogg Vorbis decoder written in Eskiu (after stb_vorbis), so it needs no
  library and runs on macOS, Linux, Windows, iOS, Android and WebAssembly alike.
  `ogg_load` and `ogg_decode` decode a whole file; `OggVorbis` (`ogg_open`,
  `ogg_open_memory`, `read`, `seek`, `tell`) decodes it a block at a time; `OggStream`
  (`ogg_stream`, `ogg_stream_from`) is an `AudioSource` that plays one through the mixer at
  the mixer's rate, looping or not, with `seek` and `position`. Seeking is exact to the frame.
  Against libvorbisfile it gives the same frame counts and samples within 2^-20.
- Loop points: a file's `LOOPSTART` and `LOOPLENGTH` (or `LOOPEND`) comments, in frames.
  `Sound.loop_start` and `Sound.loop_end` hold them, and a looping voice plays the sound
  once to its loop end and then from its loop start to its loop end; a looping `OggStream`
  does the same.
- `sound_decode`, which decodes WAV or Ogg Vorbis bytes held in memory, known by their first
  bytes.
- `tools/vorbis_ref.py`, which writes libvorbisfile's decoding of a file for the tests.

### Changed

- `sound_load` reads `.ogg` files with `<audio/ogg>` on every platform (on Android they went
  through the system's codecs before).

## [0.3.0] - 2026-11-07

### Added

- `AudioSource`, an interface for streams that render themselves (a sequencer, a decoder), and
  `Mixer_play_source` to play one as a voice. An SDAT sequence from the `nds` package plugs in
  through a small adapter struct in the program (README, "Streams"); `audio` does not depend
  on `nds`.
- Buses: `AUDIO_BUS_MASTER` with `AUDIO_BUS_MUSIC` and `AUDIO_BUS_SFX` inside it,
  `Mixer_add_bus`, `Mixer_set_bus`, `Mixer_set_bus_volume`, `Mixer_fade_bus`,
  `Mixer_bus_volume`, and `AudioPlay.bus`.
- Fades, linear in gain over a time in milliseconds: `Mixer_fade`, `Mixer_fade_in`,
  `Mixer_fade_out`, `Mixer_crossfade`, `Mixer_fade_level`.
- Roles: `Mixer_use_bgm` (crossfades from the previous music), `Mixer_stop_bgm`,
  `Mixer_use_me` (a fanfare that pauses the music and resumes it on the frame after it ends),
  `Mixer_use_bgs`, `Mixer_stop_bgs`, and `Mixer_bgm`, `Mixer_me`, `Mixer_bgs`.
- `AudioPlay.reverse` plays a sound backwards; `AudioPlay.balance` pans as a stereo balance.
- `Mixer_set_mono`, a mono downmix of the output.
- `Mixer_set_manual_clock` and `Mixer_advance`, to run the timers on a video clock when
  recording offline.
- The guarantee, documented and tested, that the mix depends only on the calls made and the
  frame counts rendered: the same calls give the same bytes, in blocks of any size.

### Changed

- Voices are mixed in the order they started (a voice that ends no longer reorders the
  others), so the output does not depend on how a render is split.
- The WAV writer's private helpers are renamed so a program can import `audio` and `nds`
  together.
