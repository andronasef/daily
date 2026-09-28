import 'dart:convert';

enum ReviewRating {
  again,
  hard,
  good,
  easy,
}

enum SrsState {
  newCard,
  learning,
  review,
  mastered;

  String get label {
    switch (this) {
      case SrsState.newCard:
        return 'جديدة';
      case SrsState.learning:
        return 'جاري الحفظ';
      case SrsState.review:
        return 'مراجعة';
      case SrsState.mastered:
        return 'تم الحفظ';
    }
  }

  static SrsState fromString(String val) {
    switch (val) {
      case 'learning':
        return SrsState.learning;
      case 'review':
        return SrsState.review;
      case 'mastered':
        return SrsState.mastered;
      case 'new':
      default:
        return SrsState.newCard;
    }
  }

  String get wireValue {
    switch (this) {
      case SrsState.newCard:
        return 'new';
      case SrsState.learning:
        return 'learning';
      case SrsState.review:
        return 'review';
      case SrsState.mastered:
        return 'mastered';
    }
  }
}

class VoiceRecording {
  const VoiceRecording({
    required this.id,
    required this.localPath,
    required this.recordedAt,
    this.durationSeconds = 0,
    this.sanityAssetId,
    this.sanityUrl,
    this.title,
  });

  final String id;
  final String localPath;
  final DateTime recordedAt;
  final int durationSeconds;
  final String? sanityAssetId;
  final String? sanityUrl;
  final String? title;

  bool get isUploadedToSanity =>
      sanityUrl != null && sanityUrl!.trim().isNotEmpty;

  VoiceRecording copyWith({
    String? id,
    String? localPath,
    DateTime? recordedAt,
    int? durationSeconds,
    String? sanityAssetId,
    String? sanityUrl,
    String? title,
  }) {
    return VoiceRecording(
      id: id ?? this.id,
      localPath: localPath ?? this.localPath,
      recordedAt: recordedAt ?? this.recordedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      sanityAssetId: sanityAssetId ?? this.sanityAssetId,
      sanityUrl: sanityUrl ?? this.sanityUrl,
      title: title ?? this.title,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'localPath': localPath,
      'recordedAt': recordedAt.toIso8601String(),
      'durationSeconds': durationSeconds,
      'sanityAssetId': sanityAssetId,
      'sanityUrl': sanityUrl,
      'title': title,
    };
  }

  factory VoiceRecording.fromMap(Map<String, dynamic> map) {
    return VoiceRecording(
      id: (map['id'] ?? '').toString(),
      localPath: (map['localPath'] ?? '').toString(),
      recordedAt: DateTime.tryParse(map['recordedAt']?.toString() ?? '') ??
          DateTime.now(),
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      sanityAssetId: map['sanityAssetId']?.toString(),
      sanityUrl: map['sanityUrl']?.toString(),
      title: map['title']?.toString(),
    );
  }
}

class MemorizeVerse {
  MemorizeVerse({
    required this.id,
    required this.title,
    required this.verse,
    this.category,
    this.translation = '',
    this.audioUrl,
    this.localVoicePath,
    this.recordings = const [],
    this.source = 'sanity',
    required this.createdAt,
    this.state = SrsState.newCard,
    this.repetition = 0,
    this.interval = 0,
    this.easeFactor = 2.5,
    required this.dueDate,
    this.lastReviewedAt,
    this.lapses = 0,
    this.streak = 0,
  });

  final String id;
  final String title;
  final String verse;
  final String? category;
  final String translation;
  final String? audioUrl;
  final String? localVoicePath;
  final List<VoiceRecording> recordings;
  final String source;
  final DateTime createdAt;

  // Anki SRS fields
  final SrsState state;
  final int repetition;
  final int interval;
  final double easeFactor;
  final DateTime dueDate;
  final DateTime? lastReviewedAt;
  final int lapses;
  final int streak;

  bool get isDue {
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return dueDate.isBefore(endOfToday) || state == SrsState.newCard;
  }

  bool get hasVoice =>
      recordings.isNotEmpty ||
      (localVoicePath != null && localVoicePath!.isNotEmpty) ||
      (audioUrl != null && audioUrl!.isNotEmpty);

