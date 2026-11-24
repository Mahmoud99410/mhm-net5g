import 'package:xml/xml.dart';

/// A simple XML node tree turned into Dart maps/lists.
/// Leaf -> String, repeated children -> List, otherwise Map.
class XmlMap {
  static dynamic parse(String body) {
    final doc = XmlDocument.parse(body.trim());
    final root = doc.rootElement;
    return {root.name.local: _node(root)};
  }

  static dynamic _node(XmlElement el) {
    final children = el.childElements.toList();
    if (children.isEmpty) return el.innerText;
    final map = <String, dynamic>{};
    for (final c in children) {
      final key = c.name.local;
      final val = _node(c);
      if (map.containsKey(key)) {
        final existing = map[key];
        if (existing is _Rep) {
          existing.items.add(val);
        } else {
          map[key] = _Rep([existing, val]);
        }
      } else {
        map[key] = val;
      }
    }
    return map.map((k, v) => MapEntry(k, v is _Rep ? v.items : v));
  }

  /// Build `<request>...</request>` from a map. Lists repeat the tag.
  static String build(Map<String, dynamic> data, {String root = 'request'}) {
    final b = XmlBuilder();
    b.processing('xml', 'version="1.0" encoding="UTF-8"');
    b.element(root, nest: () => _write(b, data));
    return b.buildDocument().toXmlString();
  }

  static void _write(XmlBuilder b, Map<String, dynamic> data) {
    data.forEach((k, v) {
      if (v is List) {
        for (final item in v) {
          b.element(k, nest: () {
            if (item is Map<String, dynamic>) {
              _write(b, item);
            } else {
              b.text('${item ?? ''}');
            }
          });
        }
      } else if (v is Map<String, dynamic>) {
        b.element(k, nest: () => _write(b, v));
      } else {
        b.element(k, nest: () => b.text('${v ?? ''}'));
      }
    });
  }
}

class _Rep {
  final List<dynamic> items;
  _Rep(this.items);
}

/// Convenience accessors.
extension MapX on Map<String, dynamic> {
  String s(String key, [String def = '']) {
    final v = this[key];
    if (v == null) return def;
    if (v is String) return v;
    return def;
  }

  int i(String key, [int def = 0]) => int.tryParse(s(key)) ?? def;

  double d(String key, [double def = 0]) {
    final raw = s(key).replaceAll(RegExp(r'[^0-9\.\-]'), '');
    return double.tryParse(raw) ?? def;
  }

  Map<String, dynamic> m(String key) {
    final v = this[key];
    return v is Map<String, dynamic> ? v : <String, dynamic>{};
  }

  /// Always returns a list of maps (handles single-item or list).
  List<Map<String, dynamic>> list(String key) {
    final v = this[key];
    if (v is List) return v.whereType<Map<String, dynamic>>().toList();
    if (v is Map<String, dynamic>) return [v];
    return [];
  }
}
