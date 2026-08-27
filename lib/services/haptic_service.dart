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
  void seal() {
    if (_on) HapticFeedback.mediumImpact();
  }

  /// A rejected pour. Soft on purpose: informative, not punishing.
  void reject() {
    if (_on) HapticFeedback.lightImpact();
  }

  /// Level cleared.
  void celebrate() {
    if (_on) HapticFeedback.heavyImpact();
  }
}
