import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'settings_service.dart';

/// Playback for the cue set synthesised by `tools/gen_audio.py`.
///
/// The design goal here is latency, because audio latency is felt as *input*
/// latency: a cue that arrives 120ms after the finger is indistinguishable, to
/// the player, from a game that responded 120ms late.
///
/// So nothing is prepared at play time. Every cue owns a player whose source
/// was set once during [init] — the expensive part, a file copy out of the
/// asset bundle plus a native prepare — and firing a cue is then just a seek
/// and a resume. The previous implementation called `stop`, `setVolume`,
/// `setSource` and `resume` on every single tap, which is four platform
/// round-trips per sound on the UI isolate's channel.
///
/// Two further rules:
///
/// * Nothing here is ever awaited by a caller. Every method returns `void` and
///   swallows its own failures. A cue that fails to load, a device with the
///   audio focus taken, a simulator with no output — none of it may be able to
///   affect whether the board responds to a tap.
/// * Cues that can overlap ([land], [seal]) hold a small ring of players, so a
///   ball landing while a vessel seals never cuts the other one off.
class AudioService {
  AudioService(this._settings);

  final SettingsService _settings;

  /// Every cue in `assets/audio`, and how many simultaneous voices it needs.
  ///
  /// The counts are the point: interface cues fire one at a time and need one
  /// voice each, while board cues arrive in overlapping runs. Giving `drop`
  /// four voices is what lets a four-ball pour sound like four balls.
  static const Map<String, int> _cues = <String, int>{
    'tap': 1,
    'whoosh': 1,
    'tick': 2,
    'star': 2,
    'unlock': 1,
    'lift': 2,
    'drop_1': 1,
    'drop_2': 1,
    'drop_3': 1,
    'drop_4': 1,
    'invalid': 1,
    'complete_1': 1,
    'complete_2': 1,
    'complete_3': 1,
    'complete_4': 1,
    'complete_5': 1,
    'complete_6': 1,
    'complete_7': 1,
    'complete_8': 1,
    'win': 1,
    'boss_win': 1,
  };

  /// The score, as stems. See `tools/gen_audio.py` for why it is four loops
  /// and not one: the game decides how many are audible.
  static const List<String> _stems = <String>['pad', 'bass', 'drums', 'melody'];

  /// Full-mix level of each stem. Balanced by ear against the board cues so
  /// that at full intensity the music sits under a landing plop, never over.
  static const Map<String, double> _stemLevel = <String, double>{
    'pad': 0.34,
    'bass': 0.40,
    'drums': 0.30,
    'melody': 0.52,
  };

  /// Intensity at which each stem comes in. Pad is always on; the rest arrive
  /// in order as [setMusicIntensity] rises — bass early, drums when the board
  /// is well under way, melody as the reward for the home stretch.
  static const Map<String, double> _stemThreshold = <String, double>{
    'pad': 0.0,
    'bass': 0.12,
    'drums': 0.40,
    'melody': 0.65,
  };

  final Map<String, _Voices> _voices = <String, _Voices>{};
  final Map<String, AudioPlayer> _music = <String, AudioPlayer>{};

  bool _ready = false;
  bool _musicReady = false;
  bool _musicPlaying = false;
  bool _suspended = false;

  /// 0 = menu (pad only) … 1 = every stem. Set by whatever screen is up.
  double _intensity = 0.0;

