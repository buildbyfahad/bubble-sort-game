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
# The glass fracturing as a vessel seals. Not written out on its own: it is a
# layer of every complete_N below, so the fracture the player *sees* and the
# fracture they *hear* are one event.
def crackle(seed, bright=1.0):
    """Dense fracture noise — the sound of the break itself."""
    layers = []
    r = Rng(seed)
    for k, at in enumerate((0.0, 0.013, 0.029, 0.044, 0.062, 0.085)):
        d = 0.016 + r.next() * 0.020
        lo = 1400 + r.next() * 1400
        hi = (7000 + r.next() * 4000) * bright
        b = env_apply(bandpass(noise(d, seed=seed + k * 13), lo, hi),
                      env_ad(int(d * SR), 0.0002, 26))
        layers.append(delay(gain(b, 0.95 - k * 0.11), at))
    return mix(*layers)


def tinkle(seed, count=16, spread=0.45, bright=1.0):
    """Shards landing.

    Many very short, very high pings scattered unevenly across half a second.
    This is the layer that makes a break read as *glass* rather than as a
    generic crunch — the ear identifies glass by the tail of small bright
    collisions after the impact, not by the impact itself. It is also what the
    first version of this cue was missing, and why it sounded like a click.
    """
    r = Rng(seed)
    layers = []
    for i in range(count):
        # Clustered toward the start: shards fall fastest right after the break.
        at = (r.next() ** 1.7) * spread
        f = (2200 + r.next() * 5200) * bright
        d = 0.030 + r.next() * 0.070
        ping = fm_bell(f, d, ratio=3.7 + r.next() * 2.0, index=1.4,
                       index_decay=60, amp_decay=16, attack=0.0004)
        layers.append(delay(gain(ping, 0.16 + r.next() * 0.30), at))
    return mix(*layers)


# --------------------------------------------------------- vessel complete
#
# One per vessel sealed, walking up the scale, so clearing a board plays as a
# rising phrase rather than the same reward eight times.
#
# Six layers, because this is the moment the entire game loop is built around
# and it has to be unmistakable with the phone in a pocket:
#
#   thump    a low body hit — the weight of the strike
#   crack    the fracture itself
#   tinkle   shards falling, the layer that says "glass"
#   bell     the reward tone, on the scale, rising with the run
#   fifth    a harmony above it so the tone has width
#   shimmer  a plucked tail that keeps ringing after the break has settled
#
# The sparkle also gets brighter and the tinkle denser as the run gets longer,
# so the eighth seal is audibly a bigger deal than the first.
for i, f in enumerate(PENTA[:8], start=1):
    lift_amt = (i - 1) / 7.0

    thump = gain(fm_bell(f / 4, 0.26, ratio=1.0, index=1.1, index_decay=30,
                         amp_decay=9.0, attack=0.0015), 0.70)
    glass = gain(crackle(200 + i * 7, bright=1.0 + lift_amt * 0.4), 0.85)
    shards = gain(tinkle(400 + i * 11,
                         count=14 + int(lift_amt * 10),
                         spread=0.42 + lift_amt * 0.18,
                         bright=1.0 + lift_amt * 0.25),
                  0.55 + lift_amt * 0.25)
    body = delay(fm_bell(f, 0.70, ratio=2.0, index=3.2 + lift_amt * 1.8,
                         index_decay=8.0, amp_decay=3.2, attack=0.002), 0.026)
    fifth = delay(gain(fm_bell(f * 1.5, 0.52, ratio=3.0, index=1.9,
                               index_decay=13, amp_decay=4.6, attack=0.003),
                       0.44 + lift_amt * 0.2), 0.062)
    shimmer = delay(gain(mix(
        pluck(f * 4, 0.40, seed=31 + i),
        delay(pluck(f * 6, 0.32, seed=57 + i), 0.035),
    ), 0.20 + lift_amt * 0.22), 0.08)

    write('complete_{}.wav'.format(i),
          reverb(mix(thump, glass, shards, body, fifth, shimmer),
                 wet=0.32, tail=1.1),
          peak=0.60 + lift_amt * 0.08,
          drive=1.5)

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
    gain(crackle(303, bright=1.3), 0.30),
    gain(tinkle(505, count=26, spread=0.8, bright=1.3), 0.34),
)
write('win.wav', reverb(win, wet=0.38, tail=1.4), peak=0.66)

# --------------------------------------------------------------- boss win
#
# The chapter finale. The ordinary win, then a second, higher cadence on top
# of it after a beat — the same phrase answered an octave up — with a longer
# shimmer and a deeper sub. One clear in forty should not sound like the other
# thirty-nine.
boss_arp = [(PENTA[0], 0.00), (PENTA[2], 0.09), (PENTA[4], 0.18), (PENTA[5], 0.27),
            (PENTA[7], 0.38), (PENTA[8], 0.60), (PENTA[9], 0.72), (PENTA[7] * 2, 0.86)]
