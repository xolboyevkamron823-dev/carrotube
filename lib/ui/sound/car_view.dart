import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Top view of a left-hand-drive sedan in centimetres, shared by the Time Alignment and
/// Fader/Balance screens. Cabin coordinates: x 0 (left door) .. 150 (right door),
/// y 0 (dashboard) .. 260 (rear shelf). The front of the car points up.
class CarView {
  CarView(this.size, {this.padding = 10}) {
    final w = size.width - 2 * padding, h = size.height - 2 * padding;
    scale = math.min(w / bodyRect.width, h / bodyRect.height);
    final used = Size(bodyRect.width * scale, bodyRect.height * scale);
    origin = Offset(
      padding + (w - used.width) / 2 - bodyRect.left * scale,
      padding + (h - used.height) / 2 - bodyRect.top * scale,
    );
  }

  final Size size;
  final double padding;
  late final double scale;
  late final Offset origin;

  /// Whole car body including bumpers (cm).
  static const bodyRect = Rect.fromLTRB(-32, -135, 182, 335);

  /// Interior area used for the fader/balance pad (cm).
  static const cabinRect = Rect.fromLTRB(0, 0, 150, 260);

  Offset px(Offset cm) => origin + cm * scale;
  Offset cm(Offset px) => (px - origin) / scale;
  Rect pxRect(Rect cm) => Rect.fromPoints(px(cm.topLeft), px(cm.bottomRight));

  /// Draws body, glass, seats, steering wheel and wheels.
  void paintBody(Canvas canvas, Color accent) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.30);
    final fill = Paint()..color = const Color(0xFF0C0F13);

    // Wheels.
    final wheel = Paint()..color = const Color(0xFF1A1D22);
    for (final r in const [
      Rect.fromLTRB(-36, -105, -20, -48),
      Rect.fromLTRB(170, -105, 186, -48),
      Rect.fromLTRB(-36, 220, -20, 277),
      Rect.fromLTRB(170, 220, 186, 277),
    ]) {
      canvas.drawRRect(RRect.fromRectAndRadius(pxRect(r), Radius.circular(3 * scale)), wheel);
    }

    // Body.
    final body = Path()
      ..moveTo(px(const Offset(10, -135)).dx, px(const Offset(10, -135)).dy)
      ..quadraticBezierTo(
        px(const Offset(-26, -130)).dx,
        px(const Offset(-26, -130)).dy,
        px(const Offset(-26, -80)).dx,
        px(const Offset(-26, -80)).dy,
      )
      ..lineTo(px(const Offset(-24, 290)).dx, px(const Offset(-24, 290)).dy)
      ..quadraticBezierTo(
        px(const Offset(-22, 332)).dx,
        px(const Offset(-22, 332)).dy,
        px(const Offset(20, 335)).dx,
        px(const Offset(20, 335)).dy,
      )
      ..lineTo(px(const Offset(130, 335)).dx, px(const Offset(130, 335)).dy)
      ..quadraticBezierTo(
        px(const Offset(172, 332)).dx,
        px(const Offset(172, 332)).dy,
        px(const Offset(174, 290)).dx,
        px(const Offset(174, 290)).dy,
      )
      ..lineTo(px(const Offset(176, -80)).dx, px(const Offset(176, -80)).dy)
      ..quadraticBezierTo(
        px(const Offset(176, -130)).dx,
        px(const Offset(176, -130)).dy,
        px(const Offset(140, -135)).dx,
        px(const Offset(140, -135)).dy,
      )
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF15191E), Color(0xFF0B0D10), Color(0xFF15191E)],
        ).createShader(pxRect(bodyRect)),
    );
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = accent.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(body, line);

    // Hood / trunk lines.
    canvas.drawLine(
      px(const Offset(0, -50)),
      px(const Offset(150, -50)),
      line..color = Colors.white.withValues(alpha: 0.12),
    );
    canvas.drawLine(px(const Offset(0, 292)), px(const Offset(150, 292)), line);

    final glass = Paint()..color = accent.withValues(alpha: 0.07);
    final glassLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = accent.withValues(alpha: 0.35);
    Path poly(List<Offset> pts) {
      final p = Path()..moveTo(px(pts.first).dx, px(pts.first).dy);
      for (final o in pts.skip(1)) {
        p.lineTo(px(o).dx, px(o).dy);
      }
      return p..close();
    }

    final windshield = poly(const [Offset(8, -44), Offset(142, -44), Offset(156, -2), Offset(-6, -2)]);
    final rear = poly(const [Offset(-2, 250), Offset(152, 250), Offset(140, 286), Offset(10, 286)]);
    for (final g in [windshield, rear]) {
      canvas.drawPath(g, glass);
      canvas.drawPath(g, glassLine);
    }

    // Cabin floor.
    canvas.drawRRect(RRect.fromRectAndRadius(pxRect(cabinRect), Radius.circular(10 * scale)), fill);

    // Dashboard.
    canvas.drawRRect(
      RRect.fromRectAndRadius(pxRect(const Rect.fromLTRB(2, 0, 148, 14)), Radius.circular(4 * scale)),
      Paint()..color = const Color(0xFF1A1E24),
    );

    // Seats.
    final seat = Paint()..color = const Color(0xFF1C2128);
    final seatLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.12);
    for (final r in const [
      Rect.fromLTRB(14, 56, 66, 124),
      Rect.fromLTRB(84, 56, 136, 124),
      Rect.fromLTRB(10, 172, 140, 236),
    ]) {
      final rr = RRect.fromRectAndRadius(pxRect(r), Radius.circular(8 * scale));
      canvas.drawRRect(rr, seat);
      canvas.drawRRect(rr, seatLine);
    }
    // Headrests.
    for (final r in const [
      Rect.fromLTRB(28, 118, 52, 130),
      Rect.fromLTRB(98, 118, 122, 130),
      Rect.fromLTRB(22, 230, 46, 240),
      Rect.fromLTRB(63, 230, 87, 240),
      Rect.fromLTRB(104, 230, 128, 240),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(pxRect(r), Radius.circular(4 * scale)),
        Paint()..color = const Color(0xFF262C34),
      );
    }
    // Steering wheel (left-hand drive).
    canvas.drawCircle(
      px(const Offset(40, 32)),
      17 * scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, 4 * scale)
        ..color = Colors.white.withValues(alpha: 0.22),
    );
  }
}