  List<String> get words => verse
      .replaceAll(RegExp(r'[\r\n]+'), ' ')
      .split(' ')
      .map((w) => w.trim())
      .where((w) => w.isNotEmpty)
      .toList();

  MemorizeVerse copyWith({
    String? id,
    String? title,
    String? verse,
    String? category,
    String? translation,
    String? audioUrl,
    String? localVoicePath,
    List<VoiceRecording>? recordings,
    String? source,
    DateTime? createdAt,
    SrsState? state,
    int? repetition,
    int? interval,
    double? easeFactor,
    DateTime? dueDate,
    DateTime? lastReviewedAt,
    int? lapses,
    int? streak,
  }) {
    return MemorizeVerse(
      id: id ?? this.id,
      title: title ?? this.title,
      verse: verse ?? this.verse,
      category: category ?? this.category,
      translation: translation ?? this.translation,
      audioUrl: audioUrl ?? this.audioUrl,
      localVoicePath: localVoicePath ?? this.localVoicePath,
      recordings: recordings ?? this.recordings,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      state: state ?? this.state,
      repetition: repetition ?? this.repetition,
      interval: interval ?? this.interval,
      easeFactor: easeFactor ?? this.easeFactor,
      dueDate: dueDate ?? this.dueDate,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      lapses: lapses ?? this.lapses,
      streak: streak ?? this.streak,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'verse': verse,
      'category': category,
      'translation': translation,
      'audio_url': audioUrl,
      'local_voice_path': recordings.isNotEmpty
          ? recordings.last.localPath
          : localVoicePath,
      'recordings_json':
          jsonEncode(recordings.map((r) => r.toMap()).toList()),
      'source': source,
      'created_at': createdAt.toIso8601String(),
      'state': state.wireValue,
      'repetition': repetition,
      'interval': interval,
      'ease_factor': easeFactor,
      'due_date': dueDate.toIso8601String(),
      'last_reviewed_at': lastReviewedAt?.toIso8601String(),
      'lapses': lapses,
      'streak': streak,
    };
  }

  factory MemorizeVerse.fromMap(Map<String, dynamic> map) {
    List<VoiceRecording> recList = [];
    if (map['recordings_json'] != null &&
        map['recordings_json'].toString().trim().isNotEmpty) {
      try {
        final decoded =
            jsonDecode(map['recordings_json'].toString()) as List;
        recList = decoded
            .map((e) => VoiceRecording.fromMap(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    final legacyPath = map['local_voice_path'] as String?;
    if (recList.isEmpty && legacyPath != null && legacyPath.isNotEmpty) {
      recList.add(VoiceRecording(
        id: 'rec_legacy_${map['id']}',
        localPath: legacyPath,
        recordedAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
            DateTime.now(),
        title: 'تسجيل سابق',
      ));
    }

    return MemorizeVerse(
      id: map['id'] as String,
      title: (map['title'] ?? '') as String,
      verse: (map['verse'] ?? '') as String,
      category: map['category'] as String?,
      translation: (map['translation'] ?? '') as String,
      audioUrl: map['audio_url'] as String?,
      localVoicePath: legacyPath,
      recordings: recList,
      source: (map['source'] ?? 'sanity') as String,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      state: SrsState.fromString((map['state'] ?? 'new') as String),
      repetition: (map['repetition'] as num?)?.toInt() ?? 0,
      interval: (map['interval'] as num?)?.toInt() ?? 0,
      easeFactor: (map['ease_factor'] as num?)?.toDouble() ?? 2.5,
      dueDate: DateTime.tryParse(map['due_date']?.toString() ?? '') ??
          DateTime.now(),
      lastReviewedAt: map['last_reviewed_at'] != null
          ? DateTime.tryParse(map['last_reviewed_at'].toString())
          : null,
      lapses: (map['lapses'] as num?)?.toInt() ?? 0,
      streak: (map['streak'] as num?)?.toInt() ?? 0,
    );
  }
}

class MemorizeStats {
  const MemorizeStats({
    required this.total,
    required this.dueCount,
    required this.learningCount,
    required this.masteredCount,
    required this.streakDays,
  });

  final int total;
  final int dueCount;
  final int learningCount;
  final int masteredCount;
  final int streakDays;
}
