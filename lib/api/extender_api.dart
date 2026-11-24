import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/crypto_utils.dart';
import 'router_api.dart';

/// Client for the Huawei EchoLife WA8021V5 extender.
/// Uses Huawei's JSON web API (same family as Huawei WiFi routers).
class ExtenderApi {
  String host;
  final http.Client _c = http.Client();
  final Map<String, String> _cookies = {};
  String _csrfParam = '';
  String _csrfToken = '';
  bool loggedIn = false;
  void Function(String)? onLog;

  ExtenderApi(this.host);

  String get base => 'http://$host';

  Map<String, String> get _headers => {
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'X-Requested-With': 'XMLHttpRequest',
        'Content-Type': 'application/json;charset=UTF-8',
        if (_cookies.isNotEmpty)
          'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      };

  void _absorb(http.Response r) {
    final sc = r.headers['set-cookie'];
    if (sc == null) return;
    for (final part in sc.split(RegExp(r',(?=[^;]+?=)'))) {
      final kv = part.split(';').first.trim();
      final i = kv.indexOf('=');
      if (i > 0) _cookies[kv.substring(0, i)] = kv.substring(i + 1);
    }
  }

  Future<http.Response> _send(Future<http.Response> f) async {
    try {
      return await f.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw ApiException('net');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('net', e.toString());
    }
  }

  /// Returns true if the extender web page answers.
  Future<bool> reachable() async {
    try {
      final r = await _send(_c.get(Uri.parse('$base/'), headers: _headers));
      _absorb(r);
      _readCsrf(r.body);
      return r.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  void _readCsrf(String html) {
    final p = RegExp(r'name="csrf_param"\s+content="([^"]+)"').firstMatch(html);
    final t = RegExp(r'name="csrf_token"\s+content="([^"]+)"').firstMatch(html);
    if (p != null) _csrfParam = p.group(1)!;
    if (t != null) _csrfToken = t.group(1)!;
  }

  void _updateCsrf(Map<String, dynamic> j) {
    if (j['csrf_param'] is String) _csrfParam = j['csrf_param'];
    if (j['csrf_token'] is String) _csrfToken = j['csrf_token'];
  }

  dynamic _decode(String body) {
    var b = body.trim();
    // Huawei wraps JSON in /*...*/ sometimes
    if (b.startsWith('while(1);')) b = b.substring(9);
    if (b.startsWith('/*') && b.endsWith('*/')) b = b.substring(2, b.length - 2);
    return jsonDecode(b);
  }

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> data) async {
    final body = jsonEncode({
      'csrf': {'csrf_param': _csrfParam, 'csrf_token': _csrfToken},
      'data': data,
    });
    final r = await _send(_c.post(Uri.parse('$base$path'), headers: _headers, body: body));
    _absorb(r);
    onLog?.call('EXT POST $path → ${r.statusCode}');
    final j = _decode(r.body);
    if (j is! Map<String, dynamic>) return {'value': j};
    _updateCsrf(j);
    final err = j['errcode'] ?? j['err'];
    if (err != null && '$err' != '0') {
      throw ApiException('$err', 'المقوي رفض الطلب (رمز $err)');
    }
    return j;
  }

  Future<dynamic> getJson(String path) async {
    final r = await _send(_c.get(Uri.parse('$base$path'), headers: _headers));
    _absorb(r);
    onLog?.call('EXT GET $path → ${r.statusCode}');
    if (r.statusCode >= 400) throw ApiException('${r.statusCode}', 'HTTP ${r.statusCode}');
    return _decode(r.body);
  }

  Future<void> login(String password, {String user = 'admin'}) async {
    _cookies.clear();
    final ok = await reachable();
    if (!ok) throw ApiException('net');
    final first = CryptoUtils.randomHex(32);
    final n = await postJson('/api/system/user_login_nonce',
        {'username': user, 'firstnonce': first});
    final serverNonce = '${n['servernonce'] ?? ''}';
    final salt = '${n['salt'] ?? ''}';
    final iter = int.tryParse('${n['iterations'] ?? 100}') ?? 100;
    if (serverNonce.isEmpty) {
      throw ApiException('ext', 'المقوي لا يدعم طريقة الدخول هذه — استخدم زر فتح لوحة المقوي');
    }
    final proof = CryptoUtils.scramClientProof(
      password: password,
      saltHex: salt,
      iterations: iter,
      firstNonce: first,
      serverNonce: serverNonce,
    );
    await postJson('/api/system/user_login_proof',
        {'clientproof': proof, 'finalnonce': serverNonce});
    loggedIn = true;
  }

  /// WiFi radios (2.4GHz / 5GHz). Returns a list of radio maps.
  Future<List<Map<String, dynamic>>> radios() async {
    for (final p in ['/api/ntwk/WlanBasic?showpass=false', '/api/ntwk/wlanradio']) {
      try {
        final j = await getJson(p);
        if (j is List) return j.whereType<Map<String, dynamic>>().toList();
        if (j is Map<String, dynamic>) {
          for (final v in j.values) {
            if (v is List) return v.whereType<Map<String, dynamic>>().toList();
          }
          return [j];
        }
      } catch (_) {}
    }
    return [];
  }

  /// Enable/disable a radio by frequency label ("2.4GHz" or "5GHz").
  Future<void> setRadio(Map<String, dynamic> radio, bool enable) async {
    final copy = Map<String, dynamic>.from(radio);
    for (final k in ['WifiEnable', 'Enable', 'enable']) {
      if (copy.containsKey(k)) copy[k] = enable;
    }
    await postJson('/api/ntwk/WlanBasic', {
      'config2g': copy['FrequencyBand'] == '2.4GHz' ? copy : null,
      'config5g': copy['FrequencyBand'] == '5GHz' ? copy : null,
    }..removeWhere((k, v) => v == null));
  }

  Future<void> setChannel(Map<String, dynamic> radio, String channel) async {
    final copy = Map<String, dynamic>.from(radio);
    copy['Channel'] = channel;
    await postJson('/api/ntwk/wlanradio', copy);
  }

  Future<List<Map<String, dynamic>>> hosts() async {
    try {
      final j = await getJson('/api/system/HostInfo');
      if (j is List) return j.whereType<Map<String, dynamic>>().toList();
    } catch (_) {}
    return [];
  }

  Future<void> reboot() => postJson('/api/service/reboot.cgi', {});

  void dispose() => _c.close();
}
