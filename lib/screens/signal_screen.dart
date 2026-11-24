import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/xml_utils.dart';
import '../widgets/advice_card.dart';
import '../widgets/common.dart';

class SignalScreen extends StatefulWidget {
  const SignalScreen({super.key});

  @override
  State<SignalScreen> createState() => _SignalScreenState();
}

class _SignalScreenState extends State<SignalScreen> {
  String? mode;
  Set<int>? bands;
  Set<int> scanBands = {1, 3, 7, 8, 20};
  bool scanSpeed = true;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final sig = s.signal;
    final curMode = s.netMode.s('NetworkMode', '00');
    mode ??= curMode;
    bands ??= s.lockedLteBands.toSet();
    final supported = s.supportedLteBands;
    scanBands = scanBands.where(supported.contains).toSet();
    if (scanBands.isEmpty) scanBands = supported.take(5).toSet();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---------- 4G ----------
        SectionCard(
          title: s.t('إشارة الفور جي (LTE)', '4G LTE signal'),
          icon: Icons.signal_cellular_alt_rounded,
          trailing: _bandChip(_carrierText(s, false)),
          child: sig.s('rsrp').isEmpty
              ? Text(s.t('لا توجد إشارة 4G حالياً', 'No 4G signal'),
                  style: const TextStyle(color: AppColors.text2))
              : Column(children: [
                  Meter(
                      label: s.t('قوة الإشارة RSRP', 'RSRP'),
                      value: sig.d('rsrp'),
                      min: -130,
                      max: -60,
                      unit: 'dBm',
                      color: rsrpQuality(sig.d('rsrp')).color),
                  Meter(
                      label: s.t('نقاء الإشارة SINR', 'SINR'),
                      value: sig.d('sinr'),
                      min: -10,
                      max: 30,
                      unit: 'dB',
                      color: sinrQuality(sig.d('sinr')).color),
                  Meter(
                      label: s.t('جودة الإشارة RSRQ', 'RSRQ'),
                      value: sig.d('rsrq'),
                      min: -20,
                      max: -3,
                      unit: 'dB',
                      color: AppColors.blue),
                  const Divider(height: 24),
                  InfoRow('RSSI', sig.s('rssi')),
                  InfoRow('PCI', sig.s('pci')),
                  InfoRow('Cell ID', sig.s('cell_id')),
                  InfoRow('EARFCN', sig.s('earfcn')),
                  InfoRow(s.t('عرض النطاق', 'Bandwidth'),
                      '${sig.s('dlbandwidth')} / ${sig.s('ulbandwidth')}'),
                ]),
        ),

        // ---------- 5G ----------
        SectionCard(
          title: s.t('إشارة الفايف جي (5G NR)', '5G NR signal'),
          icon: Icons.five_g_rounded,
          trailing: _bandChip(_carrierText(s, true)),
          child: sig.s('nrrsrp').isEmpty
              ? Text(
                  s.t('لا توجد إشارة 5G حالياً — الراوتر يعمل على 4G',
                      'No 5G signal right now — running on 4G'),
                  style: const TextStyle(color: AppColors.text2))
              : Column(children: [
                  Meter(
                      label: s.t('قوة الإشارة RSRP', 'RSRP'),
                      value: sig.d('nrrsrp'),
                      min: -130,
                      max: -60,
                      unit: 'dBm',
                      color: rsrpQuality(sig.d('nrrsrp')).color),
                  Meter(
                      label: s.t('نقاء الإشارة SINR', 'SINR'),
                      value: sig.d('nrsinr'),
                      min: -10,
                      max: 30,
                      unit: 'dB',
                      color: sinrQuality(sig.d('nrsinr')).color),
                  Meter(
                      label: s.t('جودة الإشارة RSRQ', 'RSRQ'),
                      value: sig.d('nrrsrq'),
                      min: -20,
                      max: -3,
                      unit: 'dB',
                      color: AppColors.blue),
                  const Divider(height: 24),
                  InfoRow('NR-ARFCN', sig.s('nrearfcn')),
                  InfoRow(s.t('عرض النطاق', 'Bandwidth'),
                      '${sig.s('nrdlbandwidth')} / ${sig.s('nrulbandwidth')}'),
                ]),
        ),

