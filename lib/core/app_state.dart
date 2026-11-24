import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/extender_api.dart';
import '../api/router_api.dart';
import 'format.dart';
import 'speedtest.dart';
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
  bool viaExtender;
  bool isExtender;
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
    this.viaExtender = false,
    this.isExtender = false,
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
  String band; // 'both' | '2.4' | '5'  (which WiFi band the device may use)

  DeviceRule({
    required this.mac,
    this.name = '',
    this.blocked = false,
    this.scheduleOn = false,
    this.from = '22:00',
    this.to = '07:00',
    List<int>? days,
    this.band = 'both',
  }) : days = days ?? [1, 2, 3, 4, 5, 6, 7];

  Map<String, dynamic> toJson() => {
        'mac': mac,
        'name': name,
        'blocked': blocked,
        'scheduleOn': scheduleOn,
        'from': from,
        'to': to,
        'days': days,
        'band': band,
      };

  factory DeviceRule.fromJson(Map<String, dynamic> j) => DeviceRule(
        mac: j['mac'] ?? '',
        name: j['name'] ?? '',
        blocked: j['blocked'] ?? false,
        scheduleOn: j['scheduleOn'] ?? false,
        from: j['from'] ?? '22:00',
        to: j['to'] ?? '07:00',
        days: (j['days'] as List?)?.map((e) => e as int).toList(),
        band: j['band'] ?? 'both',
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

/// One network configuration tested by the optimizer.
class OptConfig {
  final String id;
  final String labelAr;
  final String labelEn;
  final String mode; // NetworkMode code
  final String? mask; // LTE band mask, null = all bands
  const OptConfig(this.id, this.labelAr, this.labelEn, this.mode, this.mask);
}

class OptResult {
  final OptConfig cfg;
  double rsrp = 0, sinr = 0, nrRsrp = 0, nrSinr = 0;
  double mbps = 0;
  double upMbps = 0;
  bool has5g = false;
  bool ok = false;
  String bands = '';
  OptResult(this.cfg);
  // speed matters most; signal quality breaks ties and favours stability
  double get score => ok ? mbps + (has5g ? nrSinr : sinr) * 1.5 : -999;
}

enum AdviceLevel { good, info, warn, bad }

enum AdviceAction { none, autoMode, scan, unlock }

class Advice {
  final AdviceLevel level;
  final String title;
  final String body;
  final AdviceAction action;
  Advice(this.level, this.title, this.body, {this.action = AdviceAction.none});
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
  String unit = 'Mbps';
  int autoTestMin = 0; // 0 = off

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
  List<Map<String, dynamic>> extHosts = [];
  final List<double> dlHistory = [];
  final List<double> ulHistory = [];
  final List<double> testHistory = [];
  final List<double> rsrpHistory = [];
  final List<double> sinrHistory = [];
  final List<double> nrRsrpHistory = [];
  final List<double> nrSinrHistory = [];

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
  bool routerSupportsPerDeviceRate = false;

  Timer? _fast;
  Timer? _slow;
  Timer? _minute;
  int _tick = 0;
  int _minutes = 0;

  // ----- speed test results -----
  double lastTestDl = 0; // Mbps
  double lastTestUl = 0;
  int lastPing = -1;
  String lastTestAt = '';
  bool testing = false;
  double liveTest = 0;

  // ----- band scan -----
  bool scanning = false;
  String scanStatus = '';

  /// Tab requested by a widget (e.g. tapping the devices counter).
  final ValueNotifier<int?> tabRequest = ValueNotifier<int?>(null);
  void openTab(int i) => tabRequest.value = i;

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
    unit = p.getString('unit') ?? 'Mbps';
    speedUnit = unit;
    autoTestMin = p.getInt('autoTestMin') ?? 0;
    preferredServer = p.getString('prefServer') ?? '';
    lastTestDl = p.getDouble('lastTestDl') ?? 0;
    lastTestUl = p.getDouble('lastTestUl') ?? 0;
    lastTestAt = p.getString('lastTestAt') ?? '';
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
    await p.setString('unit', unit);
    await p.setInt('autoTestMin', autoTestMin);
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
    _minute = Timer.periodic(const Duration(minutes: 1), (_) {
      enforceRules();
      _minutes++;
      if (autoTestMin > 0 && _minutes % autoTestMin == 0) runSpeedTest();
    });
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
      await _safe(() async {
        signal = await api.signal();
        void push(List<double> l, String k) {
          final v = signal.s(k).isEmpty ? double.nan : signal.d(k);
          l.add(v);
          if (l.length > 150) l.removeAt(0);
        }

        push(rsrpHistory, 'rsrp');
        push(sinrHistory, 'sinr');
        push(nrRsrpHistory, 'nrrsrp');
        push(nrSinrHistory, 'nrsinr');
      });
      await _safe(() async => status = await api.status());
    }
    notifyListeners();
  }

  Future<void> _pollSlow() async {
    if (!connected) return;
    await _safe(() async => month = await api.monthStats());
    // live WiFi clients (router)
    final wlan = <String, Map<String, dynamic>>{};
    bool wlanOk = false;
    try {
      for (final h in await api.wlanHosts()) {
        final m = normMac(h.s('MacAddress'));
        if (m.isNotEmpty) wlan[m] = h;
      }
      wlanOk = true;
    } catch (_) {}
    // clients of the extender (if logged in)
    final extMacs = <String>{};
    if (ext?.loggedIn == true && ext?.mode == 'json') {
      try {
        extHosts = await ext!.hosts();
        for (final h in extHosts) {
          final m = normMac('${h['MACAddress'] ?? h['MacAddress'] ?? ''}');
          final act = '${h['Active'] ?? h['active'] ?? 'true'}'.toLowerCase();
          if (m.isNotEmpty && act != 'false' && act != '0') extMacs.add(m);
        }
      } catch (_) {}
    }
    await _safe(() async {
      final hs = await api.hosts();
      final now = DateTime.now();
      final dt = _lastHostPoll == null
          ? 0.0
          : now.difference(_lastHostPoll!).inMilliseconds / 1000.0;
      _lastHostPoll = now;
      final list = <DeviceInfo>[];
      bool anyRate = false;
      String extenderMac = '';
      for (final h in hs) {
        final mac = normMac(h.s('MacAddress'));
        if (mac.isEmpty) continue;
        final raw = Map<String, dynamic>.from(h);
        final w = wlan[mac];
        if (w != null) {
          w.forEach((k, v) {
            if (v is String && !raw.containsKey(k)) raw[k] = v;
          });
        }
        final name = [raw.s('ActualName'), raw.s('HostName'), raw.s('DeviceName')]
            .firstWhere((e) => e.isNotEmpty && e.toLowerCase() != 'unknown', orElse: () => '');
        final rx = _rateField(raw, true);
        final tx = _rateField(raw, false);
        if (rx > 0 || tx > 0) anyRate = true;
        final iface = _iface(raw);
        final ip = raw.s('IpAddress').split(';').first;
        final isExt = _looksLikeExtender(name, ip);
        if (isExt) extenderMac = mac;
        final d = DeviceInfo(
          mac: mac,
          name: name.isNotEmpty ? name : (deviceNames[mac] ?? mac),
          ip: ip,
          active: _isActive(h, mac, iface, wlan.keys.toSet(), wlanOk, extMacs),
          iface: iface,
          connectedSec: raw.i('AssociatedTime', raw.i('ConnectionTime', raw.i('OnlineTime', 0))),
          rxRate: rx,
          txRate: tx,
          isExtender: isExt,
          viaExtender: extMacs.contains(mac),
          raw: raw,
        );
        if (name.isNotEmpty) deviceNames[mac] = name;
        if (dt > 0 && dt < 120 && d.active) {
          deviceBytes[mac] = (deviceBytes[mac] ?? 0) + ((rx + tx) * dt).round();
        }
        list.add(d);
      }
      // devices whose host record points at the extender MAC are behind it
      if (extenderMac.isNotEmpty) {
        for (final d in list) {
          if (d.mac == extenderMac) continue;
          final points = d.raw.entries.any((e) =>
              e.value is String &&
              e.key.toLowerCase() != 'macaddress' &&
              normMac(e.value as String) == extenderMac);
          if (points) d.viaExtender = true;
        }
      }
      routerSupportsPerDeviceRate = anyRate;
      list.sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        return (b.rxRate + b.txRate).compareTo(a.rxRate + a.txRate);
      });
      devices = list;
    });
    await _saveUsage();
    notifyListeners();
  }

  bool _isActive(Map<String, dynamic> h, String mac, String iface, Set<String> wlanMacs,
      bool wlanOk, Set<String> extMacs) {
    if (wlanMacs.contains(mac) || extMacs.contains(mac)) return true;
    for (final k in ['Active', 'active', 'Online', 'online', 'IsActive', 'Status', 'status']) {
      final v = h[k];
      if (v is String && v.isNotEmpty) {
        final l = v.toLowerCase();
        return l == '1' || l == 'true' || l == 'online' || l == 'active' || l == 'connected';
      }
    }
    if (iface == 'LAN') return true;
    return !wlanOk;
  }

  bool _looksLikeExtender(String name, String ip) {
    final n = name.toLowerCase();
    if (extenderIp.isNotEmpty && ip == extenderIp) return true;
    return n.contains('wa8021') || n.contains('echolife') || n.contains('wa80');
  }

  DeviceInfo? get extenderDevice {
    for (final d in devices) {
      if (d.isExtender) return d;
    }
    return null;
  }

  List<DeviceInfo> get activeDevices => devices.where((d) => d.active).toList();

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

  // ================= optimizer =================
  List<OptResult> optResults = [];
  OptResult? optBaseline;
  String _optOrigMode = '00';
  String _optOrigMask = '';

  /// Configurations the optimizer can try.
  List<OptConfig> get optConfigs {
    final list = <OptConfig>[
      const OptConfig('auto', 'تلقائي 4G+5G (الافتراضي)', 'Auto 4G+5G (default)', '00', null),
    ];
    if (availableModes.contains('03')) {
      list.add(const OptConfig('4g', '4G فقط', '4G only', '03', null));
    }
    for (final b in supportedLteBands) {
      list.add(OptConfig('b$b', 'تلقائي + قفل B$b', 'Auto + lock B$b', '00', lteBandMask(b)));
    }
    return list;
  }

  Future<void> optimize(List<OptConfig> configs, {bool withSpeed = true}) async {
    if (scanning) return;
    scanning = true;
    optResults = [];
    _optOrigMode = netMode.s('NetworkMode', '00');
    _optOrigMask = netMode.s('LTEBand', '7FFFFFFFFFFFFFFF');
    notifyListeners();
    try {
      for (var i = 0; i < configs.length; i++) {
        if (!scanning) break;
        final c = configs[i];
        final label = t(c.labelAr, c.labelEn);
        scanStatus = '${i + 1}/${configs.length} · ${t('تطبيق', 'Applying')} $label';
        notifyListeners();
        final r = OptResult(c);
        try {
          await api.setNetMode(mode: c.mode, lteBand: c.mask ?? '7FFFFFFFFFFFFFFF');
          // wait for the modem to re-attach (and 5G to come back)
          await Future.delayed(const Duration(seconds: 15));
          double rsrp = 0, sinr = 0, nr = 0, nrs = 0;
          int n = 0, n5 = 0;
          for (var k = 0; k < 3; k++) {
            final sg = await api.signal();
            if (sg.s('rsrp').isNotEmpty) {
              rsrp += sg.d('rsrp');
              sinr += sg.d('sinr');
              n++;
            }
            if (sg.s('nrrsrp').isNotEmpty) {
              nr += sg.d('nrrsrp');
              nrs += sg.d('nrsinr');
              n5++;
            }
            r.bands = parseCarriers(sg.s('band')).map((e) => e.label).join('+');
            await Future.delayed(const Duration(seconds: 2));
          }
          if (n > 0 || n5 > 0) {
            r.ok = true;
            if (n > 0) {
              r.rsrp = rsrp / n;
              r.sinr = sinr / n;
            }
            if (n5 > 0) {
              r.has5g = true;
              r.nrRsrp = nr / n5;
              r.nrSinr = nrs / n5;
            }
            if (withSpeed) {
              scanStatus = '${i + 1}/${configs.length} · ${t('قياس السرعة', 'Speed test')} $label';
              notifyListeners();
              r.mbps = await quickDownload();
            }
          }
        } catch (e) {
          log('optimize ${c.id}: $e');
        }
        if (c.id == 'auto') optBaseline = r;
        optResults.add(r);
        notifyListeners();
      }
    } finally {
      scanStatus = t('إرجاع إعداداتك الأصلية...', 'Restoring your settings...');
      notifyListeners();
      try {
        await api.setNetMode(mode: _optOrigMode, lteBand: _optOrigMask);
        netMode = await api.netMode();
      } catch (_) {}
      scanning = false;
      scanStatus = '';
      notifyListeners();
    }
  }

  OptResult? get optBest {
    final ok = optResults.where((r) => r.ok).toList();
    if (ok.isEmpty) return null;
    ok.sort((a, b) => b.score.compareTo(a.score));
    return ok.first;
  }

  Future<String?> applyOpt(OptResult r) async {
    try {
      await api.setNetMode(mode: r.cfg.mode, lteBand: r.cfg.mask ?? '7FFFFFFFFFFFFFFF');
      netMode = await api.netMode();
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> resetNetworkDefault() async {
    try {
      await api.setNetMode(mode: '00', lteBand: '7FFFFFFFFFFFFFFF');
      netMode = await api.netMode();
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
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

  String _appliedSig = '';

  /// Builds a blacklist per SSID: fully-blocked devices on every SSID, plus
  /// devices limited to one WiFi band are blacklisted on the other band's SSIDs.
  Future<String?> enforceRules({bool force = false}) async {
    if (!connected) return null;
    final now = DateTime.now();
    final full = rules.values.where((r) => r.shouldBlock(now)).map((r) => r.mac).toSet();
    final no24 = rules.values.where((r) => r.band == '5').map((r) => r.mac).toSet();
    final no5 = rules.values.where((r) => r.band == '2.4').map((r) => r.mac).toSet();
    final sig = jsonEncode([
      (full.toList()..sort()),
      (no24.toList()..sort()),
      (no5.toList()..sort()),
    ]);
    if (!force && sig == _appliedSig) return null;
    try {
      final filters = await api.macFilter();
      if (filters.isEmpty) throw ApiException('100002');
      List<Map<String, dynamic>> basics = [];
      try {
        basics = await api.wifiSsids();
      } catch (_) {}
      final out = <Map<String, dynamic>>[];
      for (var k = 0; k < filters.length; k++) {
        final m = Map<String, dynamic>.from(filters[k]);
        // find the band of this SSID: own fields, else matching basic entry by Index/ID/position
        var band = _bandOf(m);
        if (band == '?') {
          Map<String, dynamic>? match;
          for (final b in basics) {
            final sameIdx = m.s('Index').isNotEmpty && b.s('Index') == m.s('Index');
            final sameId = m.s('ID').isNotEmpty && b.s('ID') == m.s('ID');
            if (sameIdx || sameId) match = b;
          }
          match ??= k < basics.length ? basics[k] : null;
          if (match != null) band = _bandOf(match);
        }
        final list = <String>{
          ...full,
          if (band == '2.4') ...no24,
          if (band == '5') ...no5,
        }.toList();
        if (list.length > 10) {
          return t('الحد الأقصى 10 أجهزة لكل شبكة', 'Max 10 devices per network');
        }
        m['WifiMacFilterStatus'] = list.isEmpty ? '0' : '2';
        for (var i = 0; i < 10; i++) {
          m['WifiMacFilterMac$i'] = i < list.length ? list[i] : '';
          if (m.containsKey('wifihostname$i')) {
            m['wifihostname$i'] = i < list.length ? (rules[list[i]]?.name ?? '') : '';
          }
        }
        out.add(m);
      }
      await api.saveMacFilter(out);
      _appliedSig = sig;
      log(t('تم تحديث قواعد الأجهزة', 'Device rules applied'));
      notifyListeners();
      return null;
    } catch (e) {
      log('rules: $e');
      return e.toString();
    }
  }

  Future<String?> setDeviceBand(String mac, String band, {String name = ''}) async {
    final r = ruleFor(mac, name);
    r.band = band;
    await saveRules();
    return enforceRules(force: true);
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
    final ed = extenderDevice;
    if (ed != null && ed.ip.isNotEmpty) return ed.ip;
    for (final d in devices) {
      final n = d.name.toLowerCase();
      if (n.contains('wa8021') || n.contains('echolife') || n.contains('huawei-wa') ||
          (n.contains('huawei') && !n.contains('phone'))) {
        return d.ip;
      }
    }
    return extenderIp.isNotEmpty ? extenderIp : '192.168.101.1';
  }

  String extenderUser = 'admin';

  Future<String?> connectExtender(String ip, String pass, {String user = 'admin'}) async {
    extenderIp = ip.trim();
    extenderPass = pass;
    extenderUser = user.trim().isEmpty ? 'admin' : user.trim();
    await saveSettings();
    ext?.dispose();
    ext = ExtenderApi(extenderIp)..onLog = log;
    try {
      await ext!.login(pass, user: extenderUser);
      log('extender login ok (${ext!.mode})');
      notifyListeners();
      return null;
    } catch (e) {
      notifyListeners();
      return e.toString();
    }
  }

  /// Finds devices on the network that serve a Huawei web panel (the extender).
  Future<List<(String, String)>> discoverExtenders() async {
    final ips = <String>{
      for (final d in devices)
        if (d.active && d.ip.isNotEmpty) d.ip,
      '192.168.101.1',
      if (extenderIp.isNotEmpty) extenderIp,
    }..remove(routerIp);
    Future<(String, String)?> probe(String ip) async {
      final c = http.Client();
      try {
        final r = await c.get(Uri.parse('http://$ip/')).timeout(const Duration(seconds: 2));
        final body = r.body.toLowerCase();
        final server = (r.headers['server'] ?? '').toLowerCase();
        final hit = body.contains('huawei') ||
            body.contains('echolife') ||
            body.contains('csrf_token') ||
            body.contains('login.cgi') ||
            body.contains('getrandcount') ||
            server.contains('huawei');
        if (!hit) return null;
        final title = RegExp(r'<title>([^<]*)</title>', caseSensitive: false)
                .firstMatch(r.body)
                ?.group(1)
                ?.trim() ??
            'Huawei';
        return (ip, title.isEmpty ? 'Huawei' : title);
      } catch (_) {
        return null;
      } finally {
        c.close();
      }
    }

    final res = await Future.wait(ips.map(probe));
    final found = res.whereType<(String, String)>().toList();
    log('discover: ${found.map((e) => e.$1).join(', ')}');
    return found;
  }

  // ================= WiFi channel planning =================
  /// Channels the router reports (key -> value), if any.
  Future<Map<String, String>> routerChannels() async {
    final out = <String, String>{};
    for (final p in ['wlan/multi-basic-settings', 'wlan/basic-settings', 'wlan/wifiprofile']) {
      try {
        final raw = await api.getRaw(p);
        for (final m in RegExp(r'<(\w*[Cc]hannel\w*)>([^<]*)</').allMatches(raw)) {
          out['${p.split('/').last}.${m.group(1)}'] = m.group(2)!;
        }
      } catch (_) {}
    }
    return out;
  }

  /// Suggested extender channels that do not overlap with the router's.
  (String, String) suggestExtenderChannels(Map<String, String> routerCh) {
    final nums = routerCh.values.map((v) => int.tryParse(v) ?? 0).where((v) => v > 0).toList();
    final r24 = nums.where((v) => v <= 14).toList();
    final r5 = nums.where((v) => v > 14).toList();
    String ch24 = '11';
    if (r24.isNotEmpty) {
      final rc = r24.first;
      // pick the 1/6/11 channel farthest from the router channel
      final opts = [1, 6, 11]..sort((a, b) => (b - rc).abs().compareTo((a - rc).abs()));
      ch24 = '${opts.first}';
    }
    String ch5 = '149';
    if (r5.isNotEmpty && r5.first >= 100) ch5 = '36';
    return (ch24, ch5);
  }

  // ================= units =================
  void setUnit(String u) {
    unit = u;
    speedUnit = u;
    saveSettings();
    notifyListeners();
  }

  void setAutoTest(int minutes) {
    autoTestMin = minutes;
    saveSettings();
    notifyListeners();
  }

  // ================= speed test (shared) =================
  String testPhase = ''; // ping / down / up
  String testServer = '';
  double liveTestUl = 0;
  int lastJitter = 0;
  SpeedServer? _server;
  DateTime? _serverAt;

  List<SpeedServer> speedServers = [];
  String preferredServer = ''; // base url chosen by the user ('' = automatic)
  double routerDuringTest = 0; // Mbps seen by the router during the download phase
  List<String> testNotes = [];

  Future<SpeedServer> _bestServer(SpeedTester t, {bool force = false}) async {
    if (speedServers.isEmpty || force) {
      speedServers = await t.servers();
    }
    if (preferredServer.isNotEmpty) {
      for (final s in speedServers) {
        if (s.base == preferredServer) return s;
      }
    }
    if (!force &&
        _server != null &&
        _serverAt != null &&
        DateTime.now().difference(_serverAt!).inMinutes < 30) {
      return _server!;
    }
    // probe the first two candidates and keep the one that really delivers more
    SpeedServer best = speedServers.first;
    var bestMbps = -1.0;
    for (final cand in speedServers.take(2)) {
      final m = await t.probe(cand);
      t.notes.add('probe ${cand.name}: ${m.toStringAsFixed(1)} Mbps');
      if (m > bestMbps) {
        bestMbps = m;
        best = cand;
      }
    }
    _server = best;
    _serverAt = DateTime.now();
    return best;
  }

  Future<void> setPreferredServer(String base) async {
    preferredServer = base;
    _server = null;
    await _prefs?.setString('prefServer', base);
    notifyListeners();
  }

  Future<void> runSpeedTest() async {
    if (testing) return;
    testing = true;
    liveTest = 0;
    liveTestUl = 0;
    routerDuringTest = 0;
    testPhase = 'ping';
    notifyListeners();
    final tester = SpeedTester();
    try {
      final srv = await _bestServer(tester);
      final (_, ping, jit) = await tester.pickServer([srv]);
      lastPing = ping;
      lastJitter = jit;
      testServer = srv.name;
      testPhase = 'down';
      notifyListeners();
      final startIdx = dlHistory.length;
      lastTestDl = await tester.download(srv, (v) {
        liveTest = v;
        notifyListeners();
      });
      final during = dlHistory.length > startIdx ? dlHistory.sublist(startIdx) : <double>[];
      if (during.isNotEmpty) {
        routerDuringTest = during.reduce(math.max) * 8 / 1e6;
      }
      liveTest = lastTestDl;
      testPhase = 'up';
      notifyListeners();
      lastTestUl = await tester.upload(srv, (v) {
        liveTestUl = v;
        notifyListeners();
      });
      liveTestUl = lastTestUl;
      final n = DateTime.now();
      lastTestAt =
          '${dayKey(n)} ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
      testHistory.add(lastTestDl);
      if (testHistory.length > 20) testHistory.removeAt(0);
      await _prefs?.setDouble('lastTestDl', lastTestDl);
      await _prefs?.setDouble('lastTestUl', lastTestUl);
      await _prefs?.setString('lastTestAt', lastTestAt);
    } catch (e) {
      log('speedtest: $e');
    } finally {
      testNotes = List.of(tester.notes);
      for (final n in testNotes) {
        log('speedtest: $n');
      }
      testing = false;
      testPhase = '';
      notifyListeners();
    }
  }

  /// Short download test used by the band finder.
  Future<double> quickDownload() async {
    final t = SpeedTester(downTime: const Duration(milliseconds: 3500));
    try {
      final srv = await _bestServer(t);
      return await t.download(srv, (_) {});
    } catch (_) {
      return 0;
    }
  }

  // ================= carriers / capacity =================
  List<Carrier> get carriers {
    final list = parseCarriers(signal.s('band'));
    final nr = signal.s('nrband');
    if (nr.isNotEmpty && !list.any((c) => c.isNr)) {
      list.add(Carrier('N$nr', signal.d('nrdlbandwidth'), signal.s('nrearfcn')));
    }
    if (list.isEmpty && signal.s('band').isNotEmpty) {
      list.add(Carrier('B${signal.s('band')}', signal.d('dlbandwidth'), signal.s('earfcn')));
    }
    return list;
  }

  /// Estimated max download the router can receive from the tower (Mbps).
  double get capacityMbps {
    var total = 0.0;
    for (final c in carriers) {
      final sinr = c.isNr ? signal.d('nrsinr', signal.d('sinr')) : signal.d('sinr');
      var mhz = c.mhz;
      if (mhz <= 0) mhz = c.isNr ? signal.d('nrdlbandwidth', 100) : signal.d('dlbandwidth', 20);
      total += estimateCapacityMbps(mhz, sinr, mimo: c.isNr ? 4 : 2);
    }
    return total;
  }

  // ================= snapshots (backup / restore) =================
  Map<String, dynamic>? get snapshot {
    final raw = _prefs?.getString('snapshot');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<String?> saveSnapshot() async {
    try {
      final nm = await api.netMode();
      List<Map<String, dynamic>> wifi = [];
      try {
        wifi = await api.wifiSsids();
      } catch (_) {}
      final n = DateTime.now();
      final snap = {
        'at': '${dayKey(n)} ${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}',
        'NetworkMode': nm.s('NetworkMode'),
        'LTEBand': nm.s('LTEBand'),
        'wifi': [
          for (final w in wifi)
            {'Index': w.s('Index'), 'ID': w.s('ID'), 'WifiEnable': w.s('WifiEnable')}
        ],
        'signal': {
          'rsrp': signal.s('rsrp'),
          'sinr': signal.s('sinr'),
          'nrrsrp': signal.s('nrrsrp'),
          'nrsinr': signal.s('nrsinr'),
        },
      };
      await _prefs?.setString('snapshot', jsonEncode(snap));
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> restoreSnapshot() async {
    final snap = snapshot;
    if (snap == null) return t('لا توجد نسخة محفوظة', 'No saved backup');
    try {
      await api.setNetMode(
          mode: '${snap['NetworkMode'] ?? '00'}', lteBand: '${snap['LTEBand'] ?? ''}');
      final saved = (snap['wifi'] as List?) ?? [];
      if (saved.isNotEmpty) {
        final cur = await api.wifiSsids();
        var changed = false;
        for (final c in cur) {
          for (final w in saved) {
            if (w is Map && '${w['ID']}${w['Index']}' == c.s('ID') + c.s('Index')) {
              if (c['WifiEnable'] != w['WifiEnable']) {
                c['WifiEnable'] = '${w['WifiEnable']}';
                changed = true;
              }
            }
          }
        }
        if (changed) await api.saveWifiSsids(cur);
      }
      netMode = await api.netMode();
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ================= advisor =================
  List<Advice> get advice {
    final out = <Advice>[];
    final rsrp = signal.d('rsrp');
    final sinr = signal.d('sinr');
    final nrrsrp = signal.d('nrrsrp');
    final nrsinr = signal.d('nrsinr');
    final mode = netMode.s('NetworkMode', '00');
    final locked = lockedLteBands;

    if (has5G && nrrsrp >= -95 && nrsinr >= 10) {
      out.add(Advice(AdviceLevel.good, t('إعدادك الحالي ممتاز', 'Current setup is excellent'),
          t('الراوتر متصل بـ 5G بإشارة قوية. اترك نوع الشبكة على "تلقائي" ولا تقفل الباندات.',
              'Strong 5G. Keep mode on Auto, no band lock.')));
    }
    if (has5G && nrsinr < 5) {
      out.add(Advice(AdviceLevel.warn, t('نقاء إشارة 5G منخفض', 'Low 5G SINR'),
          t('SINR = ${nrsinr.toStringAsFixed(0)} dB. حرّك الراوتر قرب نافذة وارفعه للأعلى، وأبعده عن الجدران والأجهزة. كل 3 dB أعلى = سرعة أكبر بشكل واضح.',
              'Move the router near a window and higher; away from walls.')));
    }
    if (!has5G && mode != '03') {
      out.add(Advice(AdviceLevel.warn, t('لا توجد إشارة 5G الآن', 'No 5G right now'),
          t('الراوتر يعمل على 4G فقط. جرّب مكاناً آخر في البيت (قرب نافذة باتجاه برج زين) ثم راقب مؤشر 5G في الرئيسية.',
              'Running on 4G only. Try another spot near a window.')));
    }
    if (mode == '03') {
      out.add(Advice(AdviceLevel.info, t('وضع 4G فقط مفعّل', '4G-only mode is on'),
          t('أنت تمنع الراوتر من استخدام 5G. إذا كانت 5G متوفرة عندك ارجع إلى "تلقائي" لسرعة أعلى بكثير.',
              'Switch to Auto to use 5G.'),
          action: AdviceAction.autoMode));
    }
    if (mode == '08') {
      out.add(Advice(AdviceLevel.warn, t('وضع 5G فقط مفعّل', '5G-only mode is on'),
          t('إذا انقطع الإنترنت أو أصبح غير مستقر ارجع إلى "تلقائي". شبكة زين 5G غالباً NSA وتحتاج 4G معها.',
              'Zain 5G is usually NSA and needs 4G; use Auto if unstable.'),
          action: AdviceAction.autoMode));
    }
    if (rsrp != 0 && rsrp < -105) {
      out.add(Advice(AdviceLevel.bad, t('إشارة 4G ضعيفة', 'Weak 4G signal'),
          t('RSRP = ${rsrp.toStringAsFixed(0)} dBm. الإشارة الجيدة أعلى من -95. غيّر مكان الراوتر أو استخدم "البحث عن أقوى تردد".',
              'Move the router or run the band finder.'),
          action: AdviceAction.scan));
    } else if (rsrp != 0 && sinr < 8 && locked.isEmpty) {
      out.add(Advice(AdviceLevel.info, t('يمكن تحسين 4G', '4G can be improved'),
          t('نقاء إشارة 4G متوسط (${sinr.toStringAsFixed(0)} dB). شغّل "البحث عن أقوى تردد" ليجرب الباندات ويختار الأفضل لك.',
              'Run the band finder to pick the best band.'),
          action: AdviceAction.scan));
    }
    if (locked.isNotEmpty) {
      out.add(Advice(AdviceLevel.info, t('باندات مقفولة: ${locked.map((b) => 'B$b').join(', ')}', 'Locked bands'),
          t('القفل مفيد إذا كان الباند المختار أقوى عندك. إذا تغير الحال (ازدحام مساءً مثلاً) أرجعه إلى "كل الباندات".',
              'Unlock if speed drops.'),
          action: AdviceAction.unlock));
    }
    final ext = extenderDevice;
    out.add(Advice(AdviceLevel.info, t('الواي فاي والمقوي', 'WiFi & extender'),
        t('اجعل 5 GHz للأجهزة القريبة (أسرع)، و 2.4 GHz للبعيدة وخلف الجدران. ضع المقوي في منتصف المسافة بين الراوتر والغرف البعيدة${ext == null ? '' : ' — المقوي ظاهر عند الراوتر ✓'}.',
            '5 GHz for near devices, 2.4 GHz for far. Place the extender half-way.')));
    return out;
  }

  // ================= router WiFi bands (2.4 / 5) =================
  String _bandOf(Map<String, dynamic> m) {
    final f = m.s('WifiFrequency', m.s('FrequencyBand'));
    final id = m.s('ID');
    if (f.isNotEmpty) return f.contains('5') ? '5' : '2.4';
    if (id.contains('Radio.2')) return '5';
    if (id.contains('Radio.1')) return '2.4';
    return '?';
  }

  bool _isGuest(Map<String, dynamic> m) =>
      m.s('wifiisguestnetwork') == '1' || m.s('WifiGuest') == '1';

  /// Returns {'2.4': bool, '5': bool} for the main (non-guest) networks.
  Future<Map<String, bool>> routerWifiBands() async {
    final l = await api.wifiSsids();
    final out = <String, bool>{};
    for (final m in l) {
      if (_isGuest(m)) continue;
      final b = _bandOf(m);
      out[b] = (out[b] ?? false) || m.s('WifiEnable') == '1';
    }
    return out;
  }

  Future<String?> setRouterWifiBands({required bool on24, required bool on5}) async {
    if (!on24 && !on5) return t('يجب تشغيل تردد واحد على الأقل', 'Keep at least one band on');
    try {
      final l = await api.wifiSsids();
      for (final m in l) {
        if (_isGuest(m)) continue;
        final b = _bandOf(m);
        if (b == '2.4') m['WifiEnable'] = on24 ? '1' : '0';
        if (b == '5') m['WifiEnable'] = on5 ? '1' : '0';
      }
      await api.saveWifiSsids(l);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ================= extender link quality (as seen by the router) =================
  Map<String, String> get extenderLink {
    final d = extenderDevice;
    final out = <String, String>{};
    if (d == null) return out;
    d.raw.forEach((k, v) {
      if (v is! String || v.isEmpty) return;
      final l = k.toLowerCase();
      if (l.contains('rssi') ||
          l.contains('signal') ||
          l.contains('snr') ||
          l.contains('rate') ||
          l.contains('speed') ||
          l.contains('frequency') ||
          l.contains('band') ||
          l.contains('channel')) {
        out[k] = v;
      }
    });
    return out;
  }

  // ================= diagnostics =================
  static const _diagPaths = [
    'device/information',
    'device/signal',
    'monitoring/status',
    'monitoring/traffic-statistics',
    'monitoring/month_statistics',
    'monitoring/start_date',
    'net/net-mode',
    'net/net-mode-list',
    'net/current-plmn',
    'lan/HostInfo',
    'wlan/host-list',
    'wlan/multi-basic-settings',
    'wlan/multi-macfilter-settings',
    'wlan/wifi-feature-switch',
    'wlan/basic-settings',
    'wlan/multi-switch-settings',
    'wlan/wifiprofile',
    'security/url-filter',
    'security/firewall-switch',
    'timerule/timerule',
    'statistic/statistics-feature-switch',
  ];

  Future<String> buildDiagnostics() async {
    final sb = StringBuffer('MHM NET5G diagnostics ${DateTime.now()}\n');
    final mask = RegExp(
        r'<(Imei|Imsi|Iccid|SerialNumber|Msisdn|WifiWpapsk|WifiWepKey\d?|Mac?Address1|Mac?Address2|WanIPAddress|WanIPv6Address)>([^<]*)</',
        caseSensitive: false);
    for (final p in _diagPaths) {
      String body;
      try {
        body = await api.getRaw(p);
      } catch (e) {
        body = 'ERROR $e';
      }
      body = body.replaceAllMapped(mask, (m) => '<${m.group(1)}>***</');
      sb.writeln('\n===== $p =====\n$body');
    }
    if (ext != null) {
      for (final p in [
        '/api/system/deviceinfo',
        '/api/system/HostInfo',
        '/api/ntwk/WlanBasic?showpass=false',
        '/api/ntwk/wlanradio',
        '/api/ntwk/wandetect',
        '/api/ntwk/repeaterinfo',
        '/api/ntwk/meshinfo',
        '/api/ntwk/wlan_channel',
      ]) {
        String body;
        try {
          body = jsonEncode(await ext!.getJson(p));
        } catch (e) {
          body = 'ERROR $e';
        }
        body = body.replaceAll(RegExp(r'"(WifiPass\w*|Password|KeyPassphrase|wpakey)"\s*:\s*"[^"]*"', caseSensitive: false), '"pass":"***"');
        sb.writeln('\n===== EXT $p =====\n$body');
      }
    } else {
      sb.writeln('\n(extender not connected)');
    }
    return sb.toString();
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
