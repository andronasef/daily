import 'package:flutter/material.dart';
import '../../data/audio_service.dart';
import '../../data/memorize_models.dart';
import '../../domain/anki_engine.dart';

class FlashcardView extends StatefulWidget {
  const FlashcardView({
    super.key,
    required this.verse,
    required this.onGrade,
    this.onOpenRecorder,
  });

  final MemorizeVerse verse;
  final void Function(ReviewRating rating) onGrade;
  final VoidCallback? onOpenRecorder;

  @override
  State<FlashcardView> createState() => _FlashcardViewState();
}

class _FlashcardViewState extends State<FlashcardView> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audio = AudioService.instance;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!_revealed) setState(() => _revealed = true);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _revealed
                        ? theme.colorScheme.primary.withValues(alpha: 0.5)
                        : theme.dividerColor,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.verse.category != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.verse.category!,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      widget.verse.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!_revealed) ...[
                      const Spacer(),
                      Icon(
                        Icons.touch_app_outlined,
                        size: 44,
                        color: theme.colorScheme.primary.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'اضغط في أي مكان لكشف نص الآية',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                    ] else ...[
                      const Divider(height: 32),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            widget.verse.verse,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              height: 1.7,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Audio control row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.verse.hasVoice)
                            ValueListenableBuilder<AudioPlayState>(
                              valueListenable: audio.playState,
                              builder: (context, playState, _) {
                                final path = widget.verse.localVoicePath ??
                                    widget.verse.audioUrl!;
                                final isPlaying =
                                    audio.currentPlayingUri.value == path &&
                                        playState == AudioPlayState.playing;

                                return ElevatedButton.icon(
                                  onPressed: () {
                                    if (isPlaying) {
                                      audio.stopPlayback();
                                    } else {
                                      audio.play(path);
                                    }
                                  },
                                  icon: Icon(
                                    isPlaying
                                        ? Icons.stop_rounded
                                        : Icons.volume_up_rounded,
                                  ),
                                  label: Text(
                                    isPlaying
                                        ? 'إيقاف الصوت'
                                        : 'استماع للتسجيل',
                                  ),
                                );
                              },
                            )
                          else if (widget.onOpenRecorder != null)
                            OutlinedButton.icon(
                              onPressed: widget.onOpenRecorder,
                              icon: const Icon(Icons.mic_rounded),
                              label: const Text('تسجيل فويس للآية'),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Anki 4-grade buttons
          if (_revealed)
            Column(
              children: [
                Text(
                  'كيف كان استذكارك للآية؟',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _GradeButton(
                      label: 'أعد مجدداً',
                      subLabel: AnkiEngine.estimateIntervalLabel(
                        verse: widget.verse,
                        rating: ReviewRating.again,
                      ),
                      color: Colors.red,
                      onTap: () => widget.onGrade(ReviewRating.again),
                    ),
                    const SizedBox(width: 8),
                    _GradeButton(
                      label: 'صعب',
                      subLabel: AnkiEngine.estimateIntervalLabel(
                        verse: widget.verse,
                        rating: ReviewRating.hard,
                      ),
                      color: Colors.amber.shade800,
                      onTap: () => widget.onGrade(ReviewRating.hard),
                    ),
                    const SizedBox(width: 8),
                    _GradeButton(
                      label: 'جيد',
                      subLabel: AnkiEngine.estimateIntervalLabel(
                        verse: widget.verse,
                        rating: ReviewRating.good,
                      ),
                      color: Colors.blue.shade700,
                      onTap: () => widget.onGrade(ReviewRating.good),
                    ),
                    const SizedBox(width: 8),
                    _GradeButton(
                      label: 'سهل جداً',
                      subLabel: AnkiEngine.estimateIntervalLabel(
                        verse: widget.verse,
                        rating: ReviewRating.easy,
                      ),
                      color: Colors.green.shade700,
                      onTap: () => widget.onGrade(ReviewRating.easy),
                    ),
                  ],
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () => setState(() => _revealed = true),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('إظهار نص الآية والتقييم'),
              ),
            ),
        ],
      ),
    );
  }
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({
    required this.label,
    required this.subLabel,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String subLabel;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: color.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
