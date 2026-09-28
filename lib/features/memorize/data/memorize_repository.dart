import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../../core/sanity/client.dart';
import '../../../core/settings.dart';
import '../domain/anki_engine.dart';
import 'audio_service.dart';
import 'memorize_db.dart';
import 'memorize_models.dart';

/// Offline-first repository for Memorization with Sanity as the single source of truth.
/// Follows the same outbox-pattern as `IntercedeStore` and `leyaana`.
class MemorizeRepository {
  MemorizeRepository._();
  static final MemorizeRepository instance = MemorizeRepository._();

  static const _sanityVerseQuery = '''
*[_type == "memorizeVerse"] | order(coalesce(order, 999999) asc, _createdAt asc){
  _id,
  title,
  verse,
  category,
  translation,
  "audioUrl": audioFile.asset->url,
  order,
  isMastered,
  _createdAt
}
''';

  static const _outboxKey = 'memorize:outbox';
  bool _flushing = false;

  /// Ensures database is open, deletes legacy mock starter cards, and syncs from Sanity
  Future<void> ensureInitialized() async {
    final db = await MemorizeDb.open();
    // Wipe any legacy starter cards so only true Sanity data is kept
    await db.deleteStarterVerses();
    // Flush outbox and pull fresh from Sanity in background
    unawaited(refreshFromSanity());
  }

