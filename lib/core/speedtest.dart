import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// A speed test server.
class SpeedServer {
  final String name;
  final String base; // https://host:port
  final bool ookla;
  SpeedServer(this.name, this.base, {this.ookla = true});

  Uri download(int bytes) => ookla
      ? Uri.parse('$base/download?nocache=${_nc()}&size=$bytes')
      : Uri.parse('$base/__down?bytes=$bytes&r=${_nc()}');

  Uri upload() => ookla
      ? Uri.parse('$base/upload?nocache=${_nc()}')
      : Uri.parse('$base/__up?r=${_nc()}');

  Uri ping() => ookla
      ? Uri.parse('$base/hello?nocache=${_nc()}')
      : Uri.parse('$base/__down?bytes=1&r=${_nc()}');

  /// Distance in km reported by the server list (if known).
  double distance = -1;

  static int _c = 0;
  static String _nc() => '${DateTime.now().microsecondsSinceEpoch}${_c++}';
}

class SpeedResult {
  double downMbps = 0;
  double upMbps = 0;
  int pingMs = -1;
  int jitterMs = 0;
  String server = '';
}

/// Multi-connection speed test (same method as Speedtest/Ookla web):
/// several parallel connections, time-limited, warm-up discarded.
class SpeedTester {
  final int streams;
  final Duration downTime;
  final Duration upTime;
  final Duration warmup;
  SpeedTester({
    this.streams = 8,
    this.downTime = const Duration(milliseconds: 4500),
    this.upTime = const Duration(milliseconds: 3500),
    this.warmup = const Duration(milliseconds: 700),
  });

  static const userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';

  HttpClient _client() => HttpClient()
    ..maxConnectionsPerHost = 32
    ..userAgent = userAgent
    ..autoUncompress = false
    ..connectionTimeout = const Duration(seconds: 5)
    ..idleTimeout = const Duration(seconds: 3);

  /// Extra details of the last run (shown to the user).
  final List<String> notes = [];

  /// Find nearby Ookla servers (Zain Jordan preferred), fallback Cloudflare.
  Future<List<SpeedServer>> servers() async {
    final c = _client();
    try {
      final req = await c
          .getUrl(Uri.parse(
              'https://www.speedtest.net/api/js/servers?engine=js&https_functional=true&limit=8'))
          .timeout(const Duration(seconds: 4));
      final res = await req.close().timeout(const Duration(seconds: 4));
      final body = await res.transform(utf8.decoder).join();
      final list = jsonDecode(body) as List;
      final out = <SpeedServer>[];
      for (final s in list) {
        if (s is! Map) continue;
        final host = '${s['host'] ?? ''}';
        if (host.isEmpty) continue;
        final srv = SpeedServer('${s['sponsor'] ?? ''} · ${s['name'] ?? ''}', 'https://$host');
        srv.distance = double.tryParse('${s['distance'] ?? ''}') ?? -1;
        out.add(srv);
      }
      // prefer the user's operator first (Zain), keep distance order otherwise
      out.sort((a, b) {
        final za = a.name.toLowerCase().contains('zain') ? 0 : 1;
        final zb = b.name.toLowerCase().contains('zain') ? 0 : 1;
        return za.compareTo(zb);
      });
      if (out.isNotEmpty) {
        notes.add('servers: ${out.length}');
        return out;
      }
    } catch (e) {
      notes.add('server list failed: $e');
    } finally {
      c.close(force: true);
    }
    return [SpeedServer('Cloudflare', 'https://speed.cloudflare.com', ookla: false)];
  }

  Future<List<int>> _pings(HttpClient c, SpeedServer s, int n) async {
    final out = <int>[];
    for (var i = 0; i < n; i++) {
      final sw = Stopwatch()..start();
      try {
        final req = await c.getUrl(s.ping()).timeout(const Duration(seconds: 3));
        final res = await req.close().timeout(const Duration(seconds: 3));
        await res.drain<void>();
        if (res.statusCode >= 400) throw Exception('bad');
        out.add(sw.elapsedMilliseconds);
      } catch (_) {
        if (i == 0) return out;
      }
    }
    return out;
  }

  /// Picks the server with the lowest latency among the first few.
  /// A server whose ping endpoint fails is still usable (ping shown as unknown).
  Future<(SpeedServer, int, int)> pickServer(List<SpeedServer> list) async {
    final c = _client();
    SpeedServer? best;
    var bestPing = 1 << 30;
    var jitter = 0;
    try {
      for (final s in list.take(3)) {
        final p = await _pings(c, s, 4);
        if (p.length < 2) {
          notes.add('ping failed: ${s.name}');
          continue;
        }
        final rest = p.sublist(1); // first includes TLS handshake
        final mn = rest.reduce(math.min);
        if (mn < bestPing) {
          bestPing = mn;
          best = s;
          var j = 0;
          for (var i = 1; i < rest.length; i++) {
            j += (rest[i] - rest[i - 1]).abs();
          }
          jitter = rest.length > 1 ? j ~/ (rest.length - 1) : 0;
        }
      }
    } finally {
      c.close(force: true);
    }
    if (best == null) return (list.first, -1, 0);
    return (best, bestPing, jitter);
  }

