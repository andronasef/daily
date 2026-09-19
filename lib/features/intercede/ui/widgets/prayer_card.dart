import 'package:flutter/material.dart';

/// One prayer, in both the flat daily list and a person's page.
///
/// The text owns a full-width row of its own and the actions sit on a second
/// row underneath. A ListTile would centre the button against the text block,
/// so "صليت" drifted up and down with how long the prayer was and the text got
/// squeezed into whatever column the button left behind.
class PrayerCard extends StatelessWidget {
  const PrayerCard({
    super.key,
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
