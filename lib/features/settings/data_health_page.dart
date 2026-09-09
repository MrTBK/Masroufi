import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/l10n/strings.dart';
import '../../core/safety/data_health.dart';
import '../../core/widgets/widgets.dart';

/// Data-health tools (Track 5): scans the no-FK plain-text refs for
/// dangling ids and offers safe repair. Repair only nulls nullable
/// category/parent refs (uncategorized); it never deletes any row.
class DataHealthPage extends ConsumerStatefulWidget {
  const DataHealthPage({super.key});
  @override
  ConsumerState<DataHealthPage> createState() => _DataHealthPageState();
}

class _DataHealthPageState extends ConsumerState<DataHealthPage> {
  List<HealthIssue>? issues;
  bool busy = false;
  String? msg;

  Future<void> _scan() async {
    setState(() {
      busy = true;
      msg = null;
    });
    try {
      issues = await DataHealth.scan(ref.read(appDbProvider));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _repair() async {
    setState(() => busy = true);
    try {
      final n = await DataHealth.repair(ref.read(appDbProvider));
      issues = await DataHealth.scan(ref.read(appDbProvider));
      if (mounted) setState(() => msg = '$n');
      bumpRefresh(ref);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(languageProvider);
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'dataHealth'))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          FilledButton(
            onPressed: busy ? null : _scan,
            child: Text(Strings.get(lang, 'dataHealth')),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (issues != null)
            Text(
              issues!.isEmpty
                  ? Strings.get(lang, 'dataHealthOk')
                  : issues!.map((e) => e.toString()).take(20).join('\n'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (issues != null && issues!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: busy ? null : _repair,
              child: Text(Strings.get(lang, 'dataHealthFix')),
            ),
          ],
          if (busy) ...[
            const SizedBox(height: AppSpacing.md),
            const LoadingView(),
          ],
          if (msg != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(msg!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
