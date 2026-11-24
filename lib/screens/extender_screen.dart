import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../widgets/common.dart';

class ExtenderScreen extends StatefulWidget {
  const ExtenderScreen({super.key});

  @override
  State<ExtenderScreen> createState() => _ExtenderScreenState();
}

class _ExtenderScreenState extends State<ExtenderScreen> {
  late final TextEditingController ip;
  late final TextEditingController pass;
  bool busy = false;
  String? error;
  List<Map<String, dynamic>> radios = [];
  List<Map<String, dynamic>> hosts = [];
  bool? reachable;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    ip = TextEditingController(text: s.guessExtenderIp());
    pass = TextEditingController(text: s.extenderPass);
  }

  Future<void> _connect(AppState s) async {
    setState(() {
      busy = true;
      error = null;
    });
    final err = await s.connectExtender(ip.text, pass.text);
    reachable = await s.ext?.reachable();
    if (err == null) {
      radios = await s.ext!.radios();
      hosts = await s.ext!.hosts();
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      error = err;
    });
  }

  Future<void> _openPanel() async {
    final uri = Uri.parse('http://${ip.text.trim()}/');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _radioName(Map<String, dynamic> r) {
    final f = '${r['FrequencyBand'] ?? r['Frequency'] ?? r['Band'] ?? ''}';
    if (f.contains('5')) return '5 GHz';
    if (f.contains('2')) return '2.4 GHz';
    return f.isEmpty ? 'WiFi' : f;
  }

  bool _radioOn(Map<String, dynamic> r) {
    final v = r['WifiEnable'] ?? r['Enable'] ?? r['enable'];
    return v == true || '$v' == '1' || '$v' == 'true';
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final logged = s.ext?.loggedIn == true;
    final extDev = s.devices.where((d) => d.ip == ip.text.trim()).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        NoteBox(
          s.t(
              'المقوي Huawei EchoLife WA8021V5 يعيد بث الواي فاي فقط (2.4 GHz و 5 GHz). نوع الإنترنت 4G أو 5G يُختار من الراوتر في صفحة "الإشارة والترددات"، والمقوي ينقل ما يصله من الراوتر تلقائياً.',
              'The WA8021V5 only repeats WiFi (2.4 / 5 GHz). Choose 4G/5G on the router (Signal page); the extender carries it automatically.'),
          color: AppColors.blue,
          icon: Icons.lightbulb_outline,
        ),
        if (extDev.isNotEmpty)
          SectionCard(
            title: s.t('المقوي كما يراه الراوتر', 'Extender seen by router'),
            icon: Icons.hub_rounded,
            child: Column(children: [
              InfoRow(s.t('الاسم', 'Name'), extDev.first.name),
              InfoRow('IP', extDev.first.ip),
              InfoRow('MAC', extDev.first.mac),
              InfoRow(s.t('متصل عبر', 'Linked via'), extDev.first.iface),
            ]),
          ),
        SectionCard(
          title: s.t('الدخول إلى المقوي', 'Extender login'),
          icon: Icons.router_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: ip,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: s.t('عنوان المقوي', 'Extender address'),
                prefixIcon: const Icon(Icons.lan_outlined),
                helperText: s.t(
                    'بعد ربطه بالراوتر يأخذ عنواناً جديداً — التطبيق يحاول اكتشافه من قائمة الأجهزة',
                    'After pairing it gets a new IP — auto-detected from the device list'),
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
            if (reachable == false)
              NoteBox(s.t('المقوي لا يرد على هذا العنوان', 'Extender not reachable at this address'),
                  color: AppColors.red),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : () => _connect(s),
                  icon: busy
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: Text(s.t('اتصال', 'Connect')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openPanel,
                  icon: const Icon(Icons.open_in_browser),
                  label: Text(s.t('فتح لوحة المقوي', 'Open panel')),
                ),
              ),
            ]),
          ]),
        ),
        if (logged) ...[
          SectionCard(
            title: s.t('ترددات البث في المقوي', 'Extender WiFi bands'),
            icon: Icons.wifi_tethering_rounded,
            child: radios.isEmpty
                ? Text(
                    s.t('المقوي لم يرسل إعدادات الواي فاي — استخدم "فتح لوحة المقوي"',
                        'No radio data — use "Open panel"'),
                    style: const TextStyle(color: AppColors.text2))
                : Column(children: [
                    for (final r in radios)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_radioName(r)),
                        subtitle: Text(
                            '${r['WifiSsid'] ?? r['Ssid'] ?? ''}  ${r['Channel'] != null ? '· CH ${r['Channel']}' : ''}'),
                        value: _radioOn(r),
                        onChanged: (v) async {
                          try {
                            await s.ext!.setRadio(r, v);
                            radios = await s.ext!.radios();
                            if (mounted) setState(() {});
                          } catch (e) {
                            if (context.mounted) toast(context, e.toString(), error: true);
                          }
                        },
                      ),
                    NoteBox(
                      s.t(
                          'نصيحة: 5 GHz أسرع للأجهزة القريبة، 2.4 GHz يصل لمسافة أبعد وخلف الجدران. تشغيل الاثنين معاً هو الأفضل غالباً.',
                          'Tip: 5 GHz is faster nearby; 2.4 GHz reaches further. Both on is usually best.'),
                      color: AppColors.green,
                      icon: Icons.tips_and_updates_outlined,
                    ),
                  ]),
          ),
          SectionCard(
            title: s.t('أجهزة متصلة بالمقوي', 'Devices on extender'),
            icon: Icons.devices_rounded,
            child: hosts.isEmpty
                ? Text(s.t('لا توجد بيانات', 'No data'),
                    style: const TextStyle(color: AppColors.text2))
                : Column(children: [
                    for (final h in hosts)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.smartphone_rounded, color: AppColors.cyan),
                        title: Text('${h['HostName'] ?? h['ActualName'] ?? h['MACAddress'] ?? ''}'),
                        subtitle: Text('${h['IPAddress'] ?? h['IpAddress'] ?? ''}'),
                      ),
                  ]),
          ),
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
      ],
    );
  }
}
