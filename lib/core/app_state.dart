import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/extender_api.dart';
import '../api/router_api.dart';
import 'format.dart';
import 'xml_utils.dart';

class DeviceInfo {
  final String mac;
  String name;
  String ip;
  bool active;
  String iface; // wifi 2.4/5 / lan
  int connectedSec;
  double rxRate; // bytes/s if router reports
  double txRate;
  Map<String, dynamic> raw;

  DeviceInfo({
    required this.mac,
    this.name = '',
    this.ip = '',
    this.active = true,
    this.iface = '',
    this.connectedSec = 0,
    this.rxRate = 0,
    this.txRate = 0,
    this.raw = const {},
  });
}

class DeviceRule {
  String mac;
  String name;
  bool blocked;
  bool scheduleOn;
  String from; // HH:mm
  String to; // HH:mm
  List<int> days; // 1..7 (Mon..Sun)

  DeviceRule({
    required this.mac,
    this.name = '',
    this.blocked = false,
    this.scheduleOn = false,
    this.from = '22:00',
    this.to = '07:00',
    List<int>? days,
  }) : days = days ?? [1, 2, 3, 4, 5, 6, 7];

  Map<String, dynamic> toJson() => {
        'mac': mac,
        'name': name,
        'blocked': blocked,
        'scheduleOn': scheduleOn,
        'from': from,
        'to': to,
        'days': days,
      };

  factory DeviceRule.fromJson(Map<String, dynamic> j) => DeviceRule(
        mac: j['mac'] ?? '',
        name: j['name'] ?? '',
        blocked: j['blocked'] ?? false,
        scheduleOn: j['scheduleOn'] ?? false,
        from: j['from'] ?? '22:00',
        to: j['to'] ?? '07:00',
        days: (j['days'] as List?)?.map((e) => e as int).toList(),
      );

  int _min(String hm) {
    final p = hm.split(':');
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
  }

  bool inSchedule(DateTime now) {
    if (!scheduleOn) return false;
    final cur = now.hour * 60 + now.minute;
    final f = _min(from), t = _min(to);
    if (f == t) return false;
    if (f < t) return days.contains(now.weekday) && cur >= f && cur < t;
    // crosses midnight
    if (cur >= f) return days.contains(now.weekday);
    final yesterday = now.subtract(const Duration(days: 1)).weekday;
    return cur < t && days.contains(yesterday);
  }

  bool shouldBlock(DateTime now) => blocked || inSchedule(now);
}

class BandScanResult {
  final int band;
  double rsrp;
  double sinr;
  double rsrq;
  double mbps;
  bool ok;
  BandScanResult(this.band,
      {this.rsrp = -140, this.sinr = -20, this.rsrq = -30, this.mbps = 0, this.ok = false});
  double get score => ok ? sinr * 2 + (rsrp + 140) / 2 + mbps / 5 : -999;
}

const socialSites = <String, List<String>>{
  'Facebook': ['facebook.com', 'fbcdn.net', 'messenger.com'],
  'Instagram': ['instagram.com', 'cdninstagram.com'],
  'TikTok': ['tiktok.com', 'tiktokv.com', 'tiktokcdn.com'],
  'Snapchat': ['snapchat.com', 'sc-cdn.net'],
  'X / Twitter': ['twitter.com', 'x.com', 'twimg.com'],
  'YouTube': ['youtube.com', 'googlevideo.com', 'ytimg.com'],
  'Telegram': ['telegram.org', 't.me'],
  'WhatsApp': ['whatsapp.com', 'whatsapp.net'],
};

class AppState extends ChangeNotifier {
  SharedPreferences? _prefs;

  // ----- settings -----
  String lang = 'ar';
  String routerIp = '192.168.8.1';
  String routerUser = 'admin';
  String savedPass = '';
  bool remember = true;
  String extenderIp = '';
  String extenderPass = '';
  int resetDay = 16;
  double monthlyLimitGb = 0;

  // ----- runtime -----
  late HuaweiCpeApi api;
  ExtenderApi? ext;
  bool connecting = false;
  bool connected = false;
  String? lastError;
  final List<String> logs = [];

