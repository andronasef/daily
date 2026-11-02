import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/sanity/client.dart';
import '../../../core/settings.dart';
import 'models.dart';
import 'repository.dart';
import 'widget_bridge.dart';

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
  @visibleForTesting
  IntercedeStore.forTesting({
    required this.readCache,
    required this.writeCache,
    required this.fetch,
    required this.send,
    required this.canWrite,
    required IntercedeWidgetBridge bridge,
  }) : _bridge = bridge;

  String? Function(String)? readCache;
  Future<void> Function(String, String)? writeCache;
  Future<List<Map<String, dynamic>>> Function()? fetch;
  Future<void> Function(List<Map<String, dynamic>>)? send;
  bool Function()? canWrite;
  IntercedeWidgetBridge _bridge = IntercedeWidgetBridge();
  Future<void> _saving = Future.value();
  Future<void>? _consuming;
  bool _hasData = false;
  bool _authoritative = false;

  String? _read(String key) => (readCache ?? Settings.instance.getCache)(key);
  Future<void> _write(String key, String value) =>
      (writeCache ?? Settings.instance.setCache)(key, value);
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
    final cache = _read(_cacheKey);
    _json = _decode(cache);
    _hasData = cache != null && _validCache(cache);
    _outbox = _decode(_read(_outboxKey));
    for (final mutation in _outbox) {
      applyMutation(_json, mutation);
    }
    _hasData = _hasData || _json.isNotEmpty;
    await consumeWidgetTaps();
    if (_hasData) _publish();
    await refresh();
  }

  /// Pulls from Sanity, replays anything still queued over the result, and
  /// republishes. Never throws — a failed refresh just leaves the cache up.
  Future<void> refresh() async {
    await flush();
    try {
      final fresh = await (fetch ?? fetchEntitiesRaw)();
      _json = fresh;
      _hasData = true;
      _authoritative = true;
      for (final m in _outbox) {
        applyMutation(_json, m);
      }
      failed.value = false;
      await _save();
      await consumeWidgetTaps();
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
    _hasData = true;
    _publish();
    unawaited(flush());
  }

  /// Sends the outbox head-first, stopping at the first failure so ordering
  /// (create before patch) holds. Silent: failures stay queued.
  Future<void> flush() async {
    if (_flushing || _outbox.isEmpty || !(canWrite?.call() ?? sanityCanWrite)) {
      return;
    }
    _flushing = true;
    try {
      while (_outbox.isNotEmpty) {
        try {
          await (send ?? sanityMutate)([_outbox.first]);
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
    if (_hasData || _json.isNotEmpty) unawaited(republish());
    if (_json.isNotEmpty) failed.value = false;
  }

  Future<void> republish() async {
    try {
      await _writeWidget();
    } catch (_) {
      // Widget failure must never roll back a locally saved prayer.
    }
  }

  Future<void> _writeWidget() => _bridge.publish(
    intercedeWidgetSnapshot(
      parseEntities(_json),
      sort: PrayerSort.fromName(Settings.instance.intercedeSort),
    ),
  );

  Future<void> onResume() async {
    await consumeWidgetTaps();
    if (_hasData) {
      _publish();
      await republish();
    }
    await flush();
  }

  Future<void> consumeWidgetTaps() =>
      _consuming ??= _consumeWidgetTaps().whenComplete(() => _consuming = null);

  Future<void> _consumeWidgetTaps() async {
    if (!_hasData) return;
    try {
      final taps = await _bridge.peek();
      final ack = <String>[];
      for (final tap in taps) {
        final exists = _json.any(
          (e) => _prayersOf(e).any((p) => p['_id'] == tap.prayerId),
        );
        if (!exists) {
          if (_authoritative) ack.add(tap.key);
          continue;
        }
        final alreadyQueued = _outbox.any((m) {
          final insert = (m['patch'] as Map?)?['insert'] as Map?;
          return (insert?['items'] as List? ?? []).any(
            (item) => item is Map && item['_key'] == tap.key,
          );
        });
        if (!alreadyQueued) {
          final mutation = prayerLogMutation(
            tap.prayerId,
            at: tap.at,
            key: tap.key,
          );
          applyMutation(_json, mutation);
          _outbox.add(mutation);
        }
        ack.add(tap.key);
      }
      if (ack.isEmpty) return;
      await _save();
      _publish();
      await _writeWidget();
      await _bridge.ack(ack);
    } catch (_) {
      // No ack on save/channel failure; stable event keys make replay safe.
    }
  }

  Future<void> _save() {
    final outbox = jsonEncode(_outbox), entities = jsonEncode(_json);
    final next = _saving.then((_) async {
      // A crash between writes replays the durable outbox on the next load.
      await _write(_outboxKey, outbox);
      await _write(_cacheKey, entities);
    });
    _saving = next.catchError((Object _) {});
    return next;
  }

  static bool _validCache(String raw) {
    try {
      return jsonDecode(raw) is List;
    } catch (_) {
      return false;
    }
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
    final items = <dynamic>[if (current is List) ...current];
    final keys = {
      for (final item in items)
        if (item is Map && item['_key'] != null) item['_key'],
    };
    for (final item in insert['items'] as List? ?? const []) {
      final key = item is Map ? item['_key'] : null;
      if (key == null || keys.add(key)) items.add(item);
    }
    doc[field] = items;
  }
}
