import 'dart:math';
import 'package:flutter/material.dart';
import '../../data/memorize_models.dart';

enum RevealDifficulty {
  easy(0.25, 'سهل (25% مخفي)'),
  medium(0.50, 'متوسط (50% مخفي)'),
  hard(0.80, 'صعب (80% مخفي)');

  const RevealDifficulty(this.ratio, this.label);
  final double ratio;
  final String label;
}

class RevealChallengeView extends StatefulWidget {
  const RevealChallengeView({
    super.key,
    required this.verse,
  });

  final MemorizeVerse verse;

  @override
  State<RevealChallengeView> createState() => _RevealChallengeViewState();
}

class _RevealChallengeViewState extends State<RevealChallengeView> {
  RevealDifficulty _difficulty = RevealDifficulty.medium;
  late List<String> _words;
  late Set<int> _hiddenIndices;
  late Set<int> _revealedIndices;
  int? _activeTargetIndex;
  List<String> _currentChoices = [];
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _words = widget.verse.words;
    _setupChallenge();
  }

  void _setupChallenge() {
    final count = _words.length;
    final hideCount = max(1, (count * _difficulty.ratio).round());

    // Deterministic or random shuffle of indices
    final indices = List<int>.generate(count, (i) => i)..shuffle(Random());
    _hiddenIndices = indices.take(hideCount).toSet();
    _revealedIndices = {};
    _isCompleted = false;

    _selectNextTarget();
  }

  void _selectNextTarget() {
    final remaining = _hiddenIndices.difference(_revealedIndices).toList();
    if (remaining.isEmpty) {
      setState(() {
        _isCompleted = true;
        _activeTargetIndex = null;
        _currentChoices = [];
      });
      return;
    }

    remaining.sort(); // Pick the first remaining hidden word in order
    final target = remaining.first;
    _activeTargetIndex = target;
    _generateChoices(target);
  }

  void _generateChoices(int targetIndex) {
    final targetWord = _cleanWord(_words[targetIndex]);
    final otherWords = _words
        .map(_cleanWord)
        .where((w) => w != targetWord && w.length > 1)
        .toSet()
        .toList();
    otherWords.shuffle();

    final choices = <String>{targetWord};
    for (final w in otherWords) {
      if (choices.length >= 4) break;
      choices.add(w);
    }

    // Add generic biblical Arabic words as fallback distractors if needed
    final fallbacks = ['الرب', 'الله', 'قلبي', 'سلام', 'إيمان', 'حق', 'صلاة'];
    for (final f in fallbacks) {
      if (choices.length >= 4) break;
      if (f != targetWord) choices.add(f);
    }

    final list = choices.toList()..shuffle();
    setState(() {
      _currentChoices = list;
    });
  }

  String _cleanWord(String word) {
    return word.replaceAll(RegExp(r'[^\u0621-\u064A]'), '').trim();
  }

  void _onChoiceSelected(String choice) {
    if (_activeTargetIndex == null) return;
    final correct = _cleanWord(_words[_activeTargetIndex!]);

    if (choice == correct) {
      setState(() {
        _revealedIndices.add(_activeTargetIndex!);
      });
      _selectNextTarget();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حاول مرة أخرى! 🤔'),
          duration: Duration(milliseconds: 700),
        ),
      );
    }
  }

  void _revealCurrent() {
    if (_activeTargetIndex == null) return;
    setState(() {
      _revealedIndices.add(_activeTargetIndex!);
    });
    _selectNextTarget();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Difficulty selector chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: RevealDifficulty.values.map((d) {
                final isSelected = _difficulty == d;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(d.label),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _difficulty = d;
                          _setupChallenge();
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Verse box with hidden blanks
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    widget.verse.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 6,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: List.generate(_words.length, (i) {
                      final isHidden = _hiddenIndices.contains(i);
                      final isRevealed = _revealedIndices.contains(i);
                      final isTarget = _activeTargetIndex == i;

                      if (!isHidden || isRevealed) {
                        return Text(
                          _words[i],
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isRevealed
                                ? Colors.green.shade700
                                : theme.colorScheme.onSurface,
                          ),
                        );
                      }

                      // Hidden blank
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isTarget
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isTarget
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          '______',
                          style: TextStyle(
                            fontSize: 15,
                            color: isTarget
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Completion Banner or Word choices
          if (_isCompleted) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.stars_rounded, color: Colors.green, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'أحسنت! أتقنت تحدي الكشف بنجاح 🎉',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'تمكنت من تذكر كل الكلمات المخفية للآية.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _setupChallenge();
                      });
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة التحدي'),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              'اختر الكلمة التالية التي تملأ الفراغ المحدد:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            // 2x2 Grid of word choices
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: _currentChoices.map((choice) {
                return SizedBox(
                  width: (MediaQuery.of(context).size.width - 64) / 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _onChoiceSelected(choice),
                    child: Text(
                      choice,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _revealCurrent,
              icon: const Icon(Icons.help_outline, size: 18),
              label: const Text('كشف الكلمة (مساعدة)'),
            ),
          ],
        ],
      ),
    );
  }
}