boss = mix(
    *[delay(gain(fm_bell(f, 2.2 - d, ratio=2.0, index=3.4, index_decay=8,
                         amp_decay=2.2, attack=0.003), 1.0), d) for f, d in boss_arp],
    *[gain(fm_bell(f, 2.8, ratio=1.0, index=0.9, index_decay=5,
                   amp_decay=1.4, attack=0.08), 0.32)
      for f in (D, D * 1.5, PENTA[1], D * 2)],
    gain(fm_bell(D / 4, 2.2, ratio=1.0, index=0.8, index_decay=12,
                 amp_decay=1.8, attack=0.008), 0.7),
    delay(gain(mix(pluck(PENTA[8], 1.0, seed=77), delay(pluck(PENTA[9], 0.9, seed=88), 0.07),
                   delay(pluck(PENTA[7] * 2, 0.8, seed=99), 0.14),
                   delay(pluck(PENTA[9] * 2, 0.7, seed=111), 0.22)), 0.30), 0.9),
    gain(crackle(303, bright=1.4), 0.34),
    gain(tinkle(606, count=34, spread=1.1, bright=1.4), 0.40),
)
write('boss_win.wav', reverb(boss, wet=0.42, tail=1.8), peak=0.70)

print('music')

# ------------------------------------------------------------- music stems
#
# The score is four loops that play *together*, and the game decides how many
# of them are audible. Pad alone on the menu; on the board, each vessel sealed
# brings in another layer, so by the last seal the full track is playing.
# Music becomes feedback for progress rather than wallpaper behind it.
#
# All four are exactly the same length and tempo, so they stay in phase:
#
#   pad     sustained chords, filtered — always on
#   bass    sub root notes with a plucked attack
#   drums   kick and hats in ONE file, so they can never drift against
#           each other (players start within tens of ms of one another, which
#           is inaudible on a pad and a flam on a drum kit)
#   melody  a plucked pentatonic line
#
# 96 BPM, eight bars of 4/4 = 32 beats = 20.0s. I - vi - IV - V in D, two
# bars per chord. Every LFO completes a whole number of cycles in the loop.
BPM = 96.0
BEAT = 60.0 / BPM
BARS = 8
LOOP = BEAT * 4 * BARS          # 20.0s
n_m = int(LOOP * MUSIC_SR)
two_pi = 2 * math.pi

# Chord tones (semitones from A4 → Hz). Two bars each.
def hz(semi, octave=0):
    return note(semi, octave)

CHORDS = [
    # D major       : D  F# A
    [hz(5, -1), hz(9, -1), hz(0, 0)],
    # B minor       : B  D  F#
    [hz(2, -1), hz(5, -1), hz(9, -1)],
    # G major       : G  B  D
    [hz(10, -2), hz(2, -1), hz(5, -1)],
    # A major       : A  C# E
    [hz(0, -1), hz(4, -1), hz(7, -1)],
]
ROOTS = [hz(5, -2), hz(2, -2), hz(10, -3), hz(0, -2)]   # one octave under

def chord_at(t):
    return int((t / LOOP) * 4) % 4

# --- pad --------------------------------------------------------------------
pad = [0.0] * n_m
for ci_, chord in enumerate(CHORDS):
    t0 = ci_ * LOOP / 4
    t1 = t0 + LOOP / 4
    i0, i1 = int(t0 * MUSIC_SR), int(t1 * MUSIC_SR)
    # Each chord tone, three slightly detuned voices, with a slow swell so the
    # change between chords is a crossfade rather than a step.
    for f in chord:
        for det in (-0.0018, 0.0, 0.0023):
            ph = 0.0
            fd = f * (1 + det)
            for i in range(i0, i1):
                t = i / MUSIC_SR
                ph += two_pi * fd / MUSIC_SR
                local = (t - t0) / (t1 - t0)
                env = min(1.0, local / 0.12) * min(1.0, (1 - local) / 0.10 + 0.0)
                env = max(env, 0.0)
                s_ = math.sin(ph) + 0.22 * math.sin(2 * ph) + 0.06 * math.sin(3 * ph)
                pad[i] += s_ * 0.11 * (0.35 + 0.65 * env)
# Slow filter breath, two cycles per loop.
out = [0.0] * n_m
prev = 0.0
dt = 1.0 / MUSIC_SR
for i in range(n_m):
    lfo = 0.5 + 0.5 * math.sin(two_pi * 2 * (i / n_m))
    f = 380 + 1400 * lfo
    rc = 1.0 / (two_pi * f)
    a = dt / (rc + dt)
    prev += a * (pad[i] - prev)
    out[i] = prev
