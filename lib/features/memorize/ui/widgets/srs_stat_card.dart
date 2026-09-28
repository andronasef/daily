import 'package:flutter/material.dart';
import '../../data/memorize_models.dart';

class SrsStatCard extends StatelessWidget {
  const SrsStatCard({
    super.key,
    required this.stats,
    required this.onStartReview,
  });

  final MemorizeStats stats;
  final VoidCallback onStartReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatColumn(
                  label: 'مستحقة اليوم',
                  value: stats.dueCount.toString(),
                  color: colorScheme.primary,
                  icon: Icons.alarm,
                ),
                _StatColumn(
                  label: 'قيد الحفظ',
                  value: stats.learningCount.toString(),
                  color: Colors.orange,
                  icon: Icons.sync,
                ),
                _StatColumn(
                  label: 'تم الحفظ',
                  value: stats.masteredCount.toString(),
                  color: Colors.green,
                  icon: Icons.check_circle_outline,
                ),
                _StatColumn(
                  label: 'أيام متتالية',
                  value: '${stats.streakDays}🔥',
                  color: Colors.deepOrange,
                  icon: Icons.local_fire_department_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: stats.dueCount > 0 ? onStartReview : null,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(
                  stats.dueCount > 0
                      ? 'ابدأ جلسة المراجعة اليوم (${stats.dueCount})'
                      : 'تمت مراجعة كل الآيات المستحقة اليوم! 🎉',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