  Map<String, dynamic> status = {};
  Map<String, dynamic> signal = {};
  Map<String, dynamic> traffic = {};
  Map<String, dynamic> month = {};
  Map<String, dynamic> info = {};
  Map<String, dynamic> netMode = {};
  Map<String, dynamic> netModeList = {};
  String operatorName = '';
  List<DeviceInfo> devices = [];
  final List<double> dlHistory = [];
  final List<double> ulHistory = [];

  // ----- usage tracking -----
  Map<String, int> daily = {}; // day -> bytes
  Map<String, int> deviceBytes = {}; // mac -> bytes in current cycle
  Map<String, String> deviceNames = {}; // mac -> last name
  String cycleKey = '';
  int? _lastTotal;
  DateTime? _lastHostPoll;

  // ----- rules -----
  Map<String, DeviceRule> rules = {};
  List<String> blockedUrls = [];
  Set<String> _appliedBlock = {};
  bool routerSupportsPerDeviceRate = false;

  Timer? _fast;
  Timer? _slow;
  Timer? _minute;
  int _tick = 0;

  // ----- band scan -----
  bool scanning = false;
  String scanStatus = '';
  List<BandScanResult> scanResults = [];

  bool get ar => lang == 'ar';
  String t(String a, String e) => ar ? a : e;

  AppState() {
    api = HuaweiCpeApi(routerIp)..onLog = log;
  }

  void log(String s) {
    final now = DateTime.now();
    logs.insert(0,
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}  $s');
    if (logs.length > 300) logs.removeLast();
  }