        // ---------- trends ----------
        SectionCard(
          title: s.t('تغيّر الإشارة مع الوقت', 'Signal over time'),
          icon: Icons.show_chart_rounded,
          child: Column(children: [
            TrendChart(
              unit: 'dBm',
              series: [
                TrendSeries('4G RSRP', s.rsrpHistory, AppColors.amber),
                TrendSeries('5G RSRP', s.nrRsrpHistory, AppColors.cyan),
              ],
            ),
            const SizedBox(height: 16),
            TrendChart(
              unit: 'dB',
              height: 110,
              series: [
                TrendSeries('4G SINR', s.sinrHistory, AppColors.purple),
                TrendSeries('5G SINR', s.nrSinrHistory, AppColors.green),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              s.t('حرّك الراوتر ببطء في الغرفة وراقب الخطوط: المكان الذي ترتفع فيه الخطوط هو الأفضل.',
                  'Move the router slowly and watch: where lines rise is the best spot.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.text2, fontSize: 12),
            ),
          ]),
        ),

        // ---------- advisor ----------
        SectionCard(
          title: s.t('مستشار الإشارة — اقتراحات لك', 'Signal advisor'),
          icon: Icons.psychology_alt_rounded,
          child: Column(children: [
            Row(children: [
              Expanded(
                child: StatTile(
                  label: s.t('القدرة المتوقعة من البرج', 'Estimated capacity'),
                  value: '${s.capacityMbps.toStringAsFixed(0)} Mbps',
                  icon: Icons.insights_rounded,
                  color: AppColors.green,
                  sub: s.t('حسب عرض النطاق ونقاء الإشارة', 'from bandwidth + SINR'),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            for (final a in s.advice) AdviceCard(a),
          ]),
        ),

        // ---------- backup ----------
        SectionCard(
          title: s.t('حفظ الإعدادات الحالية', 'Save current settings'),
          icon: Icons.backup_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
              s.snapshot == null
                  ? s.t('احفظ إعدادات الراوتر الحالية (نوع الشبكة، الباندات، الواي فاي) قبل أي تجربة، لترجع لها بضغطة واحدة.',
                      'Save current router settings before experimenting; restore with one tap.')
                  : s.t('آخر نسخة محفوظة: ${s.snapshot!['at']} — الوضع ${s.modeLabel('${s.snapshot!['NetworkMode']}')}',
                      'Last backup: ${s.snapshot!['at']}'),
              style: const TextStyle(color: AppColors.text2, height: 1.5),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: busy
                      ? null
                      : () async {
                          final err = await s.saveSnapshot();
                          if (context.mounted) {
                            toast(context, err ?? s.t('تم حفظ النسخة ✓', 'Saved ✓'),
                                error: err != null);
                          }
                        },
                  icon: const Icon(Icons.save_rounded),
                  label: Text(s.t('حفظ', 'Save')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy || s.snapshot == null
                      ? null
                      : () async {
                          setState(() => busy = true);
                          final err = await s.restoreSnapshot();
                          if (!context.mounted) return;
                          setState(() {
                            busy = false;
                            mode = null;
                            bands = null;
                          });
                          toast(context, err ?? s.t('تم الاسترجاع ✓', 'Restored ✓'),
                              error: err != null);
                        },
                  icon: const Icon(Icons.settings_backup_restore_rounded),
                  label: Text(s.t('استرجاع', 'Restore')),
                ),
              ),
            ]),
          ]),
        ),

        // ---------- network mode ----------
        SectionCard(
          title: s.t('نوع الشبكة (4G / 5G)', 'Network mode (4G / 5G)'),
          icon: Icons.settings_input_antenna_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in s.availableModes)
                ChoiceChip(
                  label: Text(s.modeLabel(m)),
                  selected: mode == m,
                  onSelected: (_) => setState(() => mode = m),
                ),
            ]),
            const SizedBox(height: 10),
            if (mode == '08')
              NoteBox(s.t(
                  'وضع "5G فقط" يحتاج شبكة 5G SA من زين. إذا انقطع الإنترنت ارجع للوضع التلقائي.',
                  '"5G only" needs a 5G SA network. If internet drops, go back to Auto.')),
            FilledButton.icon(
              onPressed: busy || mode == curMode ? null : () => _apply(s, mode!, null),
              icon: const Icon(Icons.check_rounded),
              label: Text(s.t('تطبيق نوع الشبكة', 'Apply mode')),
            ),
          ]),
        ),

        // ---------- band lock ----------
        SectionCard(
          title: s.t('قفل باندات الفور جي', 'Lock 4G bands'),
          icon: Icons.lock_outline_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            NoteBox(
              s.t(
                  'اختر باند أو أكثر ليتصل بها الراوتر فقط. بدون اختيار = كل الباندات (تلقائي). أجهزة 5G CPE من هواوي لا تسمح بقفل باندات الـ 5G، لذلك الاختيار هنا لباندات 4G.',
                  'Pick bands to lock to. None selected = all bands (auto). Huawei 5G CPEs do not allow locking 5G bands.'),
              color: AppColors.blue,
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in supported)
                FilterChip(
                  label: Text('B$b${_bandHint(b)}'),
                  selected: bands!.contains(b),
                  onSelected: (v) => setState(() => v ? bands!.add(b) : bands!.remove(b)),
                ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () {
                          setState(() => bands = {});
                          _apply(s, curMode, []);
                        },
                  child: Text(s.t('كل الباندات (تلقائي)', 'All bands (auto)')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : () => _apply(s, curMode, bands!.toList()),
                  child: Text(s.t('قفل الباندات المختارة', 'Lock selected')),
                ),
              ),
            ]),
          ]),
        ),

        // ---------- best band finder ----------
        SectionCard(
          title: s.t('البحث عن أقوى تردد تلقائياً', 'Find the best band'),
          icon: Icons.auto_awesome_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            NoteBox(s.t(
                'التطبيق يجرب كل باند لوحده، يقيس الإشارة (والسرعة إذا فعّلتها)، ثم يرجع إعداداتك الأصلية ويعرض الأفضل. الإنترنت سينقطع لثوانٍ عند كل تجربة. المدة تقريباً 30–45 ثانية لكل باند.',
                'Each band is tested alone (signal + optional speed), then your settings are restored. Internet drops briefly per band.')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in supported)
                FilterChip(
                  label: Text('B$b'),
                  selected: scanBands.contains(b),
                  onSelected: s.scanning
                      ? null
                      : (v) => setState(() => v ? scanBands.add(b) : scanBands.remove(b)),
                ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: scanSpeed,
              onChanged: s.scanning ? null : (v) => setState(() => scanSpeed = v),
              title: Text(s.t('قياس السرعة أيضاً (أدق)', 'Also measure speed (more accurate)')),
            ),
            if (s.scanning) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(s.scanStatus, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: s.stopScan, child: Text(s.t('إيقاف', 'Stop'))),
            ] else
              FilledButton.icon(
                onPressed: scanBands.isEmpty
                    ? null
                    : () async {
                        final ok = await confirm(
                            context,
                            s.t('بدء الفحص؟', 'Start scan?'),
                            s.t('سينقطع الإنترنت لفترات قصيرة أثناء الفحص.',
                                'Internet will drop briefly during the scan.'));
                        if (ok) {
                          final list = scanBands.toList()..sort();
                          s.scanBands(list, withSpeed: scanSpeed);
                        }
                      },
                icon: const Icon(Icons.radar_rounded),
                label: Text(s.t('ابدأ البحث', 'Start')),
              ),
            if (s.scanResults.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (var i = 0; i < s.scanResults.length; i++)
                _resultTile(s, s.scanResults[i], i == 0 && !s.scanning),
            ],
          ]),
        ),

        // ---------- raw ----------
        SectionCard(
          title: s.t('كل قيم الإشارة', 'All signal values'),
          icon: Icons.list_alt_rounded,
          child: Column(children: [
            for (final e in sig.entries)
              if (e.value is String && (e.value as String).isNotEmpty) InfoRow(e.key, e.value),
          ]),
        ),
      ],
    );
  }

  String? _carrierText(AppState s, bool nr) {
    final l = s.carriers.where((c) => c.isNr == nr).toList();
    if (l.isEmpty) return null;
    return l
        .map((c) => '${c.label}${c.mhz > 0 ? ' · ${c.mhz.toStringAsFixed(0)}MHz' : ''}')
        .join(' + ');
  }

  String _bandHint(int b) {
    const m = {
      1: ' 2100',
      3: ' 1800',
      7: ' 2600',
      8: ' 900',
      20: ' 800',
      28: ' 700',
      38: ' 2600T',
      40: ' 2300',
      41: ' 2500',
      42: ' 3500',
    };
    return m[b] ?? '';
  }

  Widget _bandChip(String? text) => text == null
      ? const SizedBox.shrink()
      : Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.cyan.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w700)),
        );

  Widget _resultTile(AppState s, BandScanResult r, bool best) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: best ? AppColors.green.withValues(alpha: 0.12) : AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: best ? AppColors.green : AppColors.border),
      ),
      child: Row(children: [
        if (best) const Icon(Icons.emoji_events_rounded, color: AppColors.green),
        if (best) const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('B${r.band}${_bandHint(r.band)}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text(
              r.ok
                  ? 'RSRP ${r.rsrp.toStringAsFixed(0)} · SINR ${r.sinr.toStringAsFixed(0)}${r.mbps > 0 ? ' · ${r.mbps.toStringAsFixed(1)} Mbps' : ''}'
                  : s.t('لا توجد تغطية على هذا الباند', 'No coverage on this band'),
              style: const TextStyle(color: AppColors.text2, fontSize: 12),
            ),
          ]),
        ),
        if (r.ok)
          TextButton(
            onPressed: busy
                ? null
                : () => _apply(s, s.netMode.s('NetworkMode', '00'), [r.band]),
            child: Text(s.t('اعتمد', 'Use')),
          ),
      ]),
    );
  }

  Future<void> _apply(AppState s, String m, List<int>? b) async {
    setState(() => busy = true);
    final err = await s.applyNetMode(m, b);
    if (!mounted) return;
    setState(() {
      busy = false;
      if (err == null) {
        mode = null;
        bands = null;
      }
    });
    toast(context, err ?? s.t('تم التطبيق ✓ — قد ينقطع الإنترنت لثوانٍ', 'Applied ✓'),
        error: err != null);
  }
}
