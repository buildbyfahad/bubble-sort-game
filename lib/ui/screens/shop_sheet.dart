import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../services/wallet_service.dart';
import '../app_scope.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/surfaces.dart';

/// Where coins go.
///
/// Three bundles and two ways to earn, and that is the whole shop. There is no
/// real-money purchase path and no consumable that gates play: everything on
/// sale here is hints, which shorten a board the player could always have
/// solved unaided. A shop that sells progress turns a puzzle into a toll road.
///
/// The rewarded rows only appear when the ad SDK actually came up and has a
/// video loaded. An always-visible "watch an ad" button that does nothing when
/// tapped is worse than no button at all.
class ShopSheet extends StatefulWidget {
  const ShopSheet({super.key});

  @override
  State<ShopSheet> createState() => _ShopSheetState();
}

class _ShopSheetState extends State<ShopSheet> {
  /// Set while a video is on screen, so a second tap cannot open a second one.
  bool _watching = false;

  /// Item id that just failed for want of coins, for the shake.
  String? _rejected;

  Future<void> _buy(AppScope scope, ShopItem item) async {
    final bool paid = await scope.wallet.spendCoins(item.price);
    if (!mounted) return;

    if (!paid) {
      scope.audio.reject();
      scope.haptics.reject();
      setState(() => _rejected = item.id);
      return;
    }
    await scope.wallet.grantHints(item.hints);
    if (!mounted) return;
    scope.audio.star();
    scope.haptics.seal();
    setState(() => _rejected = null);
  }

  Future<void> _watch(AppScope scope, {required int coins, required int hints}) async {
    if (_watching) return;
    setState(() => _watching = true);
    scope.audio.tap();

    final bool earned = await scope.ads.showRewarded();
    if (!mounted) return;

    if (earned) {
      await scope.wallet.grantCoins(coins);
      await scope.wallet.grantHints(hints);
      if (!mounted) return;
      scope.audio.unlock();
      scope.haptics.celebrate();
    }
    setState(() => _watching = false);
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DS.s16),
          child: Observes(
            listenables: <Listenable>[scope.wallet, scope.ads],
            builder: (BuildContext context) {
              final WalletService w = scope.wallet;
              final bool adsUsable = scope.ads.isAvailable && scope.ads.isReady;

              return SoftCard(
                radius: DS.rXl,
                padding: const EdgeInsets.fromLTRB(DS.s24, DS.s20, DS.s24, DS.s24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(child: Text('Hints', style: Type.titleMd)),
                        _Balance(icon: DIcons.coin, value: w.coins, accent: DS.gold),
                        const SizedBox(width: DS.s12),
                        _Balance(icon: DIcons.hint, value: w.hints, accent: DS.aqua),
                        const SizedBox(width: DS.s8),
                        GhostIconButton(
                          icon: DIcons.close,
                          size: 38,
                          semanticLabel: 'Close',
                          onTap: () {
                            scope.audio.tap();
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: DS.s20),

                    for (final ShopItem item in ShopItem.all) ...<Widget>[
                      _ShopRow(
                        item: item,
                        affordable: w.coins >= item.price,
                        shake: _rejected == item.id,
                        onTap: () => _buy(scope, item),
                      ),
                      const SizedBox(height: DS.s8),
                    ],

                    if (adsUsable) ...<Widget>[
                      const SizedBox(height: DS.s12),
                      Row(
                        children: <Widget>[
                          Expanded(child: _Rule()),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: DS.s12),
                            child: _OrLabel(),
                          ),
                          Expanded(child: _Rule()),
                        ],
                      ),
                      const SizedBox(height: DS.s12),
                      _WatchRow(
                        label: _watching ? 'Loading…' : 'Watch a video',
                        detail: 'Earn 40 coins',
                        icon: DIcons.coin,
                        accent: DS.gold,
                        enabled: !_watching,
                        onTap: () => _watch(scope, coins: 40, hints: 0),
                      ),
                      const SizedBox(height: DS.s8),
                      _WatchRow(
                        label: _watching ? 'Loading…' : 'Watch a video',
                        detail: 'Earn one hint',
                        icon: DIcons.hint,
                        accent: DS.aqua,
                        enabled: !_watching,
                        onTap: () => _watch(scope, coins: 0, hints: 1),
                      ),
                    ],

                    const SizedBox(height: DS.s16),
                    Center(
                      child: Text(
                        'Coins come from clearing boards. '
                        'A flawless clear pays the most.',
                        textAlign: TextAlign.center,
                        style: Type.caption,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.icon, required this.value, required this.accent});

  final DIcons icon;
  final int value;
  final Color accent;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DIcon(icon, size: 15, color: accent),
          const SizedBox(width: DS.s4),
          Text('$value', style: Type.numeralSm.copyWith(fontSize: 15, color: accent)),
        ],
      );
}

/// One bundle. Shakes rather than greying out when it cannot be afforded —
/// a disabled row tells the player nothing about why.
class _ShopRow extends StatefulWidget {
  const _ShopRow({
    required this.item,
    required this.affordable,
    required this.shake,
    required this.onTap,
  });

