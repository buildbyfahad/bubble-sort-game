"""Procedural sound design for Bubble Sort.

Every cue is synthesised here rather than sourced, so the whole palette is
original and tuned as one instrument. The house style:

  * Pitched material comes from one scale (D major pentatonic) so no two cues
    can ever clash, whatever order they fire in.
  * Everything pitched is an FM bell or a plucked string, not a raw sine. A
    sine with an envelope on it is the sound of a prototype; a bell has
    inharmonic partials that decay at different rates, which is what the ear
    reads as "an object was struck".
  * Everything goes through a plate reverb before mastering. A dry cue sounds
    like it is coming out of the phone; a cue with a short tail sounds like it
    is happening somewhere.
  * Soft-clip saturation on the master, then peak normalise. This is what
    stops the loud cues sounding thin next to the quiet ones.

Run:  python3 tools/gen_audio.py
"""

import math
import os
import struct
import wave

SR = 44100
MUSIC_SR = 22050  # the pad has nothing above 8k in it; halving the rate halves the file
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')


# --------------------------------------------------------------------- pitch

def note(semitones_from_a4, octave=0):
    return 440.0 * (2 ** ((semitones_from_a4 + 12 * octave) / 12.0))


# D major pentatonic, two and a bit octaves: D E F# A B ...
PENTA = [note(5), note(7), note(9), note(12), note(14),
         note(17), note(19), note(21), note(24), note(26)]

D = note(5)  # tonic


# ------------------------------------------------------------------- helpers

class Rng:
    """Deterministic LCG. Builds must be byte-identical run to run, or the
    asset diff is noise and nobody reviews it."""

    def __init__(self, seed=12345):
        self.x = seed & 0x7FFFFFFF

    def next(self):
        self.x = (1103515245 * self.x + 12345) & 0x7FFFFFFF
        return self.x / 0x7FFFFFFF

    def bi(self):
        return self.next() * 2 - 1


def buf(dur, sr=SR):
    return [0.0] * int(dur * sr)


def env_ad(n, attack, decay_curve=4.0, hold=0.0):
    """Percussive attack/decay. The attack is curved (x^0.55) rather than
    linear so the transient has a click of edge without a DC step."""
    a = max(1, int(attack * SR))
    h = int(hold * SR)
    out = [0.0] * n
    for i in range(n):
        if i < a:
            out[i] = (i / a) ** 0.55
        elif i < a + h:
            out[i] = 1.0
        else:
            t = (i - a - h) / max(1, n - a - h)
            out[i] = math.exp(-decay_curve * t) * (1 - t)
    return out


def fm_bell(freq, dur, ratio=2.71, index=3.4, index_decay=7.0,
            amp_decay=4.0, attack=0.003, sr=SR):
    """Two-operator FM. The modulator index falls faster than the carrier
    amplitude, so the strike is bright and the tail is pure — the single most
    important detail in making a synthesised bell sound struck rather than
    faded in."""
    n = int(dur * sr)
    e = env_ad(n, attack, amp_decay)
    out = [0.0] * n
    two_pi = 2 * math.pi
    for i in range(n):
        t = i / sr
        k = index * math.exp(-index_decay * t)
        mod = k * math.sin(two_pi * freq * ratio * t)
        out[i] = math.sin(two_pi * freq * t + mod) * e[i]
    return out


def pluck(freq, dur, damp=0.48, seed=7, sr=SR):
    """Karplus-Strong. Gives the sparkle layers a physical, stringy attack
    that FM alone cannot produce."""
    n = int(dur * sr)
    ln = max(2, int(sr / freq))
    r = Rng(seed)
    line = [r.bi() for _ in range(ln)]
    out = [0.0] * n
    idx = 0
    for i in range(n):
        v = line[idx]
        nxt = line[(idx + 1) % ln]
        line[idx] = (v + nxt) * 0.5 * (1.0 - damp * 0.02)
        out[i] = v
        idx = (idx + 1) % ln
    # global decay on top of the string's own damping
    e = env_ad(n, 0.0006, 3.2)
    return [out[i] * e[i] for i in range(n)]


def noise(dur, seed=1, sr=SR):
    r = Rng(seed)
    return [r.bi() for _ in range(int(dur * sr))]


