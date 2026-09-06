import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/l10n/strings.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final repo = ref.watch(categoriesRepoProvider);
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'category'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _dialog(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Category>>(
        stream: repo.watch(includeArchived: true),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final cats = snap.data!;
          return ListView.builder(
            itemCount: cats.length,
            itemBuilder: (context, i) {
              final c = cats[i];
              return ListTile(
                leading: Icon(appIcon(c.icon)),
                title: Text(
                  Strings.categoryName(lang, c.nameKey, c.customName),
                ),
                subtitle: c.isArchived
                    ? Text(Strings.get(lang, 'archived'))
                    : null,
                onTap: c.customName == null && c.nameKey != null
                    ? null
                    : () => _dialog(context, ref, c),
                trailing: IconButton(
                  icon: Icon(c.isArchived ? Icons.unarchive : Icons.archive),
                  onPressed: () async {
                    await repo.setArchived(c.id, !c.isArchived);
                    bumpRefresh(ref);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _dialog(BuildContext context, WidgetRef ref, Category? c) async {
    final lang = ref.read(languageProvider);
    final repo = ref.read(categoriesRepoProvider);
    final ctl = TextEditingController(text: c?.customName ?? '');
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(Strings.get(lang, 'newCategory')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: Strings.get(lang, 'categoryName'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: Text(Strings.get(lang, 'cancel')),
          ),
          FilledButton(
            onPressed: () async {
              final name = ctl.text.trim();
              if (name.isEmpty) return;
              if (c == null) {
                await repo.create(name);
              } else {
                await repo.rename(c.id, name);
              }
              bumpRefresh(ref);
              if (d.mounted) Navigator.pop(d);
            },
            child: Text(Strings.get(lang, 'save')),
          ),
        ],
      ),
    );
  }
}
