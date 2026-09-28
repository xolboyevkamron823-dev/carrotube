import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Red rounded play button + "CarroTube" wordmark.
class CarroTubeLogo extends StatelessWidget {
  const CarroTubeLogo({super.key, this.height = 22});
  final double height;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: height * 1.42,
          height: height,
          decoration: BoxDecoration(color: YtColors.red, borderRadius: BorderRadius.circular(height * 0.28)),
          alignment: Alignment.center,
          child: CustomPaint(size: Size.square(height * 0.46), painter: _PlayTriangle()),
        ),
        SizedBox(width: height * 0.18),
        Text(
          'CarroTube',
          style: TextStyle(
            color: color,
            fontSize: height * 0.95,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.9,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _PlayTriangle extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.12, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width * 0.12, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_PlayTriangle oldDelegate) => false;
}
