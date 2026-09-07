import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Rewarded video, and nothing else.
///
/// The deliberate limit here is the format. There is no banner and no
/// interstitial: every ad this game shows is one the player asked for by
/// tapping a button that says what they get. Nothing ever interrupts a board,
/// nothing plays between levels, and no ad can appear while a puzzle is on
/// screen. That is a product decision, not a technical one — an interstitial
/// after a clear is worth several times a rewarded view and costs exactly the
/// unhurried feel the rest of the game is built around.
///
/// Two rules of construction, both the same as [AudioService]:
///
/// * Nothing here may block or throw into the app. Ads are the least important
///   thing on the device — no failure to initialise, load, or show is allowed
///   to affect whether the game works.
/// * An ad is loaded *ahead* of being needed, because a spinner between the
///   tap and the video is the point most players change their mind.
class AdsService extends ChangeNotifier {
  // ---------------------------------------------------------------- ad units
  //
  // Two sets, and one switch between them.
  //
  // The test set below is Google's public demo publisher account. Every
  // developer uses that same id. It serves a real video so the flow can be
  // verified end to end, and it earns nothing — by design, and this is the
  // important part: testing against your *own* live units generates
  // impressions and clicks on your own ads, which AdMob classifies as invalid
  // traffic and permanently bans accounts for. Never point this at a live unit
  // on a device you tap ads on. Use [testDeviceIds] instead.
  static const String _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const String _testRewardedIOS = 'ca-app-pub-3940256099942544/1712485313';

  // >>> TO EARN REVENUE <<<
  //
  //  1. Create the app and a *rewarded* ad unit in your AdMob account.
  //  2. Paste the two unit ids here (format: ca-app-pub-<16 digits>/<10 digits>).
  //  3. Set [usingTestUnits] to false.
  //  4. Put your AdMob *application* ids — a different format, with a "~" —
  //     into android/app/src/main/AndroidManifest.xml and ios/Runner/Info.plist.
  //     The SDK reads those at process start, so a wrong value there is a
  //     crash on launch rather than a missing ad.
  //  5. Add your own phone to [testDeviceIds] so you can still exercise the
  //     shop without risking the account.
  static const String _liveRewardedAndroid = '';
  static const String _liveRewardedIOS = '';

  /// The switch. Kept as an explicit constant rather than a `kDebugMode` check
  /// so that shipping test ads is a visible line in a diff rather than an
  /// accident of build mode — a release built in the wrong mode would
  /// otherwise ship earning nothing and look completely normal.
  static const bool usingTestUnits = true;

  /// Devices that should always be served test ads, even in a live build.
  ///
  /// Get the id from the console on first run: the SDK logs
  /// "Use RequestConfiguration.Builder.setTestDeviceIds(["ABC123..."])".
  /// This is how you demo your own shipped game without generating invalid
  /// traffic against your own units.
  static const List<String> testDeviceIds = <String>[];

  static String get _rewardedUnitId {
    final bool iOS = defaultTargetPlatform == TargetPlatform.iOS;
    if (usingTestUnits) return iOS ? _testRewardedIOS : _testRewardedAndroid;

    final String live = iOS ? _liveRewardedIOS : _liveRewardedAndroid;
    assert(
      live.isNotEmpty,
      'usingTestUnits is false but no live rewarded unit id is set for '
      '$defaultTargetPlatform. Fill in _liveRewardedAndroid / _liveRewardedIOS.',
    );
    // Falling back rather than crashing a release build over a missed constant:
    // a player would rather see an ad that earns nothing than a broken shop.
    return live.isEmpty ? (iOS ? _testRewardedIOS : _testRewardedAndroid) : live;
  }

  RewardedAd? _ad;
  bool _loading = false;
  bool _initialised = false;

  /// Consecutive load failures, used to back off. A device with no
  /// connectivity should not spend the session retrying an ad request every
  /// few seconds.
  int _failures = 0;
  Timer? _retry;

  /// True when a video is loaded and [showRewarded] will open immediately.
  bool get isReady => _ad != null;

  /// True once the SDK came up. False on a device where it never did, which is
  /// the signal for the UI to hide its "watch an ad" affordances entirely
  /// rather than offer a button that cannot work.
  bool get isAvailable => _initialised;

  /// Brings up the SDK and preloads the first video. Bounded, and never throws.
  Future<void> init() async {
    if (_initialised) return;
    try {
      if (testDeviceIds.isNotEmpty) {
        await MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(testDeviceIds: testDeviceIds),
        );
      }
      await MobileAds.instance.initialize().timeout(const Duration(seconds: 10));

      if (usingTestUnits) {
        debugPrint(
          'Bubble Sort: serving TEST ads — these earn nothing. '
          'See AdsService.usingTestUnits.',
        );
      }
      _initialised = true;
      notifyListeners();
      unawaited(_load());
    } catch (e) {
      debugPrint('Bubble Sort ads unavailable, continuing without them: $e');
      _initialised = false;
    }
  }

  Future<void> _load() async {
    if (!_initialised || _loading || _ad != null) return;
    _loading = true;
    try {
      await RewardedAd.load(
        adUnitId: _rewardedUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) {
            _ad = ad;
            _loading = false;
            _failures = 0;
            notifyListeners();
          },
          onAdFailedToLoad: (LoadAdError error) {
            _loading = false;
            _failures++;
            debugPrint('Bubble Sort rewarded ad failed to load: $error');
            _scheduleRetry();
            notifyListeners();
          },
        ),
      );
    } catch (e) {
      _loading = false;
      _failures++;
      debugPrint('Bubble Sort rewarded ad load threw: $e');
      _scheduleRetry();
    }
  }

  /// Exponential back-off, capped at five minutes and given up on after six
  /// tries — at which point the affordance simply stays hidden for the rest of
  /// the session rather than the app hammering a network that is not there.
  void _scheduleRetry() {
    _retry?.cancel();
    if (_failures > 6) return;
    final Duration wait = Duration(seconds: math.min(300, 4 << _failures));
    _retry = Timer(wait, () => unawaited(_load()));
  }

  /// Shows the loaded video.
  ///
  /// Returns true only if the player actually earned the reward — dismissing
  /// early returns false, and the caller must grant nothing. The next video is
  /// preloaded on the way out either way.
  Future<bool> showRewarded() async {
    final RewardedAd? ad = _ad;
    if (ad == null) {
      unawaited(_load());
      return false;
    }

    // Detached from the field before showing, so a second tap during the
    // hand-off cannot show the same ad twice.
    _ad = null;
    notifyListeners();

    final Completer<bool> done = Completer<bool>();
    bool earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (RewardedAd a) {
        a.dispose();
        if (!done.isCompleted) done.complete(earned);
        unawaited(_load());
      },
      onAdFailedToShowFullScreenContent: (RewardedAd a, AdError e) {
        debugPrint('Bubble Sort rewarded ad failed to show: $e');
        a.dispose();
        if (!done.isCompleted) done.complete(false);
        unawaited(_load());
      },
    );

    try {
      await ad.show(onUserEarnedReward: (AdWithoutView _, RewardItem __) => earned = true);
    } catch (e) {
      debugPrint('Bubble Sort rewarded ad show threw: $e');
      if (!done.isCompleted) done.complete(false);
      unawaited(_load());
    }

    // A video the player never dismisses must not hang the caller forever.
    return done.future.timeout(const Duration(minutes: 5), onTimeout: () => earned);
  }

  @override
  void dispose() {
    _retry?.cancel();
    _ad?.dispose();
    _ad = null;
    super.dispose();
  }
}