  // ================= persistence =================
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    lang = p.getString('lang') ?? 'ar';
    routerIp = p.getString('routerIp') ?? '192.168.8.1';
    routerUser = p.getString('routerUser') ?? 'admin';
    savedPass = _unhide(p.getString('routerPass') ?? '');
    remember = p.getBool('remember') ?? true;
    extenderIp = p.getString('extenderIp') ?? '';
    extenderPass = _unhide(p.getString('extenderPass') ?? '');
    resetDay = p.getInt('resetDay') ?? 16;
    monthlyLimitGb = p.getDouble('limitGb') ?? 0;
    cycleKey = p.getString('cycleKey') ?? '';
    blockedUrls = p.getStringList('blockedUrls') ?? [];
    try {
      daily = Map<String, int>.from(jsonDecode(p.getString('daily') ?? '{}'));
      deviceBytes = Map<String, int>.from(jsonDecode(p.getString('deviceBytes') ?? '{}'));
      deviceNames = Map<String, String>.from(jsonDecode(p.getString('deviceNames') ?? '{}'));
      final r = jsonDecode(p.getString('rules') ?? '{}') as Map<String, dynamic>;
      rules = r.map((k, v) => MapEntry(k, DeviceRule.fromJson(Map<String, dynamic>.from(v))));
    } catch (_) {}
    api = HuaweiCpeApi(routerIp)..onLog = log;
    notifyListeners();
  }

  String _hide(String s) => base64.encode(utf8.encode(s.split('').reversed.join()));
  String _unhide(String s) {
    try {
      return utf8.decode(base64.decode(s)).split('').reversed.join();
    } catch (_) {
      return '';
    }
  }

  Future<void> saveSettings() async {
    final p = _prefs;
    if (p == null) return;
    await p.setString('lang', lang);
    await p.setString('routerIp', routerIp);
    await p.setString('routerUser', routerUser);
    await p.setString('routerPass', remember ? _hide(savedPass) : '');
    await p.setBool('remember', remember);
    await p.setString('extenderIp', extenderIp);
    await p.setString('extenderPass', remember ? _hide(extenderPass) : '');
    await p.setInt('resetDay', resetDay);
    await p.setDouble('limitGb', monthlyLimitGb);
    await p.setStringList('blockedUrls', blockedUrls);
  }

  Future<void> _saveUsage() async {
    final p = _prefs;
    if (p == null) return;
    await p.setString('daily', jsonEncode(daily));
    await p.setString('deviceBytes', jsonEncode(deviceBytes));
    await p.setString('deviceNames', jsonEncode(deviceNames));
    await p.setString('cycleKey', cycleKey);
  }

  Future<void> saveRules() async {
    await _prefs?.setString('rules', jsonEncode(rules.map((k, v) => MapEntry(k, v.toJson()))));
  }

  void setLang(String l) {
    lang = l;
    saveSettings();
    notifyListeners();
  }

  // ================= connection =================
  Future<bool> connect({String? ip, String? user, String? pass, bool? rememberMe}) async {
    connecting = true;
    lastError = null;
    notifyListeners();
    if (ip != null) routerIp = ip.trim();
    if (user != null) routerUser = user.trim();
    if (pass != null) savedPass = pass;
    if (rememberMe != null) remember = rememberMe;
    api.dispose();
    api = HuaweiCpeApi(routerIp)..onLog = log;
    try {
      await api.login(routerUser, savedPass);
      connected = true;
      log(t('تم تسجيل الدخول للراوتر', 'Logged in to router'));
      await saveSettings();
      await refreshAll();
      _startTimers();
    } catch (e) {
      lastError = e.toString();
      connected = false;
      log('Login error: $e');
    }
    connecting = false;
    notifyListeners();
    return connected;
  }

  Future<void> disconnect() async {
    _stopTimers();
    await api.logout();
    connected = false;
    savedPass = remember ? savedPass : '';
    notifyListeners();
  }

  void _startTimers() {
    _stopTimers();
    _fast = Timer.periodic(const Duration(seconds: 2), (_) => _pollFast());
    _slow = Timer.periodic(const Duration(seconds: 10), (_) => _pollSlow());
    _minute = Timer.periodic(const Duration(minutes: 1), (_) => enforceRules());
  }

  void _stopTimers() {
    _fast?.cancel();
    _slow?.cancel();
    _minute?.cancel();
  }

  Future<void> refreshAll() async {
    await Future.wait([
      _safe(() async => info = await api.deviceInfo()),
      _safe(() async => netMode = await api.netMode()),
      _safe(() async => netModeList = await api.netModeList()),
      _safe(() async => operatorName = (await api.plmn()).s('FullName')),
      _safe(() async {
        final sd = await api.startDate();
        final d = sd.i('StartDay', 0);
        if (d > 0 && d != resetDay && (_prefs?.getInt('resetDay') == null)) resetDay = d;
      }),
    ]);
    await _pollFast();
    await _pollSlow();
    await enforceRules();
  }

  Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      log('! $e');
    }
  }

  Future<void> _pollFast() async {
    if (!connected) return;
    _tick++;
    await _safe(() async {
      traffic = await api.traffic();
      final dl = traffic.d('CurrentDownloadRate');
      final ul = traffic.d('CurrentUploadRate');
      dlHistory.add(dl);
      ulHistory.add(ul);
      if (dlHistory.length > 90) dlHistory.removeAt(0);
      if (ulHistory.length > 90) ulHistory.removeAt(0);
      _trackUsage(traffic.d('TotalDownload').toInt() + traffic.d('TotalUpload').toInt());
    });
    if (_tick % 2 == 0) {
      await _safe(() async => signal = await api.signal());
      await _safe(() async => status = await api.status());
    }
    notifyListeners();
  }

  Future<void> _pollSlow() async {
    if (!connected) return;
    await _safe(() async => month = await api.monthStats());
    await _safe(() async {
      final hs = await api.hosts();
      final now = DateTime.now();
      final dt = _lastHostPoll == null
          ? 0.0
          : now.difference(_lastHostPoll!).inMilliseconds / 1000.0;
      _lastHostPoll = now;
      final list = <DeviceInfo>[];
      bool anyRate = false;
      for (final h in hs) {
        final mac = normMac(h.s('MacAddress'));
        if (mac.isEmpty) continue;
        final name = [h.s('ActualName'), h.s('HostName'), h.s('DeviceName')]
            .firstWhere((e) => e.isNotEmpty && e != 'unknown', orElse: () => '');
        final rx = _rateField(h, true);
        final tx = _rateField(h, false);
        if (rx > 0 || tx > 0) anyRate = true;
        final d = DeviceInfo(
          mac: mac,
          name: name.isNotEmpty ? name : (deviceNames[mac] ?? mac),
          ip: h.s('IpAddress').split(';').first,
          active: h.s('Active', '1') != '0' && h.s('Active', 'true') != 'false',
          iface: _iface(h),
          connectedSec: h.i('AssociatedTime', h.i('ConnectionTime', 0)),
          rxRate: rx,
          txRate: tx,
          raw: h,
        );
        if (name.isNotEmpty) deviceNames[mac] = name;
        if (dt > 0 && dt < 120 && d.active) {
          deviceBytes[mac] = (deviceBytes[mac] ?? 0) + ((rx + tx) * dt).round();
        }
        list.add(d);
      }
      routerSupportsPerDeviceRate = anyRate;
      list.sort((a, b) => (b.rxRate + b.txRate).compareTo(a.rxRate + a.txRate));
      devices = list;
    });
    await _saveUsage();
    notifyListeners();
  }

  String _iface(Map<String, dynamic> h) {
    final f = (h.s('Frequency') + h.s('InterfaceType') + h.s('Band')).toLowerCase();
    if (f.contains('5')) return '5GHz';
    if (f.contains('2.4') || f.contains('2g')) return '2.4GHz';
    if (f.contains('eth') || f.contains('lan')) return 'LAN';
    return f.isEmpty ? '' : f;
  }

  /// Looks for per-device rate fields in router host data (varies by firmware).
  double _rateField(Map<String, dynamic> h, bool down) {
    for (final e in h.entries) {
      final k = e.key.toLowerCase();
      if (e.value is! String) continue;
      final isDown = k.contains('down') || k.contains('rx');
      final isUp = k.contains('up') || k.contains('tx');
      final isRate = k.contains('rate') || k.contains('speed');
      if (!isRate || k.contains('max') || k.contains('phy') || k.contains('link')) continue;
      if ((down && isDown) || (!down && isUp)) {
        final v = double.tryParse((e.value as String).replaceAll(RegExp(r'[^0-9\.]'), ''));
        if (v != null) return k.contains('kbps') ? v * 1000 / 8 : v;
      }
    }
    return 0;
  }

  void _trackUsage(int total) {
    final now = DateTime.now();
    final ck = dayKey(cycleStart(now, resetDay));
    if (cycleKey != ck) {
      if (cycleKey.isNotEmpty) {
        log(t('بدأت دورة استهلاك جديدة', 'New usage cycle started'));
        deviceBytes.clear();
      }
      cycleKey = ck;
    }
    if (_lastTotal != null) {
      final delta = total - _lastTotal!;
      if (delta > 0 && delta < 5 * 1024 * 1024 * 1024) {
        final k = dayKey(now);
        daily[k] = (daily[k] ?? 0) + delta;
      }
    }
    _lastTotal = total;
  }

  int usageBetween(DateTime from, DateTime to) {
    var sum = 0;
    daily.forEach((k, v) {
      final d = parseDayKey(k);
      if (!d.isBefore(DateTime(from.year, from.month, from.day)) &&
          !d.isAfter(DateTime(to.year, to.month, to.day))) {
        sum += v;
      }
    });
    return sum;
  }

  int get cycleUsageApp => usageBetween(cycleStart(DateTime.now(), resetDay), DateTime.now());

  int get cycleUsageRouter =>
      (month.d('CurrentMonthDownload') + month.d('CurrentMonthUpload')).toInt();

  Future<String?> setResetDay(int day, {bool syncRouter = true}) async {
    resetDay = day;
    await saveSettings();
    notifyListeners();
    if (syncRouter && connected) {
      try {
        await api.setStartDay(day,
            dataLimit: monthlyLimitGb > 0 ? '${monthlyLimitGb.round()}GB' : null);
      } catch (e) {
        return e.toString();
      }
    }
    return null;
  }

  Future<String?> clearRouterCounters() async {
    try {
      await api.clearTraffic();
      daily.remove(dayKey(DateTime.now()));
      deviceBytes.clear();
      await _saveUsage();
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ================= signal helpers =================
  bool get has5G =>
      signal.s('nrrsrp').isNotEmpty ||
      ['111', '112', '113', '114', '115'].contains(status.s('CurrentNetworkTypeEx')) ||
      ['111', '112'].contains(status.s('CurrentNetworkType'));

  String get networkLabel {
    final ex = status.s('CurrentNetworkTypeEx', status.s('CurrentNetworkType'));
    if (has5G) {
      return signal.s('rsrp').isNotEmpty ? '5G NSA (4G+5G)' : '5G SA';
    }
    switch (ex) {
      case '19':
      case '101':
        return '4G LTE';
      case '1011':
        return '4G+ (LTE-A)';
      case '41':
      case '44':
      case '45':
      case '46':
        return '3G';
      case '0':
      case '':
        return t('لا توجد خدمة', 'No service');
    }
    return 'Type $ex';
  }

  static const modeLabelsAr = {
    '00': 'تلقائي (4G + 5G)',
    '03': '4G فقط',
    '08': '5G فقط',
    '0803': '5G + 4G',
    '0308': '4G + 5G',
    '02': '3G فقط',
    '01': '2G فقط',
  };
  static const modeLabelsEn = {
    '00': 'Auto (4G + 5G)',
    '03': '4G only',
    '08': '5G only',
    '0803': '5G + 4G',
    '0308': '4G + 5G',
    '02': '3G only',
    '01': '2G only',
  };

  String modeLabel(String code) =>
      (ar ? modeLabelsAr : modeLabelsEn)[code] ?? t('وضع $code', 'Mode $code');

  List<String> get availableModes {
    final acc = netModeList.m('AccessList');
    final raw = acc['Access'];
    final list = <String>[];
    if (raw is List) list.addAll(raw.map((e) => '$e'));
    if (raw is String && raw.isNotEmpty) list.add(raw);
    if (list.isEmpty) list.addAll(['00', '03', '08']);
    if (!list.contains('00')) list.insert(0, '00');
    return list.where((m) => m != '01' && m != '02').toList();
  }

  /// LTE bands supported by router (number list).
  List<int> get supportedLteBands {
    final out = <int>{};
    for (final b in netModeList.m('LTEBandList').list('LTEBand')) {
      out.addAll(bandsFromMask(b.s('Value')));
    }
    if (out.isEmpty) out.addAll([1, 3, 7, 8, 20, 28, 38, 40, 41]);
    final l = out.toList()..sort();
    return l;
  }

  List<int> get lockedLteBands {
    final m = netMode.s('LTEBand');
    if (m.isEmpty) return [];
    final b = bandsFromMask(m);
    return b.length > 40 ? [] : b; // all bands = auto
  }

  Future<String?> applyNetMode(String mode, List<int>? bands) async {
    try {
      String? mask;
      if (bands != null) {
        if (bands.isEmpty) {
          mask = '7FFFFFFFFFFFFFFF';
        } else {
          var v = BigInt.zero;
          for (final b in bands) {
            v |= BigInt.one << (b - 1);
          }
          mask = v.toRadixString(16).toUpperCase();
        }
      }
      await api.setNetMode(mode: mode, lteBand: mask);
      netMode = await api.netMode();
      log(t('تم تغيير وضع الشبكة', 'Network mode changed'));
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ================= speed test =================
  Future<double> measureDownload({int bytes = 15000000, void Function(double)? onProgress}) async {
    final c = http.Client();
    try {
      final sw = Stopwatch()..start();
      final req = http.Request(
          'GET', Uri.parse('https://speed.cloudflare.com/__down?bytes=$bytes'));
      final res = await c.send(req).timeout(const Duration(seconds: 20));
      var got = 0;
      await for (final chunk in res.stream.timeout(const Duration(seconds: 25))) {
        got += chunk.length;
        final s = sw.elapsedMilliseconds / 1000;
        if (s > 0) onProgress?.call(got * 8 / s / 1e6);
        if (sw.elapsed.inSeconds > 15) break;
      }
      final secs = sw.elapsedMilliseconds / 1000;
      return secs > 0 ? got * 8 / secs / 1e6 : 0;
    } catch (_) {
      return 0;
    } finally {
      c.close();
    }
  }

  Future<double> measureUpload({int bytes = 4000000}) async {
    final c = http.Client();
    try {
      final data = Uint8List(bytes);
      final sw = Stopwatch()..start();
      await c
          .post(Uri.parse('https://speed.cloudflare.com/__up'), body: data)
          .timeout(const Duration(seconds: 25));
      final secs = sw.elapsedMilliseconds / 1000;
      return secs > 0 ? bytes * 8 / secs / 1e6 : 0;
    } catch (_) {
      return 0;
    } finally {
      c.close();
    }
  }

  Future<int> measurePing() async {
    final c = http.Client();
    try {
      final times = <int>[];
      for (var i = 0; i < 4; i++) {
        final sw = Stopwatch()..start();
        await c
            .get(Uri.parse('https://speed.cloudflare.com/__down?bytes=0'))
            .timeout(const Duration(seconds: 5));
        times.add(sw.elapsedMilliseconds);
      }
      times.sort();
      return times.first;
    } catch (_) {
      return -1;
    } finally {
      c.close();
    }
  }

  // ================= best band scan =================
  Future<void> scanBands(List<int> bands, {bool withSpeed = true}) async {
    if (scanning) return;
    scanning = true;
    scanResults = [];
    final origMode = netMode.s('NetworkMode', '00');
    final origMask = netMode.s('LTEBand', '7FFFFFFFFFFFFFFF');
    notifyListeners();
    try {
      for (final b in bands) {
        if (!scanning) break;
        scanStatus = t('تجربة الباند B$b ...', 'Testing band B$b ...');
        notifyListeners();
        final r = BandScanResult(b);
        try {
          await api.setNetMode(mode: origMode, lteBand: lteBandMask(b));
          await Future.delayed(const Duration(seconds: 20));
          double rsrp = 0, sinr = 0, rsrq = 0;
          int n = 0;
          for (var i = 0; i < 3; i++) {
            final s = await api.signal();
            if (s.s('rsrp').isNotEmpty) {
              rsrp += s.d('rsrp');
              sinr += s.d('sinr');
              rsrq += s.d('rsrq');
              n++;
            }
            await Future.delayed(const Duration(seconds: 2));
          }
          if (n > 0) {
            r.rsrp = rsrp / n;
            r.sinr = sinr / n;
            r.rsrq = rsrq / n;
            r.ok = true;
            if (withSpeed) {
              scanStatus = t('قياس السرعة على B$b ...', 'Speed test on B$b ...');
              notifyListeners();
              r.mbps = await measureDownload(bytes: 8000000);
            }
          }
        } catch (e) {
          log('scan B$b: $e');
        }
        scanResults.add(r);
        notifyListeners();
      }
    } finally {
      scanStatus = t('إرجاع الإعدادات الأصلية...', 'Restoring original settings...');
      notifyListeners();
      try {
        await api.setNetMode(mode: origMode, lteBand: origMask);
        netMode = await api.netMode();
      } catch (_) {}
      scanResults.sort((a, b) => b.score.compareTo(a.score));
      scanning = false;
      scanStatus = '';
      notifyListeners();
    }
  }

  void stopScan() {
    scanning = false;
    notifyListeners();
  }

  // ================= devices / rules =================
  DeviceRule ruleFor(String mac, [String name = '']) =>
      rules.putIfAbsent(mac, () => DeviceRule(mac: mac, name: name));

  Future<String?> setBlocked(String mac, bool block, {String name = ''}) async {
    final r = ruleFor(mac, name);
    r.blocked = block;
    if (name.isNotEmpty) r.name = name;
    await saveRules();
    return enforceRules(force: true);
  }

  Future<String?> enforceRules({bool force = false}) async {
    if (!connected) return null;
    final now = DateTime.now();
    final want = rules.values.where((r) => r.shouldBlock(now)).map((r) => r.mac).toSet();
    if (!force && setEquals(want, _appliedBlock)) return null;
    try {
      final ssids = await api.macFilter();
      if (ssids.isEmpty) throw ApiException('100002');
      final macs = want.toList();
      if (macs.length > 10) {
        return t('الحد الأقصى 10 أجهزة محظورة', 'Max 10 blocked devices');
      }
      final out = <Map<String, dynamic>>[];
      for (final s in ssids) {
        final m = Map<String, dynamic>.from(s);
        m['WifiMacFilterStatus'] = macs.isEmpty ? '0' : '2';
        for (var i = 0; i < 10; i++) {
          m['WifiMacFilterMac$i'] = i < macs.length ? macs[i] : '';
          if (m.containsKey('wifihostname$i')) {
            m['wifihostname$i'] = i < macs.length ? (rules[macs[i]]?.name ?? '') : '';
          }
        }
        out.add(m);
      }
      await api.saveMacFilter(out);
      _appliedBlock = want;
      log(t('تم تحديث قائمة الحظر (${macs.length})', 'Block list updated (${macs.length})'));
      notifyListeners();
      return null;
    } catch (e) {
      log('block: $e');
      return e.toString();
    }
  }

  // ================= URL filter =================
  Future<String?> loadUrlFilters() async {
    try {
      final list = await api.urlFilters();
      final urls = list.map((e) => e.s('value', e.s('Value'))).where((e) => e.isNotEmpty).toList();
      if (urls.isNotEmpty) blockedUrls = urls;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> saveUrlFilters(List<String> urls) async {
    try {
      final clean = urls
          .map((u) => u
              .trim()
              .toLowerCase()
              .replaceFirst(RegExp(r'^https?://'), '')
              .replaceFirst(RegExp(r'^www\.'), '')
              .split('/')
              .first)
          .where((u) => u.isNotEmpty)
          .toSet()
          .toList();
      try {
        await api.enableUrlFilterSwitch();
      } catch (e) {
        log('firewall switch: $e');
      }
      await api.saveUrlFilters(clean);
      blockedUrls = clean;
      await saveSettings();
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ================= WiFi =================
  Future<List<Map<String, dynamic>>> loadWifi() => api.wifiSsids();

  Future<String?> saveWifi(List<Map<String, dynamic>> ssids) async {
    try {
      await api.saveWifiSsids(ssids);
      log(t('تم حفظ إعدادات الواي فاي — الشبكة ستعيد التشغيل', 'WiFi saved — restarting'));
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ================= Extender =================
  String guessExtenderIp() {
    for (final d in devices) {
      final n = d.name.toLowerCase();
      if (n.contains('wa8021') || n.contains('echolife') || n.contains('huawei-wa') ||
          (n.contains('huawei') && !n.contains('phone'))) {
        return d.ip;
      }
    }
    return extenderIp.isNotEmpty ? extenderIp : '192.168.101.1';
  }

  Future<String?> connectExtender(String ip, String pass) async {
    extenderIp = ip.trim();
    extenderPass = pass;
    await saveSettings();
    ext?.dispose();
    ext = ExtenderApi(extenderIp)..onLog = log;
    try {
      await ext!.login(pass);
      notifyListeners();
      return null;
    } catch (e) {
      notifyListeners();
      return e.toString();
    }
  }

  // ================= raw =================
  Future<String> raw(String path) async {
    try {
      return await api.getRaw(path.trim().replaceFirst(RegExp(r'^/+'), '').replaceFirst(RegExp(r'^api/'), ''));
    } catch (e) {
      return 'ERROR: $e';
    }
  }

  Future<String?> reboot() async {
    try {
      await api.reboot();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  @override
  void dispose() {
    _stopTimers();
    api.dispose();
    ext?.dispose();
    super.dispose();
  }
}