  /// Quick 1.5 s probe to check a server really delivers data (Mbps).
  Future<double> probe(SpeedServer s) async {
    final t = SpeedTester(
        streams: 4,
        downTime: const Duration(milliseconds: 1600),
        warmup: const Duration(milliseconds: 400));
    return t.download(s, (_) {});
  }

  /// Download test. [onLive] receives live Mbps.
  Future<double> download(SpeedServer s, void Function(double mbps) onLive) async {
    final c = _client();
    final sw = Stopwatch()..start();
    var bytes = 0;
    var warmBytes = -1;
    var warmAt = 0;
    var stop = false;

    Future<void> worker() async {
      while (!stop) {
        try {
          final req = await c.getUrl(s.download(25000000));
          final res = await req.close();
          await for (final chunk in res) {
            bytes += chunk.length;
            if (stop) break;
          }
        } catch (_) {
          if (stop) return;
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }

    final ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final ms = sw.elapsedMilliseconds;
      if (warmBytes < 0 && ms >= warmup.inMilliseconds) {
        warmBytes = bytes;
        warmAt = ms;
      }
      if (warmBytes >= 0 && ms > warmAt) {
        onLive((bytes - warmBytes) * 8 / ((ms - warmAt) / 1000) / 1e6);
      } else if (ms > 0) {
        onLive(bytes * 8 / (ms / 1000) / 1e6);
      }
      if (ms >= downTime.inMilliseconds) stop = true;
    });
    final workers = [for (var i = 0; i < streams; i++) worker()];
    while (!stop) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    ticker.cancel();
    final ms = sw.elapsedMilliseconds;
    c.close(force: true);
    await Future.wait(workers).timeout(const Duration(seconds: 2), onTimeout: () => []);
    if (warmBytes < 0) return ms > 0 ? bytes * 8 / (ms / 1000) / 1e6 : 0;
    return (bytes - warmBytes) * 8 / ((ms - warmAt) / 1000) / 1e6;
  }

  /// Upload test with fixed-size bodies sent repeatedly on parallel connections.
  Future<double> upload(SpeedServer s, void Function(double mbps) onLive) async {
    final c = _client();
    final sw = Stopwatch()..start();
    var bytes = 0;
    var warmBytes = -1;
    var warmAt = 0;
    var stop = false;
    final chunk = Uint8List(64 * 1024);
    for (var i = 0; i < chunk.length; i++) {
      chunk[i] = (i * 31 + 7) & 0xff;
    }
    const bodySize = 2 * 1024 * 1024;

    Future<void> worker() async {
      while (!stop) {
        try {
          final req = await c.postUrl(s.upload());
          req.headers.contentType = ContentType('application', 'octet-stream');
          req.contentLength = bodySize;
          var sent = 0;
          while (sent < bodySize) {
            final n = math.min(chunk.length, bodySize - sent);
            req.add(n == chunk.length ? chunk : Uint8List.sublistView(chunk, 0, n));
            await req.flush();
            sent += n;
            bytes += n;
            if (stop) break;
          }
          if (stop) {
            req.abort();
            return;
          }
          final res = await req.close();
          await res.drain<void>();
        } catch (_) {
          if (stop) return;
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    }

    final ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final ms = sw.elapsedMilliseconds;
      if (warmBytes < 0 && ms >= warmup.inMilliseconds) {
        warmBytes = bytes;
        warmAt = ms;
      }
      if (warmBytes >= 0 && ms > warmAt) {
        onLive((bytes - warmBytes) * 8 / ((ms - warmAt) / 1000) / 1e6);
      }
      if (ms >= upTime.inMilliseconds) stop = true;
    });
    final workers = [for (var i = 0; i < math.max(2, streams ~/ 2); i++) worker()];
    while (!stop) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    ticker.cancel();
    final ms = sw.elapsedMilliseconds;
    c.close(force: true);
    await Future.wait(workers).timeout(const Duration(seconds: 2), onTimeout: () => []);
    if (warmBytes < 0) return ms > 0 ? bytes * 8 / (ms / 1000) / 1e6 : 0;
    return (bytes - warmBytes) * 8 / ((ms - warmAt) / 1000) / 1e6;
  }
}
