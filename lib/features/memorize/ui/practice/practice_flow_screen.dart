import 'package:flutter/material.dart';
import '../../data/memorize_models.dart';
import '../../data/memorize_repository.dart';
import 'flashcard_view.dart';
import 'reveal_challenge_view.dart';
import 'typing_challenge_view.dart';
import 'voice_recorder_view.dart';

class PracticeFlowScreen extends StatefulWidget {
  const PracticeFlowScreen({
    super.key,
    required this.verses,
    this.initialIndex = 0,
    this.isSession = false,
  });

  final List<MemorizeVerse> verses;
  final int initialIndex;
  final bool isSession;

  @override
  State<PracticeFlowScreen> createState() => _PracticeFlowScreenState();
}

class _PracticeFlowScreenState extends State<PracticeFlowScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late int _verseIndex;
  late List<MemorizeVerse> _sessionVerses;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _verseIndex = widget.initialIndex;
    _sessionVerses = List.of(widget.verses);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  MemorizeVerse get _currentVerse => _sessionVerses[_verseIndex];

  Future<void> _onGrade(ReviewRating rating) async {
    final updated = await MemorizeRepository.instance.reviewVerse(
      verse: _currentVerse,
      rating: rating,
    );

    setState(() {
      _sessionVerses[_verseIndex] = updated;
    });

    if (widget.isSession) {
      if (_verseIndex + 1 < _sessionVerses.length) {
        setState(() {
          _verseIndex++;
        });
      } else {
        _showSessionFinishedDialog();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تسجيل المراجعة وتحديث موعد التكرار بنجاح! ✅'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  void _showSessionFinishedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.celebration, color: Colors.amber, size: 28),
            SizedBox(width: 8),
            Text('عظيم جداً!'),
          ],
        ),
        content: const Text(
          'أكملت مراجعة كل الآيات المجدولة لليوم بنجاح! تم تحديث مواعيد التكرار المتباعد.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop(); // dialog
              Navigator.of(context).pop(true); // screen
            },
            child: const Text('العودة للرئيسية'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_sessionVerses.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('المراجعة')),
        body: const Center(child: Text('لا توجد آيات')),
      );
    }

    final verse = _currentVerse;

    return Scaffold(
      appBar: AppBar(
        title: widget.isSession
            ? Text('مراجعة اليوم (${_verseIndex + 1}/${_sessionVerses.length})')
            : Text(verse.title),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.style_outlined), text: 'بطاقة Anki'),
            Tab(icon: Icon(Icons.mic_outlined), text: 'تسجيل واستماع'),
            Tab(icon: Icon(Icons.visibility_off_outlined), text: 'تحدي الكشف'),
            Tab(icon: Icon(Icons.keyboard_outlined), text: 'الحرف الأول'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          FlashcardView(
            key: ValueKey('flashcard_${verse.id}'),
            verse: verse,
            onGrade: _onGrade,
            onOpenRecorder: () {
              _tabController.animateTo(1);
            },
          ),
          VoiceRecorderView(
            key: ValueKey('recorder_${verse.id}'),
            verse: verse,
            onVoiceUpdated: (updatedVerse) {
              setState(() {
                _sessionVerses[_verseIndex] = updatedVerse;
              });
            },
          ),
          RevealChallengeView(
            key: ValueKey('reveal_${verse.id}'),
            verse: verse,
          ),
          TypingChallengeView(
            key: ValueKey('typing_${verse.id}'),
            verse: verse,
          ),
        ],
      ),
    );
  }
}