def lowpass(src, cutoff, sr=SR):
    dt = 1.0 / sr
    rc = 1.0 / (2 * math.pi * max(20.0, cutoff))
    a = dt / (rc + dt)
    out = [0.0] * len(src)
    prev = 0.0
    for i, s in enumerate(src):
        prev += a * (s - prev)
        out[i] = prev
    return out


def highpass(src, cutoff, sr=SR):
    dt = 1.0 / sr
    rc = 1.0 / (2 * math.pi * max(20.0, cutoff))
    a = rc / (rc + dt)
    out = [0.0] * len(src)
    prev_in = 0.0
    prev_out = 0.0
    for i, s in enumerate(src):
        prev_out = a * (prev_out + s - prev_in)
        prev_in = s
        out[i] = prev_out
    return out


def bandpass(src, lo, hi, sr=SR):
    return highpass(lowpass(src, hi, sr), lo, sr)


def sweep_lowpass(src, f0, f1, sr=SR):
    """Cutoff glides over the length of the buffer. Used for whooshes, where a
    static filter reads as a hiss and a moving one reads as motion."""
    n = len(src)
    out = [0.0] * n
    prev = 0.0
    dt = 1.0 / sr
    for i, s in enumerate(src):
        f = f0 + (f1 - f0) * (i / max(1, n - 1))
        rc = 1.0 / (2 * math.pi * max(20.0, f))
        a = dt / (rc + dt)
        prev += a * (s - prev)
        out[i] = prev
    return out


def env_apply(src, e):
    return [src[i] * e[i] for i in range(min(len(src), len(e)))]


def gain(src, g):
    return [s * g for s in src]


def delay(src, seconds, sr=SR):
    return [0.0] * int(seconds * sr) + list(src)


def mix(*layers):
    n = max((len(l) for l in layers), default=0)
    out = [0.0] * n
    for l in layers:
        for i, s in enumerate(l):
            out[i] += s
    return out


def pad_to(src, dur, sr=SR):
    n = int(dur * sr)
    if len(src) >= n:
        return src[:n]
    return list(src) + [0.0] * (n - len(src))


# --------------------------------------------------------------------- space

_COMB = [0.0297, 0.0371, 0.0411, 0.0437]
_ALLPASS = [0.0050, 0.0017]


def reverb(src, wet=0.25, decay=0.72, tail=0.9, sr=SR):
    """Schroeder plate: four parallel combs into two series allpasses.

    Cheap, and the only kind of reverb worth having on a cue this short —
    what matters is that the tail exists at all, not that it is convolved."""
    n = len(src) + int(tail * sr)
    x = pad_to(list(src), n / sr, sr)

    acc = [0.0] * n
    for d in _COMB:
        dl = int(d * sr)
        line = [0.0] * dl
        idx = 0
        for i in range(n):
            y = line[idx]
            line[idx] = x[i] + y * decay
            acc[i] += y * 0.25
            idx = (idx + 1) % dl

    for d in _ALLPASS:
        dl = int(d * sr)
        line = [0.0] * dl
        idx = 0
        g = 0.5
        for i in range(n):
            y = line[idx]
            v = acc[i] + y * g
            line[idx] = v
            acc[i] = y - g * v
            idx = (idx + 1) % dl

    # Roll the top off the tail so the reverb sits behind the dry signal
    acc = lowpass(acc, 5200, sr)
    return [x[i] * (1 - wet * 0.35) + acc[i] * wet for i in range(n)]


def saturate(src, drive=1.35):
    """tanh soft clip. Adds a little density and makes the peak normaliser's
    job honest — without it a single transient sets the gain for the whole
    file and everything else ends up quiet."""
    return [math.tanh(s * drive) / math.tanh(drive) for s in src]


# -------------------------------------------------------------------- output

def write(name, src, peak=0.62, sr=SR, drive=1.3, fade_in=0.003, fade_out=0.012):
    src = saturate(src, drive)
    m = max(1e-9, max(abs(s) for s in src))
    g = peak / m
    n = len(src)
    fi = max(1, int(fade_in * sr))
    fo = max(1, int(fade_out * sr))
    data = bytearray()
    for i, s in enumerate(src):
        v = s * g
        if i < fi:
            v *= i / fi
        if i > n - fo:
            v *= max(0.0, (n - i) / fo)
        data += struct.pack('<h', int(max(-1.0, min(1.0, v)) * 32767))
    path = os.path.join(OUT, name)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(bytes(data))
    print('  {:22s} {:5.2f}s  {:6.0f} KB'.format(name, n / sr, len(data) / 1024))