  /// Outbox helper: reads pending mutations
  List<Map<String, dynamic>> _getOutbox() {
    final raw = Settings.instance.getCache(_outboxKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Outbox helper: writes pending mutations
  Future<void> _saveOutbox(List<Map<String, dynamic>> outbox) async {
    await Settings.instance.setCache(_outboxKey, jsonEncode(outbox));
  }

  /// Appends a mutation to the outbox and triggers background flush
  Future<void> _queueMutation(Map<String, dynamic> mutation) async {
    final outbox = _getOutbox()..add(mutation);
    await _saveOutbox(outbox);
    unawaited(flushOutbox());
  }

  /// Flushes pending outbox mutations to Sanity
  Future<void> flushOutbox() async {
    if (_flushing || !sanityCanWrite) return;
    final outbox = _getOutbox();
    if (outbox.isEmpty) return;

    _flushing = true;
    try {
      while (outbox.isNotEmpty) {
        final mutation = outbox.first;
        try {
          await sanityMutate([mutation]);
          outbox.removeAt(0);
          await _saveOutbox(outbox);
        } catch (e) {
          debugPrint('Sanity mutate outbox flush stopped: $e');
          break; // Stop at first error to preserve ordering
        }
      }
    } finally {
      _flushing = false;
    }
  }

  /// Refreshes local store from Sanity:
  /// 1. Flushes outbox
  /// 2. Fetches fresh memorizeVerse docs from Sanity
  /// 3. Reconciles with local SQLite cache while preserving local Anki state and voice takes
  Future<List<MemorizeVerse>> refreshFromSanity() async {
    await flushOutbox();
    await uploadPendingRecordings();

    try {
      final docs = await sanityQuery(_sanityVerseQuery, cdn: false);
      final db = await MemorizeDb.open();
      final localVerses = await db.getAll();
      final localMap = {for (final v in localVerses) v.id: v};
      final outbox = _getOutbox();

      // Collect IDs pending deletion so we don't restore them
      final pendingDeletes = outbox
          .where((m) => m.containsKey('delete'))
          .map((m) => (m['delete'] as Map)['id']?.toString())
          .toSet();

      final updatedList = <MemorizeVerse>[];

      for (final doc in docs) {
        final id = (doc['_id'] ?? '').toString();
        if (id.isEmpty || pendingDeletes.contains(id)) continue;

        final existing = localMap[id];
        final serverMastered = doc['isMastered'] == true;

        final verse = MemorizeVerse(
          id: id,
          title: (doc['title'] ?? '').toString().trim(),
          verse: (doc['verse'] ?? '').toString().trim(),
          category: doc['category']?.toString().trim(),
          translation: (doc['translation'] ?? '').toString().trim(),
          audioUrl: doc['audioUrl']?.toString(),
          localVoicePath: existing?.localVoicePath,
          recordings: existing?.recordings ?? const [],
          source: 'sanity',
          createdAt: DateTime.tryParse(doc['_createdAt']?.toString() ?? '') ??
              (existing?.createdAt ?? DateTime.now()),
          state: existing != null
              ? (serverMastered ? SrsState.mastered : existing.state)
              : (serverMastered ? SrsState.mastered : SrsState.newCard),
          repetition: existing?.repetition ?? 0,
          interval: existing?.interval ?? 0,
          easeFactor: existing?.easeFactor ?? 2.5,
          dueDate: existing?.dueDate ?? DateTime.now(),
          lastReviewedAt: existing?.lastReviewedAt,
          lapses: existing?.lapses ?? 0,
          streak: existing?.streak ?? 0,
        );

        await db.upsert(verse);
        updatedList.add(verse);
      }

      // Check if local verses were deleted on Sanity (and not pending in outbox)
      final serverIds = docs.map((d) => d['_id']?.toString()).toSet();
      final pendingCreates = outbox
          .where((m) =>
              m.containsKey('create') || m.containsKey('createIfNotExists'))
          .map((m) {
            final doc = (m['createIfNotExists'] ?? m['create']) as Map?;
            return doc?['_id']?.toString();
          })
          .toSet();

      for (final local in localVerses) {
        if (!serverIds.contains(local.id) &&
            !pendingCreates.contains(local.id)) {
          await db.delete(local.id);
        }
      }

      return updatedList;
    } catch (e) {
      debugPrint('Error refreshing memorize verses from Sanity: $e');
      final db = await MemorizeDb.open();
      return await db.getAll();
    }
  }

  /// Adds a verse optimistically locally and queues creation in Sanity
  Future<void> addVerse(MemorizeVerse verse) async {
    final db = await MemorizeDb.open();
    await db.upsert(verse);

    // Queue in Sanity outbox
    final docId = verse.id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
    final mutation = {
      'createIfNotExists': {
        '_id': docId,
        '_type': 'memorizeVerse',
        'title': verse.title,
        'verse': verse.verse,
        if (verse.category != null && verse.category!.isNotEmpty)
          'category': verse.category,
        if (verse.translation.isNotEmpty)
          'translation': verse.translation,
        if (verse.state == SrsState.mastered)
          'isMastered': true,
      },
    };

    await _queueMutation(mutation);
  }

  /// Reviews a verse and applies the Anki SM-2 algorithm locally
  Future<MemorizeVerse> reviewVerse({
    required MemorizeVerse verse,
    required ReviewRating rating,
  }) async {
    final updated = AnkiEngine.calculateNextReview(
      verse: verse,
      rating: rating,
    );
    final db = await MemorizeDb.open();
    await db.upsert(updated);
    return updated;
  }

  /// Toggles mastered status optimistically and queues patch in Sanity
  Future<MemorizeVerse> toggleMastered(MemorizeVerse verse) async {
    final db = await MemorizeDb.open();
    final isMastered = verse.state == SrsState.mastered;
    final newIsMastered = !isMastered;
    final updated = verse.copyWith(
      state: newIsMastered ? SrsState.mastered : SrsState.learning,
      dueDate: newIsMastered
          ? DateTime.now().add(const Duration(days: 180))
          : DateTime.now(),
    );
    await db.upsert(updated);

    // Queue patch in Sanity outbox
    final docId = verse.id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
    final patch = {
      'patch': {
        'id': docId,
        'set': {'isMastered': newIsMastered},
      },
    };
    await _queueMutation(patch);

    return updated;
  }

  /// Deletes a verse: cleans up local audio files, deletes from local DB,
  /// and queues delete mutation in Sanity outbox
  Future<void> removeVerse(String verseId) async {
    final db = await MemorizeDb.open();
    final verse = await db.getById(verseId);
    if (verse != null) {
      final audio = AudioService.instance;
      for (final rec in verse.recordings) {
        if (audio.currentPlayingUri.value == rec.localPath ||
            audio.currentPlayingUri.value == rec.sanityUrl) {
          await audio.stopPlayback();
        }
        await audio.deleteRecording(rec.localPath);
      }
      if (verse.localVoicePath != null && verse.localVoicePath!.isNotEmpty) {
        if (audio.currentPlayingUri.value == verse.localVoicePath) {
          await audio.stopPlayback();
        }
        await audio.deleteRecording(verse.localVoicePath!);
      }
    }

    await db.delete(verseId);

    // Queue delete mutation in Sanity
    final docId = verseId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
    await _queueMutation({
      'delete': {'id': docId},
    });
  }

  /// Adds a new audio recording to a verse locally
  Future<void> addRecording(String verseId, VoiceRecording recording) async {
    final db = await MemorizeDb.open();
    await db.addRecordingToVerse(verseId, recording);
  }

  /// Deletes an audio recording from a verse locally (and stops playback)
  Future<void> deleteRecording(String verseId, String recordingId) async {
    final db = await MemorizeDb.open();
    await db.deleteRecordingFromVerse(verseId, recordingId);
  }

  /// Uploads a voice recording to Sanity Assets API, links to the verse,
  /// and updates local database
  Future<VoiceRecording> uploadRecordingToSanity({
    required MemorizeVerse verse,
    required VoiceRecording recording,
  }) async {
    final file = File(recording.localPath);
    if (!file.existsSync()) {
      return recording;
    }

    if (!sanityCanWrite) {
      // Saved locally, will upload once token is configured
      return recording;
    }

    final bytes = await file.readAsBytes();
    final filename = 'voice_${verse.id}_${recording.id}.m4a';

    // 1. Upload file binary to Sanity Assets API
    final assetDoc = await sanityUploadFile(
      bytes: bytes,
      filename: filename,
      contentType: 'audio/m4a',
    );

    final assetId = assetDoc['_id']?.toString() ?? '';
    final cdnUrl = assetDoc['url']?.toString() ?? '';

    final updatedRecording = recording.copyWith(
      sanityAssetId: assetId,
      sanityUrl: cdnUrl,
    );

    // 2. Update local SQLite DB
    final db = await MemorizeDb.open();
    await db.updateRecordingInVerse(verse.id, updatedRecording);

    // 3. Patch verse document in Sanity
    try {
      final docId = verse.id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
      final assetRef = {
        '_type': 'file',
        'asset': {
          '_type': 'reference',
          '_ref': assetId,
        },
      };

      await sanityMutate([
        {
          'patch': {
            'id': docId,
            'set': {
              'audioFile': assetRef,
            },
          },
        },
      ]);
    } catch (e) {
      debugPrint('Warning: Could not link audio to Sanity verse: $e');
    }

    return updatedRecording;
  }

  /// Attempts to upload any local recordings that haven't been uploaded to Sanity yet
  Future<void> uploadPendingRecordings() async {
    if (!sanityCanWrite) return;
    try {
      final db = await MemorizeDb.open();
      final verses = await db.getAll();
      for (final v in verses) {
        for (final r in v.recordings) {
          if (!r.isUploadedToSanity && File(r.localPath).existsSync()) {
            try {
              await uploadRecordingToSanity(verse: v, recording: r);
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }
}
