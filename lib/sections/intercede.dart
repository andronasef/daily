import 'package:flutter/material.dart';
import '../intercede_content.dart';

/// Section "تشفع": intercession tracker — entities you pray for, their prayers,
/// and a log of every time you prayed.
class IntercedeScreen extends StatefulWidget {
  const IntercedeScreen({super.key});

  @override
  State<IntercedeScreen> createState() => _IntercedeScreenState();
}

class _IntercedeScreenState extends State<IntercedeScreen>
    with SingleTickerProviderStateMixin {
  late Future<List<Entity>> _future;

  /// Listened to so the FAB can mean "add prayer" or "add person" depending on
  /// which tab you are looking at.
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));

  @override
  void initState() {
    super.initState();
    _future = fetchEntities();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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
          IconButton(
            tooltip: 'اتستجابت',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => _AnsweredPage(future: _future)),
            ),
          ),
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'الصلوات'),
            Tab(text: 'الأشخاص'),
          ],
        ),
      ),
      body: FutureBuilder<List<Entity>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return _ErrorRetry(onRetry: _reload);
          final entities = snap.data!;
          return TabBarView(
            controller: _tabs,
            children: [_prayersTab(entities), _entitiesTab(entities)],
          );
        },
      ),
      floatingActionButton: !intercedeCanEdit
          ? null
          : FloatingActionButton(
              onPressed: () => _tabs.index == 0
                  ? _addPrayerAnywhere()
                  : _addEntityDialog(context),
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _refreshable({required Widget child}) => RefreshIndicator(
    onRefresh: () async {
      _reload();
      await _future;
    },
    child: child,
  );

  /// A ListView, not a Center, so pull-to-refresh still works on an empty tab.
  Widget _hint(String text) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      SizedBox(
        height: 160,
        child: Center(child: Text(text, textAlign: TextAlign.center)),
      ),
    ],
  );

  // ---- tab 1: today's checklist ---------------------------------------------

  Widget _prayersTab(List<Entity> entities) {
    final theme = Theme.of(context);
    final items = openPrayers(entities);
    if (items.isEmpty) {
      return _refreshable(
        child: _hint(
          intercedeCanEdit
              ? 'لسه مفيش صلوات. اضغط + علشان تضيف.'
              : 'علشان تضيف، حط الـ Sanity write token في الإعدادات.',
        ),
      );
    }
    final left = items.where((i) => !i.prayer.prayedToday).length;
    return _refreshable(
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                left == 0
                    ? 'خلصت كل صلوات النهاردة ✓'
                    : 'فاضل $left من ${items.length}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }
          final it = items[i - 1];
          final p = it.prayer;
          final done = p.prayedToday;
          final last = p.lastPrayedAt;
          return _PrayerCard(
            title: p.title,
            meta:
                '${it.entity.name} · ${last == null ? 'لسه' : relativeDate(last)}',
            done: done,
            onPray: intercedeCanEdit ? () => _logSingle(p) : null,
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      _PrayerPage(prayer: p, entityName: it.entity.name),
                ),
              );
              _reload();
            },
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

  /// Adding from the prayers tab means picking the person here, since the tab
  /// itself is not scoped to one.
  Future<void> _addPrayerAnywhere() async {
    final entities = await _future;
    if (!mounted) return;
    if (entities.isEmpty) {
      _snack('ضيف شخص الأول من تاب الأشخاص.');
      return;
    }
    final draft = await Navigator.of(context).push<_PrayerDraft>(
      MaterialPageRoute(
        builder: (_) =>
            _PrayerEditorPage(heading: 'صلاة جديدة', pickFrom: entities),
      ),
    );
    if (draft == null || draft.entityId == null) return;
    try {
      await addPrayer(draft.entityId!, draft.text);
      _reload();
    } catch (e) {
      if (mounted) _snack('خطأ: $e');
    }
  }

  // ---- tab 2: the people ----------------------------------------------------

  Widget _entitiesTab(List<Entity> entities) {
    if (entities.isEmpty) {
      return _refreshable(
        child: _hint(
          intercedeCanEdit
              ? 'لسه مضفتش حد. اضغط + علشان تضيف.'
              : 'علشان تضيف، حط الـ Sanity write token في الإعدادات.',
        ),
      );
    }
    return _refreshable(
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
                horizontal: 16,
                vertical: 8,
              ),
              title: Text(
                e.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '$activeCount صلوات شغالة · '
                '${last != null ? 'آخر مرة: ${relativeDate(last)}' : 'لسه معملتش حاجة'}',
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        _EntityPage(entityId: e.id, entityName: e.name),
                  ),
                );
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
                labelText: 'الاسم',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteC,
              decoration: const InputDecoration(
                labelText: 'ملاحظة (اختياري)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (ok != true || nameC.text.trim().isEmpty) return;
    try {
      await addEntity(
        nameC.text.trim(),
        note: noteC.text.trim().isEmpty ? null : noteC.text.trim(),
      );
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
                labelText: 'الاسم',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteC,
              decoration: const InputDecoration(
                labelText: 'ملاحظة',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (ok != true || nameC.text.trim().isEmpty) return;
    try {
      await editEntity(
        entity.id,
        nameC.text.trim(),
        note: noteC.text.trim().isEmpty ? null : noteC.text.trim(),
      );
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
            child: const Text('لأ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('احذف'),
          ),
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
  const _EntityPage({required this.entityId, required this.entityName});
  final String entityId;
  final String entityName;

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
          if (snap.hasError) return _ErrorRetry(onRetry: _reload);
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
                  _PrayerCard(
                    title: p.title,
                    meta:
                        '${p.startedAt != null ? 'من ${_formatShortDate(p.startedAt!)}' : ''}'
                        '${p.lastPrayedAt != null ? ' · آخر مرة: ${relativeDate(p.lastPrayedAt!)}' : ''}',
                    onPray: canEdit ? () => _logSingle(p) : null,
                    onMenu: canEdit ? () => _showPrayerMenu(p) : null,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              _PrayerPage(prayer: p, entityName: entity.name),
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
                                  builder: (_) => _PrayerPage(
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
    final draft = await Navigator.of(context).push<_PrayerDraft>(
      MaterialPageRoute(
        builder: (_) =>
            _PrayerEditorPage(heading: 'إضافة صلاة', initialEntityId: entityId),
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
    final draft = await Navigator.of(context).push<_PrayerDraft>(
      MaterialPageRoute(
        builder: (_) =>
            _PrayerEditorPage(heading: 'تعديل الصلاة', initialText: p.title),
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
          Text(
            entityName,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            header,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
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
                  leading: Icon(
                    Icons.circle,
                    size: 10,
                    color: theme.colorScheme.primary,
                  ),
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
          const Text(
            'ملاحظة (اختياري)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteC,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'اكتب ملاحظة...',
              border: OutlineInputBorder(),
            ),
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

String _formatShortDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

String _formatFullDate(DateTime d) =>
    '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Every answered prayer across all the people, newest first. Reached from the
/// app bar rather than a third tab: you open it to remember, not every day.
class _AnsweredPage extends StatelessWidget {
  const _AnsweredPage({required this.future});
  final Future<List<Entity>> future;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('اتستجابت')),
      body: FutureBuilder<List<Entity>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return const Center(child: Text('تعذر التحميل.'));
          }
          final items = answeredPrayers(snap.data!);
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'لسه مقفلتش أي صلاة. لما تقفل واحدة هتلاقيها هنا.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final it = items[i];
              final p = it.prayer;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${it.entity.name} · ${relativeDate(p.completedAt!)}'
                        ' · ${p.logs.length} مرة',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (p.outcome != null && p.outcome!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(p.outcome!),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// One prayer, in both the flat daily list and a person's page.
///
/// The text owns a full-width row of its own and the actions sit on a second
/// row underneath. A ListTile would centre the button against the text block,
/// so "صليت" drifted up and down with how long the prayer was and the text got
/// squeezed into whatever column the button left behind.
class _PrayerCard extends StatelessWidget {
  const _PrayerCard({
    required this.title,
    required this.meta,
    required this.onTap,
    this.done = false,
    this.onPray,
    this.onMenu,
  });

  final String title;
  final String meta;
  final VoidCallback onTap;
  final bool done;
  final VoidCallback? onPray;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final hasActions = onPray != null || onMenu != null || done;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.35,
                  color: done ? muted : null,
                ),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  meta,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
              if (hasActions) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (done)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'صليت النهاردة',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      )
                    else if (onPray != null)
                      FilledButton.tonal(
                        onPressed: onPray,
                        child: const Text('صليت'),
                      ),
                    const Spacer(),
                    if (onMenu != null)
                      IconButton(
                        onPressed: onMenu,
                        icon: const Icon(Icons.more_horiz),
                        tooltip: 'خيارات',
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A page, not a dialog: prayers are sentences, not labels, and the cramped
/// single-line field made you edit a paragraph through a slot.
class _PrayerEditorPage extends StatefulWidget {
  const _PrayerEditorPage({
    required this.heading,
    this.initialText = '',
    this.pickFrom,
    this.initialEntityId,
  });

  final String heading;
  final String initialText;

  /// When present the editor also asks who the prayer is for.
  final List<Entity>? pickFrom;
  final String? initialEntityId;

  @override
  State<_PrayerEditorPage> createState() => _PrayerEditorPageState();
}

class _PrayerDraft {
  _PrayerDraft(this.text, this.entityId);
  final String text;
  final String? entityId;
}

class _PrayerEditorPageState extends State<_PrayerEditorPage> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initialText,
  );
  late String? _entityId = widget.initialEntityId ?? widget.pickFrom?.first.id;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(_PrayerDraft(text, _entityId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.heading),
        actions: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _c,
            builder: (context, value, _) => TextButton(
              onPressed: value.text.trim().isEmpty ? null : _save,
              child: const Text('حفظ'),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.pickFrom != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: DropdownButtonFormField<String>(
                  initialValue: _entityId,
                  decoration: const InputDecoration(
                    labelText: 'لمين؟',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final e in widget.pickFrom!)
                      DropdownMenuItem(value: e.id, child: Text(e.name)),
                  ],
                  onChanged: (v) => setState(() => _entityId = v ?? _entityId),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: TextField(
                  controller: _c,
                  autofocus: true,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: theme.textTheme.titleMedium?.copyWith(height: 1.6),
                  decoration: InputDecoration(
                    hintText: 'بتصلي لإيه؟',
                    border: InputBorder.none,
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
        FilledButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ],
    ),
  );
}
