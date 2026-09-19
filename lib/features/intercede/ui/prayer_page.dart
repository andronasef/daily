import 'package:flutter/material.dart';

import '../data/models.dart';

class PrayerPage extends StatelessWidget {
  const PrayerPage({super.key, required this.prayer, required this.entityName});

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
                  title: Text(formatFullDate(log.prayedAt)),
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
