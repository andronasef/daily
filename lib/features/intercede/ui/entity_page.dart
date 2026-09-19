import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'intercede_screen.dart';
import 'prayer_page.dart';
import 'widgets/prayer_card.dart';
import 'widgets/prayer_editor_page.dart';

class EntityPage extends StatefulWidget {
  const EntityPage({
    super.key,
    required this.entityId,
    required this.entityName,
  });

  final String entityId;
  final String entityName;

  @override
  State<EntityPage> createState() => _EntityPageState();
}

class _EntityPageState extends State<EntityPage> {
  late Future<List<Entity>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchEntities();
  }

  void _reload() => setState(() {
    _future = fetchEntities();
  });

  Entity? _find(List<Entity> all) {
    for (final e in all) {
      if (e.id == widget.entityId) return e;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.entityName)),
      floatingActionButton: intercedeCanEdit
          ? FloatingActionButton(
              onPressed: () => _addPrayerDialog(widget.entityId),
              child: const Icon(Icons.add),
            )
          : null,
      body: FutureBuilder<List<Entity>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return ErrorRetry(onRetry: _reload);
          final entity = _find(snap.data!);
          if (entity == null) {
            return const Center(child: Text('الشخص ده اتحذف.'));
          }

          final active = entity.active;
          final done = entity.archived;
          final canEdit = intercedeCanEdit;

          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (entity.note != null && entity.note!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      entity.note!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (canEdit && active.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: FilledButton.icon(
                      onPressed: () => _logAll(active),
                      icon: const Icon(Icons.favorite),
                      label: const Text('صليت لكلهم'),
                    ),
                  ),
                if (active.isEmpty && done.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        canEdit
                            ? 'لسه مضفتش صلوات. اضغط + علشان تضيف.'
                            : 'علشان تضيف، حط الـ Sanity write token في الإعدادات.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                for (final p in active)
                  PrayerCard(
                    title: p.title,
                    meta:
                        '${p.startedAt != null ? 'من ${formatShortDate(p.startedAt!)}' : ''}'
                        '${p.lastPrayedAt != null ? ' · آخر مرة: ${relativeDate(p.lastPrayedAt!)}' : ''}',
                    onPray: canEdit ? () => _logSingle(p) : null,
                    onMenu: canEdit ? () => _showPrayerMenu(p) : null,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              PrayerPage(prayer: p, entityName: entity.name),
                        ),
                      );
                      _reload();
                    },
                  ),
                if (done.isNotEmpty)
                  ExpansionTile(
                    title: Text('المكتمل (${done.length})'),
                    children: [
                      for (final p in done)
                        Card(
                          child: ListTile(
                            title: Text(p.title),
                            subtitle: p.outcome != null && p.outcome!.isNotEmpty
                                ? Text(
                                    p.outcome!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                            trailing: canEdit
                                ? TextButton(
                                    onPressed: () async {
                                      await reopenPrayer(p.id);
                                      _reload();
                                    },
                                    child: const Text('رجّعها'),
                                  )
                                : null,
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PrayerPage(
                                    prayer: p,
                                    entityName: entity.name,
                                  ),
                                ),
                              );
                              _reload();
                            },
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _logSingle(Prayer p) async {
    final note = await askNote(context);
    if (note == null) return;
    try {
      await logPrayed([p.id], note: note.isEmpty ? null : note);
      _reload();
      if (mounted) _snack('تم ✓');
    } catch (e) {
      if (mounted) _snack('خطأ: $e');
    }
  }

  Future<void> _logAll(List<Prayer> active) async {
    final note = await askNote(context);
    if (note == null) return;
    try {
      await logPrayed(
        active.map((p) => p.id).toList(),
        note: note.isEmpty ? null : note,
      );
      _reload();
      if (mounted) _snack('تم ✓');
    } catch (e) {
      if (mounted) _snack('خطأ: $e');
    }
  }

  void _onPrayerAction(String action, Prayer p) {
    switch (action) {
      case 'edit':
        _editPrayerDialog(p);
      case 'complete':
        _completePrayerDialog(p);
      case 'delete':
        _deletePrayerConfirm(p);
    }
  }

  void _showPrayerMenu(Prayer p) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('تعديل'),
              onTap: () {
                Navigator.pop(ctx);
                _onPrayerAction('edit', p);
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('إكمال'),
              onTap: () {
                Navigator.pop(ctx);
                _onPrayerAction('complete', p);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                'حذف',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _onPrayerAction('delete', p);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPrayerDialog(String entityId) async {
    final draft = await Navigator.of(context).push<PrayerDraft>(
      MaterialPageRoute(
        builder: (_) =>
            PrayerEditorPage(heading: 'إضافة صلاة', initialEntityId: entityId),
      ),
    );
    if (draft == null) return;
    try {
      await addPrayer(entityId, draft.text);
      _reload();
    } catch (e) {
      if (mounted) _snack('خطأ: $e');
    }
  }

  Future<void> _editPrayerDialog(Prayer p) async {
    final draft = await Navigator.of(context).push<PrayerDraft>(
      MaterialPageRoute(
        builder: (_) =>
            PrayerEditorPage(heading: 'تعديل الصلاة', initialText: p.title),
      ),
    );
    if (draft == null) return;
    try {
      await editPrayer(p.id, draft.text);
      _reload();
    } catch (e) {
      if (mounted) _snack('خطأ: $e');
    }
  }

  Future<void> _completePrayerDialog(Prayer p) async {
    final outcomeC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('اتستجابت؟ إيه اللي حصل؟'),
        content: TextField(
          controller: outcomeC,
          decoration: const InputDecoration(
            labelText: 'النتيجة (اختياري)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إكمال'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await completePrayer(
        p.id,
        outcome: outcomeC.text.trim().isEmpty ? null : outcomeC.text.trim(),
      );
      _reload();
    } catch (e) {
      if (mounted) _snack('خطأ: $e');
    }
  }

  Future<void> _deletePrayerConfirm(Prayer p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text('متأكد إنك عايز تحذف "${p.title}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لأ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('احذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await deletePrayer(p.id);
      _reload();
    } catch (e) {
      if (mounted) _snack('خطأ: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
