#!/bin/sh
# Writes the WAV and Ogg Vorbis test files in tests/data with ffmpeg (and sndfile-convert
# from libsndfile, which encodes Vorbis with libvorbis), and next to each one the
# reference decoding of it as raw float32 (NAME.f32), the expected values: ffmpeg's for
# the WAV files, libvorbisfile's (tools/vorbis_ref.py) for the Ogg Vorbis ones.
set -e
tools="$(cd "$(dirname "$0")" && pwd)"
cd "$tools/../tests/data"
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

# Ogg Vorbis: libvorbis through sndfile-convert, and ffmpeg's own encoder for ogg_ffmpeg.
tmp="$(mktemp -d)"
vorbis() { name=$1; shift; ffmpeg -loglevel error -y "$@" -c:a pcm_s16le "$tmp/$name.wav"; sndfile-convert -vorbis "$tmp/$name.wav" "$name.ogg"; }
vorbis ogg_mono -f lavfi -i "sine=frequency=440:sample_rate=22050:duration=0.05"
vorbis ogg_stereo -f lavfi -i "aevalsrc=0.6*sin(2*PI*440*t)|0.4*sin(2*PI*660*t)*exp(-3*t):s=44100:d=0.3"
vorbis ogg_51 -f lavfi -i "aevalsrc=sin(2*PI*220*t)|0.5*sin(2*PI*330*t)|0.2*sin(2*PI*1000*t)|0.3*random(0)-0.15|0.1*t|0.4*sin(2*PI*50*t):s=48000:d=0.06" -channel_layout 5.1
vorbis ogg_silent -f lavfi -i "aevalsrc=if(lt(t\,0.002)\,0.5\,0)|0:s=44100:d=0.1"
vorbis ogg_tiny -f lavfi -i "sine=frequency=880:sample_rate=44100:duration=0.0003"
vorbis loop -f lavfi -i "aevalsrc=0.5*sin(2*PI*(200+400*t)*t):s=22050:d=0.4"
ffmpeg -loglevel error -y -i loop.ogg -c copy -page_duration 40000 -metadata LOOPSTART=2000 -metadata LOOPLENGTH=5000 ogg_loop.ogg
rm loop.ogg
ffmpeg -loglevel error -y -f lavfi -i "aevalsrc=0.7*sin(2*PI*523*t)|0.5*sin(2*PI*784*t):s=22050:d=0.25" -c:a vorbis -strict -2 ogg_ffmpeg.ogg
rm -r "$tmp"
for f in ogg_*.ogg; do python3 -I "$tools/vorbis_ref.py" "$f" "${f%.ogg}.f32"; done
