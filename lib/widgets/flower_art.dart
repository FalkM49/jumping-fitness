import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/theme_context.dart';

/// Иллюстрация цветка месяца (ТЗ 4, 11.5): простая плоская картинка
/// в 2–3 цветах палитры, единый стиль для всех 14 цветков справочника.
///
/// Рисуется кодом, поэтому одинаково чётко на любом экране и сама
/// подстраивается под светлую и тёмную тему. Если позже появятся готовые
/// иллюстрации (поле `image` в flowers), их можно показать вместо этой.
class FlowerArt extends StatelessWidget {
  const FlowerArt({super.key, required this.flowerId, this.size = 88});

  /// ID из справочника `flowers`; неизвестный — нейтральный цветок.
  final String? flowerId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colors = context.colors;
    final flowerColors = _FlowerColors(
      bloom: colors.primary,
      coral: colors.secondary,
      bloomTint: palette.bloomTint,
      coralTint: palette.coralTint,
      // Тёмные серединки (подсолнух, гербера) тёмные в обеих темах —
      // цвет текста в тёмной теме светлый и сделал бы их белыми.
      ink: AppColors.inkPlum,
      leaf: palette.remainingHigh,
      white: const Color(0xFFFFFFFF),
      outline: palette.line,
    );
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _FlowerPainter(_presetFor(flowerId), flowerColors),
      ),
    );
  }
}

class _FlowerColors {
  const _FlowerColors({
    required this.bloom,
    required this.coral,
    required this.bloomTint,
    required this.coralTint,
    required this.ink,
    required this.leaf,
    required this.white,
    required this.outline,
  });

  final Color bloom;
  final Color coral;
  final Color bloomTint;
  final Color coralTint;
  final Color ink;
  final Color leaf;
  final Color white;
  final Color outline;
}

enum _Petal { round, pointed, long }

enum _Kind { radial, tulip, bells }

typedef _Pick = Color Function(_FlowerColors c);

/// Слой лепестков: число, форма, размер (доля радиуса) и цвет.
class _Layer {
  const _Layer(this.count, this.shape, this.scale, this.color, {this.turn = 0});

  final int count;
  final _Petal shape;
  final double scale;
  final _Pick color;

  /// Поворот слоя в долях лепестка — чтобы слои не совпадали.
  final double turn;
}

class _Preset {
  const _Preset({
    this.kind = _Kind.radial,
    this.layers = const [],
    this.center,
    this.centerScale = 0.2,
  });

  final _Kind kind;
  final List<_Layer> layers;
  final _Pick? center;
  final double centerScale;
}

Color _bloom(_FlowerColors c) => c.bloom;
Color _coral(_FlowerColors c) => c.coral;
Color _bloomTint(_FlowerColors c) => c.bloomTint;
Color _coralTint(_FlowerColors c) => c.coralTint;
Color _ink(_FlowerColors c) => c.ink;
Color _white(_FlowerColors c) => c.white;

_Preset _presetFor(String? id) => switch (id) {
  'peony' => const _Preset(
    layers: [
      _Layer(10, _Petal.round, 1, _bloom),
      _Layer(8, _Petal.round, 0.72, _bloomTint, turn: 0.5),
      _Layer(6, _Petal.round, 0.45, _bloom),
    ],
    center: _coral,
    centerScale: 0.14,
  ),
  'rose' => const _Preset(
    layers: [
      _Layer(6, _Petal.round, 1, _bloom),
      _Layer(5, _Petal.round, 0.7, _coral, turn: 0.5),
      _Layer(4, _Petal.round, 0.42, _bloom),
    ],
    center: _coral,
    centerScale: 0.12,
  ),
  'sunflower' => const _Preset(
    layers: [
      _Layer(16, _Petal.pointed, 1, _coral),
      _Layer(16, _Petal.pointed, 0.8, _coralTint, turn: 0.5),
    ],
    center: _ink,
    centerScale: 0.34,
  ),
  'lavender' => const _Preset(
    layers: [
      _Layer(6, _Petal.long, 1, _bloomTint),
      _Layer(6, _Petal.long, 0.7, _bloom, turn: 0.5),
    ],
    center: _bloom,
    centerScale: 0.12,
  ),
  'chamomile' => const _Preset(
    layers: [_Layer(16, _Petal.long, 1, _white)],
    center: _coral,
    centerScale: 0.26,
  ),
  'tulip' => const _Preset(kind: _Kind.tulip),
  'orchid' => const _Preset(
    layers: [
      _Layer(5, _Petal.round, 1, _coralTint),
      _Layer(5, _Petal.round, 0.55, _coral, turn: 0.5),
    ],
    center: _bloom,
    centerScale: 0.14,
  ),
  'lotus' => const _Preset(
    layers: [
      _Layer(8, _Petal.pointed, 1, _bloomTint),
      _Layer(8, _Petal.pointed, 0.7, _bloom, turn: 0.5),
    ],
    center: _coral,
    centerScale: 0.16,
  ),
  'hydrangea' => const _Preset(
    layers: [
      _Layer(12, _Petal.round, 1, _bloomTint),
      _Layer(8, _Petal.round, 0.66, _bloom, turn: 0.5),
      _Layer(5, _Petal.round, 0.36, _bloomTint),
    ],
  ),
  'freesia' => const _Preset(
    layers: [
      _Layer(6, _Petal.round, 1, _coralTint),
      _Layer(6, _Petal.round, 0.6, _coral, turn: 0.5),
    ],
    center: _bloom,
    centerScale: 0.12,
  ),
  'iris' => const _Preset(
    layers: [
      _Layer(3, _Petal.long, 1, _bloom),
      _Layer(3, _Petal.pointed, 0.8, _coral, turn: 0.5),
    ],
    center: _coralTint,
    centerScale: 0.14,
  ),
  'magnolia' => const _Preset(
    layers: [
      _Layer(6, _Petal.long, 1, _bloomTint),
      _Layer(3, _Petal.long, 0.62, _bloom, turn: 0.5),
    ],
    center: _coral,
    centerScale: 0.12,
  ),
  'lily_of_the_valley' => const _Preset(kind: _Kind.bells),
  'gerbera' => const _Preset(
    layers: [
      _Layer(20, _Petal.long, 1, _coral),
      _Layer(20, _Petal.long, 0.66, _bloom, turn: 0.5),
    ],
    center: _ink,
    centerScale: 0.22,
  ),
  _ => const _Preset(
    layers: [_Layer(8, _Petal.round, 1, _bloom)],
    center: _coral,
  ),
};

