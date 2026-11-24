import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/format.dart';

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
                  flex: 3,
                  child: Text(title!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    flex: 2,
                    child: Align(alignment: AlignmentDirectional.centerEnd, child: trailing!),
                  ),
                ],
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


/// Radial speedometer-style gauge.
class RadialGauge extends StatelessWidget {
  final double value; // current
  final double max;
  final String center;
  final String unit;
  final String label;
  final Color color;
  final double size;
  const RadialGauge({
    super.key,
    required this.value,
    required this.max,
    required this.center,
    required this.unit,
    required this.label,
    this.color = AppColors.cyan,
    this.size = 150,
  });

  @override
  Widget build(BuildContext context) {
    final frac = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size * 0.82,
      child: Stack(alignment: Alignment.center, children: [
        Positioned.fill(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: frac),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => CustomPaint(painter: _GaugePainter(v, color)),
          ),
        ),
        Positioned(
          top: size * 0.26,
          child: Column(children: [
            Text(center,
                style: TextStyle(
                    fontSize: size * 0.17, fontWeight: FontWeight.w900, color: Colors.white)),
            Text(unit, style: TextStyle(fontSize: size * 0.08, color: color)),
          ]),
        ),
        Positioned(
          bottom: 0,
          child: Text(label,
              style: TextStyle(fontSize: size * 0.085, color: AppColors.text2)),
        ),
      ]),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double frac;
  final Color color;
  _GaugePainter(this.frac, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width / 2, size.height / 1.1) - 8;
    final c = Offset(size.width / 2, r + 8);
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    final rect = Rect.fromCircle(center: c, radius: r);
    final bg = Paint()
      ..color = AppColors.surface2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, bg);
    // ticks
    final tick = Paint()
      ..color = AppColors.border
      ..strokeWidth = 2;
    for (var i = 0; i <= 10; i++) {
      final a = start + sweep * i / 10;
      final p1 = c + Offset(math.cos(a), math.sin(a)) * (r - 14);
      final p2 = c + Offset(math.cos(a), math.sin(a)) * (r - 20);
      canvas.drawLine(p1, p2, tick);
    }
    if (frac > 0) {
      final fg = Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: sweep,
          colors: [color.withValues(alpha: 0.45), color],
          transform: const GradientRotation(start),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start, sweep * frac, false, fg);
      final a = start + sweep * frac;
      final dot = c + Offset(math.cos(a), math.sin(a)) * r;
      canvas.drawCircle(dot, 7, Paint()..color = Colors.white);
      canvas.drawCircle(dot, 4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.frac != frac || old.color != color;
}

/// Live vertical bars: download (cyan) and upload (purple) side by side.
class LiveBars extends StatelessWidget {
  final List<double> down;
  final List<double> up;
  final int count;
  final double height;
  const LiveBars({
    super.key,
    required this.down,
    required this.up,
    this.count = 30,
    this.height = 150,
  });

  @override
  Widget build(BuildContext context) {
    List<double> tail(List<double> l) =>
        l.length > count ? l.sublist(l.length - count) : [...List.filled(count - l.length, 0.0), ...l];
    final d = tail(down), u = tail(up);
    final mx = math.max(1.0, [...d, ...u].reduce(math.max));
    return SizedBox(
      height: height,
      child: Column(children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            textDirection: TextDirection.ltr,
            children: [
              for (var i = 0; i < count; i++)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: _bar(d[i] / mx, AppColors.cyan)),
                      const SizedBox(width: 1),
                      Expanded(child: _bar(u[i] / mx, AppColors.purple)),
                      const SizedBox(width: 2),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _legend(AppColors.cyan, '↓'),
          const SizedBox(width: 16),
          _legend(AppColors.purple, '↑'),
          const SizedBox(width: 16),
          Text('max ${fmtRate(mx)}',
              style: const TextStyle(fontSize: 11, color: AppColors.text2)),
        ]),
      ]),
    );
  }

  Widget _bar(double f, Color c) => AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        height: math.max(2.0, (height - 26) * f.clamp(0.0, 1.0)),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [c.withValues(alpha: 0.35), c],
          ),
        ),
      );

  Widget _legend(Color c, String t) => Row(children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(t, style: const TextStyle(fontSize: 12)),
      ]);
}

/// One node of the network map.
class MapNode {
  final IconData icon;
  final String title;
  final String sub;
  final Color color;
  final VoidCallback? onTap;
  const MapNode(this.icon, this.title, this.sub, this.color, {this.onTap});
}

/// Illustrated network topology: Tower -> Router -> Extender -> Devices.
class NetworkMap extends StatefulWidget {
  final List<MapNode> nodes;
  final List<String> links; // label for each link between nodes
  const NetworkMap({super.key, required this.nodes, required this.links});

  @override
  State<NetworkMap> createState() => _NetworkMapState();
}

class _NetworkMapState extends State<NetworkMap> with SingleTickerProviderStateMixin {
  late final AnimationController ac =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < widget.nodes.length; i++) {
      items.add(Expanded(flex: 3, child: _node(widget.nodes[i])));
      if (i < widget.nodes.length - 1) {
        items.add(Expanded(
          flex: 2,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              height: 16,
              child: AnimatedBuilder(
                animation: ac,
                builder: (_, __) => CustomPaint(
                  size: Size.infinite,
                  painter: _FlowPainter(ac.value, widget.nodes[i + 1].color),
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              child: Text(i < widget.links.length ? widget.links[i] : '',
                  style: const TextStyle(fontSize: 10, color: AppColors.text2)),
            ),
          ]),
        ));
      }
    }
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: items),
    );
  }

  Widget _node(MapNode n) => InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: n.onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              n.color.withValues(alpha: 0.35),
              n.color.withValues(alpha: 0.08),
            ]),
            border: Border.all(color: n.color, width: 2),
            boxShadow: [BoxShadow(color: n.color.withValues(alpha: 0.35), blurRadius: 14)],
          ),
          child: Icon(n.icon, color: n.color, size: 28),
        ),
        const SizedBox(height: 6),
        FittedBox(
          child: Text(n.title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        ),
        FittedBox(
          child: Text(n.sub, style: TextStyle(fontSize: 10, color: n.color)),
        ),
      ]));
}

