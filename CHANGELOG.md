# Changelog

All notable changes to this package are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
