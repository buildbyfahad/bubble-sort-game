import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/cosmetics.dart';

/// What the player owns and has equipped.
///
/// Ownership is a set of ids on disk; equipping is two ids on disk. Buying is
/// not here — the shop takes coins from the wallet and then calls [grant],
/// so this service never has to know what anything costs.
class CosmeticsService extends ChangeNotifier {
  CosmeticsService._(this._prefs);

  static const String _kOwned = 'cosmetics.owned';
  static const String _kBall = 'cosmetics.ball';
  static const String _kVessel = 'cosmetics.vessel';

  final SharedPreferences _prefs;

  static Future<CosmeticsService> load() async =>
      CosmeticsService._(await SharedPreferences.getInstance());

  Set<String> get owned => <String>{
        ...Cosmetic.all.where((Cosmetic c) => c.isFree).map((Cosmetic c) => c.id),
        ...?_prefs.getStringList(_kOwned),
      };

  bool owns(String id) => owned.contains(id);

  Cosmetic get ball => Cosmetic.byId(_prefs.getString(_kBall) ?? 'ball.classic');
  Cosmetic get vessel => Cosmetic.byId(_prefs.getString(_kVessel) ?? 'vessel.glass');

  BallStyle get ballStyle => ball.ball!;
  VesselStyle get vesselStyle => vessel.vessel!;

  Future<void> grant(String id) async {
    final Set<String> next = owned..add(id);
    await _prefs.setStringList(_kOwned, next.toList());
    notifyListeners();
  }

  /// Equips an owned item. Refuses one the player does not have.
  Future<bool> equip(String id) async {
    if (!owns(id)) return false;
    final Cosmetic c = Cosmetic.byId(id);
    await _prefs.setString(c.kind == CosmeticKind.ball ? _kBall : _kVessel, id);
    notifyListeners();
    return true;
  }

  Future<void> resetAll() async {
    await _prefs.remove(_kOwned);
    await _prefs.remove(_kBall);
    await _prefs.remove(_kVessel);
    notifyListeners();
  }
}
