import 'dart:async';
import 'package:flutter/material.dart';
import '../data/audio_service.dart';
import '../data/memorize_models.dart';

class AudioPlaylistScreen extends StatefulWidget {
  const AudioPlaylistScreen({
    super.key,
    required this.verses,
    this.initialIndex = 0,
  });

  final List<MemorizeVerse> verses;
  final int initialIndex;

  @override
  State<AudioPlaylistScreen> createState() => _AudioPlaylistScreenState();
}

class _AudioPlaylistScreenState extends State<AudioPlaylistScreen> {
  final _audio = AudioService.instance;
  late int _currentIndex;
  int _repeatCount = 1; // 1x, 2x, 3x
  int _currentRepeatPlayed = 0;
  StreamSubscription<AudioPlayState>? _playSub;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _playCurrent();

    // Listen for completion to advance to next or repeat
    _audio.playState.addListener(_onPlayStateChanged);
  }

  @override
  void dispose() {
    _audio.playState.removeListener(_onPlayStateChanged);
    _playSub?.cancel();
    _audio.stopPlayback();
    super.dispose();
  }

  void _onPlayStateChanged() {
    if (_audio.playState.value == AudioPlayState.stopped) {
      if (_currentRepeatPlayed + 1 < _repeatCount) {
        _currentRepeatPlayed++;
        _playCurrent();
      } else {
        _currentRepeatPlayed = 0;
        _next();
      }
    }
  }

  MemorizeVerse get _currentVerse => widget.verses[_currentIndex];

  void _playCurrent() {
    if (widget.verses.isEmpty) return;
    final verse = _currentVerse;
    final path = verse.localVoicePath ?? verse.audioUrl;
    if (path != null && path.isNotEmpty) {
      _audio.play(path);
    }
  }

  void _next() {
    if (_currentIndex + 1 < widget.verses.length) {
      setState(() {
        _currentIndex++;
        _currentRepeatPlayed = 0;
      });
      _playCurrent();
    } else {
      // Finished all playlist
      _audio.stopPlayback();
    }
  }

  void _prev() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _currentRepeatPlayed = 0;
      });
      _playCurrent();
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.verses.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('مشغل الفويس')),
        body: const Center(
          child: Text('لا توجد آيات مسجل لها صوت بعد.'),
        ),
      );
    }

    final verse = _currentVerse;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مشغل الآيات الصوتي'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'تكرار كل آية',
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.repeat_rounded, size: 20),
                const SizedBox(width: 4),
                Text('${_repeatCount}x',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            onSelected: (val) {
              setState(() {
                _repeatCount = val;
                _currentRepeatPlayed = 0;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 1, child: Text('تشغيل مرة واحدة (1x)')),
              const PopupMenuItem(value: 2, child: Text('تكرار مرتين (2x)')),
              const PopupMenuItem(value: 3, child: Text('تكرار 3 مرات (3x)')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Upper Player Card
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    verse.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: Text(
                          verse.verse,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Progress slider
                  ValueListenableBuilder<Duration>(
                    valueListenable: _audio.currentPosition,
                    builder: (context, pos, _) {
                      return ValueListenableBuilder<Duration>(
                        valueListenable: _audio.totalDuration,
                        builder: (context, dur, _) {
                          final maxSec =
                              dur.inSeconds > 0 ? dur.inSeconds.toDouble() : 1.0;
                          final curSec = pos.inSeconds
                              .toDouble()
                              .clamp(0.0, maxSec);

                          return Column(
                            children: [
                              Slider(
                                value: curSec,
                                max: maxSec,
                                onChanged: (val) {
                                  _audio.seek(Duration(seconds: val.toInt()));
                                },
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_formatDuration(pos),
                                        style: const TextStyle(fontSize: 12)),
                                    Text(_formatDuration(dur),
                                        style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 32,
                        icon: const Icon(Icons.skip_next_rounded),
                        onPressed: _currentIndex > 0 ? _prev : null,
                      ),
                      const SizedBox(width: 16),
                      ValueListenableBuilder<AudioPlayState>(
                        valueListenable: _audio.playState,
                        builder: (context, state, _) {
                          final isPlaying = state == AudioPlayState.playing;
                          return IconButton.filled(
                            iconSize: 44,
                            icon: Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            onPressed: () {
                              if (isPlaying) {
                                _audio.pausePlayback();
                              } else {
                                _playCurrent();
                              }
                            },
                          );
                        },
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        iconSize: 32,
                        icon: const Icon(Icons.skip_previous_rounded),
                        onPressed: _currentIndex + 1 < widget.verses.length
                            ? _next
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Playlist Queue below
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.playlist_play_rounded, size: 20),
                SizedBox(width: 8),
                Text(
                  'قائمة التشغيل:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: ListView.builder(
              itemCount: widget.verses.length,
              itemBuilder: (context, i) {
                final v = widget.verses[i];
                final isCurrent = i == _currentIndex;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isCurrent
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    foregroundColor: isCurrent
                        ? Colors.white
                        : theme.colorScheme.onSurface,
                    child: Text('${i + 1}'),
                  ),
                  title: Text(
                    v.title,
                    style: TextStyle(
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    v.verse,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isCurrent
                      ? const Icon(Icons.equalizer, color: Colors.blue)
                      : null,
                  onTap: () {
                    setState(() {
                      _currentIndex = i;
                      _currentRepeatPlayed = 0;
                    });
                    _playCurrent();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
