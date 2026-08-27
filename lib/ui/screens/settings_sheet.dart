import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../app_scope.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/surfaces.dart';
import '../widgets/switch.dart';

/// Four switches and one destructive action.
///
/// Every option here is something a player might genuinely want to change
/// while playing on a train. There is no volume slider, no graphics quality,
/// no language picker — an options screen that needs scrolling is a sign the
/// product has not decided what it is.
class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  /// Wiping progress is the one irreversible action in the game, so it asks
  /// twice — in place, on the same control, rather than through a dialog.
  bool _confirmingReset = false;
  Timer? _confirmTimer;

  @override
  void dispose() {
    _confirmTimer?.cancel();
    super.dispose();
  }

  void _armReset(AppScope scope) {
    scope.haptics.reject();
    setState(() => _confirmingReset = true);
    _confirmTimer?.cancel();
    _confirmTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _confirmingReset = false);
    });
  }

  Future<void> _doReset(AppScope scope) async {
    _confirmTimer?.cancel();
    setState(() => _confirmingReset = false);
    scope.haptics.seal();
    await scope.progress.resetAll();
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
            listenables: <Listenable>[scope.settings, scope.progress],
            builder: (BuildContext context) => SoftCard(
              radius: DS.rXl,
              padding: const EdgeInsets.fromLTRB(DS.s24, DS.s20, DS.s24, DS.s24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(child: Text('Settings', style: Type.titleMd)),
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
                  _Row(
                    icon: scope.settings.sound ? DIcons.sound : DIcons.mute,
                    title: 'Sound effects',
                    subtitle: 'Pour, settle and completion cues',
                    value: scope.settings.sound,
                    onChanged: (bool v) {
                      scope.settings.setSound(v);
                      if (v) scope.audio.tap();
                    },
                  ),
                  const _Divider(),
                  _Row(
                    icon: DIcons.music,
                    title: 'Music',
                    subtitle: 'A quiet loop under the board',
                    value: scope.settings.music,
                    accent: DS.aqua,
                    onChanged: (bool v) {
                      scope.settings.setMusic(v);
                      // Applied immediately rather than on close, so the switch
                      // is auditioned by the thing it controls.
                      scope.audio.syncMusic();
                    },
                  ),
                  const _Divider(),
                  _Row(
                    icon: DIcons.vibrate,
                    title: 'Haptics',
                    subtitle: 'Touch feedback on key moments',
                    value: scope.settings.haptics,
                    onChanged: (bool v) {
                      scope.settings.setHaptics(v);
                      if (v) scope.haptics.select();
                    },
                  ),
                  const _Divider(),
                  _Row(
                    icon: DIcons.eye,
                    title: 'Colour assist',
                    subtitle: 'A shape marker on every colour',
                    value: scope.settings.colorAssist,
                    accent: DS.aqua,
                    onChanged: scope.settings.setColorAssist,
                  ),
                  const SizedBox(height: DS.s24),
                  Center(
                    child: TextAction(
                      icon: _confirmingReset ? DIcons.check : DIcons.restart,
                      label: _confirmingReset
                          ? 'Tap again to erase everything'
                          : 'Reset all progress',
                      onTap: () =>
                          _confirmingReset ? _doReset(scope) : _armReset(scope),
                    ),
                  ),
                  const SizedBox(height: DS.s12),
                  Center(
                    child: Text(
                      'Bubble Sort · ${scope.catalog.length} levels · v1.0',
                      style: Type.caption.copyWith(color: DS.textTertiary.withValues(alpha: 0.7)),
                    ),
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

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.accent = DS.gold,
  });

  final DIcons icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: DS.s12),
          child: Row(
            children: <Widget>[
              DIcon(icon, size: 20, color: value ? accent : DS.textTertiary),
              const SizedBox(width: DS.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Type.bodyStrong),
                    const SizedBox(height: 2),
                    Text(subtitle, style: Type.caption),
                  ],
                ),
              ),
              const SizedBox(width: DS.s12),
              DSwitch(value: value, onChanged: onChanged, accent: accent),
            ],
          ),
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: const Color(0xFFFFFFFF).withValues(alpha: 0.045));
}
