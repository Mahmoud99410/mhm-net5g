import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/format.dart';
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
          title: s.t('وحدة قياس السرعة', 'Speed unit'),
          icon: Icons.straighten_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: [
                for (final u in speedUnits) ButtonSegment(value: u, label: Text(u)),
              ],
              selected: {s.unit},
              onSelectionChanged: (v) => s.setUnit(v.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 8),
            Text(
              s.t('Mbps = ميغابت (المستخدم في عروض الشركات). MB/s = ميغابايت (سرعة التحميل الظاهرة في المتصفح). 1 MB/s = 8 Mbps.',
                  'Mbps = megabits (ISP plans). MB/s = megabytes (download managers). 1 MB/s = 8 Mbps.'),
              style: const TextStyle(color: AppColors.text2, fontSize: 12, height: 1.5),
            ),
          ]),
        ),
        SectionCard(
          title: s.t('فحص السرعة التلقائي', 'Automatic speed test'),
          icon: Icons.av_timer_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final m in [0, 15, 30, 60, 180])
                ChoiceChip(
                  label: Text(m == 0
                      ? s.t('متوقف', 'Off')
                      : m < 60
                          ? s.t('كل $m دقيقة', 'Every $m min')
                          : s.t('كل ${m ~/ 60} ساعة', 'Every ${m ~/ 60} h')),
                  selected: s.autoTestMin == m,
                  onSelected: (_) => s.setAutoTest(m),
                ),
            ]),
            const SizedBox(height: 8),
            Text(
              s.t('يقيس السرعة الفعلية التي يستقبلها الراوتر بشكل دوري ويعرضها في الرئيسية. كل فحص يستهلك تقريباً 70 ميغا.',
                  'Periodically measures the real speed. Each test uses ~70 MB.'),
              style: const TextStyle(color: AppColors.text2, fontSize: 12),
            ),
          ]),
        ),
        SectionCard(
          title: s.t('تقرير التشخيص', 'Diagnostics report'),
          icon: Icons.bug_report_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              s.t('يجمع ردود الراوتر والمقوي في نص واحد (مع إخفاء IMEI وكلمات المرور) لتنسخه وترسله للمطور.',
                  'Collects router & extender responses (secrets masked) to send to the developer.'),
              style: const TextStyle(color: AppColors.text2, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: loadingRaw
                  ? null
                  : () async {
                      setState(() => loadingRaw = true);
                      final r = await s.buildDiagnostics();
                      await Clipboard.setData(ClipboardData(text: r));
                      if (!mounted) return;
                      setState(() {
                        rawOut = r;
                        loadingRaw = false;
                      });
                      toast(context, s.t('تم نسخ التقرير — الصقه في المحادثة', 'Report copied'));
                    },
              icon: const Icon(Icons.copy_all_rounded),
              label: Text(s.t('إنشاء ونسخ التقرير', 'Build & copy report')),
            ),
          ]),
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
            child: Text('MHM NET5G v1.3.0', style: TextStyle(color: AppColors.text2)),
          ),
        ),
      ],
    );
  }
}
