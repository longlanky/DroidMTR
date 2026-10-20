import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class LatencySparkline extends StatelessWidget {
  const LatencySparkline({
    super.key,
    required this.samples,
    required this.color,
    this.height = 36,
    this.showLossTicks = true,
  });

  final List<int> samples;
  final Color color;
  final double height;
  final bool showLossTicks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _SparklinePainter(
            samples: samples,
            color: color,
            lossColor: colors.bad,
            gridColor: colors.grid,
            showLossTicks: showLossTicks,
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.samples,
    required this.color,
    required this.lossColor,
    required this.gridColor,
    required this.showLossTicks,
  });

  final List<int> samples;
  final Color color;
  final Color lossColor;
  final Color gridColor;
  final bool showLossTicks;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final baseline = size.height - 1.5;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      gridPaint,
    );

    if (samples.isEmpty) return;

    final positives = samples.where((value) => value >= 0).toList()..sort();
    final maxValue = positives.isEmpty
        ? 10.0
        : math.max(
            10.0,
            positives[(positives.length * 0.95).floor().clamp(
                  0,
                  positives.length - 1,
                )] /
                1000.0 *
                1.12,
          );
    final count = samples.length;
    final step = count <= 1 ? 0.0 : size.width / (count - 1);
    double xFor(int index) => count <= 1 ? size.width / 2 : index * step;
    double yFor(double ms) {
      final clamped = ms.clamp(0.0, maxValue);
      return 3 + (1 - clamped / maxValue) * (baseline - 6);
    }

    final lossPaint = Paint()
      ..color = lossColor.withValues(alpha: 0.65)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    if (showLossTicks) {
      for (var i = 0; i < count; i++) {
        if (samples[i] < 0) {
          canvas.drawLine(
            Offset(xFor(i), size.height - 4.5),
            Offset(xFor(i), baseline),
            lossPaint,
          );
        }
      }
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Path? line;
    Path? fill;
    double? segmentStartX;
    double? lastX;
    double? lastY;
    var previousLost = true;

    void finishSegment() {
      final currentFill = fill;
      final start = segmentStartX;
      final endX = lastX;
      if (currentFill != null && start != null && endX != null) {
        currentFill.lineTo(endX, baseline);
        currentFill.lineTo(start, baseline);
        currentFill.close();
        final rect = Offset.zero & size;
        final paint = Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, 0),
            Offset(0, size.height),
            [color.withValues(alpha: 0.20), color.withValues(alpha: 0.0)],
          );
        canvas.save();
        canvas.clipRect(rect);
        canvas.drawPath(currentFill, paint);
        canvas.restore();
      }
      fill = null;
      segmentStartX = null;
    }

    for (var i = 0; i < count; i++) {
      final value = samples[i];
      if (value < 0) {
        if (!previousLost) {
          if (line != null) canvas.drawPath(line, linePaint);
          finishSegment();
          line = null;
        }
        previousLost = true;
        continue;
      }
      final x = xFor(i);
      final y = yFor(value / 1000.0);
      if (line == null) {
        line = Path()..moveTo(x, y);
        fill = Path()
          ..moveTo(x, baseline)
          ..lineTo(x, y);
        segmentStartX = x;
      } else {
        line.lineTo(x, y);
        fill?.lineTo(x, y);
      }
      lastX = x;
      lastY = y;
      previousLost = false;
    }
    if (line != null) {
      canvas.drawPath(line, linePaint);
      finishSegment();
    }
    if (!previousLost && lastX != null && lastY != null) {
      canvas.drawCircle(Offset(lastX, lastY), 2.3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.showLossTicks != showLossTicks ||
        !listEquals(oldDelegate.samples, samples);
  }
}

class LatencyChart extends StatelessWidget {
  const LatencyChart({
    super.key,
    required this.samples,
    required this.color,
    this.height = 180,
  });