def write_loop(name, src, peak=0.5, sr=MUSIC_SR):
    """No fades — a loop with fades in it ticks once per bar. The generator is
    responsible for making the ends meet instead."""
    src = saturate(src, 1.15)
    m = max(1e-9, max(abs(s) for s in src))
    g = peak / m
    data = bytearray()
    for s in src:
        data += struct.pack('<h', int(max(-1.0, min(1.0, s * g)) * 32767))
    path = os.path.join(OUT, name)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(bytes(data))
    print('  {:22s} {:5.2f}s  {:6.0f} KB'.format(name, len(src) / sr, len(data) / 1024))


os.makedirs(OUT, exist_ok=True)
print('interface')

# ---------------------------------------------------------------- UI: tap
#
# Barely there. A menu tap that announces itself is the fastest way to make a
# player reach for the mute switch inside thirty seconds.
tap = mix(
    fm_bell(PENTA[5], 0.09, ratio=3.1, index=1.6, index_decay=40, amp_decay=16, attack=0.0008),
    gain(env_apply(bandpass(noise(0.02, seed=3), 1800, 7000), env_ad(int(0.02 * SR), 0.0004, 20)), 0.30),
)
write('tap.wav', reverb(tap, wet=0.10, tail=0.20), peak=0.34)

# ---------------------------------------------------------------- UI: whoosh
#
# Screen transitions. Filtered noise with the cutoff climbing — reads as
# something passing, which is exactly what a push transition is.
wh = env_apply(sweep_lowpass(noise(0.34, seed=91), 400, 5200),
               env_ad(int(0.34 * SR), 0.10, 3.0))
write('whoosh.wav', reverb(gain(wh, 0.8), wet=0.22, tail=0.4), peak=0.30)

# ---------------------------------------------------------------- UI: tick
write('tick.wav', fm_bell(PENTA[7], 0.06, ratio=4.2, index=1.2, index_decay=50,
                          amp_decay=20, attack=0.0005), peak=0.30)

# ------------------------------------------------------------------ UI: star
#
# The counter pip on the win sheet. Rises rather than sits, so a run of them
# reads as an accumulating total.
star = mix(
    fm_bell(PENTA[7], 0.30, ratio=2.0, index=2.2, index_decay=16, amp_decay=7, attack=0.001),
    delay(gain(pluck(PENTA[9], 0.24, seed=5), 0.35), 0.02),
)
write('star.wav', reverb(star, wet=0.30, tail=0.5), peak=0.44)

# ---------------------------------------------------------------- UI: unlock
#
# A new node opening on the map: a rising sweep that resolves onto the tonic.
unl = mix(
    env_apply(sweep_lowpass(noise(0.30, seed=44), 300, 6000),
              env_ad(int(0.30 * SR), 0.14, 4.0)),
    delay(gain(fm_bell(PENTA[4], 0.52, ratio=2.0, index=2.6, index_decay=12,
                       amp_decay=4.5, attack=0.002), 1.5), 0.22),
    delay(gain(fm_bell(PENTA[7], 0.40, ratio=3.0, index=1.6, index_decay=18,
                       amp_decay=6.0, attack=0.002), 0.7), 0.30),
)
write('unlock.wav', reverb(unl, wet=0.30, tail=0.8), peak=0.52)

print('board')

# ------------------------------------------------------------------- lift
#
# The stack leaving the vessel. Upward pitch glide plus a breath of air, so
# picking up feels like the inverse of putting down.
n_lift = int(0.16 * SR)
glide = [0.0] * n_lift
ph = 0.0
for i in range(n_lift):
    t = i / n_lift
    f = PENTA[2] * (1 + 0.42 * t)
    ph += 2 * math.pi * f / SR
    glide[i] = math.sin(ph) + 0.22 * math.sin(2 * ph)
lift = mix(
    env_apply(glide, env_ad(n_lift, 0.004, 5.0)),
    gain(env_apply(sweep_lowpass(noise(0.16, seed=17), 700, 4200),
                   env_ad(n_lift, 0.03, 5.0)), 0.28),
)
write('lift.wav', reverb(lift, wet=0.18, tail=0.3), peak=0.40)

