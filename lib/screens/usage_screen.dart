import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/xml_utils.dart';
import '../widgets/common.dart';

class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  DateTimeRange? range;
  late final TextEditingController limitCtrl;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    limitCtrl = TextEditingController(
        text: s.monthlyLimitGb > 0 ? s.monthlyLimitGb.toStringAsFixed(0) : '');
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final now = DateTime.now();
    final start = cycleStart(now, s.resetDay);
    final next = nextCycleStart(now, s.resetDay);
    final routerUsed = s.cycleUsageRouter;
    final appUsed = s.cycleUsageApp;
    final used = routerUsed > 0 ? routerUsed : appUsed;
    final limitBytes = s.monthlyLimitGb * 1024 * 1024 * 1024;
    final frac = limitBytes > 0 ? (used / limitBytes).clamp(0.0, 1.0) : 0.0;

    // last 30 days chart
    final labels = <String>[];
    final values = <double>[];
    for (var i = 29; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      labels.add('${d.day}/${d.month}');
      values.add((s.daily[dayKey(d)] ?? 0).toDouble());
    }
    final r = range ?? DateTimeRange(start: start, end: now);
    final rangeUsed = s.usageBetween(r.start, r.end);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: s.t('الدورة الحالية', 'Current cycle'),
          icon: Icons.donut_large_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(fmtBytes(used),
                style: const TextStyle(
                    fontSize: 34, fontWeight: FontWeight.w900, color: AppColors.cyan)),
            Text(
              '${s.t('من', 'From')} ${dayKey(start)}  ${s.t('إلى', 'to')} ${dayKey(next.subtract(const Duration(days: 1)))}',
              style: const TextStyle(color: AppColors.text2),
            ),
            if (limitBytes > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 12,
                  backgroundColor: AppColors.surface2,
                  valueColor: AlwaysStoppedAnimation(frac > 0.9
                      ? AppColors.red
                      : frac > 0.7
                          ? AppColors.amber
                          : AppColors.green),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                s.t(
                    'المتبقي ${fmtBytes((limitBytes - used).clamp(0, double.infinity))} من ${s.monthlyLimitGb.toStringAsFixed(0)} GB',
                    'Left ${fmtBytes((limitBytes - used).clamp(0, double.infinity))} of ${s.monthlyLimitGb.toStringAsFixed(0)} GB'),
                style: const TextStyle(color: AppColors.text2),
              ),
            ],
            const Divider(height: 24),
            InfoRow(s.t('عدّاد الراوتر (هذا الشهر)', 'Router counter'), fmtBytes(routerUsed)),
            InfoRow(s.t('عدّاد التطبيق (الدورة)', 'App counter (cycle)'), fmtBytes(appUsed)),
            InfoRow(s.t('إجمالي منذ آخر تشغيل', 'Total since boot'),
                fmtBytes(s.traffic.d('TotalDownload') + s.traffic.d('TotalUpload'))),
            InfoRow(s.t('تجديد الدورة بعد', 'Cycle resets in'),
                '${next.difference(now).inDays + 1} ${s.t('يوم', 'days')}'),
          ]),
        ),
        SectionCard(
          title: s.t('إعدادات الدورة الشهرية', 'Monthly cycle settings'),
          icon: Icons.event_repeat_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(s.t('يوم تصفير العداد كل شهر', 'Reset day each month'))),
              DropdownButton<int>(
                value: s.resetDay,
                items: [
                  for (var d = 1; d <= 31; d++) DropdownMenuItem(value: d, child: Text('$d')),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  final err = await s.setResetDay(v);
                  if (!context.mounted) return;
                  toast(
                      context,
                      err == null
                          ? s.t('تم: يتصفر العداد يوم $v من كل شهر ✓', 'Reset day set to $v ✓')
                          : '${s.t('حُفظ في التطبيق، والراوتر رد', 'Saved in app; router said')}: $err',
                      error: err != null);
                },
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: limitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: s.t('حجم الباقة بالجيجا (اختياري)', 'Plan size in GB (optional)'),
                    prefixIcon: const Icon(Icons.sd_storage_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  s.monthlyLimitGb = double.tryParse(limitCtrl.text.trim()) ?? 0;
                  final err = await s.setResetDay(s.resetDay);
                  if (!context.mounted) return;
                  toast(context, err ?? s.t('تم الحفظ ✓', 'Saved ✓'), error: err != null);
                },
                child: Text(s.t('حفظ', 'Save')),
              ),
            ]),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await confirm(
                    context,
                    s.t('تصفير العدادات الآن؟', 'Reset counters now?'),
                    s.t('سيتم تصفير عداد الراوتر وعدادات الأجهزة.',
                        'Router and device counters will be cleared.'));
                if (!ok) return;
                final err = await s.clearRouterCounters();
                if (!context.mounted) return;
                toast(context, err ?? s.t('تم التصفير ✓', 'Cleared ✓'), error: err != null);
              },
              icon: const Icon(Icons.restart_alt_rounded, color: AppColors.red),
              label: Text(s.t('تصفير العداد الآن', 'Reset now'),
                  style: const TextStyle(color: AppColors.red)),
            ),
          ]),
        ),
        SectionCard(
          title: s.t('الاستهلاك حسب التاريخ الذي تختاره', 'Usage for a date range'),
          icon: Icons.date_range_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                  initialDateRange: r,
                );
                if (picked != null) setState(() => range = picked);
              },
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text('${dayKey(r.start)}  →  ${dayKey(r.end)}'),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(fmtBytes(rangeUsed),
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.green)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                  s.t('محسوب من سجل التطبيق اليومي', 'From the app daily log'),
                  style: const TextStyle(color: AppColors.text2, fontSize: 12)),
            ),
          ]),
        ),
        SectionCard(
          title: s.t('آخر 30 يوم', 'Last 30 days'),
          icon: Icons.bar_chart_rounded,
          child: BarChart(labels: labels, values: values, fmt: (v) => fmtBytes(v)),
        ),
        NoteBox(
          s.t('السجل اليومي يُحسب أثناء فتح التطبيق. عدّاد الراوتر يعمل دائماً حتى لو كان التطبيق مغلقاً.',
              'Daily log is recorded while the app runs. The router counter always runs.'),
          color: AppColors.blue,
        ),
      ],
    );
  }
}
