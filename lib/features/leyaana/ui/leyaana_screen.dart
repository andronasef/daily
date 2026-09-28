import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/repository.dart';
import 'leyaana_admin_screen.dart';

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
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LeyaanaAdminScreen()),
                );
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
                _NamedTab(
                  item: c.blessing,
                  emptyLabel: 'مفيش بركة متاحة دلوقتي.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Soft rounded card matching leyaana's paper (radius ~24) with long press support.
class _SoftCard extends StatelessWidget {
  const _SoftCard({required this.child, this.onLongPress});
  final Widget child;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.dividerColor),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _VersesTab extends StatelessWidget {
  const _VersesTab({required this.content});
  final DailyContent content;

  static const _arabicDays = [
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  static const _arabicMonths = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

  static String _formatDate(DateTime now) {
    final dayName = _arabicDays[now.weekday - 1];
    final monthName = _arabicMonths[now.month - 1];
    return '$dayName، ${now.day} $monthName ${now.year}';
  }

  static String _formatWeek(DateTime now) {
    final weekOfMonth = ((now.day - 1) ~/ 7) + 1;
    final firstDayOfYear = DateTime(now.year, 1, 1);
    final dayOfYear = now.difference(firstDayOfYear).inDays + 1;
    final weekOfYear = ((dayOfYear - 1) ~/ 7) + 1;
    return 'الأسبوع $weekOfMonth في الشهر • الأسبوع $weekOfYear في السنة';
  }

  static String _formatMonth(DateTime now) {
    final monthName = _arabicMonths[now.month - 1];
    return 'شهر ${now.month} ($monthName ${now.year})';
  }

  void _copyVerse(BuildContext context, Verse verse) {
    final text = verse.title != null && verse.title!.isNotEmpty
        ? '${verse.verse}\n— ${verse.title}'
        : verse.verse;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('تم نسخ الآية إلى الحافظة'),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final rows = <(String, String, Verse)>[
      if (content.dailyVerse != null)
        ('آية النهارده', _formatDate(now), content.dailyVerse!),
      if (content.weeklyVerse != null)
        ('آية الأسبوع', _formatWeek(now), content.weeklyVerse!),
      if (content.monthlyVerse != null)
        ('آية الشهر', _formatMonth(now), content.monthlyVerse!),
    ];

    if (rows.isEmpty) return const _Empty('مفيش آيات متاحة دلوقتي.');

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final (label, meta, verse) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _SoftCard(
              onLongPress: () => _copyVerse(context, verse),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            meta,
                            textAlign: TextAlign.end,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '"${verse.verse}"',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      height: 1.8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (verse.title != null && verse.title!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      verse.title!,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 13,
                        color: theme.colorScheme.outline.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'اضغط مطولاً للنسخ',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.outline.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
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

  void _copy(BuildContext context, NamedContent it) {
    final parts = [
      it.name,
      if (it.mean != null && it.mean!.isNotEmpty) it.mean!,
      if (it.content != null && it.content!.isNotEmpty) it.content!,
    ];
    Clipboard.setData(ClipboardData(text: parts.join('\n')));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('تم النسخ إلى الحافظة'),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (item == null) return _Empty(emptyLabel);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SoftCard(
          onLongPress: () => _copy(context, item!),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                item!.name,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (item!.mean != null && item!.mean!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  item!.mean!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
              if (item!.content != null && item!.content!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  item!.content!,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.9),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    size: 13,
                    color: theme.colorScheme.outline.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'اضغط مطولاً للنسخ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.outline.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
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
