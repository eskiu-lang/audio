#!/bin/sh
# Writes the WAV test files in tests/data with ffmpeg, and next to each one
# ffmpeg's own decoding of it as raw float32 (NAME.f32), the expected values.
set -e
cd "$(dirname "$0")/../tests/data"
src="-f lavfi -i sine=frequency=440:sample_rate=22050:duration=0.05"
stereo="-f lavfi -i aevalsrc=0.6*sin(2*PI*440*t)|0.4*sin(2*PI*660*t):s=22050:d=0.05"
gen() { name=$1; shift; ffmpeg -loglevel error -y "$@" "$name.wav"; ffmpeg -loglevel error -y -i "$name.wav" -f f32le -acodec pcm_f32le "$name.f32"; }
gen u8 $src -c:a pcm_u8
gen s16 $stereo -c:a pcm_s16le
gen s24 $stereo -c:a pcm_s24le
gen s32 $src -c:a pcm_s32le
gen f32 $stereo -c:a pcm_f32le
gen f64 $src -c:a pcm_f64le
gen ima $stereo -c:a adpcm_ima_wav
gen ima_mono $src -c:a adpcm_ima_wav
gen ms $stereo -c:a adpcm_ms
gen ms_mono $src -c:a adpcm_ms
gen ext6 -f lavfi -i "aevalsrc=sin(2*PI*220*t)|0.5*sin(2*PI*330*t)|0.2|-0.2|0.1*t|0:s=22050:d=0.02" -c:a pcm_s16le -channel_layout 5.1
