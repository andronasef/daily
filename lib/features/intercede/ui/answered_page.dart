import 'package:flutter/material.dart';

import '../data/models.dart';

/// Every answered prayer across all the people, newest first. Reached from the
/// app bar rather than a third tab: you open it to remember, not every day.
class AnsweredPage extends StatelessWidget {
  const AnsweredPage({super.key, required this.future});
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