  final ShopItem item;
  final bool affordable;
  final bool shake;
  final VoidCallback onTap;

  @override
  State<_ShopRow> createState() => _ShopRowState();
}

class _ShopRowState extends State<_ShopRow> with TickerProviderStateMixin, PressMixin {
  late final AnimationController _shake =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 320));

  @override
  void didUpdateWidget(_ShopRow old) {
    super.didUpdateWidget(old);
    if (widget.shake && !old.shake) _shake.forward(from: 0);
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.affordable ? DS.gold : DS.textTertiary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => pressDown(),
      onTapCancel: pressUp,
      onTapUp: (_) => pressUp(),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[press, _shake]),
        builder: (BuildContext context, _) {
          final double t = _shake.value;
          final double dx = t == 0
              ? 0
              : (1 - t) * (1 - t) * 9 * (t * 18).remainder(2) - (1 - t) * (1 - t) * 4.5;

          return Transform.translate(
            offset: Offset(dx, 0),
            child: Transform.scale(
              scale: 1 - press.value.clamp(0.0, 1.0) * 0.02,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DS.rMd),
                  color: const Color(0x08FFFFFF),
                  border: Border.all(
                    color: widget.affordable ? DS.hairlineStrong : DS.hairline,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    DIcon(DIcons.hint, size: 18, color: accent),
                    const SizedBox(width: DS.s16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(widget.item.label, style: Type.bodyStrong),
                          const SizedBox(height: 2),
                          Text(widget.item.detail, style: Type.caption),
                        ],
                      ),
                    ),
                    const SizedBox(width: DS.s12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DS.s12,
                        vertical: DS.s4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(DS.rPill),
                        color: accent.withValues(alpha: widget.affordable ? 0.12 : 0.06),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          DIcon(DIcons.coin, size: 12, color: accent),
                          const SizedBox(width: DS.s4),
                          Text(
                            '${widget.item.price}',
                            style: Type.numeralSm.copyWith(fontSize: 13, color: accent),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// An opt-in rewarded video. Never auto-plays; the player taps it knowing what
/// they get, and gets nothing if they close the video early.
class _WatchRow extends StatelessWidget {
  const _WatchRow({
    required this.label,
    required this.detail,
    required this.icon,
    required this.accent,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String detail;
  final DIcons icon;
  final Color accent;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: DS.s16, vertical: DS.s12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DS.rMd),
              color: accent.withValues(alpha: 0.07),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: <Widget>[
                DIcon(DIcons.play, size: 14, color: accent),
                const SizedBox(width: DS.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(label, style: Type.bodyStrong),
                      const SizedBox(height: 2),
                      Text(detail, style: Type.caption.copyWith(color: accent)),
                    ],
                  ),
                ),
                DIcon(icon, size: 16, color: accent),
              ],
            ),
          ),
        ),
      );
}

class _Rule extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: const Color(0xFFFFFFFF).withValues(alpha: 0.06));
}

class _OrLabel extends StatelessWidget {
  const _OrLabel();

  @override
  Widget build(BuildContext context) =>
      Text('OR EARN', style: Type.label.copyWith(letterSpacing: 1.4));
}
