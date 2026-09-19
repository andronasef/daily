import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'answered_page.dart';
import 'entity_page.dart';
import 'prayer_page.dart';
import 'widgets/prayer_card.dart';
import 'widgets/prayer_editor_page.dart';

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
              MaterialPageRoute(builder: (_) => AnsweredPage(future: _future)),
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
          if (snap.hasError) return ErrorRetry(onRetry: _reload);
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
          return PrayerCard(
            title: p.title,
            meta:
                '${it.entity.name} · ${last == null ? 'لسه' : relativeDate(last)}',
            done: done,
            onPray: intercedeCanEdit ? () => _logSingle(p) : null,
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      PrayerPage(prayer: p, entityName: it.entity.name),
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

  /// Adding from the prayers tab means picking the person here, since the tab
  /// itself is not scoped to one.
  Future<void> _addPrayerAnywhere() async {
    final entities = await _future;
    if (!mounted) return;
    if (entities.isEmpty) {
      _snack('ضيف شخص الأول من تاب الأشخاص.');
      return;
    }
    final draft = await Navigator.of(context).push<PrayerDraft>(
      MaterialPageRoute(
        builder: (_) =>
            PrayerEditorPage(heading: 'صلاة جديدة', pickFrom: entities),
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
                        EntityPage(entityId: e.id, entityName: e.name),
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

// ---- shared helpers ---------------------------------------------------------

Future<String?> askNote(BuildContext context) async {
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

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.onRetry});
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
