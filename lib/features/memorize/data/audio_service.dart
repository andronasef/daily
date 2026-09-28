import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum AudioPlayState { stopped, playing, paused }

/// Manages recording user voice notes and playing audio (both local and remote).
class AudioService {
  AudioService._() {
    _initPlayer();
  }
  static final AudioService instance = AudioService._();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  final isRecording = ValueNotifier<bool>(false);
  final playState = ValueNotifier<AudioPlayState>(AudioPlayState.stopped);
  final currentPlayingUri = ValueNotifier<String?>(null);
  final currentPosition = ValueNotifier<Duration>(Duration.zero);
  final totalDuration = ValueNotifier<Duration>(Duration.zero);

  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;

  void _initPlayer() {
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      switch (state) {
        case PlayerState.playing:
          playState.value = AudioPlayState.playing;
          break;
        case PlayerState.paused:
          playState.value = AudioPlayState.paused;
          break;
        case PlayerState.stopped:
        case PlayerState.completed:
          playState.value = AudioPlayState.stopped;
          currentPlayingUri.value = null;
          currentPosition.value = Duration.zero;
          break;
        case PlayerState.disposed:
          break;
      }
    });

    _posSub = _player.onPositionChanged.listen((pos) {
      currentPosition.value = pos;
    });

    _durSub = _player.onDurationChanged.listen((dur) {
      totalDuration.value = dur;
    });
  }

  /// Directory where local user voice recordings are stored.
  Future<Directory> _getVoicesDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final voicesDir = Directory(p.join(appDir.path, 'verses_voices'));
    if (!await voicesDir.exists()) {
      await voicesDir.create(recursive: true);
    }
    return voicesDir;
  }

  /// Constructs the path for a given verse's voice recording.
  Future<String> getRecordingPathForVerse(String verseId) async {
    final dir = await _getVoicesDirectory();
    final sanitizedId = verseId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return p.join(dir.path, 'voice_$sanitizedId.m4a');
  }

  /// Checks if microphone permission is granted.
  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  /// Starts recording audio for [verseId]. Returns the target file path.
  Future<String?> startRecording(String verseId) async {
    try {
      if (!await _recorder.hasPermission()) {
        return null;
      }

      // Stop any active playback
      await stopPlayback();

      final filePath = await getRecordingPathForVerse(verseId);
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      isRecording.value = true;
      return filePath;
    } catch (e) {
      debugPrint('Error starting recording: $e');
      isRecording.value = false;
      return null;
    }
  }

  /// Stops recording and returns the path to the recorded audio file.
  Future<String?> stopRecording() async {
    try {
      if (!await _recorder.isRecording()) {
        isRecording.value = false;
        return null;
      }

      final path = await _recorder.stop();
      isRecording.value = false;
      return path;
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      isRecording.value = false;
      return null;
    }
  }

  /// Plays a local audio file or remote URL.
  Future<void> play(String pathOrUrl) async {
    try {
      if (currentPlayingUri.value == pathOrUrl &&
          playState.value == AudioPlayState.paused) {
        await _player.resume();
        return;
      }

      await stopPlayback();
      currentPlayingUri.value = pathOrUrl;

      if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
        await _player.play(UrlSource(pathOrUrl));
      } else {
        await _player.play(DeviceFileSource(pathOrUrl));
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
      playState.value = AudioPlayState.stopped;
      currentPlayingUri.value = null;
    }
  }

  Future<void> pausePlayback() async {
    await _player.pause();
  }

  Future<void> resumePlayback() async {
    await _player.resume();
  }

  Future<void> stopPlayback() async {
    await _player.stop();
    playState.value = AudioPlayState.stopped;
    currentPlayingUri.value = null;
    currentPosition.value = Duration.zero;
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Deletes a local voice recording file.
  Future<void> deleteRecording(String? filePath) async {
    if (filePath == null || filePath.isEmpty) return;
    try {
      if (currentPlayingUri.value == filePath) {
        await stopPlayback();
      }
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting recording file: $e');
    }
  }

  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _player.dispose();
    _recorder.dispose();
  }
}
