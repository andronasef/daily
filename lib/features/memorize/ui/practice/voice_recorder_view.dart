import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

import '../../../../core/sanity/client.dart';
import '../../data/audio_service.dart';
import '../../data/memorize_models.dart';
import '../../data/memorize_repository.dart';

class VoiceRecorderView extends StatefulWidget {
  const VoiceRecorderView({
    super.key,
    required this.verse,
    required this.onVoiceUpdated,
  });

  final MemorizeVerse verse;
  final ValueChanged<MemorizeVerse> onVoiceUpdated;

  @override
  State<VoiceRecorderView> createState() => _VoiceRecorderViewState();
}

class _VoiceRecorderViewState extends State<VoiceRecorderView> {
  final _audio = AudioService.instance;
  final _repo = MemorizeRepository.instance;

  Timer? _recordTimer;
  int _recordSeconds = 0;
  late List<VoiceRecording> _recordings;
  final Set<String> _uploadingIds = {};

  @override
  void initState() {
    super.initState();
    _recordings = List.of(widget.verse.recordings);
    if (_recordings.isEmpty &&
        widget.verse.localVoicePath != null &&
        widget.verse.localVoicePath!.isNotEmpty) {
      _recordings.add(
        VoiceRecording(
          id: 'rec_legacy_${widget.verse.id}',
          localPath: widget.verse.localVoicePath!,
          recordedAt: DateTime.now(),
          title: 'تسجيل سابق',
        ),
      );
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    super.dispose();
  }

  void _startRecordTimer() {
    _recordSeconds = 0;
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _recordSeconds++);
    });
  }

  void _stopRecordTimer() {
    _recordTimer?.cancel();
    _recordTimer = null;
  }

  void _notifyParent() {
    final updated = widget.verse.copyWith(
      recordings: _recordings,
      localVoicePath:
          _recordings.isNotEmpty ? _recordings.last.localPath : null,
    );
    widget.onVoiceUpdated(updated);
  }

  Future<void> _toggleRecord() async {
    if (_audio.isRecording.value) {
      final path = await _audio.stopRecording();
      final duration = _recordSeconds;
      _stopRecordTimer();

      if (path != null) {
        final rec = VoiceRecording(
          id: 'rec_${DateTime.now().millisecondsSinceEpoch}',
          localPath: path,
          recordedAt: DateTime.now(),
          durationSeconds: duration,
          title: 'تسجيل ${_recordings.length + 1}',
        );

        await _repo.addRecording(widget.verse.id, rec);
        setState(() {
          _recordings.add(rec);
        });
        _notifyParent();

        // Automatically upload to Sanity immediately!
        unawaited(_uploadToSanity(rec, isAutomatic: true));
      }
    } else {
      final hasPerm = await _audio.hasPermission();
      if (!hasPerm) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('برجاء السماح بإذن الميكروفون لتسجيل صوتك'),
            ),
          );
        }
      }
      final tempId =
          '${widget.verse.id}_${DateTime.now().millisecondsSinceEpoch}';
      final path = await _audio.startRecording(tempId);
      if (path != null) {
        _startRecordTimer();
      }
    }
  }

  Future<void> _deleteRecording(VoiceRecording recording) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف التسجيل؟'),
        content: Text(
          'هل تريد بالتأكيد حذف "${recording.title ?? 'هذا التسجيل'}"؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (_audio.currentPlayingUri.value == recording.localPath) {
      await _audio.stopPlayback();
    }

    await _audio.deleteRecording(recording.localPath);
    await _repo.deleteRecording(widget.verse.id, recording.id);

    setState(() {
      _recordings.removeWhere((r) => r.id == recording.id);
    });
    _notifyParent();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف التسجيل 🗑️'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _uploadToSanity(
    VoiceRecording recording, {
    bool isAutomatic = false,
  }) async {
    if (!sanityCanWrite) {
      if (!isAutomatic && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'مطلوب إدخال Sanity Write Token في شاشة الإعدادات لرفع الفويسات سحابياً.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    setState(() => _uploadingIds.add(recording.id));

    try {
      final updated = await _repo.uploadRecordingToSanity(
        verse: widget.verse,
        recording: recording,
      );

      setState(() {
        final index = _recordings.indexWhere((r) => r.id == recording.id);
        if (index >= 0) {
          _recordings[index] = updated;
        }
        _uploadingIds.remove(recording.id);
      });
      _notifyParent();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم رفع التسجيل تلقائياً إلى Sanity! ☁️'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _uploadingIds.remove(recording.id));
      if (!isAutomatic && mounted) {
        String msg = 'التسجيل محفوظ محلياً على جهازك. تعذر الرفع السحابي حالياً.';
        final err = e.toString();
        if (err.contains('401') ||
            err.contains('Unauthorized') ||
            err.contains('Session not found')) {
          msg =
              'التسجيل محفوظ محلياً ويعمل بدون إنترنت. توكن Sanity غير صالح أو انتهت صلاحيته.';
        } else if (err.contains('SocketException') ||
            err.contains('timed out')) {
          msg = 'التسجيل محفوظ محلياً. لا يوجد اتصال بالإنترنت للرفع السحابي حالياً.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(msg)),
              ],
            ),
            backgroundColor: Colors.orange.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  String _formatSeconds(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Verse card for reference while recording
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    widget.verse.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.verse.verse,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w500,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Studio Recording controls
          ValueListenableBuilder<bool>(
            valueListenable: _audio.isRecording,
            builder: (context, recording, _) {
              return Column(
                children: [
                  if (recording) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.fiber_manual_record,
                            color: Colors.red,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'جاري التسجيل: ${_formatSeconds(_recordSeconds)}',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Big Record Button
                  GestureDetector(
                    onTap: _toggleRecord,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: recording
                            ? Colors.red
                            : theme.colorScheme.primaryContainer,
                        boxShadow: [
                          BoxShadow(
                            color: (recording
                                    ? Colors.red
                                    : theme.colorScheme.primary)
                                .withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(
                        recording ? Icons.stop_rounded : Icons.mic_rounded,
                        size: 40,
                        color: recording
                            ? Colors.white
                            : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    recording
                        ? 'اضغط هنا للإنهاء وحفظ التسجيل'
                        : 'اضغط لبدء تسجيل صوتي جديد (يمكنك تجربة أكثر من فويس)',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 28),

          // Reference Audio from Sanity (if any)
          if (widget.verse.audioUrl != null &&
              widget.verse.audioUrl!.isNotEmpty) ...[
            Card(
              color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
              child: ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.cloud_done_rounded),
                ),
                title: const Text(
                  'تلاوة الآية المرجعية (Sanity)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('تسجيل مرجعي رسمي للآية'),
                trailing: ValueListenableBuilder<AudioPlayState>(
                  valueListenable: _audio.playState,
                  builder: (context, playState, _) {
                    final isPlaying =
                        _audio.currentPlayingUri.value == widget.verse.audioUrl &&
                            playState == AudioPlayState.playing;
                    return IconButton.filled(
                      icon: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      onPressed: () {
                        if (isPlaying) {
                          _audio.pausePlayback();
                        } else {
                          _audio.play(widget.verse.audioUrl!);
                        }
                      },
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Multiple recordings list
          Row(
            children: [
              const Icon(Icons.headphones_rounded, size: 20),
              const SizedBox(width: 8),
              Text(
                'التسجيلات الصوتية (${_recordings.length}):',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_recordings.isEmpty)
            Card(
              color: theme.colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(
                      Icons.mic_none,
                      size: 44,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'لا توجد تسجيلات صوتية بعد',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'سجّل تلاوتك بصوتك لتستمع إليها وتجرب عدة مرات براحتك.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _recordings.length,
              itemBuilder: (context, index) {
                final rec = _recordings[index];
                final isUploading = _uploadingIds.contains(rec.id);

                return ValueListenableBuilder<AudioPlayState>(
                  valueListenable: _audio.playState,
                  builder: (context, playState, _) {
                    final hasLocalFile = File(rec.localPath).existsSync();
                    final audioUri = hasLocalFile
                        ? rec.localPath
                        : (rec.sanityUrl ?? rec.localPath);
                    final isPlaying =
                        _audio.currentPlayingUri.value == audioUri &&
                            playState == AudioPlayState.playing;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                IconButton.filled(
                                  icon: Icon(
                                    isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                  onPressed: () {
                                    if (isPlaying) {
                                      _audio.pausePlayback();
                                    } else {
                                      _audio.play(audioUri);
                                    }
                                  },
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            rec.title ?? 'تسجيل ${index + 1}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (rec.isUploadedToSanity)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.green
                                                    .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.cloud_done_rounded,
                                                    size: 14,
                                                    color: Colors.green,
                                                  ),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'سحابي',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.green,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          else
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: theme
                                                    .colorScheme
                                                    .primaryContainer
                                                    .withValues(alpha: 0.5),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.phone_android_rounded,
                                                    size: 12,
                                                    color: theme
                                                        .colorScheme.primary,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'محلي',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: theme
                                                          .colorScheme.primary,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'المدة: ${_formatSeconds(rec.durationSeconds)} • ${_formatDate(rec.recordedAt)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isUploading)
                                  const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                else if (!rec.isUploadedToSanity)
                                  IconButton(
                                    tooltip: 'رفع وحفظ في Sanity',
                                    icon: const Icon(
                                      Icons.cloud_upload_outlined,
                                      color: Colors.blue,
                                    ),
                                    onPressed: () => _uploadToSanity(rec),
                                  ),
                                IconButton(
                                  tooltip: 'حذف هذا التسجيل',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _deleteRecording(rec),
                                ),
                              ],
                            ),
                            if (isPlaying) ...[
                              const SizedBox(height: 6),
                              ValueListenableBuilder<Duration>(
                                valueListenable: _audio.currentPosition,
                                builder: (context, pos, _) {
                                  return ValueListenableBuilder<Duration>(
                                    valueListenable: _audio.totalDuration,
                                    builder: (context, dur, _) {
                                      final totalMs = dur.inMilliseconds;
                                      final curMs = pos.inMilliseconds;
                                      final progress = totalMs > 0
                                          ? (curMs / totalMs).clamp(0.0, 1.0)
                                          : 0.0;

                                      return Column(
                                        children: [
                                          LinearProgressIndicator(
                                            value: progress,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _formatSeconds(pos.inSeconds),
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                ),
                                              ),
                                              Text(
                                                _formatSeconds(dur.inSeconds),
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),

          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tips_and_updates_outlined,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'يمكنك تسجيل محاولات متعددة، حذف أي تسجيل لا تريده، ورفع أفضل تسجيل إلى Sanity لتجده على أي جهاز! ☁️',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
