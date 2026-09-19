import 'package:flutter/material.dart';
import '../intercede_content.dart';

/// Section "تشفع": intercession tracker — entities you pray for, their prayers,
/// and a log of every time you prayed.
class IntercedeScreen extends StatefulWidget {
  const IntercedeScreen({super.key});

  @override
  State<IntercedeScreen> createState() => _IntercedeScreenState();
}

class _IntercedeScreenState extends State<IntercedeScreen> {
  late Future<List<Entity>> _future;

  @override
  void initState() {
    super.initState();
    _future = fetchEntities();
  }

  void _reload() => setState(() {
        _future = fetchEntities();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تشفع'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<Entity>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorRetry(onRetry: _reload);
          }
          final entities = snap.data!;
          if (entities.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  intercedeCanEdit
                      ? 'لسه مضفتش حد. اضغط + علشان تضيف.'
                      : 'علشان تضيف، حط الـ Sanity write token في الإعدادات.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              _reload();
              await _future;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entities.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final e = entities[i];
                final activeCount = e.active.length;
                final last = e.lastPrayedAt;
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    title: Text(e.name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      '$activeCount صلوات شغالة · '
                      '${last != null ? 'آخر مرة: ${relativeDate(last)}' : 'لسه معملتش حاجة'}',
                    ),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _EntityPage(entityId: e.id),
                      ));
                      _reload();
                    },
                    onLongPress: intercedeCanEdit
                        ? () => _showEntityOptions(context, e)
                        : null,
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: intercedeCanEdit
          ? FloatingActionButton(
              onPressed: () => _addEntityDialog(context),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  void _showEntityOptions(BuildContext ctx, Entity e) {
    showModalBottomSheet(
      context: ctx,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('تعديل'),
              onTap: () {
                Navigator.pop(ctx);
                _editEntityDialog(ctx, e);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text('حذف',
                  style:
                      TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteEntity(ctx, e);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addEntityDialog(BuildContext ctx) async {
    final nameC = TextEditingController();
    final noteC = TextEditingController();
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('إضافة شخص / موضوع'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameC,
              decoration: const InputDecoration(
                  labelText: 'الاسم', border: OutlineInputBorder()),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteC,
              decoration: const InputDecoration(
                  labelText: 'ملاحظة (اختياري)', border: OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إضافة')),
        ],
      ),
    );
    if (ok != true || nameC.text.trim().isEmpty) return;
    try {
      await addEntity(nameC.text.trim(),
          note: noteC.text.trim().isEmpty ? null : noteC.text.trim());
      _reload();
    } catch (e) {
      if (mounted) _snack('خطأ: $e');
    }
  }

  Future<void> _editEntityDialog(BuildContext ctx, Entity entity) async {
    final nameC = TextEditingController(text: entity.name);
    final noteC = TextEditingController(text: entity.note ?? '');
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('تعديل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameC,
              decoration: const InputDecoration(
                  labelText: 'الاسم', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteC,
              decoration: const InputDecoration(
                  labelText: 'ملاحظة', border: OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || nameC.text.trim().isEmpty) return;
    try {
      await editEntity(entity.id, nameC.text.trim(),
          note: noteC.text.trim().isEmpty ? null : noteC.text.trim());
      _reload();
    } catch (e) {
      if (mounted) _snack('خطأ: $e');
    }
  }

  Future<void> _confirmDeleteEntity(BuildContext ctx, Entity e) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        content: Text('متأكد إنك عايز تحذف "${e.name}" وكل صلواته؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لأ')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('احذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await deleteEntity(e);
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

// ---- entity page ------------------------------------------------------------

class _EntityPage extends StatefulWidget {
  const _EntityPage({required this.entityId});
  final String entityId;

  @override
  State<_EntityPage> createState() => _EntityPageState();
}

class _EntityPageState extends State<_EntityPage> {
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
      appBar: AppBar(title: const Text('...')),
      body: FutureBuilder<List<Entity>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return _ErrorRetry(onRetry: _reload);
          final entity = _find(snap.data!);
          if (entity == null) {
            return const Center(child: Text('الشخص ده اتحذف.'));
          }

          final active = entity.active;
          final done = entity.archived;
          final canEdit = intercedeCanEdit;

          return Scaffold(
            appBar: AppBar(title: Text(entity.name)),
            body: RefreshIndicator(
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
                      child: Text(entity.note!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
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
                    Card(
                      child: ListTile(
                        title: Text(p.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${p.startedAt != null ? 'من ${_formatShortDate(p.startedAt!)}' : ''}'
                          '${p.lastPrayedAt != null ? ' · آخر مرة: ${relativeDate(p.lastPrayedAt!)}' : ''}',
                        ),
                        trailing: canEdit
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FilledButton.tonal(
                                    onPressed: () =>
                                        _logSingle(p),
                                    child: const Text('صليت'),
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (v) =>
                                        _onPrayerAction(v, p),
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                          value: 'edit',
                                          child: Text('تعديل')),
                                      PopupMenuItem(
                                          value: 'complete',
                                          child: Text('إكمال')),
                                      PopupMenuItem(
                                          value: 'delete',
                                          child: Text('حذف')),
                                    ],
                                  ),
                                ],
                              )
                            : null,
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => _PrayerPage(
                                prayer: p, entityName: entity.name),
                          ));
                          _reload();
                        },
                      ),
                    ),
                  if (done.isNotEmpty)
                    ExpansionTile(
                      title: Text('المكتمل (${done.length})'),
                      children: [
                        for (final p in done)
                          Card(
                            child: ListTile(
                              title: Text(p.title),
                              subtitle: p.outcome != null &&
                                      p.outcome!.isNotEmpty
                                  ? Text(p.outcome!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis)
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
                                await Navigator.of(context)
                                    .push(MaterialPageRoute(
                                  builder: (_) => _PrayerPage(
                                      prayer: p,
                                      entityName: entity.name),
                                ));
                                _reload();
                              },
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            floatingActionButton: canEdit
                ? FloatingActionButton(
                    onPressed: () => _addPrayerDialog(entity.id),
                    child: const Icon(Icons.add),
                  )
                : null,
          );
        },
      ),
    );
  }

  Future<void> _logSingle(Prayer p) async {
    final note = await _askNote(context);
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
    final note = await _askNote(context);
    if (note == null) return;
    try {
      await logPrayed(active.map((p) => p.id).toList(),
          note: note.isEmpty ? null : note);
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

  Future<void> _addPrayerDialog(String entityId) async {
    final titleC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إضافة صلاة'),
        content: TextField(
          controller: titleC,
          decoration: const InputDecoration(
              labelText: 'العنوان', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إضافة')),
        ],
      ),
    );
    if (ok != true || titleC.text.trim().isEmpty) return;
    try {
      await addPrayer(entityId, titleC.text.trim());
      _reload();
    } catch (e) {
      if (mounted) _snack('خطأ: $e');
    }
  }

  Future<void> _editPrayerDialog(Prayer p) async {
    final titleC = TextEditingController(text: p.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تعديل الصلاة'),
        content: TextField(
          controller: titleC,
          decoration: const InputDecoration(
              labelText: 'العنوان', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || titleC.text.trim().isEmpty) return;
    try {
      await editPrayer(p.id, titleC.text.trim());
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
              labelText: 'النتيجة (اختياري)', border: OutlineInputBorder()),
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إكمال')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await completePrayer(p.id,
          outcome: outcomeC.text.trim().isEmpty ? null : outcomeC.text.trim());
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
              child: const Text('لأ')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('احذف')),
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

// ---- prayer detail page -----------------------------------------------------

class _PrayerPage extends StatelessWidget {
  const _PrayerPage({required this.prayer, required this.entityName});
  final Prayer prayer;
  final String entityName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logs = prayer.logs;
    final count = logs.length;

    String header = '$count مرة';
    if (prayer.startedAt != null && count > 0) {
      header += ' على مدى ${durationSpan(prayer.startedAt!)}';
    }

    return Scaffold(
      appBar: AppBar(title: Text(prayer.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(entityName,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(header,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          if (prayer.isDone && prayer.outcome != null) ...[
            const SizedBox(height: 8),
            Chip(label: Text('مكتمل: ${prayer.outcome}')),
          ],
          const SizedBox(height: 16),
          if (logs.isEmpty)
            const Center(child: Text('لسه مفيش سجل صلوات.'))
          else
            for (final log in logs)
              Card(
                child: ListTile(
                  leading: Icon(Icons.circle,
                      size: 10, color: theme.colorScheme.primary),
                  title: Text(_formatFullDate(log.prayedAt)),
                  subtitle: log.note != null && log.note!.isNotEmpty
                      ? Text(log.note!)
                      : null,
                ),
              ),
        ],
      ),
    );
  }
}

// ---- shared helpers ---------------------------------------------------------

Future<String?> _askNote(BuildContext context) async {
  final noteC = TextEditingController();
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
        top: 24,
        left: 24,
        right: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('ملاحظة (اختياري)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: noteC,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(
                hintText: 'اكتب ملاحظة...', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تم'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
  if (ok != true) return null;
  return noteC.text.trim();
}

String _formatShortDate(DateTime d) =>
    '${d.day}/${d.month}/${d.year}';

String _formatFullDate(DateTime d) =>
    '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('تعذر التحميل. اتأكد من الاتصال بالإنترنت.'),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
}
