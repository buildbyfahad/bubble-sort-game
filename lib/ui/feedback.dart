import 'package:flutter/widgets.dart';

import 'app_scope.dart';

/// The game's interaction vocabulary, in one place.
///
/// Feedback used to be attached at call sites: a screen that pushed a route
/// remembered to play a whoosh, and one that did not, did not. An audit found
/// `buttons.dart` carrying twenty-eight tap handlers and zero cues — every
/// button in the game was silent unless whoever used it thought to add a
/// sound. That is precisely why it felt arbitrary: the same control made a
/// noise on one screen and none on the next.
///
/// So the components fire their own, through this. The rule is now
/// structural rather than remembered: **if it is the same kind of action, it
/// makes the same sound and the same vibration, everywhere, always.**
///
/// Every method no-ops when there is no [AppScope] above — a button in a
/// golden test stays silent instead of throwing.
abstract final class Fx {
  // ------------------------------------------------------------- controls

  /// The main action on a screen: PLAY, CLAIM, NEXT LEVEL.
  static void press(BuildContext context) {
    final AppScope? s = AppScope.maybeOf(context);
    s?.audio.press();
    s?.haptics.press();
  }

  /// Any secondary control: icon buttons, dock buttons, text actions, rows.
  static void tap(BuildContext context) {
    final AppScope? s = AppScope.maybeOf(context);
    s?.audio.tap();
    s?.haptics.select();
  }

  /// A switch changing state. Two pitches so on and off are distinguishable
  /// without looking.
  static void toggle(BuildContext context, {required bool on}) {
    final AppScope? s = AppScope.maybeOf(context);
    on ? s?.audio.toggleOn() : s?.audio.toggleOff();
    s?.haptics.select();
  }

  /// Moving between screens.
  static void navigate(BuildContext context) {
    final AppScope? s = AppScope.maybeOf(context);
    s?.audio.whoosh();
    s?.haptics.select();
  }

  /// A control that refused: locked level, unaffordable item, illegal tap.
  static void refuse(BuildContext context) {
    final AppScope? s = AppScope.maybeOf(context);
    s?.audio.reject();
    s?.haptics.reject();
  }

  /// One coin arriving in the balance during a payout flight. Deliberately
  /// the lightest thing in the vocabulary — a dozen of these fire in half a
  /// second, and anything heavier becomes a machine gun.
  static void coinLand(BuildContext context) {
    final AppScope? s = AppScope.maybeOf(context);
    s?.audio.tick();
    s?.haptics.select();
  }

  // -------------------------------------------------------------- rewards

  /// Something was bought or earned.
  static void reward(BuildContext context) {
    final AppScope? s = AppScope.maybeOf(context);
    s?.audio.star();
    s?.haptics.seal();
  }

  /// Something was unlocked — a daily claim, a cosmetic, a chapter.
  static void unlock(BuildContext context) {
    final AppScope? s = AppScope.maybeOf(context);
    s?.audio.unlock();
    s?.haptics.celebrate();
  }
}
