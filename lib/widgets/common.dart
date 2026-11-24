import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0B1220);
  static const surface = Color(0xFF121B2E);
  static const surface2 = Color(0xFF1A2540);
  static const border = Color(0xFF26314F);
  static const cyan = Color(0xFF00E5FF);
  static const blue = Color(0xFF3D8BFF);
  static const green = Color(0xFF2EE59D);
  static const amber = Color(0xFFFFC145);
  static const red = Color(0xFFFF5C7A);
  static const purple = Color(0xFFB07CFF);
  static const text2 = Color(0xFF8B97B5);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.cyan,
      brightness: Brightness.dark,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.bg,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    ),
  );
}

class SectionCard extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets padding;
  const SectionCard({
    super.key,
    this.title,
    this.icon,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                if (icon != null) ...[
                  Icon(icon, color: AppColors.cyan, size: 20),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(title!,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                if (trailing != null) trailing!,
              ]),
            ),
          child,
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? sub;
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AppColors.cyan,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: AppColors.text2, fontSize: 12),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          ),
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(sub!,
                  style: const TextStyle(color: AppColors.text2, fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }
}

/// Responsive grid of tiles.
class TileGrid extends StatelessWidget {
  final List<Widget> children;
  final double minWidth;
  const TileGrid({super.key, required this.children, this.minWidth = 160});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final cols = math.max(2, (c.maxWidth / minWidth).floor());
      final w = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

/// Signal quality level 0..4 with label and color.
class Quality {
  final int level;
  final String ar;
  final String en;
  final Color color;
  const Quality(this.level, this.ar, this.en, this.color);
}

Quality rsrpQuality(double rsrp) {
  if (rsrp == 0) return const Quality(0, 'لا يوجد', 'None', AppColors.text2);
  if (rsrp >= -80) return const Quality(4, 'ممتازة', 'Excellent', AppColors.green);
  if (rsrp >= -90) return const Quality(3, 'جيدة', 'Good', AppColors.cyan);
  if (rsrp >= -100) return const Quality(2, 'متوسطة', 'Fair', AppColors.amber);
  return const Quality(1, 'ضعيفة', 'Poor', AppColors.red);
}

Quality sinrQuality(double sinr) {
  if (sinr >= 20) return const Quality(4, 'ممتازة', 'Excellent', AppColors.green);
  if (sinr >= 13) return const Quality(3, 'جيدة', 'Good', AppColors.cyan);
  if (sinr >= 0) return const Quality(2, 'متوسطة', 'Fair', AppColors.amber);
  return const Quality(1, 'ضعيفة', 'Poor', AppColors.red);
}

class SignalBars extends StatelessWidget {
  final int level;
  final Color color;
  final double size;
  const SignalBars({super.key, required this.level, required this.color, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (i) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: size / 4,
            height: size * (i + 1) / 4,
            decoration: BoxDecoration(
              color: i < level ? color : AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

/// A horizontal meter for a metric between min and max.
class Meter extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String unit;
  final Color color;
  const Meter({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final frac = ((value - min) / (max - min)).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.text2))),
          Text('${value.toStringAsFixed(value.abs() < 100 ? 1 : 0)} $unit',
              style: TextStyle(fontWeight: FontWeight.w700, color: color)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 8,
            backgroundColor: AppColors.surface2,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ]),
    );
  }
}

/// Live line chart for two series.
class Sparkline extends StatelessWidget {
  final List<double> a;
  final List<double> b;
  final double height;
  const Sparkline({super.key, required this.a, required this.b, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(painter: _SparkPainter(a, b), size: Size.infinite),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> a;
  final List<double> b;
  _SparkPainter(this.a, this.b);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final mx = [...a, ...b, 1.0].reduce(math.max);
    void line(List<double> d, Color c) {
      if (d.length < 2) return;
      final path = Path();
      final fill = Path();
      for (var i = 0; i < d.length; i++) {
        final x = size.width * i / (d.length - 1);
        final y = size.height - size.height * (d[i] / mx) * 0.92;
        if (i == 0) {
          path.moveTo(x, y);
          fill.moveTo(x, size.height);
          fill.lineTo(x, y);
        } else {
          path.lineTo(x, y);
          fill.lineTo(x, y);
        }
      }
      fill.lineTo(size.width, size.height);
      fill.close();
      canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [c.withValues(alpha: 0.35), c.withValues(alpha: 0.0)],
            ).createShader(Offset.zero & size));
      canvas.drawPath(
          path,
          Paint()
            ..color = c
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2);
    }

    line(b, AppColors.purple);
    line(a, AppColors.cyan);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => true;
}

/// Simple bar chart (labels + values).
class BarChart extends StatelessWidget {
  final List<String> labels;
  final List<double> values;
  final String Function(double) fmt;
  final double height;
  const BarChart({
    super.key,
    required this.labels,
    required this.values,
    required this.fmt,
    this.height = 170,
  });

  @override
  Widget build(BuildContext context) {
    final mx = values.isEmpty ? 1.0 : math.max(1.0, values.reduce(math.max));
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Tooltip(
                message: '${labels[i]}\n${fmt(values[i])}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: math.max(2.0, (height - 22) * values[i] / mx),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [AppColors.cyan, AppColors.blue],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 14,
                      child: FittedBox(
                        child: Text(labels[i],
                            style: const TextStyle(fontSize: 9, color: AppColors.text2)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? AppColors.red.withValues(alpha: 0.95) : AppColors.surface2,
    behavior: SnackBarBehavior.floating,
  ));
}

Future<bool> confirm(BuildContext context, String title, String body,
    {String ok = 'موافق', String cancel = 'إلغاء'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(cancel)),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}

class InfoRow extends StatelessWidget {
  final String k;
  final String v;
  const InfoRow(this.k, this.v, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text(k, style: const TextStyle(color: AppColors.text2))),
        Flexible(
          child: SelectableText(v.isEmpty ? '—' : v,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class NoteBox extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const NoteBox(this.text,
      {super.key, this.color = AppColors.amber, this.icon = Icons.info_outline});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5))),
      ]),
    );
  }
}
