import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/xml_utils.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final pathCtrl = TextEditingController(text: 'lan/HostInfo');
  String rawOut = '';
  bool loadingRaw = false;

  static const quickPaths = [
    'device/signal',
    'monitoring/status',
    'net/net-mode',
    'net/net-mode-list',
    'lan/HostInfo',
    'wlan/multi-basic-settings',
    'wlan/multi-macfilter-settings',
    'security/url-filter',
    'monitoring/start_date',
  ];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final i = s.info;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: s.t('اللغة', 'Language'),
          icon: Icons.translate_rounded,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ar', label: Text('العربية')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {s.lang},
            onSelectionChanged: (v) => s.setLang(v.first),
          ),
        ),
        SectionCard(
          title: s.t('معلومات الراوتر', 'Router info'),
          icon: Icons.info_outline_rounded,
          child: Column(children: [
            InfoRow(s.t('الموديل', 'Model'), i.s('DeviceName')),
            InfoRow(s.t('إصدار النظام', 'Software'), i.s('SoftwareVersion')),
            InfoRow(s.t('إصدار الجهاز', 'Hardware'), i.s('HardwareVersion')),
            InfoRow(s.t('عنوان الراوتر', 'Address'), s.routerIp),
            InfoRow('WAN IP', i.s('WanIPAddress')),
            InfoRow(s.t('المشغل', 'Operator'), s.operatorName),
          ]),
        ),
        SectionCard(
          title: s.t('التحكم', 'Control'),
          icon: Icons.power_settings_new_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await confirm(context, s.t('إعادة تشغيل الراوتر؟', 'Reboot router?'),
                    s.t('سينقطع الإنترنت دقيقتين تقريباً.', 'Internet will be down ~2 minutes.'));
                if (!ok) return;
                final err = await s.reboot();
                if (context.mounted) {
                  toast(context, err ?? s.t('جاري إعادة التشغيل...', 'Rebooting...'),
                      error: err != null);
                }
              },
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(s.t('إعادة تشغيل الراوتر', 'Reboot router')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: s.disconnect,
              icon: const Icon(Icons.logout_rounded, color: AppColors.red),
              label: Text(s.t('تسجيل الخروج', 'Sign out'),
                  style: const TextStyle(color: AppColors.red)),
            ),
          ]),
        ),
        SectionCard(
          title: s.t('وحدة API (للمطور)', 'API console (developer)'),
          icon: Icons.terminal_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in quickPaths)
                ActionChip(
                  label: Text(p, style: const TextStyle(fontSize: 11)),
                  onPressed: () => setState(() => pathCtrl.text = p),
                ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: pathCtrl,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(prefixText: '/api/'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: loadingRaw
                    ? null
                    : () async {
                        setState(() => loadingRaw = true);
                        final r = await s.raw(pathCtrl.text);
                        if (!mounted) return;
                        setState(() {
                          rawOut = r;
                          loadingRaw = false;
                        });
                      },
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            ]),
            if (rawOut.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                constraints: const BoxConstraints(maxHeight: 320),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(rawOut,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11, color: AppColors.green)),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: rawOut));
                  toast(context, s.t('تم النسخ', 'Copied'));
                },
                icon: const Icon(Icons.copy_rounded),
                label: Text(s.t('نسخ الرد', 'Copy')),
              ),
            ],
          ]),
        ),
        SectionCard(
          title: s.t('السجل', 'Log'),
          icon: Icons.receipt_long_rounded,
          trailing: IconButton(
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: s.logs.join('\n')));
              toast(context, s.t('تم النسخ', 'Copied'));
            },
          ),
          child: SizedBox(
            height: 220,
            child: ListView(children: [
              for (final l in s.logs.take(120))
                Text(l,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11, color: AppColors.text2)),
            ]),
          ),
        ),
        const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text('MHM NET5G v1.0.0', style: TextStyle(color: AppColors.text2)),
          ),
        ),
      ],
    );
  }
}
