import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/crypto_utils.dart';
import '../core/xml_utils.dart';

class ApiException implements Exception {
  final String code;
  final String message;
  ApiException(this.code, [this.message = '']);

  String get friendly {
    switch (code) {
      case '100002':
        return 'غير مدعوم في هذا الراوتر (100002)';
      case '100003':
        return 'لا توجد صلاحية — سجّل الدخول (100003)';
      case '100004':
        return 'الراوتر مشغول، حاول بعد قليل (100004)';
      case '100005':
        return 'بيانات غير صحيحة أرسلت للراوتر (100005)';
      case '108001':
      case '108002':
      case '108006':
        return 'اسم المستخدم أو كلمة المرور غير صحيحة';
      case '108003':
        return 'يوجد مستخدم آخر مسجل الدخول';
      case '108007':
        return 'محاولات كثيرة — انتظر قليلاً ثم حاول';
      case '125002':
      case '125003':
        return 'انتهت الجلسة — أعد تسجيل الدخول';
      case 'net':
        return 'لا يوجد اتصال بالراوتر. تأكد أنك متصل بشبكته';
    }
    return message.isNotEmpty ? message : 'خطأ من الراوتر ($code)';
  }

  @override
  String toString() => friendly;
}

/// Client for Huawei HiLink-style XML API (5G CPE 5 / H155-383 and similar).
class HuaweiCpeApi {
  String host;
  String username = 'admin';
  String? _password;
  final http.Client _c = http.Client();
  final Map<String, String> _cookies = {};
  final List<String> _tokens = [];
  bool loggedIn = false;
  void Function(String line)? onLog;

  HuaweiCpeApi(this.host);

  String get base => 'http://$host';

  void _log(String s) => onLog?.call(s);

