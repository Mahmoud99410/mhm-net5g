import 'dart:math' as math;

String fmtBytes(num bytes) {
  final b = bytes.toDouble();
  if (b < 1024) return '${b.toStringAsFixed(0)} B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// Speed display units.
const speedUnits = ['Mbps', 'MB/s', 'KB/s', 'Kbps'];
String speedUnit = 'Mbps';

/// bytes per second -> value in the selected unit.
double rateValue(num bytesPerSec, [String? unit]) {
  switch (unit ?? speedUnit) {
    case 'MB/s':
      return bytesPerSec / 1024 / 1024;
    case 'KB/s':
      return bytesPerSec / 1024;
    case 'Kbps':
      return bytesPerSec * 8 / 1000;
    default:
      return bytesPerSec * 8 / 1000 / 1000;
  }
}

String fmtRate(num bytesPerSec, [String? unit]) {
  final u = unit ?? speedUnit;
  final v = rateValue(bytesPerSec, u);
  final digits = v >= 100 ? 0 : (v >= 10 ? 1 : 2);
  return '${v.toStringAsFixed(digits)} $u';
}

/// Mbps (megabits) -> bytes/sec
double mbpsToBytes(double mbps) => mbps * 1000 * 1000 / 8;

/// One carrier parsed from Huawei "band" text, e.g. 10MHz@1250(B3)
class Carrier {
  final String band; // B3 / N78
  final double mhz;
  final String arfcn;
  Carrier(this.band, this.mhz, this.arfcn);
  bool get isNr => band.toUpperCase().startsWith('N');
  String get label => isNr ? 'n${band.substring(1)}' : band.toUpperCase();
}

List<Carrier> parseCarriers(String text) {
  final out = <Carrier>[];
  final re = RegExp(r'(\d+(?:\.\d+)?)\s*MHz\s*@\s*(\d+)\s*\(\s*([BbNn]\d+)\s*\)');
  for (final m in re.allMatches(text)) {
    out.add(Carrier(m.group(3)!, double.parse(m.group(1)!), m.group(2)!));
  }
  if (out.isEmpty) {
    final simple = RegExp(r'^\d+$').hasMatch(text.trim());
    if (simple) out.add(Carrier('B${text.trim()}', 0, ''));
  }
  return out;
}

/// Rough downlink capacity estimate (Mbps) from bandwidth + SINR (Shannon x MIMO x efficiency).
double estimateCapacityMbps(double mhz, double sinrDb, {int mimo = 2}) {
  if (mhz <= 0) return 0;
  final s = sinrDb.clamp(-5.0, 30.0);
  final lin = math.pow(10, s / 10).toDouble();
  final se = (math.log(1 + lin) / math.ln2).clamp(0.0, 7.4);
  return mhz * se * mimo * 0.6;
}

String fmtDuration(int seconds) {
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (d > 0) return '${d}ي ${h}س';
  if (h > 0) return '${h}س ${m}د';
  return '${m}د';
}

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDayKey(String k) {
  final p = k.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Start of the billing cycle that contains [now] for a reset day (1..31).
DateTime cycleStart(DateTime now, int resetDay) {
  int clampDay(int y, int m) {
    final last = DateTime(y, m + 1, 0).day;
    return resetDay > last ? last : resetDay;
  }

  final thisMonth = DateTime(now.year, now.month, clampDay(now.year, now.month));
  if (!now.isBefore(thisMonth)) return thisMonth;
  final pm = DateTime(now.year, now.month - 1, 1);
  return DateTime(pm.year, pm.month, clampDay(pm.year, pm.month));
}

DateTime nextCycleStart(DateTime now, int resetDay) {
  final s = cycleStart(now, resetDay);
  final nm = DateTime(s.year, s.month + 1, 1);
  final last = DateTime(nm.year, nm.month + 1, 0).day;
  return DateTime(nm.year, nm.month, resetDay > last ? last : resetDay);
}

String normMac(String mac) => mac.trim().toUpperCase().replaceAll('-', ':');

/// LTE band number -> hex bitmask used by Huawei (band n => bit n-1).
String lteBandMask(int band) => (BigInt.one << (band - 1)).toRadixString(16).toUpperCase();

List<int> bandsFromMask(String hexMask) {
  final v = BigInt.tryParse(hexMask, radix: 16);
  if (v == null) return [];
  final out = <int>[];
  for (var i = 0; i < 64; i++) {
    if (((v >> i) & BigInt.one) == BigInt.one) out.add(i + 1);
  }
  return out;
}