class _FlowerPainter extends CustomPainter {
  _FlowerPainter(this.preset, this.c);

  final _Preset preset;
  final _FlowerColors c;

  @override
  void paint(Canvas canvas, Size size) {
    switch (preset.kind) {
      case _Kind.radial:
        _paintRadial(canvas, size);
      case _Kind.tulip:
        _paintTulip(canvas, size);
      case _Kind.bells:
        _paintBells(canvas, size);
    }
  }

  void _paintRadial(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.46;
    final outline = Paint()
      ..color = c.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (final layer in preset.layers) {
      final fill = Paint()..color = layer.color(c);
      final r = radius * layer.scale;
      for (var i = 0; i < layer.count; i++) {
        final angle =
            (i + layer.turn) * 2 * math.pi / layer.count - math.pi / 2;
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(angle);
        final path = _petal(layer.shape, r, layer.count);
        canvas.drawPath(path, fill);
        // Белым лепесткам нужна тонкая обводка, иначе они теряются на светлом фоне.
        if (layer.color(c) == c.white) canvas.drawPath(path, outline);
        canvas.restore();
      }
    }
    final centerColor = preset.center;
    if (centerColor != null) {
      canvas.drawCircle(
        center,
        radius * preset.centerScale,
        Paint()..color = centerColor(c),
      );
    }
  }

  /// Лепесток вдоль оси X от центра на длину [r].
  Path _petal(_Petal shape, double r, int count) {
    // Ширина лепестка зависит от их числа: у пиона широкие, у герберы узкие.
    final width = math.min(r * 0.9, r * 3.2 / count + r * 0.08);
    return switch (shape) {
      _Petal.round =>
        Path()..addOval(
          Rect.fromCenter(
            center: Offset(r * 0.55, 0),
            width: r * 0.95,
            height: width * 1.1,
          ),
        ),
      _Petal.long =>
        Path()..addOval(
          Rect.fromCenter(
            center: Offset(r * 0.55, 0),
            width: r * 0.95,
            height: width * 0.6,
          ),
        ),
      _Petal.pointed =>
        Path()
          ..moveTo(r * 0.1, 0)
          ..quadraticBezierTo(r * 0.5, -width * 0.7, r, 0)
          ..quadraticBezierTo(r * 0.5, width * 0.7, r * 0.1, 0)
          ..close(),
    };
  }

  void _paintStem(Canvas canvas, Size size, double topY) {
    final stem = Paint()
      ..color = c.leaf
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.04
      ..strokeCap = StrokeCap.round;
    final x = size.width / 2;
    canvas.drawLine(Offset(x, topY), Offset(x, size.height * 0.95), stem);
    final leaf = Paint()..color = c.leaf;
    canvas.save();
    canvas.translate(x, size.height * 0.75);
    canvas.rotate(-0.6);
    canvas.drawOval(
      Rect.fromLTWH(
        0,
        -size.height * 0.05,
        size.width * 0.26,
        size.height * 0.1,
      ),
      leaf,
    );
    canvas.restore();
  }

  void _paintTulip(Canvas canvas, Size size) {
    _paintStem(canvas, size, size.height * 0.45);
    final w = size.width;
    final h = size.height;
    final back = Paint()..color = c.bloom;
    final front = Paint()..color = c.coral;
    // Три лепестка-чаши: два боковых и передний.
    for (final dx in [-0.13, 0.13]) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * (0.5 + dx), h * 0.34),
          width: w * 0.3,
          height: h * 0.42,
        ),
        back,
      );
    }
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.38),
        width: w * 0.3,
        height: h * 0.4,
      ),
      front,
    );
  }

  void _paintBells(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stem = Paint()
      ..color = c.leaf
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;
    // Изогнутый стебель и колокольчики вдоль него.
    final path = Path()
      ..moveTo(w * 0.5, h * 0.95)
      ..quadraticBezierTo(w * 0.45, h * 0.35, w * 0.78, h * 0.12);
    canvas.drawPath(path, stem);
    final bell = Paint()..color = c.white;
    final edge = Paint()
      ..color = c.bloom
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final t in [0.25, 0.42, 0.58, 0.74]) {
      final metric = path.computeMetrics().first;
      final pos = metric.getTangentForOffset(metric.length * (1 - t))!.position;
      final rect = Rect.fromCenter(
        center: pos.translate(-w * 0.08, h * 0.07),
        width: w * 0.15,
        height: h * 0.13,
      );
      canvas.drawOval(rect, bell);
      canvas.drawOval(rect, edge);
    }
    final leaf = Paint()..color = c.leaf.withValues(alpha: 0.8);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.33, h * 0.72),
        width: w * 0.2,
        height: h * 0.5,
      ),
      leaf,
    );
  }

  @override
  bool shouldRepaint(_FlowerPainter old) =>
      old.preset != preset || old.c.bloom != c.bloom || old.c.ink != c.ink;
}
