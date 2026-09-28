import 'package:flutter/material.dart';
import '../../data/memorize_models.dart';

class TypingChallengeView extends StatefulWidget {
  const TypingChallengeView({
    super.key,
    required this.verse,
  });

  final MemorizeVerse verse;

  @override
  State<TypingChallengeView> createState() => _TypingChallengeViewState();
}

class _TypingChallengeViewState extends State<TypingChallengeView> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late List<String> _words;
  int _currentIndex = 0;
  bool _isWrong = false;
  bool _isCompleted = false;
  bool _showHint = false;
  bool _fullWordMode = false;

  @override
  void initState() {
    super.initState();
    _words = widget.verse.words;
  }

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _normalizeArabic(String text) {
    var s = text.trim();
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), ''); // remove tashkeel
    s = s.replaceAll(RegExp(r'[^\u0621-\u064A0-9]'), ''); // keep arabic letters
    s = s.replaceAll(RegExp(r'[إأآا]'), 'ا');
    s = s.replaceAll('ة', 'ه');
    s = s.replaceAll('ى', 'ي');
    return s;
  }

  void _onInputChanged(String text) {
    if (text.isEmpty || _isCompleted || _currentIndex >= _words.length) return;

    final targetWord = _words[_currentIndex];
    final normalizedTarget = _normalizeArabic(targetWord);

    if (normalizedTarget.isEmpty) {
      // Punctuation only word, skip
      setState(() {
        _currentIndex++;
        _showHint = false;
      });
      _checkCompletion();
      _inputController.clear();
      return;
    }

    if (_fullWordMode) {
      final normalizedInput = _normalizeArabic(text);
      if (normalizedInput == normalizedTarget) {
        setState(() {
          _currentIndex++;
          _isWrong = false;
          _showHint = false;
        });
        _checkCompletion();
        _inputController.clear();
      } else if (normalizedTarget.startsWith(normalizedInput)) {
        setState(() {
          _isWrong = false;
        });
      } else {
        setState(() {
          _isWrong = true;
        });
      }
    } else {
      final typedChar = _normalizeArabic(text.characters.last);
      final expectedChar = normalizedTarget.characters.first;

      if (typedChar == expectedChar) {
        setState(() {
          _currentIndex++;
          _isWrong = false;
          _showHint = false;
        });
        _checkCompletion();
      } else {
        setState(() {
          _isWrong = true;
        });
      }
      _inputController.clear();
    }
  }

  void _checkCompletion() {
    if (_currentIndex >= _words.length) {
      setState(() {
        _isCompleted = true;
      });
      _focusNode.unfocus();
    }
  }

  void _restart() {
    setState(() {
      _currentIndex = 0;
      _isWrong = false;
      _isCompleted = false;
      _showHint = false;
    });
    _inputController.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _words.isEmpty ? 0.0 : _currentIndex / _words.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Progress bar
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'التقدم: $_currentIndex / ${_words.length} كلمة',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Mode selector
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                label: Text('الحرف الأول (من الذاكرة)'),
                icon: Icon(Icons.abc_rounded),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text('الكلمة كاملة'),
                icon: Icon(Icons.text_fields_rounded),
              ),
            ],
            selected: {_fullWordMode},
            onSelectionChanged: (set) {
              setState(() {
                _fullWordMode = set.first;
                _restart();
              });
            },
          ),
          const SizedBox(height: 16),

          // Verse Words display
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
                      final isRevealed = i < _currentIndex;
                      final isCurrent = i == _currentIndex;

                      if (isRevealed) {
                        return Text(
                          _words[i],
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        );
                      }

                      if (isCurrent) {
                        final currentWord = _words[i];
                        final displayHint = _showHint && currentWord.isNotEmpty;

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _isWrong
                                ? Colors.red.withValues(alpha: 0.15)
                                : theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _isWrong
                                  ? Colors.red
                                  : theme.colorScheme.primary,
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            displayHint
                                ? '${currentWord.characters.first}...'
                                : (_fullWordMode ? '_____' : '___'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _isWrong
                                  ? Colors.red
                                  : (_showHint
                                      ? Colors.amber.shade900
                                      : theme.colorScheme.primary),
                            ),
                          ),
                        );
                      }

                      // Still hidden
                      return Text(
                        '••••',
                        style: TextStyle(
                          fontSize: 16,
                          letterSpacing: 2,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.4),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

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
                  const Icon(Icons.check_circle_outline,
                      color: Colors.green, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'ممتاز جداً! كتبت الآية كاملة بنجاح 🎯',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'هذا التحدي يثبت حفظ الآية في عقلك بدقة وسرعة بديهة.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _restart,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة التحدي'),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Typing input field
            TextField(
              controller: _inputController,
              focusNode: _focusNode,
              autofocus: true,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: _fullWordMode
                    ? 'اكتب الكلمة كاملة هنا...'
                    : 'اكتب الحرف الأول للكلمة من ذاكرتك...',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                filled: true,
                fillColor: _isWrong
                    ? Colors.red.withValues(alpha: 0.08)
                    : theme.colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: _isWrong ? Colors.red : theme.dividerColor,
                  ),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _showHint ? 'إخفاء التلميح' : 'تلميح: إظهار الحرف الأول',
                      icon: Icon(
                        _showHint ? Icons.lightbulb : Icons.lightbulb_outline,
                        color: _showHint ? Colors.amber : null,
                      ),
                      onPressed: () {
                        setState(() {
                          _showHint = !_showHint;
                        });
                      },
                    ),
                    IconButton(
                      tooltip: 'مساعدة: تخطي كلمة',
                      icon: const Icon(Icons.skip_next_rounded),
                      onPressed: () {
                        setState(() {
                          _currentIndex++;
                          _isWrong = false;
                          _showHint = false;
                        });
                        _checkCompletion();
                      },
                    ),
                  ],
                ),
              ),
              onChanged: _onInputChanged,
            ),
            const SizedBox(height: 12),
            Text(
              _fullWordMode
                  ? 'اكتب الكلمة كاملة لتثبيت الآية حرفاً بحرف!'
                  : 'الكلمة التالية مخفية — فكّر في الكلمة واكتب أول حرف فقط من الذاكرة!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
