import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/xml_utils.dart';
import 'common.dart';

class AdviceCard extends StatelessWidget {
  final Advice a;
  const AdviceCard(this.a, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final (color, icon) = switch (a.level) {
      AdviceLevel.good => (AppColors.green, Icons.verified_rounded),
      AdviceLevel.info => (AppColors.blue, Icons.lightbulb_rounded),
      AdviceLevel.warn => (AppColors.amber, Icons.warning_amber_rounded),
      AdviceLevel.bad => (AppColors.red, Icons.error_outline_rounded),
    };
    String? actionLabel;
    switch (a.action) {
      case AdviceAction.autoMode:
        actionLabel = s.t('ارجع إلى تلقائي', 'Set Auto');
        break;
      case AdviceAction.unlock:
        actionLabel = s.t('فك القفل', 'Unlock bands');
        break;
      case AdviceAction.scan:
        actionLabel = s.t('كيف؟', 'How?');
        break;
      case AdviceAction.none:
        break;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: BorderDirectional(start: BorderSide(color: color, width: 4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.title, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 4),
            Text(a.body, style: const TextStyle(fontSize: 13, height: 1.5)),
            if (actionLabel != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => _act(context, s),
                  child: Text(actionLabel),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _act(BuildContext context, AppState s) async {
    String? err;
    switch (a.action) {
      case AdviceAction.autoMode:
        err = await s.applyNetMode('00', null);
        break;
      case AdviceAction.unlock:
        err = await s.applyNetMode(s.netMode.s('NetworkMode', '00'), []);
        break;
      case AdviceAction.scan:
        toast(
            context,
            s.t('افتح "الإشارة والترددات" ثم "البحث عن أقوى تردد"',
                'Open Signal & Bands → Find the best band'));
        return;
      case AdviceAction.none:
        return;
    }
    if (context.mounted) {
      toast(context, err ?? s.t('تم التطبيق ✓', 'Applied ✓'), error: err != null);
    }
  }
}