class _FlowPainter extends CustomPainter {
  final double t;
  final Color color;
  _FlowPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = color.withValues(alpha: 0.25)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    for (var k = 0; k < 3; k++) {
      final p = ((t + k / 3) % 1.0) * size.width;
      canvas.drawCircle(Offset(p, y), 3.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _FlowPainter old) => true;
}

/// Small pill showing a band / carrier.
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, {super.key, this.color = AppColors.cyan, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Text(text,
              textDirection: TextDirection.ltr,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      );
}


/// Line chart for one or more series over time (NaN = gap).
class TrendSeries {
  final String name;
  final List<double> values;
  final Color color;
  const TrendSeries(this.name, this.values, this.color);
}

class TrendChart extends StatelessWidget {
  final List<TrendSeries> series;
  final String unit;
  final double height;
  const TrendChart({super.key, required this.series, this.unit = '', this.height = 140});

  @override
  Widget build(BuildContext context) {
    final all = [
      for (final s in series)
        for (final v in s.values)
          if (!v.isNaN) v
    ];
    if (all.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('…', style: TextStyle(color: AppColors.text2))),
      );
    }
    var mn = all.reduce(math.min), mx = all.reduce(math.max);
    if (mx - mn < 4) {
      mn -= 2;
      mx += 2;
    }
    return Column(children: [
      SizedBox(
        height: height,
        child: Row(children: [
          SizedBox(
            width: 38,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mx.toStringAsFixed(0),
                    style: const TextStyle(fontSize: 10, color: AppColors.text2)),
                Text(((mx + mn) / 2).toStringAsFixed(0),
                    style: const TextStyle(fontSize: 10, color: AppColors.text2)),
                Text(mn.toStringAsFixed(0),
                    style: const TextStyle(fontSize: 10, color: AppColors.text2)),
              ],
            ),
          ),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _TrendPainter(series, mn, mx),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 14, children: [
        for (final s in series)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 3, color: s.color),
            const SizedBox(width: 4),
            Text(
                '${s.name}${s.values.isNotEmpty && !s.values.last.isNaN ? ': ${s.values.last.toStringAsFixed(0)} $unit' : ''}',
                style: const TextStyle(fontSize: 11)),
          ]),
      ]),
    ]);
  }
}

class _TrendPainter extends CustomPainter {
  final List<TrendSeries> series;
  final double mn, mx;
  _TrendPainter(this.series, this.mn, this.mx);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (final s in series) {
      final v = s.values;
      if (v.length < 2) continue;
      final path = Path();
      var started = false;
      for (var i = 0; i < v.length; i++) {
        if (v[i].isNaN) {
          started = false;
          continue;
        }
        final x = size.width * i / (v.length - 1);
        final y = size.height - size.height * (v[i] - mn) / (mx - mn);
        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = s.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2
            ..strokeJoin = StrokeJoin.round);
      if (!v.last.isNaN) {
        final y = size.height - size.height * (v.last - mn) / (mx - mn);
        canvas.drawCircle(Offset(size.width, y), 4, Paint()..color = s.color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => true;
}

/// Donut chart with legend.
class Donut extends StatelessWidget {
  final List<String> labels;
  final List<double> values;
  final String center;
  final String sub;
  const Donut({
    super.key,
    required this.labels,
    required this.values,
    required this.center,
    this.sub = '',
  });

  static const palette = [
    AppColors.cyan,
    AppColors.purple,
    AppColors.green,
    AppColors.amber,
    AppColors.blue,
    AppColors.red,
    AppColors.text2,
  ];

  @override
  Widget build(BuildContext context) {
    final total = values.fold<double>(0, (a, b) => a + b);
    return Row(children: [
      SizedBox(
        width: 140,
        height: 140,
        child: Stack(alignment: Alignment.center, children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, t, __) => CustomPaint(
              size: const Size(140, 140),
              painter: _DonutPainter(values, total, t),
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            if (sub.isNotEmpty)
              Text(sub, style: const TextStyle(fontSize: 10, color: AppColors.text2)),
          ]),
        ]),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: palette[i % palette.length], shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(labels[i],
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                ),
                Text(total > 0 ? '${(values[i] / total * 100).toStringAsFixed(0)}%' : '',
                    style: const TextStyle(fontSize: 12, color: AppColors.text2)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final double total;
  final double t;
  _DonutPainter(this.values, this.total, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(10, 10, size.width - 20, size.height - 20);
    canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = AppColors.surface2
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18);
    if (total <= 0) return;
    var a = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = math.pi * 2 * values[i] / total * t;
      canvas.drawArc(
          rect,
          a,
          math.max(0.0, sweep - 0.03),
          false,
          Paint()
            ..color = Donut.palette[i % Donut.palette.length]
            ..style = PaintingStyle.stroke
            ..strokeWidth = 18);
      a += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.t != t || old.total != total;
}
