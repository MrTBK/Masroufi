import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/icons/category_icons.dart';
import '../../core/l10n/strings.dart';
import '../../core/widgets/design.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database/app_db.dart';
import '../../data/database/category_hierarchy.dart';
import '../../data/repositories/categories_repo.dart';

/// Grouped settings-style list: parent header rows (avatar + name + child
/// count) expand to indented children. Expense and income live in separate
/// sections; dashboard order elsewhere is untouched.
class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final repo = ref.watch(categoriesRepoProvider);
    return Scaffold(
      appBar: AppBar(title: Text(Strings.get(lang, 'category'))),
      floatingActionButton: FloatingActionButton(
        heroTag: null,
        tooltip: Strings.get(lang, 'newCategory'),
        onPressed: () => _dialog(context, ref, null),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Category>>(
        stream: repo.watch(includeArchived: true),
        builder: (context, snap) {
          if (!snap.hasData) return const LoadingView();
          final cats = snap.data!;
          final byId = {for (final c in cats) c.id: c};
          final expense = cats.where((c) => c.kind != 'income').toList();
          final income = cats.where((c) => c.kind == 'income').toList();
          return ListView(
            children: [
              _sectionHeader(context, lang, 'expenseCategories'),
              for (final node in _forest(expense))
                _node(context, ref, lang, repo, byId, node),
              _sectionHeader(context, lang, 'incomeCategories'),
              for (final node in _forest(income))
                _node(context, ref, lang, repo, byId, node),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }

  /// In-memory forest: top-level first, orphans surface as roots so
  /// nothing vanishes when a parent is archived/filtered away.
  List<({Category parent, List<Category> children})> _forest(
    List<Category> cats,
  ) {
    final ids = {for (final c in cats) c.id};
    final kids = <String, List<Category>>{};
    for (final c in cats) {
      if (c.parentId != null) {
        (kids[c.parentId!] ??= []).add(c);
      }
    }
    return [
      for (final c in cats)
        if (c.parentId == null || !ids.contains(c.parentId))
          (parent: c, children: kids[c.id] ?? const []),
    ];
  }

  Widget _node(
    BuildContext context,
    WidgetRef ref,
    String lang,
    CategoriesRepo repo,
    Map<String, Category> byId,
    ({Category parent, List<Category> children}) node,
  ) {
    final p = node.parent;
    if (node.children.isEmpty) {
      return _row(context, ref, lang, repo, byId, p);
    }
    final visibleKids = node.children;
    return ExpansionTile(
      leading: CategoryAvatar(
        iconKey: p.icon,
        radius: 18,
        semanticLabel: Strings.categoryName(lang, p.nameKey, p.customName),
      ),
      title: Text(Strings.categoryName(lang, p.nameKey, p.customName)),
      subtitle: Text(
        '${visibleKids.length} ${Strings.get(lang, 'subcategories')}',
      ),
      trailing: _menu(context, ref, lang, repo, p),
      childrenPadding: const EdgeInsetsDirectional.only(start: 24),
      children: [
        for (final c in visibleKids) _row(context, ref, lang, repo, byId, c),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String lang, String key) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        Strings.get(lang, key),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    String lang,
    CategoriesRepo repo,
    Map<String, Category> byId,
    Category c,
  ) {
    final name = CategoryHierarchy.displayName(lang, c, byId);
    return CategoryListTile(
      iconKey: c.icon,
      title: name,
      subtitle: c.isArchived ? Strings.get(lang, 'archived') : null,
      onTap: () => _dialog(context, ref, c),
      trailing: _menu(context, ref, lang, repo, c),
    );
  }

  Widget _menu(
    BuildContext context,
    WidgetRef ref,
    String lang,
    CategoriesRepo repo,
    Category c,
  ) {
    final isDefault = c.customName == null && c.nameKey != null;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: Strings.get(lang, 'more'),
      onSelected: (v) async {
        if (v == 'archive') {
          await repo.setArchived(c.id, !c.isArchived);
          bumpRefresh(ref);
        } else if (v == 'delete') {
          try {
            await repo.delete(c.id);
            bumpRefresh(ref);
          } on StateError {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(Strings.get(lang, 'hasChildrenDeleteBlocked')),
                ),
              );
            }
          }
        } else if (v == 'up') {
          await repo.move(c.id, -1);
          bumpRefresh(ref);
        } else if (v == 'down') {
          await repo.move(c.id, 1);
          bumpRefresh(ref);
        } else {
          await _dialog(context, ref, c);
        }
      },
      itemBuilder: (c2) => [
        PopupMenuItem(value: 'rename', child: Text(Strings.get(lang, 'edit'))),
        PopupMenuItem(
          value: 'icon',
          child: Text(Strings.get(lang, 'pickIcon')),
        ),
        PopupMenuItem(value: 'up', child: Text(Strings.get(lang, 'moveUp'))),
        PopupMenuItem(
          value: 'down',
          child: Text(Strings.get(lang, 'moveDown')),
        ),
        PopupMenuItem(
          value: 'archive',
          child: Text(
            Strings.get(lang, c.isArchived ? 'unarchive' : 'archive'),
          ),
        ),
        if (!isDefault)
          PopupMenuItem(
            value: 'delete',
            child: Text(Strings.get(lang, 'delete')),
          ),
      ],
    );
  }

  Future<void> _dialog(BuildContext context, WidgetRef ref, Category? c) async {
    final lang = ref.read(languageProvider);
    final repo = ref.read(categoriesRepoProvider);
    final ctl = TextEditingController(text: c?.customName ?? '');
    var icon = c?.icon ?? 'other';
    var kind = c?.kind ?? 'expense';
    var parentId = c?.parentId;
    final isDefault = c != null && c.customName == null && c.nameKey != null;
    if (!context.mounted) return;
    // Top-level candidates for the parent dropdown (same kind section).
    final allCats = await repo.roots(includeArchived: false);
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) {
          final tops = allCats
              .where((t) => t.kind == kind && t.id != c?.id)
              .toList();
          if (parentId != null && tops.every((t) => t.id != parentId)) {
            parentId = null;
          }
          return AlertDialog(
            title: Text(Strings.get(lang, c == null ? 'newCategory' : 'edit')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c == null) ...[
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'expense',
                          label: Text(Strings.get(lang, 'expense')),
                        ),
                        ButtonSegment(
                          value: 'income',
                          label: Text(Strings.get(lang, 'income')),
                        ),
                      ],
                      selected: {kind},
                      onSelectionChanged: (s) => setS(() {
                        kind = s.first;
                        parentId = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Any category can be renamed (defaults gain a customName
                  // override while keeping their nameKey identity). Only
                  // custom categories can change parent: default parents are
                  // system-managed (taxonomy upgrades would revert moves).
                  TextField(
                    controller: ctl,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: Strings.get(lang, 'categoryName'),
                      hintText: isDefault
                          ? Strings.categoryName(lang, c.nameKey, null)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!isDefault) ...[
                    DropdownButtonFormField<String?>(
                      initialValue: parentId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: Strings.get(lang, 'parentCategory'),
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(Strings.get(lang, 'noParent')),
                        ),
                        for (final t in tops)
                          DropdownMenuItem<String?>(
                            value: t.id,
                            child: Text(
                              Strings.categoryName(
                                lang,
                                t.nameKey,
                                t.customName,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (v) => setS(() => parentId = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    Strings.get(lang, 'pickIcon'),
                    style: Theme.of(d).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  IconPickerGrid(
                    keys: CategoryIcons.all,
                    selected: icon,
                    onSelected: (k) => setS(() => icon = k),
                  ),
                ],
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
                  if (c == null) {
                    if (name.isEmpty) return;
                    await repo.create(
                      name,
                      icon: icon,
                      kind: kind,
                      parentId: parentId,
                    );
                  } else {
                    if (name.isNotEmpty) await repo.rename(c.id, name);
                    await repo.setIcon(c.id, icon);
                    if (!isDefault) await repo.setParent(c.id, parentId);
                  }
                  bumpRefresh(ref);
                  if (d.mounted) Navigator.pop(d);
                },
                child: Text(Strings.get(lang, 'save')),
              ),
            ],
          );
        },
      ),
    );
  }
}
