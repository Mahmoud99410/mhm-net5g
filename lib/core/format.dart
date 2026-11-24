String fmtBytes(num bytes) {
  final b = bytes.toDouble();
  if (b < 1024) return '${b.toStringAsFixed(0)} B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// bytes per second -> Mbps / Kbps text
String fmtRate(num bytesPerSec) {
  final bits = bytesPerSec * 8;
  if (bits < 1000 * 1000) return '${(bits / 1000).toStringAsFixed(0)} Kbps';
  return '${(bits / 1000 / 1000).toStringAsFixed(1)} Mbps';
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
