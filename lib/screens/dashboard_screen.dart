import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/xml_utils.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool testing = false;
  double liveDl = 0;
  double? dl, ul;
  int? ping;

  void _set(VoidCallback f) {
    if (mounted) setState(f);
  }

  Future<void> _speedTest(AppState s) async {
    _set(() {
      testing = true;
      dl = null;
      ul = null;
      ping = null;
      liveDl = 0;
    });
    final p = await s.measurePing();
    _set(() => ping = p);
    final d = await s.measureDownload(
        bytes: 50000000, onProgress: (v) => _set(() => liveDl = v));
    _set(() => dl = d);
    final u = await s.measureUpload(bytes: 8000000);
    _set(() {
      ul = u;
      testing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final sig = s.signal;
    final rsrp4 = sig.d('rsrp');
    final rsrp5 = sig.d('nrrsrp');
    final q4 = rsrpQuality(rsrp4);
    final q5 = rsrpQuality(rsrp5);
    final dlRate = s.traffic.d('CurrentDownloadRate');
    final ulRate = s.traffic.d('CurrentUploadRate');
    final active = s.devices.where((d) => d.active).length;
    final cycleUsed = s.cycleUsageRouter > 0 ? s.cycleUsageRouter : s.cycleUsageApp;
    final next = nextCycleStart(DateTime.now(), s.resetDay);
    final daysLeft = next.difference(DateTime.now()).inDays + 1;

    return RefreshIndicator(
      onRefresh: s.refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---------- network header ----------
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF0E3A66), Color(0xFF0B1F3D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.operatorName.isEmpty ? 'Zain JO' : s.operatorName,
                      style: const TextStyle(color: AppColors.text2)),
                  const SizedBox(height: 4),
                  Text(s.networkLabel,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (sig.s('band').isNotEmpty) '4G: B${sig.s('band')}',
                      if (sig.s('nrband').isNotEmpty) '5G: n${sig.s('nrband')}',
                      if (s.info.s('DeviceName').isNotEmpty) s.info.s('DeviceName'),
                    ].join('  ·  '),
                    style: const TextStyle(color: AppColors.text2, fontSize: 12),
                  ),
                ]),
              ),
              Column(children: [
                Row(children: [
                  const Text('4G ', style: TextStyle(fontSize: 12)),
                  SignalBars(level: q4.level, color: q4.color),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  const Text('5G ', style: TextStyle(fontSize: 12)),
                  SignalBars(level: q5.level, color: q5.color),
                ]),
              ]),
            ]),
          ),

          // ---------- live speed ----------
          SectionCard(
            title: s.t('السرعة الآن', 'Live speed'),
            icon: Icons.speed_rounded,
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: _speed(s.t('تنزيل', 'Download'), fmtRate(dlRate),
                        Icons.arrow_downward_rounded, AppColors.cyan)),
                const SizedBox(width: 10),
                Expanded(
                    child: _speed(s.t('رفع', 'Upload'), fmtRate(ulRate),
                        Icons.arrow_upward_rounded, AppColors.purple)),
              ]),
              const SizedBox(height: 12),
              Sparkline(a: s.dlHistory, b: s.ulHistory),
            ]),
          ),

          TileGrid(children: [
            StatTile(
              label: s.t('أجهزة متصلة', 'Connected devices'),
              value: '$active',
              icon: Icons.devices_other_rounded,
              color: AppColors.green,
            ),
            StatTile(
              label: s.t('استهلاك الدورة', 'Cycle usage'),
              value: fmtBytes(cycleUsed),
              icon: Icons.data_usage_rounded,
              sub: s.t('يتجدد بعد $daysLeft يوم (يوم ${s.resetDay})',
                  'Resets in $daysLeft d (day ${s.resetDay})'),
            ),
            StatTile(
              label: s.t('مدة الاتصال', 'Connected for'),
              value: fmtDuration(s.traffic.i('CurrentConnectTime')),
              icon: Icons.timer_outlined,
              color: AppColors.amber,
            ),
            StatTile(
              label: s.t('إشارة 5G (RSRP)', '5G RSRP'),
              value: rsrp5 == 0 ? '—' : '${rsrp5.toStringAsFixed(0)} dBm',
              icon: Icons.five_g_rounded,
              color: q5.color,
              sub: s.ar ? q5.ar : q5.en,
            ),
            StatTile(
              label: s.t('إشارة 4G (RSRP)', '4G RSRP'),
              value: rsrp4 == 0 ? '—' : '${rsrp4.toStringAsFixed(0)} dBm',
              icon: Icons.signal_cellular_alt_rounded,
              color: q4.color,
              sub: s.ar ? q4.ar : q4.en,
            ),
            StatTile(
              label: 'SINR',
              value: sig.s('sinr').isEmpty && sig.s('nrsinr').isEmpty
                  ? '—'
                  : '${(sig.s('nrsinr').isNotEmpty ? sig.d('nrsinr') : sig.d('sinr')).toStringAsFixed(0)} dB',
              icon: Icons.graphic_eq_rounded,
              color: AppColors.blue,
              sub: s.t('جودة الإشارة', 'Signal quality'),
            ),
          ]),
          const SizedBox(height: 14),

          // ---------- speed test ----------
          SectionCard(
            title: s.t('فحص سرعة الإنترنت', 'Internet speed test'),
            icon: Icons.network_check_rounded,
            trailing: FilledButton.tonalIcon(
              onPressed: testing ? null : () => _speedTest(s),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(testing ? s.t('جاري...', 'Running...') : s.t('ابدأ', 'Start')),
            ),
            child: Row(children: [
              Expanded(
                  child: _speed(
                      s.t('تنزيل', 'Download'),
                      dl != null
                          ? '${dl!.toStringAsFixed(1)} Mbps'
                          : (testing && liveDl > 0 ? '${liveDl.toStringAsFixed(1)} …' : '—'),
                      Icons.download_rounded,
                      AppColors.cyan)),
              const SizedBox(width: 8),
              Expanded(
                  child: _speed(
                      s.t('رفع', 'Upload'),
                      ul != null ? '${ul!.toStringAsFixed(1)} Mbps' : '—',
                      Icons.upload_rounded,
                      AppColors.purple)),
              const SizedBox(width: 8),
              Expanded(
                  child: _speed(
                      'Ping',
                      ping == null ? '—' : (ping! < 0 ? '×' : '$ping ms'),
                      Icons.bolt_rounded,
                      AppColors.amber)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _speed(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        FittedBox(
          child: Text(value,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        ),
        Text(label, style: const TextStyle(color: AppColors.text2, fontSize: 12)),
      ]),
    );
  }
}
