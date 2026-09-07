import 'package:flutter/services.dart';

import 'settings_service.dart';

/// A small vocabulary of touch responses, named by intent rather than by
/// platform primitive.
///
/// The rule this enforces: haptics confirm *state changes*, never ordinary
/// taps on ordinary controls. Buzzing on every touch is the fastest way to
/// make a game feel cheap — and the first thing players switch off.
class HapticService {
  HapticService(this._settings);

  final SettingsService _settings;

  bool get _on => _settings.haptics;

  /// Lightest tick — selecting a vessel, lifting a stack.
  void select() {
    if (_on) HapticFeedback.selectionClick();
  }

  /// A ball settling into place.
  void land() {
    if (_on) HapticFeedback.lightImpact();
  }

  /// A vessel sealing — the game's core reward beat.
  ///
  /// Three impacts rather than one, spaced to match the fracture: the strike,
  /// then two lighter taps as the cracks run and the shards land. A single
  /// mediumImpact is over before the animation has started and reads as a
  /// button press; the burst is felt as the glass giving way.
  ///
  /// This is the only place in the game that fires more than one impact, and
  /// that is the point — it is the moment the whole loop is built around, and
  /// it should be the one thing the hand can identify without looking.
  void seal() {
    if (!_on) return;
    HapticFeedback.heavyImpact();
    Future<void>.delayed(const Duration(milliseconds: 90), () {
      if (_on) HapticFeedback.lightImpact();
    });
    Future<void>.delayed(const Duration(milliseconds: 190), () {
      if (_on) HapticFeedback.lightImpact();
    });
  }

  /// A rejected pour. Soft on purpose: informative, not punishing.
  void reject() {
    if (_on) HapticFeedback.lightImpact();
  }

  /// Level cleared. A rising pair, so finishing a board is distinguishable by
  /// touch from finishing a single vessel.
  void celebrate() {
    if (!_on) return;
    HapticFeedback.mediumImpact();
    Future<void>.delayed(const Duration(milliseconds: 110), () {
      if (_on) HapticFeedback.heavyImpact();
    });
  }
}
