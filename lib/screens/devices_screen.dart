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

  bool showOld = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final online = {for (final d in s.devices) d.mac: d};
    int cmp(String a, String b) {
      if (byUsage) return (s.deviceBytes[b] ?? 0).compareTo(s.deviceBytes[a] ?? 0);
      final da = online[a], db = online[b];
      return ((db?.rxRate ?? 0) + (db?.txRate ?? 0))
          .compareTo((da?.rxRate ?? 0) + (da?.txRate ?? 0));
    }

    final activeMacs = s.devices.where((d) => d.active).map((d) => d.mac).toList();
    final routerMacs = activeMacs.where((m) => !(online[m]!.viaExtender)).toList()..sort(cmp);
    final extMacs = activeMacs.where((m) => online[m]!.viaExtender).toList()..sort(cmp);
    // blocked devices are not "active" but must stay visible to unblock them
    final blocked = s.rules.values
        .where((r) => r.shouldBlock(DateTime.now()) && !activeMacs.contains(r.mac))
        .map((r) => r.mac)
        .toList();
    final old = s.devices
        .where((d) => !d.active && !blocked.contains(d.mac))
        .map((d) => d.mac)
        .toList()
      ..sort(cmp);
    final total = s.deviceBytes.values.fold<int>(0, (a, b) => a + b);
    final ext = s.extenderDevice;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TileGrid(minWidth: 150, children: [
          StatTile(
            label: s.t('متصل الآن', 'Online now'),
            value: '${activeMacs.length}',
            icon: Icons.wifi_rounded,
            color: AppColors.green,
          ),
          StatTile(
            label: s.t('على الراوتر', 'On router'),
            value: '${routerMacs.length}',
            icon: Icons.router_rounded,
          ),
          StatTile(
            label: s.t('على المقوي', 'On extender'),
            value: ext == null && extMacs.isEmpty ? '—' : '${extMacs.length}',
            icon: Icons.wifi_tethering_rounded,
            color: AppColors.purple,
            sub: ext == null && extMacs.isEmpty
                ? s.t('سجّل دخول المقوي لمعرفة أجهزته', 'Log in to extender')
                : null,
          ),
          StatTile(
            label: s.t('استهلاك مرصود', 'Tracked usage'),
            value: fmtBytes(total),
            icon: Icons.data_usage_rounded,
            color: AppColors.amber,
          ),
        ]),
        const SizedBox(height: 12),
        if (total > 0) _donut(s, total),
        if (!s.routerSupportsPerDeviceRate)
          NoteBox(s.t(
              'الراوتر لا يرسل سرعة كل جهاز بشكل منفصل، لذلك قد يبقى عدّاد الجيجات لكل جهاز صفراً. أرسل لي "تقرير التشخيص" من الإعدادات لأضيف الحقول الصحيحة لراوترك.',
              'Router does not report per-device speed yet; send the diagnostics report.')),
        Row(children: [
          Expanded(
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text(s.t('الأكثر استهلاكاً', 'Top usage'))),
                ButtonSegment(value: false, label: Text(s.t('الأسرع الآن', 'Fastest now'))),
              ],
              selected: {byUsage},
              onSelectionChanged: (v) => setState(() => byUsage = v.first),
              showSelectedIcon: false,
            ),
          ),
        ]),
        const SizedBox(height: 14),
        _header(s.t('متصلة بالراوتر', 'Connected to router'), Icons.router_rounded,
            AppColors.cyan, routerMacs.length),
        for (final mac in routerMacs) _deviceCard(s, mac, online[mac], total),
        if (routerMacs.isEmpty) _empty(s),
        if (extMacs.isNotEmpty || ext != null) ...[
          _header(s.t('متصلة بالمقوي', 'Connected to extender'), Icons.wifi_tethering_rounded,
              AppColors.purple, extMacs.length),
          for (final mac in extMacs) _deviceCard(s, mac, online[mac], total),
          if (extMacs.isEmpty)
            NoteBox(
                s.t('لمعرفة الأجهزة المتصلة بالمقوي سجّل الدخول إليه من صفحة "المقوي".',
                    'Log in to the extender to list its devices.'),
                color: AppColors.purple),
        ],
        if (blocked.isNotEmpty) ...[
          _header(s.t('محظورة', 'Blocked'), Icons.block, AppColors.red, blocked.length),
          for (final mac in blocked) _deviceCard(s, mac, online[mac], total),
        ],
        const SizedBox(height: 6),
        SwitchListTile(
          value: showOld,
          onChanged: (v) => setState(() => showOld = v),
          title: Text(s.t('إظهار الأجهزة التي اتصلت سابقاً (${old.length})',
              'Show previously connected (${old.length})')),
        ),
        if (showOld)
          for (final mac in old) _deviceCard(s, mac, online[mac], total),
      ],
    );
  }

  Widget _donut(AppState s, int total) {
    final entries = s.deviceBytes.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.take(5).toList();
    final rest = entries.skip(5).fold<int>(0, (a, e) => a + e.value);
    String nm(String mac) => s.rules[mac]?.name.isNotEmpty == true
        ? s.rules[mac]!.name
        : (s.deviceNames[mac] ?? mac);
    return SectionCard(
      title: s.t('من يستهلك الإنترنت؟', 'Who uses the internet?'),
      icon: Icons.pie_chart_rounded,
      child: Donut(
        labels: [for (final e in top) nm(e.key), if (rest > 0) s.t('أخرى', 'Other')],
        values: [for (final e in top) e.value.toDouble(), if (rest > 0) rest.toDouble()],
        center: fmtBytes(total),
        sub: s.t('هذه الدورة', 'this cycle'),
      ),
    );
  }

  Widget _header(String t, IconData icon, Color c, int n) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
        child: Row(children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(width: 8),
          Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(width: 8),
          Pill('$n', color: c),
        ]),
      );

  Widget _empty(AppState s) => Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
            child: Text(s.t('لا توجد أجهزة', 'No devices'),
                style: const TextStyle(color: AppColors.text2))),
      );

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
              if (rule != null && rule.band != 'both') 'WiFi ${rule.band}GHz',
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
    final nameCtrl = TextEditingController(text: name);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => Directionality(
        textDirection: s.ar ? TextDirection.rtl : TextDirection.ltr,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            builder: (c, sc) => StatefulBuilder(builder: (c, set) {
              final rule = s.rules[mac];
              final blocked = rule?.blocked ?? false;
              return ListView(controller: sc, padding: const EdgeInsets.all(20), children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                        color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.cyan.withValues(alpha: 0.15),
                    child: Icon(_icon(name), color: AppColors.cyan, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(
                          d?.active == true
                              ? s.t('متصل الآن', 'Online')
                              : s.t('غير متصل', 'Offline'),
                          style: TextStyle(
                              color: d?.active == true ? AppColors.green : AppColors.text2)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 18),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: s.t('اسم الجهاز', 'Device name'),
                    prefixIcon: const Icon(Icons.edit_rounded),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check_rounded, color: AppColors.green),
                      onPressed: () async {
                        final v = nameCtrl.text.trim();
                        if (v.isEmpty) return;
                        s.ruleFor(mac).name = v;
                        s.deviceNames[mac] = v;
                        await s.saveRules();
                        if (mounted) setState(() {});
                        if (c.mounted) {
                          FocusScope.of(c).unfocus();
                          toast(context, s.t('تم حفظ الاسم ✓', 'Name saved ✓'));
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: (blocked ? AppColors.red : AppColors.green).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SwitchListTile(
                    value: !blocked,
                    activeThumbColor: AppColors.green,
                    title: Text(blocked
                        ? s.t('محظور من الإنترنت', 'Blocked')
                        : s.t('مسموح له بالإنترنت', 'Allowed')),
                    secondary: Icon(blocked ? Icons.block : Icons.check_circle_rounded,
                        color: blocked ? AppColors.red : AppColors.green),
                    onChanged: (allow) async {
                      final err = await s.setBlocked(mac, !allow, name: nameCtrl.text.trim());
                      set(() {});
                      if (mounted) setState(() {});
                      if (c.mounted && err != null) toast(context, err, error: true);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      const Icon(Icons.wifi_rounded, color: AppColors.cyan),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(s.t('شبكة الواي فاي المسموحة لهذا الجهاز', 'Allowed WiFi band'),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: '2.4', label: Text(s.t('2.4 فقط', '2.4 only'))),
                        ButtonSegment(value: '5', label: Text(s.t('5 فقط', '5 only'))),
                        ButtonSegment(value: 'both', label: Text(s.t('الاثنين', 'Both'))),
                      ],
                      selected: {rule?.band ?? 'both'},
                      showSelectedIcon: false,
                      onSelectionChanged: (v) async {
                        final err =
                            await s.setDeviceBand(mac, v.first, name: nameCtrl.text.trim());
                        set(() {});
                        if (mounted) setState(() {});
                        if (c.mounted) {
                          toast(context, err ?? s.t('تم التطبيق ✓', 'Applied ✓'),
                              error: err != null);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.t('شبكة 2.4 GHz (أبعد مدى) أو 5 GHz (أسرع). عند اختيار واحدة يمنع الراوتر الجهاز من الاتصال بالأخرى، فيتصل تلقائياً بالمسموحة. هذا خاص بالواي فاي، أما 4G/5G من البرج فهي للراوتر كله.',
                          '2.4 GHz (range) or 5 GHz (speed). The device is blocked on the other band so it joins the allowed one.'),
                      style: const TextStyle(color: AppColors.text2, fontSize: 12, height: 1.5),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  tileColor: AppColors.surface2,
                  leading: const Icon(Icons.schedule_rounded, color: AppColors.amber),
                  title: Text(s.t('وقت الإنترنت (جدولة)', 'Internet schedule')),
                  subtitle: Text(rule?.scheduleOn == true
                      ? '${rule!.from} → ${rule.to}'
                      : s.t('غير مفعّل', 'Off')),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    await _schedule(s, mac, nameCtrl.text.trim());
                    set(() {});
                  },
                ),
                const SizedBox(height: 16),
                InfoRow('MAC', mac),
                InfoRow('IP', d?.ip ?? ''),
                InfoRow(s.t('الاتصال', 'Link'),
                    d == null ? '' : (d.viaExtender ? s.t('عبر المقوي', 'via extender') : d.iface)),
                InfoRow(s.t('الاستهلاك بالدورة', 'Cycle usage'), fmtBytes(s.deviceBytes[mac] ?? 0)),
                InfoRow(s.t('مدة الاتصال', 'Connected'), fmtDuration(d?.connectedSec ?? 0)),
                if (d != null)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(s.t('كل البيانات من الراوتر', 'All router data'),
                        style: const TextStyle(fontSize: 13, color: AppColors.text2)),
                    children: [
                      for (final e in d.raw.entries)
                        if (e.value is String) InfoRow(e.key, e.value),
                    ],
                  ),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}