# ------------------------------------------------------------------- drops
#
# Four variants, one per ball in a run, rising through the scale. A four-ball
# pour therefore plays as a little four-note figure instead of the same plop
# four times — this is the single change that does most to stop repeated pours
# sounding mechanical.
for i in range(4):
    f = PENTA[i]
    body = fm_bell(f / 2, 0.20, ratio=1.41, index=2.8, index_decay=22,
                   amp_decay=7.0, attack=0.0012)
    # The "pip": a fast upward blip, the sound of a liquid surface closing.
    n_pip = int(0.05 * SR)
    pip = [0.0] * n_pip
    ph = 0.0
    for k in range(n_pip):
        t = k / n_pip
        ph += 2 * math.pi * (f * (0.7 + 1.1 * t)) / SR
        pip[k] = math.sin(ph)
    pip = env_apply(pip, env_ad(n_pip, 0.0008, 12))
    click = gain(env_apply(bandpass(noise(0.03, seed=23 + i), 900, 5200),
                           env_ad(int(0.03 * SR), 0.0004, 26)), 0.34)
    write('drop_{}.wav'.format(i + 1),
          reverb(mix(body, gain(pip, 0.45), click), wet=0.16, tail=0.28), peak=0.50)

# ----------------------------------------------------------------- invalid
#
# Dull, damped, and *below* the music. An illegal tap is usually a misjudged
# tap, and a buzzer for a misjudgement is what makes a puzzle feel hostile.
inv = mix(
    fm_bell(D / 2, 0.16, ratio=1.19, index=1.1, index_decay=30, amp_decay=13, attack=0.004),
    gain(env_apply(lowpass(noise(0.06, seed=61), 620), env_ad(int(0.06 * SR), 0.003, 16)), 0.4),
)
write('invalid.wav', reverb(inv, wet=0.10, tail=0.2), peak=0.30)

print('completion')

# ------------------------------------------------------------------- crack
#
# The glass fracturing as a vessel seals. Four short bursts through a high
# resonant band, spaced unevenly — evenly spaced crackles read as a machine.
# Not written out on its own: it is a layer of every complete_N below, so that
# the fracture the player *sees* and the fracture they *hear* are one event.
def crackle(seed, bright=1.0):
    layers = []
    r = Rng(seed)
    for k, at in enumerate((0.0, 0.021, 0.047, 0.068)):
        d = 0.018 + r.next() * 0.014
        lo = 1600 + r.next() * 1200
        hi = (6500 + r.next() * 3500) * bright
        b = env_apply(bandpass(noise(d, seed=seed + k * 13), lo, hi),
                      env_ad(int(d * SR), 0.0003, 30))
        layers.append(delay(gain(b, 0.9 - k * 0.16), at))
    return mix(*layers)


# --------------------------------------------------------- vessel complete
#
# One per vessel sealed, walking up the scale, so clearing a board plays as a
# rising phrase rather than the same reward eight times. Each is three things
# at once: the glass cracking, the vessel ringing, and a sparkle above it —
# and the sparkle gets brighter as the run gets longer, so the eighth seal is
# audibly a bigger deal than the first.
for i, f in enumerate(PENTA[:8], start=1):
    lift_amt = (i - 1) / 7.0
    body = fm_bell(f, 0.62, ratio=2.0, index=3.0 + lift_amt * 1.6,
                   index_decay=9.0, amp_decay=3.6, attack=0.0025)
    fifth = delay(gain(fm_bell(f * 1.5, 0.48, ratio=3.0, index=1.8,
                               index_decay=14, amp_decay=5.0, attack=0.003),
                       0.42 + lift_amt * 0.2), 0.045)
    shimmer = delay(gain(mix(
        pluck(f * 4, 0.34, seed=31 + i),
        delay(pluck(f * 6, 0.28, seed=57 + i), 0.035),
    ), 0.16 + lift_amt * 0.20), 0.06)
    glass = gain(crackle(200 + i * 7, bright=1.0 + lift_amt * 0.4), 0.55)
    sub = gain(fm_bell(f / 2, 0.34, ratio=1.0, index=0.6, index_decay=20,
                       amp_decay=6.0, attack=0.004), 0.35)
    write('complete_{}.wav'.format(i),
          reverb(mix(glass, body, fifth, shimmer, sub), wet=0.34, tail=1.0),
          peak=0.52 + lift_amt * 0.08)

