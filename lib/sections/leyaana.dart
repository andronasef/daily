import 'package:flutter/material.dart';
import '../leyaana_content.dart';
import 'leyaana_admin.dart';

/// Section 2 "ليا انا": daily/weekly/monthly verses, a daily God-name, and a
/// daily blessing — same picks as the leyaana PWA (see leyaana_content.dart).
/// Vibe: leyaana's soft rounded cards + full-width tabs, in the app palette.
class LeyaanaScreen extends StatefulWidget {
  const LeyaanaScreen({super.key});

  @override
  State<LeyaanaScreen> createState() => _LeyaanaScreenState();
}

class _LeyaanaScreenState extends State<LeyaanaScreen> {
  late Future<DailyContent> _future;

  @override
  void initState() {
    super.initState();
    _future = loadDailyContent();
  }

  void _reload() {
    final f = loadDailyContent();
    setState(() {
      _future = f;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ليا انا'),
          actions: [
            IconButton(
              tooltip: 'إدارة المحتوى',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const LeyaanaAdminScreen()));
                _reload();
              },
            ),
            IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'الآيات'),
              Tab(text: 'أسماء الله'),
              Tab(text: 'البركات'),
            ],
          ),
        ),
        body: FutureBuilder<DailyContent>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _ErrorView(onRetry: _reload);
            }
            final c = snap.data!;
            return TabBarView(
              children: [
                _VersesTab(content: c),
                _NamedTab(item: c.godName, emptyLabel: 'مفيش اسم متاح دلوقتي.'),
                _NamedTab(item: c.blessing, emptyLabel: 'مفيش بركة متاحة دلوقتي.'),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Soft rounded card matching leyaana's paper (radius ~24).
class _SoftCard extends StatelessWidget {
  const _SoftCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.dividerColor),
      ),
      child: child,
    );
  }
}

class _VersesTab extends StatelessWidget {
  const _VersesTab({required this.content});
  final DailyContent content;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, Verse?)>[
      ('آية النهارده', content.dailyVerse),
      ('آية الأسبوع', content.weeklyVerse),
      ('آية الشهر', content.monthlyVerse),
    ].where((r) => r.$2 != null).toList();

    if (rows.isEmpty) return const _Empty('مفيش آيات متاحة دلوقتي.');

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (label, verse) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(label,
                      style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary)),
                  const SizedBox(height: 10),
                  Text('"${verse!.verse}"',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(height: 1.8, fontWeight: FontWeight.bold)),
                  if (verse.title != null && verse.title!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(verse.title!,
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _NamedTab extends StatelessWidget {
  const _NamedTab({required this.item, required this.emptyLabel});
  final NamedContent? item;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (item == null) return _Empty(emptyLabel);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(item!.name,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              if (item!.mean != null && item!.mean!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(item!.mean!,
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary)),
              ],
              if (item!.content != null && item!.content!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(item!.content!,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.9)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(label)),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('تعذر تحميل المحتوى. اتأكد من الاتصال بالإنترنت.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
}
