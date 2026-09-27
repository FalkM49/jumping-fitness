import 'package:flutter/material.dart';

/// Значок кубика льда для кнопки «Заморозить абонемент» (ТЗ 5, 11.5):
/// линейный, одной толщины, в холодном голубом акценте — как в макете.
class IceCubeIcon extends StatelessWidget {
  const IceCubeIcon({super.key, this.size = 18, this.color});

  final double size;

  /// По умолчанию — ледяной голубой из макета.
  final Color? color;

  static const Color ice = Color(0xFF5FB3E4);

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _IceCubePainter(color ?? ice)),
    );
  }
}

class _IceCubePainter extends CustomPainter {
  _IceCubePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // Кубик в изометрии: верхняя грань, две боковые, блик.
    final top = Offset(w * 0.5, h * 0.08);
    final left = Offset(w * 0.1, h * 0.3);
    final right = Offset(w * 0.9, h * 0.3);
    final middle = Offset(w * 0.5, h * 0.52);
    final bottom = Offset(w * 0.5, h * 0.94);
    final leftBottom = Offset(w * 0.1, h * 0.72);
    final rightBottom = Offset(w * 0.9, h * 0.72);

    final outline = Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(right.dx, right.dy)
      ..lineTo(rightBottom.dx, rightBottom.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..lineTo(leftBottom.dx, leftBottom.dy)
      ..lineTo(left.dx, left.dy)
      ..close()
      ..moveTo(left.dx, left.dy)
      ..lineTo(middle.dx, middle.dy)
      ..lineTo(right.dx, right.dy)
      ..moveTo(middle.dx, middle.dy)
      ..lineTo(bottom.dx, bottom.dy);
    canvas.drawPath(outline, stroke);

    canvas.drawLine(
      Offset(w * 0.24, h * 0.45),
      Offset(w * 0.24, h * 0.6),
      stroke..strokeWidth = w * 0.07,
    );
  }

  @override
  bool shouldRepaint(_IceCubePainter old) => old.color != color;
}
