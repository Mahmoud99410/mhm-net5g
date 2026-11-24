import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../widgets/common.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  bool byUsage = true;

  IconData _icon(String name) {
    final n = name.toLowerCase();
    if (n.contains('tv') || n.contains('android-tv') || n.contains('box') || n.contains('shield')) {
      return Icons.tv_rounded;
    }
    if (n.contains('laptop') || n.contains('desktop') || n.contains('pc') || n.contains('win')) {
      return Icons.laptop_rounded;
    }
    if (n.contains('ipad') || n.contains('tab')) return Icons.tablet_android_rounded;
    if (n.contains('server') || n.contains('nas') || n.contains('raspberry')) {
      return Icons.dns_rounded;
    }
    if (n.contains('huawei') || n.contains('wa80')) return Icons.router_rounded;
    return Icons.smartphone_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    // devices known (online) + blocked/offline devices with rules
    final online = {for (final d in s.devices) d.mac: d};
    final macs = <String>{...online.keys, ...s.rules.keys, ...s.deviceBytes.keys}.toList();
    macs.sort((a, b) {
      if (byUsage) return (s.deviceBytes[b] ?? 0).compareTo(s.deviceBytes[a] ?? 0);
      final da = online[a], db = online[b];
      return ((db?.rxRate ?? 0) + (db?.txRate ?? 0))
          .compareTo((da?.rxRate ?? 0) + (da?.txRate ?? 0));
    });
    final total = s.deviceBytes.values.fold<int>(0, (a, b) => a + b);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (!s.routerSupportsPerDeviceRate)
          NoteBox(s.t(
              'نسخة نظام الراوتر لا ترسل سرعة كل جهاز بشكل منفصل حتى الآن، لذلك عدّاد الجيجات لكل جهاز قد يبقى صفراً. الحظر والجدولة والقائمة تعمل بشكل طبيعي. أرسل لي صفحة "الإعدادات ← وحدة API" لـ lan/HostInfo لأضيف الحقول الصحيحة.',
              'Router firmware does not report per-device speed yet, so per-device GB may stay 0. Blocking and scheduling still work.')),
        SectionCard(
          title: s.t('أكثر الأجهزة استهلاكاً (الدورة الحالية)', 'Top consumers (this cycle)'),
          icon: Icons.leaderboard_rounded,
          trailing: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(s.t('الاستهلاك', 'Usage'))),
              ButtonSegment(value: false, label: Text(s.t('السرعة', 'Speed'))),
            ],
            selected: {byUsage},
            onSelectionChanged: (v) => setState(() => byUsage = v.first),
            showSelectedIcon: false,
          ),
          child: Text(
            s.t('إجمالي ما تم رصده: ${fmtBytes(total)} · الأجهزة المتصلة: ${s.devices.where((d) => d.active).length}',
                'Tracked total: ${fmtBytes(total)} · online: ${s.devices.where((d) => d.active).length}'),
            style: const TextStyle(color: AppColors.text2),
          ),
        ),
        for (final mac in macs) _deviceCard(s, mac, online[mac], total),
        if (macs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40),
            child: Center(child: Text(s.t('لا توجد أجهزة', 'No devices'))),
          ),
      ],
    );
  }

  Widget _deviceCard(AppState s, String mac, DeviceInfo? d, int total) {
    final rule = s.rules[mac];
    final name = rule?.name.isNotEmpty == true
        ? rule!.name
        : (d?.name ?? s.deviceNames[mac] ?? mac);
    final used = s.deviceBytes[mac] ?? 0;
    final blockedNow = rule?.shouldBlock(DateTime.now()) ?? false;
    final online = d != null && d.active;
    final share = total > 0 ? used / total : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: blockedNow ? AppColors.red : AppColors.border),
      ),
      child: Column(children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: (online ? AppColors.cyan : AppColors.text2).withValues(alpha: 0.15),
            child: Icon(_icon(name), color: online ? AppColors.cyan : AppColors.text2),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            [
              if (d?.ip.isNotEmpty == true) d!.ip,
              mac,
              if (d?.iface.isNotEmpty == true) d!.iface,
              if (!online) s.t('غير متصل', 'offline'),
              if (blockedNow) s.t('محظور', 'BLOCKED'),
            ].join(' · '),
            style: TextStyle(fontSize: 11, color: blockedNow ? AppColors.red : AppColors.text2),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fmtBytes(used),
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.cyan)),
              if (d != null && (d.rxRate + d.txRate) > 0)
                Text('↓${fmtRate(d.rxRate)} ↑${fmtRate(d.txRate)}',
                    style: const TextStyle(fontSize: 10, color: AppColors.text2)),
            ],
          ),
          onTap: () => _details(s, mac, name, d),
        ),
        if (share > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LinearProgressIndicator(
              value: share,
              minHeight: 4,
              backgroundColor: AppColors.surface2,
              valueColor: const AlwaysStoppedAnimation(AppColors.cyan),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: Row(children: [
            TextButton.icon(
              onPressed: () async {
                final err = await s.setBlocked(mac, !(rule?.blocked ?? false), name: name);
                if (mounted) {
                  toast(context,
                      err ??
                          (s.rules[mac]?.blocked == true
                              ? s.t('تم الحظر', 'Blocked')
                              : s.t('تم السماح', 'Allowed')),
                      error: err != null);
                }
              },
              icon: Icon(rule?.blocked == true ? Icons.check_circle_outline : Icons.block,
                  color: rule?.blocked == true ? AppColors.green : AppColors.red, size: 18),
              label: Text(rule?.blocked == true ? s.t('السماح', 'Allow') : s.t('حظر', 'Block'),
                  style: TextStyle(
                      color: rule?.blocked == true ? AppColors.green : AppColors.red)),
            ),
            TextButton.icon(
              onPressed: () => _schedule(s, mac, name),
              icon: Icon(Icons.schedule,
                  size: 18,
                  color: rule?.scheduleOn == true ? AppColors.amber : AppColors.text2),
              label: Text(
                rule?.scheduleOn == true
                    ? '${rule!.from} → ${rule.to}'
                    : s.t('وقت الإنترنت', 'Schedule'),
                style: TextStyle(
                    color: rule?.scheduleOn == true ? AppColors.amber : AppColors.text2),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: s.t('تسمية', 'Rename'),
              icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.text2),
              onPressed: () => _rename(s, mac, name),
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _rename(AppState s, String mac, String name) async {
    final c = TextEditingController(text: name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('اسم الجهاز', 'Device name')),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('إلغاء', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text(s.t('حفظ', 'Save'))),
        ],
      ),
    );
    if (v == null || v.isEmpty) return;
    s.ruleFor(mac).name = v;
    s.deviceNames[mac] = v;
    await s.saveRules();
    setState(() {});
  }

  Future<void> _schedule(AppState s, String mac, String name) async {
    final r = s.ruleFor(mac, name);
    var on = r.scheduleOn;
    var from = r.from, to = r.to;
    final days = r.days.toSet();
    const dayNamesAr = ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'];
    const dayNamesEn = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

    TimeOfDay parse(String hm) {
      final p = hm.split(':');
      return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
    }

    String fmt(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        return AlertDialog(
          title: Text(s.t('وقت الإنترنت لـ $name', 'Internet schedule: $name')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: on,
                onChanged: (v) => set(() => on = v),
                title: Text(s.t('قطع الإنترنت في الوقت المحدد', 'Block during these hours')),
              ),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(context: ctx, initialTime: parse(from));
                      if (t != null) set(() => from = fmt(t));
                    },
                    child: Text('${s.t('من', 'From')} $from'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final t = await showTimePicker(context: ctx, initialTime: parse(to));
                      if (t != null) set(() => to = fmt(t));
                    },
                    child: Text('${s.t('إلى', 'To')} $to'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 4, children: [
                for (var i = 1; i <= 7; i++)
                  FilterChip(
                    label: Text(s.ar ? dayNamesAr[i - 1] : dayNamesEn[i - 1]),
                    selected: days.contains(i),
                    onSelected: (v) => set(() => v ? days.add(i) : days.remove(i)),
                  ),
              ]),
              const SizedBox(height: 12),
              NoteBox(
                s.t('الجدولة تُنفَّذ من التطبيق: اترك نسخة الويندوز أو التطبيق مفتوحاً ليتم الحظر والسماح في الوقت المحدد.',
                    'Schedules are enforced by the app: keep the Windows app or phone app open.'),
                color: AppColors.blue,
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('إلغاء', 'Cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('حفظ', 'Save'))),
          ],
        );
      }),
    );
    if (saved != true) return;
    r
      ..scheduleOn = on
      ..from = from
      ..to = to
      ..days = (days.toList()..sort());
    await s.saveRules();
    final err = await s.enforceRules(force: true);
    if (mounted) toast(context, err ?? s.t('تم الحفظ ✓', 'Saved ✓'), error: err != null);
    setState(() {});
  }

  void _details(AppState s, String mac, String name, DeviceInfo? d) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (c) => Directionality(
        textDirection: s.ar ? TextDirection.rtl : TextDirection.ltr,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (c, sc) => ListView(controller: sc, padding: const EdgeInsets.all(20), children: [
            Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            InfoRow('MAC', mac),
            InfoRow('IP', d?.ip ?? ''),
            InfoRow(s.t('الاستهلاك بالدورة', 'Cycle usage'), fmtBytes(s.deviceBytes[mac] ?? 0)),
            InfoRow(s.t('مدة الاتصال', 'Connected'), fmtDuration(d?.connectedSec ?? 0)),
            const Divider(),
            if (d != null)
              for (final e in d.raw.entries)
                if (e.value is String) InfoRow(e.key, e.value),
          ]),
        ),
      ),
    );
  }
}
