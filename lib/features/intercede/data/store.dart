import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/sanity/client.dart';
import '../../../core/settings.dart';
import 'models.dart';
import 'repository.dart';

const _cacheKey = 'intercede:entities';
const _outboxKey = 'intercede:outbox';

/// Offline-first store for تشفع. Holds the raw Sanity payload, applies every
/// mutation to it locally before it ever reaches the network, and keeps the
/// unsent mutations in an outbox on disk.
///
/// ponytail: the Sanity mutation JSON is both the optimistic update and the
/// queue entry — one apply path, no copyWith/toJson on the models. Ceiling:
/// [applyMutation] only understands the operations this app emits.
class IntercedeStore {
  IntercedeStore._();
  static final instance = IntercedeStore._();

  /// null until the first load finishes; empty list is a legitimate value.
  final entities = ValueNotifier<List<Entity>?>(null);

  /// True when the last refresh failed and there is nothing cached to show.
  final failed = ValueNotifier<bool>(false);

  List<Map<String, dynamic>> _json = [];
  List<Map<String, dynamic>> _outbox = [];
  bool _flushing = false;

  bool get hasPending => _outbox.isNotEmpty;

  /// Reads both caches, paints them, then refreshes in the background.
  Future<void> load() async {
    _json = _decode(Settings.instance.getCache(_cacheKey));
    _outbox = _decode(Settings.instance.getCache(_outboxKey));
    if (_json.isNotEmpty) _publish();
    await refresh();
  }

  /// Pulls from Sanity, replays anything still queued over the result, and
  /// republishes. Never throws — a failed refresh just leaves the cache up.
  Future<void> refresh() async {
    await flush();
    try {
      final fresh = await fetchEntitiesRaw();
      _json = fresh;
      for (final m in _outbox) {
        applyMutation(_json, m);
      }
      failed.value = false;
      await _save();
      _publish();
    } catch (_) {
      failed.value = _json.isEmpty;
    }
  }

  /// Applies [mutations] locally, queues them, and kicks off a flush. Returns
  /// as soon as the local state is saved, so callers never wait on the network.
  Future<void> apply(List<Map<String, dynamic>> mutations) async {
    for (final m in mutations) {
      applyMutation(_json, m);
      _outbox.add(m);
    }
    await _save();
    _publish();
    unawaited(flush());
  }

  /// Sends the outbox head-first, stopping at the first failure so ordering
  /// (create before patch) holds. Silent: failures stay queued.
  Future<void> flush() async {
    if (_flushing || _outbox.isEmpty || !sanityCanWrite) return;
    _flushing = true;
    try {
      while (_outbox.isNotEmpty) {
        try {
          await sanityMutate([_outbox.first]);
        } catch (_) {
          break;
        }
        _outbox.removeAt(0);
        await _save();
      }
    } finally {
      _flushing = false;
    }
  }

  // ---- internals ------------------------------------------------------------

  void _publish() {
    entities.value = parseEntities(_json);
    if (_json.isNotEmpty) failed.value = false;
  }

  Future<void> _save() async {
    await Settings.instance.setCache(_cacheKey, jsonEncode(_json));
    await Settings.instance.setCache(_outboxKey, jsonEncode(_outbox));
  }

  static List<Map<String, dynamic>> _decode(String? raw) {
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
}

// ---- local replay of a Sanity mutation --------------------------------------

/// Applies one Sanity mutation to [json] — the raw `_query` payload, i.e. a
/// list of entity maps each holding a nested `prayers` list. Understands only
/// what this app emits: create/createIfNotExists, delete, and patch with
/// set / unset / setIfMissing / insert-after-logs[-1].
void applyMutation(List<Map<String, dynamic>> json, Map<String, dynamic> m) {
  final create =
      (m['createIfNotExists'] ?? m['create']) as Map<String, dynamic>?;
  if (create != null) return _applyCreate(json, create);

  final del = m['delete'] as Map<String, dynamic>?;
  if (del != null) return _applyDelete(json, del['id'] as String);

  final patch = m['patch'] as Map<String, dynamic>?;
  if (patch != null) _applyPatch(json, patch);
}

/// The entity map with [id], or the prayer map with that id, or null.
Map<String, dynamic>? _findDoc(List<Map<String, dynamic>> json, String id) {
  for (final e in json) {
    if (e['_id'] == id) return e;
    for (final p in _prayersOf(e)) {
      if (p['_id'] == id) return p;
    }
  }
  return null;
}

List<Map<String, dynamic>> _prayersOf(Map<String, dynamic> entity) {
  final raw = entity['prayers'];
  if (raw is! List) return [];
  return raw.whereType<Map<String, dynamic>>().toList();
}

void _applyCreate(List<Map<String, dynamic>> json, Map<String, dynamic> doc) {
  final id = doc['_id'] as String?;
  if (id == null || _findDoc(json, id) != null) return;
  if (doc['_type'] == 'intercedeEntity') {
    json.add({...doc, 'prayers': <Map<String, dynamic>>[]});
    return;
  }
  final ref = (doc['entity'] as Map?)?['_ref'];
  for (final e in json) {
    if (e['_id'] != ref) continue;
    e['prayers'] = [..._prayersOf(e), Map<String, dynamic>.from(doc)];
    return;
  }
}

void _applyDelete(List<Map<String, dynamic>> json, String id) {
  json.removeWhere((e) => e['_id'] == id);
  for (final e in json) {
    e['prayers'] = _prayersOf(e).where((p) => p['_id'] != id).toList();
  }
}

void _applyPatch(List<Map<String, dynamic>> json, Map<String, dynamic> patch) {
  final doc = _findDoc(json, patch['id'] as String);
  if (doc == null) return;

  final setIfMissing = patch['setIfMissing'] as Map<String, dynamic>?;
  if (setIfMissing != null) {
    setIfMissing.forEach((k, v) => doc.putIfAbsent(k, () => v));
  }
  final set = patch['set'] as Map<String, dynamic>?;
  if (set != null) doc.addAll(set);

  for (final k in (patch['unset'] as List? ?? const [])) {
    doc.remove(k);
  }

  // Only `insert after logs[-1]` is ever emitted — append is the whole story.
  final insert = patch['insert'] as Map<String, dynamic>?;
  if (insert != null) {
    final field = (insert['after'] ?? '').toString().split('[').first;
    final current = doc[field];
    doc[field] = [
      if (current is List) ...current,
      ...(insert['items'] as List? ?? const []),
    ];
  }
}