  /// Prepares every player. Bounded and never allowed to throw.
  ///
  /// Audio is a garnish, not a dependency — an audio stack that is slow,
  /// missing or simply never answers must not be able to hold the game on its
  /// splash screen, which is exactly what an unbounded await here would do.
  Future<void> init() async {
    if (_ready) return;
    try {
      await Future<void>(() async {
        // Ambient, so the game mixes politely: it honours the hardware mute
        // switch and does not stop whatever the player already had playing.
        // A puzzle game that kills someone's podcast gets uninstalled.
        await AudioPlayer.global.setAudioContext(
          AudioContext(
            // `ambient` already mixes with other apps and already honours the
            // hardware mute switch, which is exactly the policy wanted here.
            // Setting `mixWithOthers` on top of it is not merely redundant —
            // audioplayers asserts against it, and the whole audio stack then
            // fails to initialise and the game runs silent.
            iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
            android: const AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: false,
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.game,
              audioFocus: AndroidAudioFocus.none,
            ),
          ),
        );

        // Copy every asset out of the bundle up front, in parallel.
        await AudioCache.instance.loadAll(<String>[
          for (final String c in _cues.keys) 'audio/$c.wav',
          for (final String m in _stems) 'audio/music_$m.wav',
        ]);

        await Future.wait<void>(<Future<void>>[
          for (final MapEntry<String, int> e in _cues.entries) _prepare(e.key, e.value),
        ]);
      }).timeout(const Duration(seconds: 8));
      _ready = _voices.isNotEmpty;
    } catch (e) {
      debugPrint('Bubble Sort audio unavailable, continuing silently: $e');
      _ready = false;
    }
  }

  Future<void> _prepare(String cue, int count) async {
    final List<AudioPlayer> players = <AudioPlayer>[];
    for (int i = 0; i < count; i++) {
      final AudioPlayer p = AudioPlayer(playerId: 'bubblesort_${cue}_$i');
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setPlayerMode(PlayerMode.lowLatency);
      await p.setSource(AssetSource('audio/$cue.wav'));
      players.add(p);
    }
    _voices[cue] = _Voices(players);
  }

  // ------------------------------------------------------------------- fire

  /// Fires [cue]. Returns immediately; the work happens on a detached future.
  void _play(String cue, {double volume = 1.0}) {
    if (!_ready || !_settings.sound || _suspended) return;
    final _Voices? v = _voices[cue];
    if (v == null) return;
    unawaited(_fire(v.next(), cue, volume));
  }

  Future<void> _fire(AudioPlayer p, String cue, double volume) async {
    try {
      await p.setVolume(volume);
      // Rewind rather than re-prepare. On Android's SoundPool backend a seek to
      // zero is special-cased to a restart, and on iOS it is a property set —
      // both are an order of magnitude cheaper than setting the source again.
      await p.seek(Duration.zero);
      await p.resume();
    } catch (_) {
      // Any platform that dislikes the fast path falls back to the slow one
      // rather than going silent for the rest of the session.
      try {
        await p.play(AssetSource('audio/$cue.wav'), volume: volume);
      } catch (_) {
        // A dropped cue is not worth interrupting play for.
      }
    }
  }

  // ---------------------------------------------------------------- the cues

  void tap() => _play('tap', volume: 0.55);
  void whoosh() => _play('whoosh', volume: 0.42);
  void lift() => _play('lift', volume: 0.62);
  void reject() => _play('invalid', volume: 0.6);
  void tick() => _play('tick', volume: 0.5);
  void star() => _play('star', volume: 0.7);
  void unlock() => _play('unlock', volume: 0.75);
  void win() => _play('win', volume: 0.9);

  /// The chapter finale. Bigger than [win], and distinct from it — the one
  /// clear in forty that should not sound like the other thirty-nine.
  void bossWin() => _play('boss_win', volume: 0.95);

  /// A ball settling. [indexInRun] is its position within the pour, 0-based —
  /// successive balls step up the scale so a four-ball pour lands as a phrase
  /// rather than as the same plop four times.
  void land([int indexInRun = 0]) =>
      _play('drop_${(indexInRun % 4) + 1}', volume: 0.72 + (indexInRun % 4) * 0.04);

  /// A vessel sealing. [index] is the count sealed so far, 1-based, and walks
  /// up a pentatonic scale so clearing a board is a rising phrase.
  void seal(int index) => _play('complete_${index.clamp(1, 8)}', volume: 0.8);

  // --------------------------------------------------------------- the score

  /// Starts the stems, if the player wants music. Safe to call repeatedly.
  void startMusic() {
    if (!_settings.music || _suspended) return;
    unawaited(_startMusic());
  }

  Future<void> _startMusic() async {
    try {
      if (_music.isEmpty) {
        for (final String m in _stems) {
          final AudioPlayer p = AudioPlayer(playerId: 'bubblesort_music_$m');
          await p.setReleaseMode(ReleaseMode.loop);
          await p.setVolume(0);
          await p.setSource(AssetSource('audio/music_$m.wav'));
          _music[m] = p;
        }
        _musicReady = true;
      }
      if (!_musicReady || _musicPlaying) return;

      // All four started back to back with nothing awaited between them, so
      // they begin as close to together as the platform allows. The rhythm is
      // one file, so the only thing that can drift is a pad against a pluck,
      // which is inaudible at the offsets involved.
      _musicPlaying = true;
      await Future.wait<void>(<Future<void>>[
        for (final AudioPlayer p in _music.values) p.resume(),
      ]);
      await _applyIntensity(fade: true);
    } catch (e) {
      debugPrint('Bubble Sort music unavailable: $e');
      _musicReady = false;
      _musicPlaying = false;
    }
  }

  /// How much of the score is playing. The board sets this to the fraction
  /// of vessels sealed; the menu sets it to zero.
  void setMusicIntensity(double v) {
    final double clamped = v.clamp(0.0, 1.0);
    if ((clamped - _intensity).abs() < 0.001) return;
    _intensity = clamped;
    if (_musicPlaying) unawaited(_applyIntensity(fade: true));
  }

  /// Rewinds every stem to the top together. Called on entering a board, so
  /// any drift the platform has accumulated is thrown away at the one moment
  /// the player is not listening closely — the level transition.
  void resyncMusic() {
    if (!_musicPlaying) return;
    unawaited(Future.wait<void>(<Future<void>>[
      for (final AudioPlayer p in _music.values) p.seek(Duration.zero),
    ]).catchError((Object _) => <void>[]));
  }

  Future<void> _applyIntensity({required bool fade}) async {
    final List<Future<void>> ramps = <Future<void>>[];
    for (final String m in _stems) {
      final AudioPlayer? p = _music[m];
      if (p == null) continue;
      final double threshold = _stemThreshold[m]!;
      // Each stem fades in across a short band above its threshold rather
      // than switching on, so a seal brings the bass *up* instead of in.
      final double presence = threshold == 0
          ? 1.0
          : ((_intensity - threshold) / 0.18).clamp(0.0, 1.0);
      final double target = _stemLevel[m]! * presence;
      ramps.add(fade ? _rampTo(p, target) : p.setVolume(target));
    }
    await Future.wait(ramps);
  }

  void stopMusic() => unawaited(_stopMusic());

  Future<void> _stopMusic() async {
    if (!_musicPlaying) return;
    try {
      await Future.wait<void>(<Future<void>>[
        for (final AudioPlayer p in _music.values) _rampTo(p, 0),
      ]);
      await Future.wait<void>(<Future<void>>[
        for (final AudioPlayer p in _music.values) p.pause(),
      ]);
    } catch (_) {
      // Nothing to recover; the track is already effectively off.
    }
    _musicPlaying = false;
  }

  /// A hard cut into or out of a loop is audible and cheap-sounding, so every
  /// change of level is ramped over a handful of frames.
  Future<void> _rampTo(AudioPlayer p, double to, {int steps = 10}) async {
    final double from = p.volume;
    if ((to - from).abs() < 0.005) return;
    for (int i = 1; i <= steps; i++) {
      await p.setVolume(from + (to - from) * (i / steps));
      await Future<void>.delayed(const Duration(milliseconds: 22));
    }
  }

  /// Called when the player flips the music switch.
  void syncMusic() => _settings.music ? startMusic() : stopMusic();

  // ------------------------------------------------------------- lifecycle

  /// Backgrounding. Everything goes quiet and stays quiet until [resumeAll].
  void suspend() {
    if (_suspended) return;
    _suspended = true;
    for (final AudioPlayer p in _music.values) {
      unawaited(p.pause());
    }
    _musicPlaying = false;
  }

  void resumeAll() {
    if (!_suspended) return;
    _suspended = false;
    syncMusic();
  }

  Future<void> dispose() async {
    for (final _Voices v in _voices.values) {
      for (final AudioPlayer p in v.players) {
        await p.dispose();
      }
    }
    _voices.clear();
    for (final AudioPlayer p in _music.values) {
      await p.dispose();
    }
    _music.clear();
    _ready = false;
    _musicReady = false;
  }
}

/// A ring of interchangeable players for one cue.
class _Voices {
  _Voices(this.players);

  final List<AudioPlayer> players;
  int _i = 0;

  AudioPlayer next() {
    final AudioPlayer p = players[_i];
    _i = (_i + 1) % players.length;
    return p;
  }
}
