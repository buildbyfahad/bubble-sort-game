"""Builds the game's cue set from CC0 sample packs.

This replaces `gen_audio.py`, which synthesised every sound from sine partials
and FM bells. That was original and reproducible and, after three passes and
three rounds of "the sounds are still bad", clearly not going to get there: a
Python script making oscillators cannot compete with recorded and designed
samples, and the honest fix was to stop trying.

Sources, all Creative Commons Zero (free for any use, commercial included, no
attribution required) from Kenney — https://kenney.nl:

    tools/audio_src/interface   Interface Sounds
    tools/audio_src/impact      Impact Sounds
    tools/audio_src/jingles     Music Jingles

Two things happen here:

  * **Ogg to WAV.** The packs ship Ogg Vorbis, which Android plays and iOS
    does not. macOS's own `afconvert` decodes it, so the build converts
    everything to 16-bit PCM.
  * **Pitch stairs.** The eight vessel-completion cues have to be one sound
    walking up a scale, and the pack has one glass hit. Resampling the same
    sample at rising rates gives the staircase — and because it is literally
    the same hit, the set is coherent in a way eight separately chosen
    samples never would be.

Run:  python3 tools/build_audio.py
"""

import math
import os
import struct
import subprocess
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'audio_src')
OUT = os.path.join(HERE, '..', 'assets', 'audio')
SR = 44100

# Cue -> (pack, file, gain). Chosen by ear-equivalent: short and bright for
# interface, glass for anything touching a vessel, a struck bell for rewards.
MAP = {
    # --- interface -------------------------------------------------------
    # Not one of the `click_*` samples: every one of them is a 10ms artifact
    # that reads as a glitch rather than a button.
    'tap':        ('interface', 'toggle_001',       0.70),
    'press':      ('interface', 'confirmation_002', 0.85),
    # Matched crest factors, so on and off land at the same perceived
    # loudness — the first pair sounded like a volume change rather than a
    # direction change.
    'toggle_on':  ('interface', 'switch_005',       0.80),
    'toggle_off': ('interface', 'switch_004',       0.80),
    'whoosh':     ('interface', 'scratch_004',      0.55),
    'tick':       ('interface', 'tick_002',         0.60),
    'star':       ('interface', 'confirmation_001', 0.85),
    'unlock':     ('interface', 'maximize_006',     0.90),
    'invalid':    ('interface', 'error_004',        0.65),
    'lift':       ('interface', 'select_004',       0.70),

    # --- the board -------------------------------------------------------
    # Balls landing in glass, which is what is actually happening.
    'drop_1':     ('impact', 'impactGlass_light_000', 0.85),
    'drop_2':     ('impact', 'impactGlass_light_001', 0.85),
    'drop_3':     ('impact', 'impactGlass_light_002', 0.85),
    'drop_4':     ('impact', 'impactGlass_light_003', 0.85),
}

# The eight seal cues: one struck bell, resampled up a pentatonic-ish stair.
SEAL_SOURCE = ('impact', 'impactBell_heavy_001')
SEAL_STEPS = [0, 2, 4, 7, 9, 12, 14, 16]   # semitones above the root

# Clearing a board, and clearing a chapter.
WIN = ('jingles', 'jingles_STEEL00')
BOSS_WIN = ('jingles', 'jingles_STEEL16')


def find(pack, stem):
    root = os.path.join(SRC, pack)
    for dirpath, _dirs, files in os.walk(root):
        for f in files:
            if f == stem + '.ogg':
                return os.path.join(dirpath, f)
    raise SystemExit('missing sample: {}/{}.ogg'.format(pack, stem))


def decode(path):
    """Ogg -> mono 16-bit PCM at SR, via macOS's own converter.

    The RIFF chunks are parsed by hand rather than with the `wave` module:
    afconvert writes WAVE_FORMAT_EXTENSIBLE (tag 0xFFFE), which is a perfectly
    ordinary PCM file that `wave` refuses to open on sight.
    """
    tmp = os.path.join(HERE, '_decode.wav')
    subprocess.run(
        ['afconvert', '-f', 'WAVE', '-d', 'LEI16@{}'.format(SR), '-c', '1', path, tmp],
        check=True, capture_output=True,
    )
    with open(tmp, 'rb') as f:
        raw = f.read()
    os.remove(tmp)

    if raw[:4] != b'RIFF' or raw[8:12] != b'WAVE':
        raise SystemExit('not a WAVE file: {}'.format(path))
    pos = 12
    bits = 16
    pcm = b''
    while pos + 8 <= len(raw):
        cid = raw[pos:pos + 4]
        size = struct.unpack('<I', raw[pos + 4:pos + 8])[0]
        body = raw[pos + 8:pos + 8 + size]
        if cid == b'fmt ':
            bits = struct.unpack('<H', body[14:16])[0]
        elif cid == b'data':
            pcm = body
        pos += 8 + size + (size & 1)      # chunks are word-aligned
    if bits != 16:
        raise SystemExit('expected 16-bit PCM, got {}'.format(bits))
    n = len(pcm) // 2
    return list(struct.unpack('<{}h'.format(n), pcm[:n * 2]))


def resample(samples, ratio):
    """Varispeed: plays the sample faster or slower, so pitch and length move
    together. Exactly what a struck object does when it is a different size,
    which is why a resampled bell still sounds like a bell."""
    out_n = max(1, int(len(samples) / ratio))
    out = [0] * out_n
    for i in range(out_n):
        pos = i * ratio
        a = int(pos)
        b = min(a + 1, len(samples) - 1)
        frac = pos - a
        out[i] = int(samples[a] * (1 - frac) + samples[b] * frac)
    return out


def write(name, samples, gain=1.0, fade_out=0.010):
    peak = max(1, max(abs(s) for s in samples))
    # Normalise, then apply the cue's own level, so the mix is set here and
    # not left to whatever level the sample happened to be recorded at.
    scale = (32767 * gain) / peak
    n = len(samples)
    fo = max(1, int(fade_out * SR))
    data = bytearray()
    for i, s in enumerate(samples):
        v = s * scale
        if i > n - fo:
            v *= max(0.0, (n - i) / fo)
        data += struct.pack('<h', int(max(-32768, min(32767, v))))
    path = os.path.join(OUT, name + '.wav')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(data))
    return n / SR


def main():
    if sys.platform != 'darwin':
        raise SystemExit('needs macOS afconvert to decode Ogg')
    os.makedirs(OUT, exist_ok=True)

    for cue, (pack, stem, gain) in sorted(MAP.items()):
        dur = write(cue, decode(find(pack, stem)), gain)
        print('  {:14s} {:5.2f}s   <- {}/{}'.format(cue, dur, pack, stem))

    bell = decode(find(*SEAL_SOURCE))
    for i, semis in enumerate(SEAL_STEPS, start=1):
        shifted = resample(bell, 2 ** (semis / 12.0))
        # Later seals sit a touch louder as well as higher, so a run of eight
        # escalates on two axes rather than one.
        dur = write('complete_{}'.format(i), shifted, 0.80 + i * 0.015)
        print('  complete_{:<5d} {:5.2f}s   <- bell +{} semitones'.format(i, dur, semis))

    print('  {:14s} {:5.2f}s'.format('win', write('win', decode(find(*WIN)), 0.90)))
    print('  {:14s} {:5.2f}s'.format('boss_win', write('boss_win', decode(find(*BOSS_WIN)), 0.95)))


if __name__ == '__main__':
    main()
