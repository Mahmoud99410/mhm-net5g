import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../widgets/common.dart';

class ProtectionScreen extends StatefulWidget {
  const ProtectionScreen({super.key});

  @override
  State<ProtectionScreen> createState() => _ProtectionScreenState();
}

class _ProtectionScreenState extends State<ProtectionScreen> {
  final urlCtrl = TextEditingController();
  List<String> urls = [];
  bool loading = true;
  bool saving = false;
  String? loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = context.read<AppState>();
    final err = await s.loadUrlFilters();
    if (!mounted) return;
    setState(() {
      urls = List.of(s.blockedUrls);
      loadError = err;
      loading = false;
    });
  }

  void _add() {
    final parts = urlCtrl.text
        .split(RegExp(r'[\s,]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    setState(() {
      for (final p in parts) {
        if (!urls.contains(p)) urls.add(p);
      }
      urlCtrl.clear();
    });
  }

  bool _socialOn(String name) => socialSites[name]!.every(urls.contains);

  void _toggleSocial(String name, bool on) {
    setState(() {
      for (final d in socialSites[name]!) {
        if (on) {
          if (!urls.contains(d)) urls.add(d);
        } else {
          urls.remove(d);
        }
      }
    });
  }

  Future<void> _save(AppState s) async {
    setState(() => saving = true);
    final err = await s.saveUrlFilters(urls);
    if (!mounted) return;
    setState(() {
      saving = false;
      if (err == null) urls = List.of(s.blockedUrls);
    });
    toast(context, err ?? s.t('تم حفظ قائمة الحظر في الراوتر ✓', 'Saved to router ✓'),
        error: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (loadError != null)
          NoteBox(
              '${s.t('تعذر قراءة قائمة الحظر من الراوتر', 'Could not read URL filter')}: $loadError',
              color: AppColors.red),
        SectionCard(
          title: s.t('حظر مواقع التواصل الاجتماعي', 'Block social media'),
          icon: Icons.people_alt_rounded,
          child: Column(children: [
            for (final name in socialSites.keys)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _socialOn(name),
                onChanged: (v) => _toggleSocial(name, v),
                title: Text(name),
                subtitle: Text(socialSites[name]!.join(', '),
                    style: const TextStyle(fontSize: 11, color: AppColors.text2)),
              ),
          ]),
        ),
        SectionCard(
          title: s.t('حظر مواقع بالرابط', 'Block websites by URL'),
          icon: Icons.link_off_rounded,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: urlCtrl,
                  textDirection: TextDirection.ltr,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    hintText: 'example.com',
                    labelText: s.t('رابط الموقع', 'Website'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _add, icon: const Icon(Icons.add)),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final u in urls)
                InputChip(
                  label: Text(u),
                  onDeleted: () => setState(() => urls.remove(u)),
                ),
            ]),
            if (urls.isEmpty)
              Text(s.t('لا توجد مواقع محظورة', 'No blocked sites'),
                  style: const TextStyle(color: AppColors.text2)),
          ]),
        ),
        NoteBox(
          s.t(
              'الراوتر يطبق حظر المواقع على كل الأجهزة المتصلة. لمنع جهاز معين (مثل هاتف طفل) من الإنترنت في أوقات محددة استخدم "وقت الإنترنت" أو "حظر" من صفحة الأجهزة.',
              'The router applies URL blocking to all devices. To restrict a single device, use Schedule / Block on the Devices page.'),
          color: AppColors.blue,
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: saving ? null : () => _save(s),
          icon: saving
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_rounded),
          label: Text(s.t('حفظ في الراوتر', 'Save to router')),
        ),
      ],
    );
  }
}
