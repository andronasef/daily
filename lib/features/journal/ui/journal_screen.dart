import 'package:flutter/material.dart';
import '../data/journal_db.dart';

/// Section 4 "مسلم": daily surrender note to the Holy Spirit. Today's editor +
/// history of past days. Autosaves on change and on leaving the screen.
class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مسلم'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'النهارده'),
              Tab(text: 'الأيام اللي فاتت'),
            ],
          ),
        ),
        body: const TabBarView(children: [_Editor(date: null), _History()]),
      ),
    );
  }
}

class _Editor extends StatefulWidget {
  const _Editor({required this.date});

  /// null = today; otherwise edit a specific past day.
  final String? date;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> with AutomaticKeepAliveClientMixin {
  final _controller = TextEditingController();
  late final String _date = widget.date ?? JournalDb.dateKey();
  JournalDb? _db;
  bool _loaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _db = await JournalDb.open();
    _controller.text = await _db!.get(_date);
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _save() async {
    await _db?.save(_date, _controller.text);
  }

  @override
  void dispose() {
    _save();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'سلّم يومك للروح القدس 🕊️',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _date,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: (_) => _save(),
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(height: 1.8, fontSize: 16),
              decoration: const InputDecoration(
                hintText: 'اكتب هنا... "بسلّم لك يومي وحياتي..."',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _History extends StatefulWidget {
  const _History();

  @override
  State<_History> createState() => _HistoryState();
}

class _HistoryState extends State<_History> {
  late Future<List<JournalEntry>> _future = _load();

  Future<List<JournalEntry>> _load() async => (await JournalDb.open()).all();

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<JournalEntry>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snap.data ?? const [];
        if (entries.isEmpty) {
          return const Center(child: Text('لسه مفيش كتابات. ابدأ النهارده 🌱'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final e = entries[i];
            return Card(
              child: ListTile(
                title: Text(
                  e.date,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  e.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(e.date)),
                        body: _Editor(date: e.date),
                      ),
                    ),
                  );
                  _reload();
                },
              ),
            );
          },
        );
      },
    );
  }
}