# ---------------------------------------------------------------- level win
#
# A real cadence, not a jingle: a sustained Dsus2 pad underneath a five-note
# arpeggio that lands on the octave, with a sub thump on the downbeat and a
# shimmer tail. Roughly two seconds — long enough to feel earned, short enough
# that the player never waits for it.
arp = [(PENTA[0], 0.00), (PENTA[2], 0.10), (PENTA[4], 0.20),
       (PENTA[5], 0.30), (PENTA[7], 0.42)]
win = mix(
    *[delay(gain(fm_bell(f, 1.7 - d, ratio=2.0, index=3.2, index_decay=9,
                         amp_decay=2.6, attack=0.003), 1.0), d) for f, d in arp],
    # sustaining chord bed
    *[gain(fm_bell(f, 2.0, ratio=1.0, index=0.9, index_decay=6,
                   amp_decay=1.7, attack=0.06), 0.30)
      for f in (D, D * 1.5, PENTA[1])],
    gain(fm_bell(D / 2, 1.6, ratio=1.0, index=0.7, index_decay=14,
                 amp_decay=2.2, attack=0.006), 0.55),
    # sparkle tail, arriving after the arpeggio has resolved
    delay(gain(mix(pluck(PENTA[8], 0.7, seed=77),
                   delay(pluck(PENTA[9], 0.6, seed=88), 0.06),
                   delay(pluck(PENTA[7] * 2, 0.5, seed=99), 0.13)), 0.26), 0.46),
    gain(crackle(303, bright=1.3), 0.22),
)
write('win.wav', reverb(win, wet=0.38, tail=1.4), peak=0.66)

print('music')

# ------------------------------------------------------------- ambient loop
#
# 25.6 seconds of Dsus2 pad. Everything that moves in it — the filter LFO, the
# tremolo, the arpeggio — completes a whole number of cycles inside the loop,
# which is what lets it repeat without a seam. There is no drum track and no
# melody on purpose: the player is thinking, and the score's job is to make
# the room feel occupied, not to be listened to.
LOOP = 25.6
n_m = int(LOOP * MUSIC_SR)
music = [0.0] * n_m

# Pad: three voices, each slightly detuned and each with its own slow tremolo.
voices = [
    (D / 2, 0.55, 1.0),
    (D, 0.34, 2.0),
    (D * 1.5, 0.26, 3.0),   # the fifth
    (PENTA[1], 0.18, 2.0),  # the sus2
]
two_pi = 2 * math.pi
for f, amp, trem_cycles in voices:
    for det in (-0.0016, 0.0, 0.0021):
        ph = 0.0
        fd = f * (1 + det)
        for i in range(n_m):
            t = i / MUSIC_SR
            ph += two_pi * fd / MUSIC_SR
            trem = 0.72 + 0.28 * math.sin(two_pi * trem_cycles * t / LOOP)
            s = math.sin(ph) + 0.24 * math.sin(2 * ph) + 0.07 * math.sin(3 * ph)
            music[i] += s * amp * trem * 0.33

# Slow filter breath: two full cycles across the loop.
out = [0.0] * n_m
prev = 0.0
dt = 1.0 / MUSIC_SR
for i in range(n_m):
    lfo = 0.5 + 0.5 * math.sin(two_pi * 2 * (i / n_m))
    f = 420 + 1500 * lfo
    rc = 1.0 / (two_pi * f)
    a = dt / (rc + dt)
    prev += a * (music[i] - prev)
    out[i] = prev
music = out

# Sparse plucks over the top, on beats that divide the loop evenly.
pluck_plan = [(0.0, PENTA[4]), (3.2, PENTA[5]), (6.4, PENTA[7]),
              (9.6, PENTA[5]), (12.8, PENTA[8]), (16.0, PENTA[4]),
              (19.2, PENTA[7]), (22.4, PENTA[5])]
for at, f in pluck_plan:
    p = gain(pluck(f, 2.4, damp=0.62, seed=int(f) % 977, sr=MUSIC_SR), 0.16)
    start = int(at * MUSIC_SR)
    for k, s in enumerate(p):
        # wrap, so a pluck near the end of the loop rings into its own start
        music[(start + k) % n_m] += s

music = reverb(music, wet=0.34, decay=0.78, tail=0.0, sr=MUSIC_SR)[:n_m]
write_loop('music_loop.wav', music, peak=0.46)

print('done')
