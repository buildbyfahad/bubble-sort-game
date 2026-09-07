import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The icon set, drawn rather than imported.
///
/// A stock icon font is the fastest way to make a game look like a business
/// app: the shapes come from someone else's system, at someone else's optical
/// weight. These are all built on one grid with one stroke width, round caps
/// and round joins, so they read as a family and match the rounded geometry of
/// the vessels and buttons.
enum DIcons { back, settings, undo, hint, restart, close, next, lock, check, sound, mute, grid, map, music, vibrate, eye, coin, flame, play }

class DIcon extends StatelessWidget {
  const DIcon(this.icon, {super.key, this.size = 22, this.color = const Color(0xFFF2F4F8), this.weight = 1.9});

  final DIcons icon;
  final double size;
  final Color color;

  /// Stroke width on the icon's own 24-unit grid, so weight stays optically
  /// constant as the icon scales.
  final double weight;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _IconPainter(icon, color, weight)),
      );
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color, this.weight);

  final DIcons icon;
  final Color color;
  final double weight;

  @override
  void paint(Canvas canvas, Size size) {
    final double u = size.width / 24; // one grid unit
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = weight * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint fill = Paint()..color = color;

    Offset p(double x, double y) => Offset(x * u, y * u);
    final Path path = Path();

    switch (icon) {
      case DIcons.back:
        path
          ..moveTo(15 * u, 5 * u)
          ..lineTo(8 * u, 12 * u)
          ..lineTo(15 * u, 19 * u);
        canvas.drawPath(path, stroke);

      case DIcons.next:
        path
          ..moveTo(9 * u, 5 * u)
          ..lineTo(16 * u, 12 * u)
          ..lineTo(9 * u, 19 * u);
        canvas.drawPath(path, stroke);

      case DIcons.settings:
        // Two sliders rather than a cog — a cog reads as "system settings",
        // and this game's options are preferences, not configuration.
        canvas.drawLine(p(4, 8.5), p(20, 8.5), stroke);
        canvas.drawLine(p(4, 15.5), p(20, 15.5), stroke);
        canvas.drawCircle(p(9, 8.5), 2.6 * u, Paint()..color = color);
        canvas.drawCircle(p(15, 15.5), 2.6 * u, Paint()..color = color);

      case DIcons.undo:
        path
          ..moveTo(8 * u, 8 * u)
          ..lineTo(4 * u, 12 * u)
          ..lineTo(8 * u, 16 * u);
        canvas.drawPath(path, stroke);
        canvas.drawPath(
          Path()
            ..moveTo(4 * u, 12 * u)
            ..lineTo(14 * u, 12 * u)
            ..arcToPoint(p(14, 20), radius: Radius.circular(4 * u), clockwise: true)
            ..lineTo(10 * u, 20 * u),
          stroke,
        );

      case DIcons.restart:
        // An open circle with an arrowhead — deliberately not a closed loop,
        // so it never reads as "loading".
        canvas.drawArc(
          Rect.fromCircle(center: p(12, 12), radius: 7.5 * u),
          -math.pi * 0.35,
          math.pi * 1.62,
          false,
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(14.4 * u, 3.4 * u)
            ..lineTo(18.4 * u, 5.6 * u)
            ..lineTo(15.6 * u, 9.2 * u),
          stroke,
        );

      case DIcons.hint:
        // A four-point sparkle. Suggests insight without a lightbulb cliché.
        _sparkle(canvas, p(11, 11), 8.2 * u, fill);
        _sparkle(canvas, p(18.5, 18), 3.6 * u, Paint()..color = color.withValues(alpha: color.a * 0.7));

      case DIcons.close:
        canvas.drawLine(p(6.5, 6.5), p(17.5, 17.5), stroke);
        canvas.drawLine(p(17.5, 6.5), p(6.5, 17.5), stroke);

      case DIcons.check:
        canvas.drawPath(
          Path()
            ..moveTo(5.5 * u, 12.5 * u)
            ..lineTo(10 * u, 17 * u)
            ..lineTo(18.5 * u, 7.5 * u),
          stroke,
        );

      case DIcons.lock:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(5.5 * u, 10.5 * u, 13 * u, 9.5 * u),
            Radius.circular(2.8 * u),
          ),
          stroke,
        );
        canvas.drawArc(
          Rect.fromCircle(center: p(12, 10.5), radius: 3.9 * u),
          math.pi,
          math.pi,
          false,
          stroke,
        );

      case DIcons.sound:
        canvas.drawPath(
          Path()
            ..moveTo(4.5 * u, 9.5 * u)
            ..lineTo(8 * u, 9.5 * u)
            ..lineTo(12.5 * u, 5.5 * u)
            ..lineTo(12.5 * u, 18.5 * u)
            ..lineTo(8 * u, 14.5 * u)
            ..lineTo(4.5 * u, 14.5 * u)
            ..close(),
          stroke,
        );
        canvas.drawArc(Rect.fromCircle(center: p(13.5, 12), radius: 3.4 * u), -0.9, 1.8, false, stroke);
        canvas.drawArc(Rect.fromCircle(center: p(13.5, 12), radius: 6.4 * u), -0.9, 1.8, false, stroke);

      case DIcons.mute:
        canvas.drawPath(
          Path()
            ..moveTo(4.5 * u, 9.5 * u)
            ..lineTo(8 * u, 9.5 * u)
            ..lineTo(12.5 * u, 5.5 * u)
            ..lineTo(12.5 * u, 18.5 * u)
            ..lineTo(8 * u, 14.5 * u)
            ..lineTo(4.5 * u, 14.5 * u)
            ..close(),
          stroke,
        );
        canvas.drawLine(p(16, 9.5), p(20.5, 14.5), stroke);
        canvas.drawLine(p(20.5, 9.5), p(16, 14.5), stroke);

      case DIcons.vibrate:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(8.5 * u, 4.5 * u, 7 * u, 15 * u),
            Radius.circular(2.2 * u),
          ),
          stroke,
        );
        canvas.drawLine(p(4.5, 9.5), p(4.5, 14.5), stroke);
        canvas.drawLine(p(19.5, 9.5), p(19.5, 14.5), stroke);

      case DIcons.music:
        // A single beamed pair of notes. Two notes rather than one: one note
        // is the universal "audio file" glyph, two read as music.
        canvas.drawLine(p(9.5, 17), p(9.5, 6), stroke);
        canvas.drawLine(p(18, 15), p(18, 4.2), stroke);
        canvas.drawLine(p(9.5, 6), p(18, 4.2), stroke);
        canvas.drawCircle(p(7.4, 17.4), 2.6 * u, fill);
        canvas.drawCircle(p(15.9, 15.4), 2.6 * u, fill);

      case DIcons.coin:
        // A struck token: an outer rim with a solid boss in the middle. Not a
        // currency glyph — a "$" or a "¢" would name a real currency, and
        // these are not money.
        //
        // Built from two solid shapes rather than by punching a hole through
        // the disc: this paints straight onto the parent layer, so a
        // BlendMode.clear here erases the background behind the icon rather
        // than the face of the coin.
        canvas.drawCircle(
          p(12, 12),
          8.4 * u,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = weight * u,
        );
        canvas.drawCircle(p(12, 12), 4.0 * u, fill);

      case DIcons.flame:
        // The streak marker. A single teardrop with one lick off the side —
        // a many-tongued fire turns to noise at badge size.
        canvas.drawPath(
          Path()
            ..moveTo(12 * u, 3 * u)
            ..cubicTo(17.5 * u, 8 * u, 19 * u, 11.5 * u, 19 * u, 14.2 * u)
            ..cubicTo(19 * u, 18.5 * u, 15.9 * u, 21 * u, 12 * u, 21 * u)
            ..cubicTo(8.1 * u, 21 * u, 5 * u, 18.5 * u, 5 * u, 14.2 * u)
            ..cubicTo(5 * u, 11 * u, 7.5 * u, 8.5 * u, 9.5 * u, 6 * u)
            ..cubicTo(10 * u, 8.8 * u, 11 * u, 10 * u, 12.4 * u, 10.6 * u)
            ..cubicTo(12.2 * u, 7.6 * u, 12 * u, 5.2 * u, 12 * u, 3 * u)
            ..close(),
          fill,
        );

      case DIcons.play:
        canvas.drawPath(
          Path()
            ..moveTo(8 * u, 5 * u)
            ..lineTo(19 * u, 12 * u)
            ..lineTo(8 * u, 19 * u)
            ..close(),
          fill,
        );

      case DIcons.map:
        // A road with three stops on it — the levels screen's own subject,
        // rather than a generic pin or folded map. Beads on a string: the
        // stops are drawn wider than the road so they still separate from it
        // at the 16px this is actually used at, which the first version of
        // this icon did not survive.
        canvas.drawPath(
          Path()
            ..moveTo(5.5 * u, 19.5 * u)
            ..quadraticBezierTo(5.5 * u, 12.5 * u, 12 * u, 12.5 * u)
            ..quadraticBezierTo(18.5 * u, 12.5 * u, 18.5 * u, 5 * u),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = weight * u * 0.8
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
        canvas.drawCircle(p(5.5, 19.5), 1.9 * u, fill);
        canvas.drawCircle(p(12, 12.5), 1.9 * u, fill);
        canvas.drawCircle(p(18.5, 5), 2.6 * u, fill);

      case DIcons.eye:
        canvas.drawPath(
          Path()
            ..moveTo(2.8 * u, 12 * u)
            ..quadraticBezierTo(12 * u, 3.4 * u, 21.2 * u, 12 * u)
            ..quadraticBezierTo(12 * u, 20.6 * u, 2.8 * u, 12 * u)
            ..close(),
          stroke,
        );
        canvas.drawCircle(p(12, 12), 2.5 * u, stroke);

      case DIcons.grid:
        // Three vessels — the game's own mark, reused as the levels icon.
        // Filled rather than stroked: three thin outlined vessels turn to mush
        // below about 20px, which is exactly the size this icon is used at.
        for (int i = 0; i < 3; i++) {
          final double h = <double>[15.0, 10.5, 12.5][i];
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              Rect.fromLTWH((4.6 + i * 5.6) * u, (19.5 - h) * u, 4.2 * u, h * u),
              topLeft: Radius.circular(1.1 * u),
              topRight: Radius.circular(1.1 * u),
              bottomLeft: Radius.circular(2.1 * u),
              bottomRight: Radius.circular(2.1 * u),
            ),
            fill,
          );
        }
    }
  }

  void _sparkle(Canvas canvas, Offset c, double r, Paint paint) {
    // A four-point star with concave sides: straight-line rays look like a
    // "new" badge; curved waists look like light.
    final Path s = Path()..moveTo(c.dx, c.dy - r);
    for (int i = 0; i < 4; i++) {
      final double a0 = -math.pi / 2 + i * math.pi / 2;
      final double a1 = a0 + math.pi / 2;
      s.quadraticBezierTo(
        c.dx + math.cos(a0 + math.pi / 4) * r * 0.16,
        c.dy + math.sin(a0 + math.pi / 4) * r * 0.16,
        c.dx + math.cos(a1) * r,
        c.dy + math.sin(a1) * r,
      );
    }
    s.close();
    canvas.drawPath(s, paint);
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color || old.weight != weight;
}
