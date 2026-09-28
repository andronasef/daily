import 'package:flutter/material.dart';
import '../../data/audio_service.dart';
import '../../data/memorize_models.dart';

class VerseItemTile extends StatelessWidget {
  const VerseItemTile({
    super.key,
    required this.verse,
    required this.onTap,
    required this.onDelete,
    this.onRecordVoice,
    this.onToggleMastered,
  });

  final MemorizeVerse verse;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onRecordVoice;
  final VoidCallback? onToggleMastered;

  Color _stateColor(SrsState state) {
    switch (state) {
      case SrsState.newCard:
        return Colors.blue;
      case SrsState.learning:
        return Colors.orange;
      case SrsState.review:
        return Colors.purple;
      case SrsState.mastered:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audio = AudioService.instance;
    final isMastered = verse.state == SrsState.mastered;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: isMastered
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Colors.green.withValues(alpha: 0.4),
                width: 1.2,
              ),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      verse.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _stateColor(verse.state).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      verse.state.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _stateColor(verse.state),
                      ),
                    ),
                  ),
                  if (verse.isDue) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'مستحقة',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                verse.verse,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (verse.category != null && verse.category!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        verse.category!,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const Spacer(),
                  // Voice quick play / record button
                  if (verse.hasVoice)
                    ValueListenableBuilder<AudioPlayState>(
                      valueListenable: audio.playState,
                      builder: (context, state, _) {
                        final audioPath =
                            verse.localVoicePath ?? verse.audioUrl!;
                        final isPlayingThis =
                            audio.currentPlayingUri.value == audioPath &&
                                state == AudioPlayState.playing;

                        return IconButton.filledTonal(
                          iconSize: 20,
                          tooltip: isPlayingThis ? 'إيقاف' : 'استماع للتسجيل',
                          icon: Icon(
                            isPlayingThis
                                ? Icons.pause_rounded
                                : Icons.volume_up_rounded,
                          ),
                          onPressed: () {
                            if (isPlayingThis) {
                              audio.stopPlayback();
                            } else {
                              audio.play(audioPath);
                            }
                          },
                        );
                      },
                    )
                  else if (onRecordVoice != null)
                    IconButton.outlined(
                      iconSize: 20,
                      tooltip: 'تسجيل صوت للآية',
                      icon: const Icon(Icons.mic_none_rounded),
                      onPressed: onRecordVoice,
                    ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (val) {
                      if (val == 'delete') {
                        onDelete();
                      } else if (val == 'record' && onRecordVoice != null) {
                        onRecordVoice!();
                      } else if (val == 'toggle_mastered' &&
                          onToggleMastered != null) {
                        onToggleMastered!();
                      }
                    },
                    itemBuilder: (context) => [
                      if (onToggleMastered != null)
                        PopupMenuItem(
                          value: 'toggle_mastered',
                          child: Row(
                            children: [
                              Icon(
                                isMastered
                                    ? Icons.replay_rounded
                                    : Icons.check_circle_outline_rounded,
                                color: isMastered
                                    ? Colors.orange
                                    : Colors.green,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isMastered
                                    ? 'إعادة للتدريب'
                                    : 'تم حفظها خلاص ✅',
                                style: TextStyle(
                                  color: isMastered
                                      ? Colors.orange
                                      : Colors.green,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (onRecordVoice != null)
                        const PopupMenuItem(
                          value: 'record',
                          child: Row(
                            children: [
                              Icon(Icons.mic, size: 18),
                              SizedBox(width: 8),
                              Text('تسجيل فويس'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline,
                                color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text('حذف من الحفظ',
                                style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
