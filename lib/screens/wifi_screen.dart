import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/xml_utils.dart';
import '../widgets/common.dart';

class WifiScreen extends StatefulWidget {
  const WifiScreen({super.key});

  @override
  State<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends State<WifiScreen> {
  List<Map<String, dynamic>> ssids = [];
  final names = <int, TextEditingController>{};
  final passes = <int, TextEditingController>{};
  bool loading = true;
  bool saving = false;
  String? error;
  final obscure = <int, bool>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final l = await s.loadWifi();
      ssids = l.map((e) => Map<String, dynamic>.from(e)).toList();
      for (var i = 0; i < ssids.length; i++) {
        names[i] = TextEditingController(text: ssids[i].s('WifiSsid'));
        passes[i] = TextEditingController(text: ssids[i].s('WifiWpapsk'));
      }
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  bool _isGuest(Map<String, dynamic> m) =>
      m.s('wifiisguestnetwork') == '1' || m.s('WifiGuest') == '1';

  String _band(Map<String, dynamic> m) {
    final id = m.s('ID') + m.s('Index');
    final f = m.s('WifiFrequency', m.s('FrequencyBand'));
    if (f.isNotEmpty) return f.contains('5') ? '5 GHz' : '2.4 GHz';
    if (id.contains('Radio.2')) return '5 GHz';
    if (id.contains('Radio.1')) return '2.4 GHz';
    return '';
  }

  Future<void> _save(AppState s) async {
    for (var i = 0; i < ssids.length; i++) {
      final p = passes[i]!.text;
      if (ssids[i].s('WifiEnable') == '1' && p.isNotEmpty && p.length < 8) {
        toast(context, s.t('كلمة المرور يجب أن تكون 8 أحرف على الأقل', 'Password must be 8+ chars'),
            error: true);
        return;
      }
    }
    final ok = await confirm(
        context,
        s.t('حفظ إعدادات الواي فاي؟', 'Save WiFi settings?'),
        s.t('ستنقطع الشبكة وتعود خلال دقيقة. إذا غيرت كلمة المرور أعد الاتصال بالكلمة الجديدة.',
            'WiFi will restart. Reconnect with the new password if changed.'));
    if (!ok) return;
    setState(() => saving = true);
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < ssids.length; i++) {
      final m = Map<String, dynamic>.from(ssids[i]);
      m['WifiSsid'] = names[i]!.text.trim();
      if (passes[i]!.text.isNotEmpty) m['WifiWpapsk'] = passes[i]!.text;
      out.add(m);
    }
    final err = await s.saveWifi(out);
    if (!mounted) return;
    setState(() => saving = false);
    toast(context, err ?? s.t('تم الحفظ ✓', 'Saved ✓'), error: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (error != null) NoteBox(error!, color: AppColors.red),
          if (ssids.isNotEmpty) _bandModeCard(s),
          for (var i = 0; i < ssids.length; i++) _ssidCard(s, i),
          if (ssids.isNotEmpty)
            FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: saving ? null : () => _save(s),
              icon: const Icon(Icons.save_rounded),
              label: Text(s.t('حفظ إعدادات الواي فاي', 'Save WiFi settings')),
            ),
        ],
      ),
    );
  }

  String _routerMode() {
    bool a = false, b = false;
    for (final m in ssids) {
      if (_isGuest(m)) continue;
      final band = _band(m);
      final on = m.s('WifiEnable', '1') == '1';
      if (band.startsWith('5')) b = b || on;
      if (band.startsWith('2')) a = a || on;
    }
    if (a && b) return 'both';
    if (b) return '5';
    if (a) return '2.4';
    return 'both';
  }

  Widget _bandModeCard(AppState s) {
    return SectionCard(
      title: s.t('ترددات بث الراوتر', 'Router WiFi bands'),
      icon: Icons.cell_wifi_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: '2.4', label: Text(s.t('2.4 فقط', '2.4 only'))),
            ButtonSegment(value: '5', label: Text(s.t('5 فقط', '5 only'))),
            ButtonSegment(value: 'both', label: Text(s.t('الاثنين', 'Both'))),
          ],
          selected: {_routerMode()},
          onSelectionChanged: saving
              ? null
              : (v) async {
                  final m = v.first;
                  final ok = await confirm(
                      context,
                      s.t('تغيير ترددات البث؟', 'Change bands?'),
                      s.t('ستعيد الشبكة التشغيل خلال دقيقة. الأجهزة المتصلة على التردد الذي ستوقفه ستنقطع.',
                          'WiFi will restart; devices on the disabled band disconnect.'));
                  if (!ok) return;
                  setState(() => saving = true);
                  final err = await s.setRouterWifiBands(on24: m != '5', on5: m != '2.4');
                  if (!mounted) return;
                  setState(() => saving = false);
                  toast(context, err ?? s.t('تم التطبيق ✓', 'Applied ✓'), error: err != null);
                  if (err == null) _load();
                },
        ),
        const SizedBox(height: 10),
        Text(
          s.t('2.4 GHz: مدى أبعد ويخترق الجدران. 5 GHz: أسرع بكثير للأجهزة القريبة. الأفضل غالباً تشغيل الاثنين.',
              '2.4 GHz: longer range. 5 GHz: much faster nearby. Both is usually best.'),
          style: const TextStyle(color: AppColors.text2, fontSize: 12, height: 1.5),
        ),
      ]),
    );
  }

  Widget _ssidCard(AppState s, int i) {
    final m = ssids[i];
    final guest = _isGuest(m);
    final band = _band(m);
    final enabled = m.s('WifiEnable', '1') == '1';
    return SectionCard(
      title: guest
          ? '${s.t('شبكة الضيوف', 'Guest network')} ${band.isNotEmpty ? '($band)' : ''}'
          : '${s.t('الشبكة الرئيسية', 'Main network')} ${band.isNotEmpty ? '($band)' : ''}',
      icon: guest ? Icons.people_outline_rounded : Icons.wifi_rounded,
      trailing: Switch(
        value: enabled,
        onChanged: (v) => setState(() => m['WifiEnable'] = v ? '1' : '0'),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (guest)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              enabled
                  ? s.t('الضيوف يمكنهم الاتصال بالإنترنت فقط بدون رؤية أجهزتك',
                      'Guests get internet only, isolated from your devices')
                  : s.t('شبكة الضيوف متوقفة', 'Guest network is off'),
              style: TextStyle(color: enabled ? AppColors.green : AppColors.text2),
            ),
          ),
        TextField(
          controller: names[i],
          decoration: InputDecoration(
            labelText: s.t('اسم الشبكة (SSID)', 'Network name (SSID)'),
            prefixIcon: const Icon(Icons.badge_outlined),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: passes[i],
          obscureText: obscure[i] ?? true,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: s.t('كلمة مرور الواي فاي', 'WiFi password'),
            prefixIcon: const Icon(Icons.key_rounded),
            suffixIcon: IconButton(
              icon: Icon((obscure[i] ?? true) ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => obscure[i] = !(obscure[i] ?? true)),
            ),
          ),
        ),
        if (m.containsKey('WifiBroadcast'))
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.t('إخفاء اسم الشبكة', 'Hide network name')),
            value: m.s('WifiBroadcast') == '1',
            onChanged: (v) => setState(() => m['WifiBroadcast'] = v ? '1' : '0'),
          ),
      ]),
    );
  }
}