pad = reverb(out, wet=0.36, decay=0.80, tail=0.0, sr=MUSIC_SR)[:n_m]
write_loop('music_pad.wav', pad, peak=0.40)

# --- bass -------------------------------------------------------------------
bass = [0.0] * n_m
def bass_note(f, at, dur):
    n = int(dur * MUSIC_SR)
    start = int(at * MUSIC_SR)
    ph = 0.0
    for k in range(n):
        t = k / MUSIC_SR
        # A little pitch drop at the attack — the "pluck".
        fk = f * (1 + 0.6 * math.exp(-t * 60))
        ph += two_pi * fk / MUSIC_SR
        env = math.exp(-t * 2.6) * min(1.0, k / 40)
        s_ = math.sin(ph) + 0.35 * math.sin(2 * ph) + 0.12 * math.sin(3 * ph)
        bass[(start + k) % n_m] += s_ * env * 0.9
for bar in range(BARS):
    root = ROOTS[bar // 2]
    b0 = bar * 4 * BEAT
    bass_note(root, b0, BEAT * 1.6)                 # beat 1
    bass_note(root, b0 + 2 * BEAT, BEAT * 1.2)      # beat 3
    bass_note(root * 2, b0 + 3.5 * BEAT, BEAT * 0.5)  # the "and" of 4, an octave up
bass = lowpass(bass, 900, MUSIC_SR)
write_loop('music_bass.wav', bass, peak=0.55)

# --- drums ------------------------------------------------------------------
drums = [0.0] * n_m
def kick(at):
    n = int(0.28 * MUSIC_SR); start = int(at * MUSIC_SR); ph = 0.0
    for k in range(n):
        t = k / MUSIC_SR
        f = 48 + 90 * math.exp(-t * 28)
        ph += two_pi * f / MUSIC_SR
        env = math.exp(-t * 9)
        drums[(start + k) % n_m] += math.sin(ph) * env * 1.0
def hat(at, open_=False, accent=1.0):
    d = 0.22 if open_ else 0.045
    n = int(d * MUSIC_SR); start = int(at * MUSIC_SR)
    r = Rng(int(at * 1000) + 7)
    buf = [r.bi() for _ in range(n)]
    buf = bandpass(buf, 6000, 11000, MUSIC_SR)
    for k in range(n):
        t = k / MUSIC_SR
        env = math.exp(-t * (14 if open_ else 70))
        drums[(start + k) % n_m] += buf[k] * env * 0.28 * accent
for bar in range(BARS):
    b0 = bar * 4 * BEAT
    kick(b0)
    kick(b0 + 2 * BEAT)
    # A ghost kick before beat 3 on bars 4 and 8 — the tiny swing that stops
    # eight bars of the same pattern sounding like a metronome.
    if bar % 4 == 3:
        kick(b0 + 1.5 * BEAT)
    for e in range(8):
        at = b0 + e * BEAT / 2
        accent = 0.55 if e % 2 == 0 else 1.0     # offbeats louder: the lo-fi lean
        hat(at, open_=(bar % 4 == 3 and e == 7), accent=accent)
write_loop('music_drums.wav', drums, peak=0.50)

# --- melody -----------------------------------------------------------------
melody = [0.0] * n_m
# One phrase per two bars, over the chord that is playing. Written as
# (beat offset, pentatonic degree, length in beats). The rests matter as much
# as the notes: a melody with no gaps in it is a texture, not a tune.
PHRASES = [
    [(0, 4, 1), (1, 5, 0.5), (1.5, 4, 0.5), (2.5, 2, 1), (4, 1, 1.5), (6, 2, 2)],
    [(0, 2, 1), (1.5, 4, 0.5), (2, 5, 1), (4, 7, 1), (5, 5, 0.5), (5.5, 4, 2.5)],
    [(0.5, 1, 1), (2, 2, 0.5), (2.5, 4, 1.5), (4, 5, 1), (6, 4, 0.5), (6.5, 2, 1.5)],
    [(0, 4, 0.5), (0.5, 5, 0.5), (1, 7, 1.5), (3, 5, 1), (4.5, 4, 1), (6, 0, 2)],
]
for ph_i, phrase in enumerate(PHRASES):
    t0 = ph_i * 2 * 4 * BEAT
    for (beat, deg, length) in phrase:
        f = PENTA[deg]
        p = gain(pluck(f, min(length * BEAT * 1.4, 2.2), damp=0.55,
                       seed=int(f * 3) % 977 + ph_i, sr=MUSIC_SR), 0.30)
        start = int((t0 + beat * BEAT) * MUSIC_SR)
        for k, v in enumerate(p):
            melody[(start + k) % n_m] += v
melody = reverb(melody, wet=0.30, decay=0.74, tail=0.0, sr=MUSIC_SR)[:n_m]
write_loop('music_melody.wav', melody, peak=0.42)

print('done')
