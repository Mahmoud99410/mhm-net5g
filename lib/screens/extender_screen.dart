import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/extender_api.dart';
import '../core/app_state.dart';
import '../widgets/common.dart';
import 'web_panel.dart';

class ExtenderScreen extends StatefulWidget {
  const ExtenderScreen({super.key});

  @override
  State<ExtenderScreen> createState() => _ExtenderScreenState();
}

class _ExtenderScreenState extends State<ExtenderScreen> {
  late final TextEditingController ip;
  late final TextEditingController pass;
  late final TextEditingController user;
  bool busy = false;
  bool discovering = false;
  List<(String, String)> found = [];
  Map<String, String> routerCh = {};
  String? error;
  List<Map<String, dynamic>> radios = [];
  Map<String, dynamic> uplink = {};
  bool? reachable;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    ip = TextEditingController(text: s.guessExtenderIp());
    pass = TextEditingController(text: s.extenderPass);
    user = TextEditingController(text: s.extenderUser);
    if (s.ext?.loggedIn == true) _reload(s);
    s.routerChannels().then((v) {
      if (mounted) setState(() => routerCh = v);
    });
  }

  Future<void> _reload(AppState s) async {
    final e = s.ext;
    if (e == null || e.mode != 'json') return;
    radios = await e.radios();
    uplink = await e.uplink();
    if (mounted) setState(() {});
  }

  Future<void> _connect(AppState s) async {
    setState(() {
      busy = true;
      error = null;
    });
    final err = await s.connectExtender(ip.text, pass.text, user: user.text);
    reachable = await s.ext?.reachable();
    if (err == null) await _reload(s);
    if (!mounted) return;
    setState(() {
      busy = false;
      error = err;
    });
  }

  bool _on(Map<String, dynamic> r) {
    final v = r['WifiEnable'] ?? r['Enable'] ?? r['enable'];
    return v == true || '$v' == '1' || '$v' == 'true';
  }

  Map<String, dynamic>? _radio(bool five) {
    for (final r in radios) {
      if (ExtenderApi.is5g(r) == five) return r;
    }
    return null;
  }

  String _mode() {
    final r24 = _radio(false), r5 = _radio(true);
    final a = r24 != null && _on(r24), b = r5 != null && _on(r5);
    if (a && b) return 'both';
    if (b) return '5';
    if (a) return '2.4';
    return 'both';
  }

  Future<void> _discover(AppState s) async {
    setState(() => discovering = true);
    final f = await s.discoverExtenders();
    if (!mounted) return;
    setState(() {
      found = f;
      discovering = false;
      if (f.isNotEmpty) ip.text = f.first.$1;
    });
    if (f.isEmpty) {
      toast(
          context,
          s.t('لم أجد المقوي. تأكد أنه يعمل ومتصل بالراوتر، أو اتصل بشبكة المقوي مباشرة.',
              'Extender not found. Make sure it is on, or join its WiFi directly.'),
          error: true);
    }
  }

  Future<void> _setMode(AppState s, String m) async {
    final r24 = _radio(false), r5 = _radio(true);
    setState(() => busy = true);
    try {
      if (r24 != null) await s.ext!.setRadio(r24, m != '5');
      if (r5 != null) await s.ext!.setRadio(r5, m != '2.4');
      await _reload(s);
      if (mounted) toast(context, s.t('تم التطبيق ✓', 'Applied ✓'));
    } catch (e) {
      if (mounted) toast(context, e.toString(), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final logged = s.ext?.loggedIn == true;
    final dev = s.extenderDevice;
    final link = s.extenderLink;
    final clients = s.activeDevices.where((d) => d.viaExtender).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---------- diagram ----------
        SectionCard(
          child: Column(children: [
            NetworkMap(
              nodes: [
                MapNode(Icons.router_rounded, s.t('الراوتر', 'Router'), s.networkLabel,
                    AppColors.cyan),
                MapNode(Icons.wifi_tethering_rounded, 'WA8021V5',
                    dev == null ? s.t('غير ظاهر', 'not seen') : s.t('متصل', 'online'),
                    dev == null ? AppColors.text2 : AppColors.purple),
                MapNode(Icons.devices_rounded, s.t('أجهزته', 'Clients'), '${clients.length}',
                    AppColors.blue),
              ],
              links: [s.t('استقبال', 'receive'), s.t('بث', 'broadcast')],
            ),
            const SizedBox(height: 12),
            Text(
              s.t('المقوي يستقبل الإنترنت من الراوتر عبر الواي فاي ثم يعيد بثه. نوع الشبكة 4G أو 5G يتحكم به الراوتر (صفحة الإشارة)، والمقوي يتحكم بترددات البث 2.4 GHz و 5 GHz.',
                  'The extender receives from the router over WiFi and re-broadcasts. 4G/5G is set on the router; the extender controls 2.4/5 GHz.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.text2, fontSize: 12, height: 1.5),
            ),
          ]),
        ),

        // ---------- receive quality ----------
        SectionCard(
          title: s.t('جودة الاستقبال (من الراوتر إلى المقوي)', 'Receive quality (router → extender)'),
          icon: Icons.call_received_rounded,
          child: dev == null
              ? Text(
                  s.t('الراوتر لم يتعرف على المقوي بعد. اكتب عنوانه بالأسفل واضغط اتصال.',
                      'Router has not identified the extender yet.'),
                  style: const TextStyle(color: AppColors.text2))
              : Column(children: [
                  InfoRow(s.t('الاسم', 'Name'), dev.name),
                  InfoRow('IP', dev.ip),
                  InfoRow(s.t('متصل عبر', 'Linked via'), dev.iface),
                  for (final e in link.entries) InfoRow(e.key, e.value),
                  for (final e in uplink.entries)
                    if (e.value is String || e.value is num) InfoRow(e.key, '${e.value}'),
                  if (link.isEmpty && uplink.isEmpty)
                    NoteBox(
                        s.t('الراوتر لا يرسل قوة إشارة المقوي. سجّل الدخول للمقوي ثم أرسل لي "تقرير التشخيص" من الإعدادات لأضيف عرض قوة الاستقبال بدقة.',
                            'Send diagnostics so I can add exact link quality.'),
                        color: AppColors.blue),
                ]),
        ),

        // ---------- login ----------
        SectionCard(
          title: s.t('الدخول إلى المقوي', 'Extender login'),
          icon: Icons.login_rounded,
          trailing: logged ? const Pill('✓', color: AppColors.green) : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: ip,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: s.t('عنوان المقوي', 'Extender address'),
                    prefixIcon: const Icon(Icons.lan_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: discovering ? null : () => _discover(s),
                icon: discovering
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.travel_explore_rounded),
                label: Text(s.t('اكتشاف', 'Find')),
              ),
            ]),
            if (found.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in found)
                  ChoiceChip(
                    label: Text('${f.$1} · ${f.$2}', style: const TextStyle(fontSize: 12)),
                    selected: ip.text == f.$1,
                    onSelected: (_) => setState(() => ip.text = f.$1),
                  ),
              ]),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: user,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: s.t('اسم المستخدم', 'Username'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: pass,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: s.t('كلمة مرور المقوي', 'Extender password'),
                prefixIcon: const Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 12),
            if (error != null) NoteBox(error!, color: AppColors.red),
            if (logged && s.ext?.mode == 'ont')
              NoteBox(
                  s.t('تم الدخول ✓ — هذا الموديل يُدار من لوحته. اضغط "لوحة المقوي" لتتحكم بالترددات والقنوات من داخل التطبيق، وأرسل لي تقرير التشخيص لأضيف التحكم المباشر.',
                      'Logged in. This model is managed via its panel; open it inside the app.'),
                  color: AppColors.green,
                  icon: Icons.check_circle_rounded),
            NoteBox(
                s.t('إذا فصلت الراوتر الرئيسي واتصلت بشبكة المقوي مباشرة، اضغط "اكتشاف" أو جرّب العنوان 192.168.101.1.',
                    'If you join the extender WiFi directly, press Find or try 192.168.101.1.'),
                color: AppColors.blue),
            if (reachable == false)
              NoteBox(s.t('المقوي لا يرد على هذا العنوان', 'Extender not reachable'),
                  color: AppColors.red),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : () => _connect(s),
                  icon: const Icon(Icons.login),
                  label: Text(s.t('اتصال', 'Connect')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => openWebPanel(
                      context, 'http://${ip.text.trim()}/', s.t('لوحة المقوي', 'Extender panel')),
                  icon: const Icon(Icons.web_rounded),
                  label: Text(s.t('لوحة المقوي', 'Panel')),
                ),
              ),
            ]),
          ]),
        ),

        // ---------- channel planner ----------
        _channelCard(s, logged),

        // ---------- broadcast control ----------
        if (logged && s.ext?.mode == 'json')
          SectionCard(
            title: s.t('ترددات البث من المقوي', 'Extender broadcast bands'),
            icon: Icons.cell_wifi_rounded,
            child: radios.isEmpty
                ? Text(s.t('المقوي لم يرسل إعدادات البث — استخدم "لوحة المقوي"', 'No radio data'),
                    style: const TextStyle(color: AppColors.text2))
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: '2.4', label: Text(s.t('2.4 فقط', '2.4 only'))),
                        ButtonSegment(value: '5', label: Text(s.t('5 فقط', '5 only'))),
                        ButtonSegment(value: 'both', label: Text(s.t('الاثنين', 'Both'))),
                      ],
                      selected: {_mode()},
                      onSelectionChanged: busy ? null : (v) => _setMode(s, v.first),
                    ),
                    const SizedBox(height: 12),
                    for (final r in radios) _radioCard(s, r),
                  ]),
          ),

        // ---------- clients ----------
        SectionCard(
          title: s.t('الأجهزة المتصلة بالمقوي', 'Devices on the extender'),
          icon: Icons.devices_rounded,
          child: clients.isEmpty
              ? Text(
                  logged
                      ? s.t('لا توجد أجهزة الآن', 'None right now')
                      : s.t('سجّل الدخول للمقوي لعرض أجهزته', 'Log in to list devices'),
                  style: const TextStyle(color: AppColors.text2))
              : Column(children: [
                  for (final d in clients)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.smartphone_rounded, color: AppColors.purple),
                      title: Text(d.name),
                      subtitle: Text('${d.ip} · ${d.mac}', style: const TextStyle(fontSize: 11)),
                    ),
                ]),
        ),

        if (logged)
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await confirm(context, s.t('إعادة تشغيل المقوي؟', 'Reboot extender?'), '');
              if (!ok) return;
              try {
                await s.ext!.reboot();
                if (context.mounted) toast(context, s.t('جاري إعادة التشغيل', 'Rebooting'));
              } catch (e) {
                if (context.mounted) toast(context, e.toString(), error: true);
              }
            },
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(s.t('إعادة تشغيل المقوي', 'Reboot extender')),
          ),
      ],
    );
  }

  Widget _radioCard(AppState s, Map<String, dynamic> r) {
    final five = ExtenderApi.is5g(r);
    final on = _on(r);
    final ch = '${r['Channel'] ?? r['channel'] ?? ''}';
    final power = r.keys.firstWhere(
        (k) => k.toLowerCase().contains('power') || k.toLowerCase().contains('txpwr'),
        orElse: () => '');
    final bw = '${r['BandWidth'] ?? r['Bandwidth'] ?? r['FrequencyWidth'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: on ? (five ? AppColors.cyan : AppColors.amber) : AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.wifi_rounded, color: five ? AppColors.cyan : AppColors.amber),
          const SizedBox(width: 8),
          Text(five ? '5 GHz' : '2.4 GHz',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const Spacer(),
          Pill(on ? s.t('يبث', 'ON') : s.t('متوقف', 'OFF'),
              color: on ? AppColors.green : AppColors.text2),
        ]),
        const SizedBox(height: 6),
        Text(
          five
              ? s.t('أسرع، مناسب للأجهزة القريبة', 'Faster, for nearby devices')
              : s.t('أبعد مدى ويخترق الجدران', 'Longer range'),
          style: const TextStyle(color: AppColors.text2, fontSize: 12),
        ),
        if ('${r['WifiSsid'] ?? r['Ssid'] ?? ''}'.isNotEmpty)
          InfoRow('SSID', '${r['WifiSsid'] ?? r['Ssid']}'),
        if (ch.isNotEmpty)
          Row(children: [
            Expanded(child: Text(s.t('القناة', 'Channel'), style: const TextStyle(color: AppColors.text2))),
            DropdownButton<String>(
              value: _channels(five).contains(ch) ? ch : null,
              hint: Text(ch),
              items: [
                for (final c in _channels(five))
                  DropdownMenuItem(value: c, child: Text(c == '0' ? s.t('تلقائي', 'Auto') : c)),
              ],
              onChanged: busy
                  ? null
                  : (v) async {
                      if (v == null) return;
                      try {
                        await s.ext!.setChannel(r, v);
                        await _reload(s);
                      } catch (e) {
                        if (mounted) toast(context, e.toString(), error: true);
                      }
                    },
            ),
          ]),
        if (bw.isNotEmpty) InfoRow(s.t('عرض القناة', 'Width'), bw),
        if (power.isNotEmpty) ...[
          InfoRow(s.t('قوة البث', 'TX power'), '${r[power]}'),
          Wrap(spacing: 6, children: [
            for (final p in ['100', '75', '50'])
              ChoiceChip(
                label: Text('$p%'),
                selected: '${r[power]}' == p,
                onSelected: busy
                    ? null
                    : (_) async {
                        try {
                          await s.ext!.setRadioFields(r, {power: p});
                          await _reload(s);
                        } catch (e) {
                          if (mounted) toast(context, e.toString(), error: true);
                        }
                      },
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _channelCard(AppState s, bool logged) {
    final (c24, c5) = s.suggestExtenderChannels(routerCh);
    final canApply = logged && s.ext?.mode == 'json' && radios.isNotEmpty;
    return SectionCard(
      title: s.t('منع التشويش بين الراوتر والمقوي', 'Avoid interference router ↔ extender'),
      icon: Icons.compare_arrows_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          s.t('عندما يبث الراوتر والمقوي على نفس القناة يحدث تداخل ويبطؤ الإنترنت. الحل: قنوات غير متداخلة. في 2.4 GHz القنوات التي لا تتداخل هي 1 و 6 و 11 فقط. وفي 5 GHz نبعد المقوي عن قناة الراوتر.',
              'Same channel = interference. On 2.4 GHz only 1, 6, 11 do not overlap; on 5 GHz keep them apart.'),
          style: const TextStyle(color: AppColors.text2, fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 10),
        if (routerCh.isNotEmpty)
          for (final e in routerCh.entries)
            InfoRow('${s.t('الراوتر', 'Router')} ${e.key}', e.value == '0' ? s.t('تلقائي', 'Auto') : e.value)
        else
          InfoRow(s.t('قناة الراوتر', 'Router channel'), s.t('تلقائي / غير معروف', 'Auto / unknown')),
        const Divider(height: 20),
        Row(children: [
          Expanded(child: _chBox(s.t('اقتراح للمقوي 2.4', 'Extender 2.4'), c24, AppColors.amber)),
          const SizedBox(width: 10),
          Expanded(child: _chBox(s.t('اقتراح للمقوي 5', 'Extender 5'), c5, AppColors.cyan)),
        ]),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: !canApply || busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    for (final r in radios) {
                      await s.ext!.setChannel(r, ExtenderApi.is5g(r) ? c5 : c24);
                    }
                    await _reload(s);
                    if (mounted) toast(context, s.t('تم ضبط القنوات ✓', 'Channels set ✓'));
                  } catch (e) {
                    if (mounted) toast(context, e.toString(), error: true);
                  }
                  if (mounted) setState(() => busy = false);
                },
          icon: const Icon(Icons.auto_fix_high_rounded),
          label: Text(canApply
              ? s.t('طبّق القنوات المقترحة على المقوي', 'Apply to extender')
              : s.t('سجّل دخول المقوي لتطبيقها (أو اضبطها من لوحته)', 'Log in to apply (or set in its panel)')),
        ),
      ]),
    );
  }

  Widget _chBox(String label, String ch, Color c) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withValues(alpha: 0.5)),
        ),
        child: Column(children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.text2)),
          Text('CH $ch', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c)),
        ]),
      );

  List<String> _channels(bool five) => five
      ? ['0', '36', '40', '44', '48', '52', '56', '60', '64', '149', '153', '157', '161']
      : ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13'];
}
