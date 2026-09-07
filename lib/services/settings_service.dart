import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Player-facing preferences. Deliberately short — four switches, no menu
/// tree. Every preference is stored locally and there is no account. The only
/// network traffic the app makes at all is the rewarded-video request, and
/// that happens solely when a player taps a button asking for one.
class SettingsService extends ChangeNotifier {
  SettingsService._(this._prefs)
      : _sound = _prefs.getBool(_kSound) ?? true,
        _music = _prefs.getBool(_kMusic) ?? true,
        _haptics = _prefs.getBool(_kHaptics) ?? true,
        _colorAssist = _prefs.getBool(_kColorAssist) ?? false;

  static const String _kSound = 'settings.sound';
  static const String _kMusic = 'settings.music';
  static const String _kHaptics = 'settings.haptics';
  static const String _kColorAssist = 'settings.colorAssist';

  final SharedPreferences _prefs;

  bool _sound;
  bool _music;
  bool _haptics;
  bool _colorAssist;

  bool get sound => _sound;

  /// The ambient loop. Split from [sound] on purpose: a great many players
  /// want the board's cues and not a score, and forcing that choice through
  /// one switch means they turn everything off.
  bool get music => _music;

  bool get haptics => _haptics;

  /// Draws a faint shape marker inside each ball so hue is never the only
  /// thing distinguishing one stack from another.
  bool get colorAssist => _colorAssist;

  static Future<SettingsService> load() async =>
      SettingsService._(await SharedPreferences.getInstance());

  void setSound(bool v) {
    _sound = v;
    _prefs.setBool(_kSound, v);
    notifyListeners();
  }

  void setMusic(bool v) {
    _music = v;
    _prefs.setBool(_kMusic, v);
    notifyListeners();
  }

  void setHaptics(bool v) {
    _haptics = v;
    _prefs.setBool(_kHaptics, v);
    notifyListeners();
  }

  void setColorAssist(bool v) {
    _colorAssist = v;
    _prefs.setBool(_kColorAssist, v);
    notifyListeners();
  }
}
