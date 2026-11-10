#!/usr/bin/env python3
"""Decodes an Ogg Vorbis file with libvorbisfile, the reference decoder, and writes its
samples as raw interleaved float32 (the expected values the tests compare against).

    python3 -I tools/vorbis_ref.py in.ogg out.f32

Needs libvorbisfile (libvorbis on Homebrew, libvorbisfile3 on Debian and Ubuntu).
"""

import ctypes
import ctypes.util
import os
import struct
import sys


def load():
    names = [ctypes.util.find_library("vorbisfile"), "/opt/homebrew/lib/libvorbisfile.dylib",
             "/usr/local/lib/libvorbisfile.dylib", "libvorbisfile.so.3"]
    for name in names:
        if not name:
            continue
        try:
            return ctypes.CDLL(name)
        except OSError:
            pass
    sys.exit("libvorbisfile not found")


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: vorbis_ref.py in.ogg out.f32")
    vf = load()
    vf.ov_fopen.argtypes = [ctypes.c_char_p, ctypes.c_void_p]
    vf.ov_info.restype = ctypes.POINTER(ctypes.c_int)
    vf.ov_read_float.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.POINTER(ctypes.POINTER(ctypes.c_float))),
                                 ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
    vf.ov_read_float.restype = ctypes.c_long
    handle = ctypes.create_string_buffer(16384)  # OggVorbis_File, opaque here
    if vf.ov_fopen(os.fsencode(sys.argv[1]), handle) != 0:
        sys.exit("cannot open " + sys.argv[1])
    channels = vf.ov_info(handle, -1)[1]  # vorbis_info: int version, int channels, ...
    out = bytearray()
    pcm = ctypes.POINTER(ctypes.POINTER(ctypes.c_float))()
    section = ctypes.c_int()
    while True:
        n = vf.ov_read_float(handle, ctypes.byref(pcm), 4096, ctypes.byref(section))
        if n <= 0:
            break
        for i in range(n):
            for c in range(channels):
                out += struct.pack("<f", pcm[c][i])
    vf.ov_clear(handle)
    with open(sys.argv[2], "wb") as f:
        f.write(out)


main()
