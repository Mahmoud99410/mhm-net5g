import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/format.dart';
import '../core/xml_utils.dart';
import '../widgets/advice_card.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

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
    final active = s.activeDevices;
    final behindExt = active.where((d) => d.viaExtender).length;
    final ext = s.extenderDevice;
    final cycleUsed = s.cycleUsageRouter > 0 ? s.cycleUsageRouter : s.cycleUsageApp;
    final next = nextCycleStart(DateTime.now(), s.resetDay);
    final daysLeft = next.difference(DateTime.now()).inDays + 1;
    final cap = s.capacityMbps;
    final avail = s.testing && s.testPhase == 'down'
        ? s.liveTest
        : (s.lastTestDl > 0 ? s.lastTestDl : cap);
    final maxBytes = mbpsToBytes(math.max(avail, 50));
    final advice = s.advice;

    return RefreshIndicator(
      onRefresh: s.refreshAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---------- network map ----------
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                colors: [Color(0xFF0E3A66), Color(0xFF0B1F3D), Color(0xFF151A3D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(children: [
              NetworkMap(
                nodes: [
                  MapNode(
                      Icons.cell_tower_rounded,
                      s.operatorName.isEmpty ? 'Zain' : s.operatorName,
                      s.has5G ? '5G + 4G' : '4G',
                      s.has5G ? AppColors.green : AppColors.amber,
                      onTap: () => s.openTab(1)),
                  MapNode(Icons.router_rounded, s.t('الراوتر', 'Router'),
                      '${active.length - behindExt} ${s.t('جهاز', 'dev')}', AppColors.cyan,
                      onTap: () => s.openTab(2)),
                  if (ext != null)
                    MapNode(Icons.wifi_tethering_rounded, s.t('المقوي', 'Extender'),
                        '$behindExt ${s.t('جهاز', 'dev')}', AppColors.purple,
                        onTap: () => s.openTab(6)),
                  MapNode(Icons.devices_other_rounded, s.t('الأجهزة', 'Devices'),
                      '${active.length} ${s.t('اضغط', 'tap')}', AppColors.blue,
                      onTap: () => s.openTab(2)),
                ],
                links: [
                  s.carriers.map((c) => c.label).join('+'),
                  'WiFi',
                  if (ext != null) 'WiFi',
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  Pill(s.networkLabel, color: AppColors.green, icon: Icons.podcasts_rounded),
                  for (final c in s.carriers)
                    Pill(
                        '${c.isNr ? '5G' : '4G'} ${c.label}${c.mhz > 0 ? ' · ${c.mhz.toStringAsFixed(0)}MHz' : ''}',
                        color: c.isNr ? AppColors.cyan : AppColors.amber),
                ],
              ),
            ]),
          ),

          // ---------- gauges ----------
          SectionCard(
            title: s.t('السرعة', 'Speed'),
            icon: Icons.speed_rounded,
            trailing: _unitMenu(s),
            child: Column(children: [
              Wrap(
                alignment: WrapAlignment.spaceEvenly,
                runSpacing: 10,
                spacing: 6,
                children: [
                  RadialGauge(
                    value: dlRate,
                    max: maxBytes,
                    center: _num(rateValue(dlRate)),
                    unit: s.unit,
                    label: s.t('التنزيل الآن', 'Download now'),
                    color: AppColors.cyan,
                    size: 140,
                  ),
                  RadialGauge(
                    value: ulRate,
                    max: maxBytes / 3,
                    center: _num(rateValue(ulRate)),
                    unit: s.unit,
                    label: s.t('الرفع الآن', 'Upload now'),
                    color: AppColors.purple,
                    size: 140,
                  ),
                  RadialGauge(
                    value: mbpsToBytes(avail),
                    max: mbpsToBytes(math.max(avail * 1.25, 100)),
                    center: _num(rateValue(mbpsToBytes(avail))),
                    unit: s.unit,
                    label: s.lastTestDl > 0
                        ? s.t('ما يستقبله الراوتر', 'Router receives')
                        : s.t('المتوقع من البرج', 'Tower estimate'),
                    color: AppColors.green,
                    size: 140,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                s.t(
                    'الأول والثاني = ما تستخدمه أجهزتك الآن. الثالث = أقصى سرعة يستقبلها الراوتر من البرج${s.lastTestDl > 0 ? ' (آخر فحص ${s.lastTestAt})' : ' (تقدير من الإشارة، اضغط "ابدأ" للقياس الفعلي)'}.',
                    'Gauges 1-2 = live use. Gauge 3 = max speed the router can receive.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.text2, fontSize: 11),
              ),
              const Divider(height: 24),
              LiveBars(down: s.dlHistory, up: s.ulHistory),
            ]),
          ),

          // ---------- speed test ----------
          SectionCard(
            title: s.t('فحص السرعة الفعلية', 'Real speed test'),
            icon: Icons.network_check_rounded,
            trailing: FilledButton.tonalIcon(
              onPressed: s.testing ? null : s.runSpeedTest,
              icon: s.testing
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(s.testing ? s.t('جاري', 'Running') : s.t('ابدأ', 'Start')),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (s.testing) ...[
                LinearProgressIndicator(
                  color: s.testPhase == 'up' ? AppColors.purple : AppColors.cyan,
                ),
                const SizedBox(height: 8),
                Text(
                  switch (s.testPhase) {
                    'ping' => s.t('اختيار أقرب سيرفر...', 'Picking nearest server...'),
                    'down' => s.t('قياس التنزيل...', 'Measuring download...'),
                    'up' => s.t('قياس الرفع...', 'Measuring upload...'),
                    _ => '',
                  },
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.text2, fontSize: 12),
                ),
                const SizedBox(height: 8),
              ],
              Row(children: [
                Expanded(
                    child: _metric(
                        s.t('تنزيل', 'Download'),
                        s.testing && s.testPhase == 'down'
                            ? fmtRate(mbpsToBytes(s.liveTest))
                            : (s.lastTestDl > 0 ? fmtRate(mbpsToBytes(s.lastTestDl)) : '—'),
                        Icons.download_rounded,
                        AppColors.cyan)),
                const SizedBox(width: 8),
                Expanded(
                    child: _metric(
                        s.t('رفع', 'Upload'),
                        s.testing && s.testPhase == 'up'
                            ? fmtRate(mbpsToBytes(s.liveTestUl))
                            : (s.lastTestUl > 0 ? fmtRate(mbpsToBytes(s.lastTestUl)) : '—'),
                        Icons.upload_rounded,
                        AppColors.purple)),
                const SizedBox(width: 8),
                Expanded(
                    child: _metric(
                        'Ping',
                        s.lastPing <= 0 ? '—' : '${s.lastPing} ms',
                        Icons.bolt_rounded,
                        AppColors.amber)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.dns_rounded, size: 16, color: AppColors.text2),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.testServer.isEmpty
                        ? s.t('السيرفر: تلقائي (الأقرب والأسرع)', 'Server: automatic')
                        : '${s.testServer}  ·  Jitter ${s.lastJitter} ms',
                    style: const TextStyle(color: AppColors.text2, fontSize: 11),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: s.t('اختيار السيرفر', 'Choose server'),
                  onSelected: s.setPreferredServer,
                  itemBuilder: (_) => [
                    PopupMenuItem(value: '', child: Text(s.t('تلقائي', 'Automatic'))),
                    for (final sv in s.speedServers)
                      PopupMenuItem(
                        value: sv.base,
                        child: Text(
                            '${sv.name}${sv.distance >= 0 ? ' · ${sv.distance.toStringAsFixed(0)} km' : ''}'),
                      ),
                  ],
                  child: Pill(
                      s.preferredServer.isEmpty ? s.t('تلقائي', 'Auto') : s.t('مختار', 'Manual'),
                      icon: Icons.swap_horiz_rounded,
                      color: AppColors.blue),
                ),
              ]),
              if (s.routerDuringTest > 0 && !s.testing)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    s.t('الراوتر سجّل أثناء الفحص: ${fmtRate(mbpsToBytes(s.routerDuringTest))}',
                        'Router saw during test: ${fmtRate(mbpsToBytes(s.routerDuringTest))}'),
                    style: const TextStyle(color: AppColors.text2, fontSize: 11),
                  ),
                ),
              if (s.testHistory.length > 1) ...[
                const Divider(height: 24),
                Text(s.t('نتائج الفحوصات السابقة (تنزيل)', 'Previous tests (download)'),
                    style: const TextStyle(color: AppColors.text2, fontSize: 12)),
                const SizedBox(height: 8),
                BarChart(
                  labels: [for (var i = 0; i < s.testHistory.length; i++) '${i + 1}'],
                  values: [for (final v in s.testHistory) rateValue(mbpsToBytes(v))],
                  fmt: (v) => '${v.toStringAsFixed(1)} ${s.unit}',
                  height: 110,
                ),
              ],
            ]),
          ),

          // ---------- advisor ----------
          if (advice.isNotEmpty)
            SectionCard(
              title: s.t('مستشار الشبكة', 'Network advisor'),
              icon: Icons.psychology_alt_rounded,
              child: Column(children: [
                for (final a in advice.take(3)) AdviceCard(a),
              ]),
            ),

          TileGrid(children: [
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
              label: s.t('إشارة 5G', '5G signal'),
              value: rsrp5 == 0 ? '—' : '${rsrp5.toStringAsFixed(0)} dBm',
              icon: Icons.five_g_rounded,
              color: q5.color,
              sub: s.ar ? q5.ar : q5.en,
            ),
            StatTile(
              label: s.t('إشارة 4G', '4G signal'),
              value: rsrp4 == 0 ? '—' : '${rsrp4.toStringAsFixed(0)} dBm',
              icon: Icons.signal_cellular_alt_rounded,
              color: q4.color,
              sub: s.ar ? q4.ar : q4.en,
            ),
          ]),
        ],
      ),
    );
  }

  static String _num(double v) => v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  static Widget _unitMenu(AppState s) => PopupMenuButton<String>(
        initialValue: s.unit,
        onSelected: s.setUnit,
        itemBuilder: (_) => [
          for (final u in speedUnits) PopupMenuItem(value: u, child: Text(u)),
        ],
        child: Pill(s.unit, icon: Icons.tune_rounded),
      );

  static Widget _metric(String label, String value, IconData icon, Color color) {
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
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        ),
        Text(label, style: const TextStyle(color: AppColors.text2, fontSize: 12)),
      ]),
    );
  }
}
