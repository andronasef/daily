import 'package:flutter/material.dart';
import '../data/audio_service.dart';
import '../data/memorize_models.dart';
import '../data/memorize_repository.dart';

class AddVerseSheet extends StatefulWidget {
  const AddVerseSheet({super.key});

  @override
  State<AddVerseSheet> createState() => _AddVerseSheetState();
}

class _AddVerseSheetState extends State<AddVerseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _verseController = TextEditingController();
  final _categoryController = TextEditingController();
  final _translationController = TextEditingController();

  String? _recordedVoicePath;
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _verseController.dispose();
    _categoryController.dispose();
    _translationController.dispose();
    super.dispose();
  }

  Future<void> _recordVoice() async {
    final audio = AudioService.instance;
    final tempId = 'custom_${DateTime.now().millisecondsSinceEpoch}';

    if (audio.isRecording.value) {
      final path = await audio.stopRecording();
      setState(() => _recordedVoicePath = path);
    } else {
      final hasPerm = await audio.hasPermission();
      if (!hasPerm) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('برجاء إعطاء إذن الميكروفون')),
          );
        }
      }
      final path = await audio.startRecording(tempId);
      if (path != null) {
        setState(() => _recordedVoicePath = null);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';

    final recordings = <VoiceRecording>[];
    if (_recordedVoicePath != null && _recordedVoicePath!.isNotEmpty) {
      recordings.add(VoiceRecording(
        id: 'rec_${DateTime.now().millisecondsSinceEpoch}',
        localPath: _recordedVoicePath!,
        recordedAt: DateTime.now(),
        title: 'تسجيل 1',
      ));
    }

    final newVerse = MemorizeVerse(
      id: id,
      title: _titleController.text.trim(),
      verse: _verseController.text.trim(),
      category: _categoryController.text.trim().isEmpty
          ? 'آياتي الخاصة'
          : _categoryController.text.trim(),
      translation: _translationController.text.trim(),
      localVoicePath: _recordedVoicePath,
      recordings: recordings,
      source: 'custom',
      createdAt: DateTime.now(),
      dueDate: DateTime.now(),
    );

    await MemorizeRepository.instance.addVerse(newVerse);

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audio = AudioService.instance;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'إضافة آية للحفظ',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'الشاهد الكتابي',
                  hintText: 'مثال: يوحنا 14: 27 أو مزمور 23: 1',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.bookmark_outline),
                ),
                validator: (val) =>
                    (val == null || val.trim().isEmpty) ? 'مطلوب' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _verseController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'نص الآية',
                  hintText: 'اكتب نص الآية هنا...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.format_quote_outlined),
                ),
                validator: (val) =>
                    (val == null || val.trim().isEmpty) ? 'مطلوب' : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _categoryController,
                      decoration: const InputDecoration(
                        labelText: 'التصنيف / الموضوع',
                        hintText: 'مثال: سلام، نصرة، محبة',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _translationController,
                      decoration: const InputDecoration(
                        labelText: 'الترجمة (اختياري)',
                        hintText: 'مثال: فاندايك، المشتركة...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Voice recording option directly in the add form
              Card(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      ValueListenableBuilder<bool>(
                        valueListenable: audio.isRecording,
                        builder: (context, recording, _) {
                          return IconButton.filled(
                            style: IconButton.styleFrom(
                              backgroundColor: recording
                                  ? Colors.red
                                  : theme.colorScheme.primary,
                            ),
                            icon: Icon(
                              recording
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                              color: Colors.white,
                            ),
                            onPressed: _recordVoice,
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _recordedVoicePath != null
                                  ? 'تم تسجيل الصوت بنجاح! 🎙️'
                                  : 'تسجيل فويس للآية (اختياري)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _recordedVoicePath != null
                                    ? Colors.green
                                    : null,
                              ),
                            ),
                            const Text(
                              'سجّل قراءتك أو تسميعك بصوتك الآن',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      if (_recordedVoicePath != null)
                        IconButton(
                          icon: const Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.blue,
                            size: 28,
                          ),
                          onPressed: () {
                            audio.play(_recordedVoicePath!);
                          },
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: const Icon(Icons.add_rounded),
                label: Text(_isSaving ? 'جاري الحفظ...' : 'إضافة للائحة الحفظ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