  Map<String, String> _headers({bool post = false}) {
    final h = <String, String>{
      'X-Requested-With': 'XMLHttpRequest',
      '_ResponseSource': 'Broswer',
      'Accept': '*/*',
    };
    if (_cookies.isNotEmpty) {
      h['Cookie'] = _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }
    if (post) {
      h['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8';
    }
    if (_tokens.isNotEmpty) {
      h['__RequestVerificationToken'] = post ? _tokens.removeAt(0) : _tokens.first;
    }
    return h;
  }

  void _absorb(http.Response r) {
    final sc = r.headers['set-cookie'];
    if (sc != null) {
      for (final part in sc.split(RegExp(r',(?=[^;]+?=)'))) {
        final kv = part.split(';').first.trim();
        final idx = kv.indexOf('=');
        if (idx > 0) _cookies[kv.substring(0, idx)] = kv.substring(idx + 1);
      }
    }
    final newTokens = <String>[];
    for (final key in [
      '__requestverificationtokenone',
      '__requestverificationtokentwo',
      '__requestverificationtoken'
    ]) {
      final v = r.headers[key];
      if (v != null && v.isNotEmpty) {
        newTokens.addAll(v.split('#').where((e) => e.isNotEmpty));
      }
    }
    if (newTokens.isNotEmpty) {
      _tokens
        ..clear()
        ..addAll(newTokens);
    }
  }

  Map<String, dynamic> _parse(String path, String body) {
    dynamic parsed;
    try {
      parsed = XmlMap.parse(body);
    } catch (_) {
      throw ApiException('parse', 'رد غير مفهوم من $path');
    }
    final map = parsed as Map<String, dynamic>;
    if (map.containsKey('error')) {
      final e = map['error'];
      final code = e is Map<String, dynamic> ? e.s('code') : '$e';
      throw ApiException(code, e is Map<String, dynamic> ? e.s('message') : '');
    }
    final resp = map['response'];
    if (resp is Map<String, dynamic>) return resp;
    return {'value': resp?.toString() ?? ''};
  }

  Future<http.Response> _send(Future<http.Response> f) async {
    try {
      return await f.timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw ApiException('net');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('net', e.toString());
    }
  }

  Future<void> initSession() async {
    try {
      final r = await _send(_c.get(Uri.parse('$base/api/webserver/SesTokInfo'),
          headers: _headers()));
      _absorb(r);
      final m = _parse('SesTokInfo', r.body);
      final ses = m.s('SesInfo');
      if (ses.isNotEmpty) {
        final v = ses.startsWith('SessionID=') ? ses.substring(10) : ses;
        _cookies['SessionID'] = v;
      }
      final tok = m.s('TokInfo');
      if (tok.isNotEmpty) {
        _tokens
          ..clear()
          ..add(tok);
      }
      return;
    } on ApiException catch (e) {
      if (e.code == 'net') rethrow;
    }
    // Newer firmware: token from homepage meta + /api/webserver/token
    final home = await _send(_c.get(Uri.parse('$base/'), headers: _headers()));
    _absorb(home);
    final meta = RegExp(r'name="csrf_token"\s+content="([^"]+)"').allMatches(home.body);
    _tokens.clear();
    for (final m in meta) {
      _tokens.add(m.group(1)!);
    }
    if (_tokens.isEmpty) await _refreshToken();
  }

  Future<void> _refreshToken() async {
    final r = await _send(_c.get(Uri.parse('$base/api/webserver/token'), headers: _headers()));
    _absorb(r);
    final m = _parse('token', r.body);
    final t = m.s('token');
    if (t.isNotEmpty) {
      _tokens
        ..clear()
        ..add(t.length > 32 ? t.substring(t.length - 32) : t);
    }
  }

  Future<Map<String, dynamic>> get(String path, {bool retry = true}) async {
    final r = await _send(_c.get(Uri.parse('$base/api/$path'), headers: _headers()));
    _absorb(r);
    _log('GET $path → ${r.statusCode}');
    try {
      return _parse(path, r.body);
    } on ApiException catch (e) {
      if (retry && (e.code == '100003' || e.code.startsWith('12500')) && _password != null) {
        await login(username, _password!);
        return get(path, retry: false);
      }
      rethrow;
    }
  }

  Future<String> getRaw(String path) async {
    final r = await _send(_c.get(Uri.parse('$base/api/$path'), headers: _headers()));
    _absorb(r);
    return r.body;
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> data,
      {bool retry = true}) async {
    if (_tokens.isEmpty) {
      try {
        await _refreshToken();
      } catch (_) {
        await initSession();
      }
    }
    final body = XmlMap.build(data);
    final r = await _send(
        _c.post(Uri.parse('$base/api/$path'), headers: _headers(post: true), body: body));
    _absorb(r);
    _log('POST $path → ${r.statusCode}');
    try {
      return _parse(path, r.body);
    } on ApiException catch (e) {
      if (retry && (e.code.startsWith('12500') || e.code == '100003')) {
        if (e.code == '100003' && _password != null) {
          await login(username, _password!);
        } else {
          await _refreshToken();
        }
        return post(path, data, retry: false);
      }
      rethrow;
    }
  }

  // ---------------- Auth ----------------
  Future<void> login(String user, String password) async {
    username = user;
    _cookies.clear();
    _tokens.clear();
    await initSession();
    try {
      await _scramLogin(user, password);
    } on ApiException catch (e) {
      if (e.code == '100002' || e.code == 'parse') {
        _log('SCRAM غير مدعوم، تجربة الطريقة القديمة');
        await _legacyLogin(user, password);
      } else {
        rethrow;
      }
    }
    _password = password;
    loggedIn = true;
  }

  Future<void> _scramLogin(String user, String password) async {
    final first = CryptoUtils.randomHex(32);
    final ch = await post(
        'user/challenge_login',
        {'username': user, 'firstnonce': first, 'mode': '1'},
        retry: false);
    final serverNonce = ch.s('servernonce');
    final salt = ch.s('salt');
    final iter = ch.i('iterations', 100);
    if (serverNonce.isEmpty) throw ApiException('parse', 'challenge failed');
    final proof = CryptoUtils.scramClientProof(
      password: password,
      saltHex: salt,
      iterations: iter,
      firstNonce: first,
      serverNonce: serverNonce,
    );
    await post('user/authentication_login',
        {'clientproof': proof, 'finalnonce': serverNonce},
        retry: false);
  }

  Future<void> _legacyLogin(String user, String password) async {
    await initSession();
    String type = '4';
    try {
      final st = await get('user/state-login', retry: false);
      type = st.s('password_type', '4');
    } catch (_) {}
    final token = _tokens.isNotEmpty ? _tokens.first : '';
    final pw = type == '4'
        ? CryptoUtils.legacyType4(user, password, token)
        : base64.encode(utf8.encode(password));
    await post('user/login',
        {'Username': user, 'Password': pw, 'password_type': type},
        retry: false);
  }

  Future<void> logout() async {
    try {
      await post('user/logout', {'Logout': '1'}, retry: false);
    } catch (_) {}
    loggedIn = false;
    _password = null;
  }

  // ---------------- Info ----------------
  Future<Map<String, dynamic>> deviceInfo() => get('device/information');
  Future<Map<String, dynamic>> status() => get('monitoring/status');
  Future<Map<String, dynamic>> signal() => get('device/signal');
  Future<Map<String, dynamic>> traffic() => get('monitoring/traffic-statistics');
  Future<Map<String, dynamic>> monthStats() => get('monitoring/month_statistics');
  Future<Map<String, dynamic>> plmn() => get('net/current-plmn');

  // ---------------- Usage cycle ----------------
  Future<Map<String, dynamic>> startDate() => get('monitoring/start_date');

  Future<void> setStartDay(int day, {String? dataLimit, int? threshold}) async {
    Map<String, dynamic> cur = {};
    try {
      cur = await startDate();
    } catch (_) {}
    await post('monitoring/start_date', {
      'StartDay': '$day',
      'DataLimit': dataLimit ?? cur.s('DataLimit', '0MB'),
      'MonthThreshold': '${threshold ?? cur.i('MonthThreshold', 90)}',
      'SetMonthData': '1',
    });
  }

  Future<void> clearTraffic() => post('monitoring/clear-traffic', {'ClearTraffic': '1'});

  // ---------------- Network mode / bands ----------------
  Future<Map<String, dynamic>> netMode() => get('net/net-mode');
  Future<Map<String, dynamic>> netModeList() => get('net/net-mode-list');

  Future<void> setNetMode({
    required String mode,
    String? lteBand,
    String? networkBand,
    String? nrBand,
  }) async {
    final cur = await netMode();
    final data = <String, dynamic>{
      'NetworkMode': mode,
      'NetworkBand': networkBand ?? cur.s('NetworkBand', '3FFFFFFF'),
      'LTEBand': lteBand ?? cur.s('LTEBand', '7FFFFFFFFFFFFFFF'),
    };
    if (cur.containsKey('NRBand') || nrBand != null) {
      data['NRBand'] = nrBand ?? cur.s('NRBand');
    }
    await post('net/net-mode', data);
  }

  // ---------------- Hosts ----------------
  Future<List<Map<String, dynamic>>> hosts() async {
    try {
      final r = await get('lan/HostInfo');
      final list = r.m('Hosts').list('Host');
      if (list.isNotEmpty) return list;
    } catch (_) {}
    final r = await get('wlan/host-list');
    return r.m('Hosts').list('Host');
  }

  // ---------------- WiFi ----------------
  Future<List<Map<String, dynamic>>> wifiSsids() async {
    final r = await get('wlan/multi-basic-settings');
    return r.m('Ssids').list('Ssid');
  }

  Future<void> saveWifiSsids(List<Map<String, dynamic>> ssids) async {
    await post('wlan/multi-basic-settings', {
      'Ssids': {'Ssid': ssids},
      'WifiRestart': '1',
    });
  }

  Future<Map<String, dynamic>> wifiFeatures() => get('wlan/wifi-feature-switch');

  // ---------------- MAC filter ----------------
  Future<List<Map<String, dynamic>>> macFilter() async {
    final r = await get('wlan/multi-macfilter-settings');
    return r.m('Ssids').list('Ssid');
  }

  Future<void> saveMacFilter(List<Map<String, dynamic>> ssids) async {
    await post('wlan/multi-macfilter-settings', {
      'Ssids': {'Ssid': ssids},
    });
  }

  // ---------------- URL filter ----------------
  Future<List<Map<String, dynamic>>> urlFilters() async {
    final r = await get('security/url-filter');
    return r.m('urlfilters').list('urlfilter').isNotEmpty
        ? r.m('urlfilters').list('urlfilter')
        : r.m('UrlFilters').list('UrlFilter');
  }

  Future<void> saveUrlFilters(List<String> urls) async {
    await post('security/url-filter', {
      'urlfilters': {
        'urlfilter': [
          for (final u in urls) {'value': u, 'status': '1'}
        ]
      }
    });
  }

  Future<Map<String, dynamic>> firewall() => get('security/firewall-switch');

  Future<void> enableUrlFilterSwitch() async {
    final cur = await firewall();
    final data = <String, dynamic>{};
    cur.forEach((k, v) {
      if (v is String) data[k] = v;
    });
    data['FirewallMainSwitch'] = '1';
    data['FirewallUrlFilterSwitch'] = '1';
    await post('security/firewall-switch', data);
  }

  // ---------------- Control ----------------
  Future<void> reboot() => post('device/control', {'Control': '1'});

  void dispose() => _c.close();
}