  final List<int> samples;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _ChartPainter(
          samples: samples,
          color: color,
          lossColor: colors.bad,
          gridColor: colors.grid,
          textColor: theme.colorScheme.onSurfaceVariant,
          labelStyle:
              theme.textTheme.labelSmall ?? const TextStyle(fontSize: 10),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.samples,
    required this.color,
    required this.lossColor,
    required this.gridColor,
    required this.textColor,
    required this.labelStyle,
  });

  final List<int> samples;
  final Color color;
  final Color lossColor;
  final Color gridColor;
  final Color textColor;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final left = 42.0;
    final right = 8.0;
    final top = 10.0;
    final bottom = size.height - 22.0;
    final plotWidth = size.width - left - right;
    final plotHeight = bottom - top;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    final positives = samples.where((value) => value >= 0).toList()..sort();
    var maxMs = positives.isEmpty
        ? 100.0
        : positives[(positives.length * 0.95).floor().clamp(
                0,
                positives.length - 1,
              )] /
              1000.0 *
              1.18;
    if (maxMs < 10) maxMs = 10;
    final niceMax = _niceCeiling(maxMs);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final labelPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    );

    for (var i = 0; i <= 2; i++) {
      final fraction = i / 2;
      final y = top + fraction * plotHeight;
      canvas.drawLine(Offset(left, y), Offset(left + plotWidth, y), gridPaint);
      final value = niceMax * (1 - fraction);
      labelPainter
        ..text = TextSpan(
          text: _axisLabel(value),
          style: labelStyle.copyWith(color: textColor, fontSize: 10),
        )
        ..layout(maxWidth: 36);
      labelPainter.paint(
        canvas,
        Offset(left - labelPainter.width - 7, y - labelPainter.height / 2),
      );
    }

    final count = samples.length;
    final step = count <= 1 ? 0.0 : plotWidth / (count - 1);
    double xFor(int index) =>
        left + (count <= 1 ? plotWidth / 2 : index * step);
    double yFor(double ms) =>
        top + (1 - (ms / niceMax).clamp(0.0, 1.0)) * plotHeight;

    final lossPaint = Paint()
      ..color = lossColor.withValues(alpha: 0.7)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      if (samples[i] < 0) {
        canvas.drawLine(
          Offset(xFor(i), bottom - 5),
          Offset(xFor(i), bottom),
          lossPaint,
        );
      }
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Path? line;
    var previousLost = true;
    Offset? lastPoint;
    for (var i = 0; i < count; i++) {
      final value = samples[i];
      if (value < 0) {
        if (line != null) canvas.drawPath(line, linePaint);
        line = null;
        previousLost = true;
        continue;
      }
      final point = Offset(xFor(i), yFor(value / 1000.0));
      if (line == null) {
        line = Path()..moveTo(point.dx, point.dy);
      } else {
        line.lineTo(point.dx, point.dy);
      }
      lastPoint = point;
      previousLost = false;
    }
    if (line != null) {
      canvas.drawPath(line, linePaint);
      if (lastPoint != null) {
        canvas.drawCircle(lastPoint, 3.2, Paint()..color = color);
        canvas.drawCircle(
          lastPoint,
          6.5,
          Paint()
            ..color = color.withValues(alpha: 0.16)
            ..style = PaintingStyle.fill,
        );
      }
    }

    labelPainter
      ..text = TextSpan(
        text: count == 0 ? 'no probes yet' : '$count probes',
        style: labelStyle.copyWith(color: textColor, fontSize: 10),
      )
      ..layout(maxWidth: plotWidth);
    labelPainter.paint(
      canvas,
      Offset(left + plotWidth - labelPainter.width, bottom + 6),
    );
    if (!previousLost) {
      // A subtle right-edge fade is drawn over the plot to imply live data.
      final fade = Paint()
        ..shader = ui.Gradient.linear(
          Offset(left + plotWidth - 26, 0),
          Offset(left + plotWidth, 0),
          [color.withValues(alpha: 0.0), color.withValues(alpha: 0.06)],
        );
      canvas.drawRect(
        Rect.fromLTWH(left + plotWidth - 26, top, 26, plotHeight),
        fade,
      );
    }
  }

  static double _niceCeiling(double value) {
    if (value <= 10) return 10;
    final magnitude = math
        .pow(10, (math.log(value) / math.ln10).floor())
        .toDouble();
    final normalized = value / magnitude;
    final nice = normalized <= 1
        ? 1
        : normalized <= 2
        ? 2
        : normalized <= 5
        ? 5
        : 10;
    return nice * magnitude;
  }

  static String _axisLabel(double ms) {
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(1)}s';
    return '${ms.toStringAsFixed(ms < 10 ? 0 : 0)}ms';
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.textColor != textColor ||
        !listEquals(oldDelegate.samples, samples);
  }
}
