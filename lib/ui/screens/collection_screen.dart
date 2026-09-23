import 'package:flutter/widgets.dart';

import '../../data/cosmetics.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../app_scope.dart';
import '../feedback.dart';
import '../widgets/ambient_background.dart';
import '../widgets/bubble.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/tube.dart';

/// What the player owns, and what they could.
///
/// This is where the economy gets a *want*. Hints are a consolation; nobody
/// looks forward to buying one. A marble set you cannot afford yet is a reason
/// to clear three more boards, and a vessel that only comes from finishing
/// chapter five is a reason to finish chapter five.
///
/// Every card is a live preview using the real renderers, so what is on
/// sale is exactly what will be on the board. A screenshot of a cosmetic is
/// how a collection screen starts lying about its contents.
class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppScope scope = AppScope.of(context);

    return AmbientBackground(
      intensity: 0.8,
      child: SafeArea(
        child: Observes(
          listenables: <Listenable>[scope.cosmetics, scope.wallet, scope.progress],
          builder: (BuildContext context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(DS.s16, DS.s8, DS.s16, DS.s12),
                child: Row(
                  children: <Widget>[
                    GhostIconButton(
                      icon: DIcons.back,
                      semanticLabel: 'Back',
                      onTap: () {
                        Navigator.of(context).pop();
                      },
                    ),
                    Expanded(
                      child: Column(
                        children: <Widget>[
                          Text('COLLECTION', style: Type.labelBright),
                          const SizedBox(height: DS.s4),
                          Text(
                            '${scope.cosmetics.owned.length} of ${Cosmetic.all.length} owned',
                            style: Type.caption.copyWith(color: DS.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    StickerPill(
                      icon: DIcons.coin,
                      value: '${scope.wallet.coins}',
                      accent: DS.gold,
                      deep: DS.goldDeep,
                      semanticLabel: 'Coins',
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(DS.s16, 0, DS.s16, DS.s32),
                  children: <Widget>[
                    _SectionLabel('BALLS'),
                    _Grid(
                      items: Cosmetic.balls.toList(),
                      scope: scope,
                    ),
                    const SizedBox(height: DS.s24),
                    _SectionLabel('VESSELS'),
                    _Grid(
                      items: Cosmetic.vessels.toList(),
                      scope: scope,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(DS.s4, 0, 0, DS.s12),
        child: Text(text, style: Type.label.copyWith(color: DS.textPrimary)),
      );
}

class _Grid extends StatelessWidget {
  const _Grid({required this.items, required this.scope});

  final List<Cosmetic> items;
  final AppScope scope;

  @override
  Widget build(BuildContext context) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: DS.s12,
          crossAxisSpacing: DS.s12,
          childAspectRatio: 0.86,
        ),
        itemCount: items.length,
        itemBuilder: (BuildContext context, int i) => _Card(item: items[i], scope: scope),
      );
}

class _Card extends StatefulWidget {
  const _Card({required this.item, required this.scope});

  final Cosmetic item;
  final AppScope scope;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> with TickerProviderStateMixin, PressMixin {
  bool _shake = false;

  Future<void> _tap() async {
    final AppScope scope = widget.scope;
    final Cosmetic item = widget.item;

    if (scope.cosmetics.owns(item.id)) {
      Fx.tap(context);
      await scope.cosmetics.equip(item.id);
      return;
    }
    if (item.isChapterReward) {
      // Not for sale. The refusal is informative rather than punishing: the
      // card already says which chapter earns it.
      Fx.refuse(context);
      return;
    }
    final bool paid = await scope.wallet.spendCoins(item.price);
    if (!mounted) return;
    if (!paid) {
      Fx.refuse(context);
      setState(() => _shake = !_shake);
      return;
    }
    await scope.cosmetics.grant(item.id);
    await scope.cosmetics.equip(item.id);
    if (!mounted) return;
    Fx.unlock(context);
  }

  @override
  Widget build(BuildContext context) {
    final AppScope scope = widget.scope;
    final Cosmetic item = widget.item;
    final bool owned = scope.cosmetics.owns(item.id);
    final bool equipped = owned &&
        (item.kind == CosmeticKind.ball
            ? scope.cosmetics.ball.id == item.id
            : scope.cosmetics.vessel.id == item.id);
    final bool affordable = !owned && !item.isChapterReward && scope.wallet.coins >= item.price;
    final bool chapterDone = item.unlockChapter != null &&
        scope.progress.isCleared(scope.catalog.chapterByNumber(item.unlockChapter!).to);

    // Three states, three constructions — not one construction at three
    // opacities. Equipped is a gold-outlined sticker that glows; owned is the
    // same sticker in the neutral outline; locked loses the bevel entirely and
    // becomes a recess, so it reads as *not an object you can pick up* before
    // any of its text is read.
    final Color edge = equipped ? DS.gold : DS.outline;
    final bool solid = owned || affordable;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => pressDown(),
      onTapCancel: pressUp,
      onTapUp: (_) => pressUp(),
      onTap: _tap,
      child: AnimatedBuilder(
        animation: press,
        builder: (BuildContext context, _) => Transform.scale(
          scale: 1 - press.value.clamp(0.0, 1.0) * 0.04,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DS.rMd + 2),
              color: equipped ? DS.goldDeep : DS.outline,
              border: Border.all(color: edge, width: DS.stroke),
              boxShadow: equipped
                  ? DS.glow(DS.goldDeep, opacity: 0.28, blur: 24, y: 8)
                  : (solid ? DS.e1 : null),
            ),
            padding: EdgeInsets.only(bottom: solid ? DS.bevel : 0),
            child: Container(
            padding: const EdgeInsets.all(DS.s12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DS.rMd),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: solid
                    ? const <Color>[DS.surfaceRaised, DS.surface]
                    : const <Color>[DS.inkDeep, DS.inkDeep],
              ),
            ),
            child: Column(
              children: <Widget>[
                Expanded(child: Center(child: _Preview(item: item, scope: scope))),
                const SizedBox(height: DS.s8),
                Text(item.name, style: Type.bodyStrong.copyWith(fontSize: 14, color: DS.textPrimary)),
                const SizedBox(height: 2),
                Text(item.blurb, style: Type.caption.copyWith(fontSize: 11.5)),
                const SizedBox(height: DS.s8),
                _Status(
                  item: item,
                  owned: owned,
                  equipped: equipped,
                  affordable: affordable,
                  chapterDone: chapterDone,
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The item itself, drawn by the same code the board uses.
class _Preview extends StatelessWidget {
  const _Preview({required this.item, required this.scope});

  final Cosmetic item;
  final AppScope scope;

  @override
  Widget build(BuildContext context) {
    if (item.kind == CosmeticKind.ball) {
      // Three of the palette, so a look's treatment of light and dark hues
      // is both visible.
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final int h in <int>[0, 4, 3]) ...<Widget>[
            Bubble(hue: DS.hues[h], size: 30, style: item.ball!),
            const SizedBox(width: DS.s4),
          ],
        ],
      );
    }
    // A vessel holding three balls in the player's current ball look.
    return Tube(
      contents: const <int>[1, 5, 0],
      metrics: const TubeMetrics(22, 4),
      selected: false,
      liftCount: 0,
      sealed: false,
      colorAssist: false,
      rejectToken: -1,
      settleToken: -1,
      settleCount: 0,
      sealToken: -1,
      hinted: false,
      dim: 0,
      onTap: () {},
      ballStyle: scope.cosmetics.ballStyle,
      skin: item.vessel!,
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.item,
    required this.owned,
    required this.equipped,
    required this.affordable,
    required this.chapterDone,
  });

  final Cosmetic item;
  final bool owned;
  final bool equipped;
  final bool affordable;
  final bool chapterDone;

  @override
  Widget build(BuildContext context) {
    if (equipped) return _pill('EQUIPPED', DS.gold, icon: DIcons.check);
    if (owned) return _pill('TAP TO EQUIP', DS.aqua);

    if (item.isChapterReward) {
      return _pill(
        chapterDone ? 'CHAPTER ${item.unlockChapter}' : 'FINISH CHAPTER ${item.unlockChapter}',
        DS.textTertiary,
        icon: DIcons.lock,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DIcon(DIcons.coin, size: 12, color: affordable ? DS.gold : DS.textTertiary),
        const SizedBox(width: DS.s4),
        Text(
          '${item.price}',
          style: Type.numeralSm.copyWith(
            fontSize: 13,
            color: affordable ? DS.gold : DS.textTertiary,
          ),
        ),
      ],
    );
  }

  Widget _pill(String text, Color c, {DIcons? icon}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[DIcon(icon, size: 10, color: c), const SizedBox(width: DS.s4)],
          Text(text, style: Type.label.copyWith(color: c, fontSize: 9.5, letterSpacing: 1.2)),
        ],
      );
}
