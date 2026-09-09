import 'package:flutter/material.dart';
import 'package:masroufi/core/l10n/strings.dart';
import 'package:masroufi/core/theme/app_theme.dart';
import 'package:masroufi/core/widgets/design.dart';
import 'package:masroufi/data/database/app_db.dart';

/// Two-step hierarchical category picker (Primary → Subcategory).
///
/// Step 1 lists top-level categories of the active kind with their
/// subcategory counts. Tapping a parent drills into step 2, which lists
/// its subcategories under a `← Parent` header plus a "Use this category"
/// row (transactions may sit on parents too). Childless parents are
/// selected directly from step 1.
///
/// Returns the chosen category id, or null when dismissed. The sheet never
/// shows flat `Parent › Child` duplicates: each level shows its own names.
Future<String?> showCategoryPicker(
  BuildContext context, {
  required String lang,
  required List<Category> visible,
  required Map<String, Category> byId,
  String? selectedId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _PickerSheet(
      lang: lang,
      visible: visible,
      byId: byId,
      selectedId: selectedId,
    ),
  );
}

class _PickerSheet extends StatefulWidget {
  final String lang;
  final List<Category> visible;
  final Map<String, Category> byId;
  final String? selectedId;
  const _PickerSheet({
    required this.lang,
    required this.visible,
    required this.byId,
    required this.selectedId,
  });

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  /// Null = primary step; non-null = subcategory step for that parent id.
  String? parentId;

  List<Category> get _roots {
    final ids = {for (final c in widget.visible) c.id};
    final roots = widget.visible
        .where((c) => c.parentId == null || !ids.contains(c.parentId))
        .toList();
    roots.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return roots;
  }

  List<Category> _childrenOf(String id) {
    final kids = widget.visible.where((c) => c.parentId == id).toList();
    kids.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return kids;
  }

  String _name(Category c) =>
      Strings.categoryName(widget.lang, c.nameKey, c.customName);

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final parent = parentId == null ? null : widget.byId[parentId];
    final kids = parent == null ? const <Category>[] : _childrenOf(parent.id);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (parent == null) ...[
                Text(
                  Strings.get(lang, 'selectCategory'),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final root in _roots) _rootRow(root),
              ] else ...[
                Row(
                  children: [
                    IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .backButtonTooltip,
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(() => parentId = null),
                    ),
                    CategoryAvatar(
                      iconKey: parent.icon,
                      radius: 18,
                      semanticLabel: _name(parent),
                    ),
                    const SizedBox(width: AppSpacing.md2),
                    Expanded(
                      child: Text(
                        _name(parent),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                _useParentRow(parent),
                const Divider(indent: 68),
                for (var i = 0; i < kids.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 68),
                  _childRow(kids[i]),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _rootRow(Category root) {
    final kids = _childrenOf(root.id);
    final selected = widget.selectedId == root.id;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CategoryAvatar(
        iconKey: root.icon,
        radius: 20,
        semanticLabel: _name(root),
      ),
      title: Text(_name(root), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: kids.isEmpty
          ? null
          : Text(
              '${kids.length} ${Strings.get(widget.lang, 'subcategories')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: selected
          ? Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            )
          : kids.isEmpty
          ? null
          : Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      onTap: () {
        if (kids.isEmpty) {
          Navigator.pop(context, root.id);
        } else {
          setState(() => parentId = root.id);
        }
      },
    );
  }

  Widget _useParentRow(Category parent) {
    final selected = widget.selectedId == parent.id;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CategoryAvatar(
        iconKey: parent.icon,
        radius: 20,
        semanticLabel: _name(parent),
      ),
      title: Text(
        Strings.get(widget.lang, 'useThisCategory'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      subtitle: Text(
        _name(parent),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: selected
          ? Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
      onTap: () => Navigator.pop(context, parent.id),
    );
  }

  Widget _childRow(Category child) {
    final selected = widget.selectedId == child.id;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: CategoryAvatar(
        iconKey: child.icon,
        radius: 20,
        semanticLabel: _name(child),
      ),
      title: Text(_name(child), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: selected
          ? Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
      onTap: () => Navigator.pop(context, child.id),
    );
  }
}
