import 'package:flutter/material.dart';
import '../data/memorize_db.dart';
import '../data/memorize_models.dart';
import '../data/memorize_repository.dart';
import 'add_verse_sheet.dart';
import 'audio_playlist_screen.dart';
import 'practice/practice_flow_screen.dart';
import 'widgets/srs_stat_card.dart';
import 'widgets/verse_item_tile.dart';

class MemorizeScreen extends StatefulWidget {
  const MemorizeScreen({super.key});

  @override
  State<MemorizeScreen> createState() => _MemorizeScreenState();
}

class _MemorizeScreenState extends State<MemorizeScreen> {
  final _repo = MemorizeRepository.instance;

  List<MemorizeVerse> _allVerses = [];
  List<MemorizeVerse> _filteredVerses = [];
  MemorizeStats _stats = const MemorizeStats(
    total: 0,
    dueCount: 0,
    learningCount: 0,
    masteredCount: 0,
    streakDays: 0,
  );

  bool _loading = true;
  String _searchQuery = '';
  String _selectedFilter = 'all'; // all, due, learning, mastered, voice

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await _repo.ensureInitialized();
    final db = await MemorizeDb.open();
    final verses = await db.getAll();
    final stats = await db.getStats();

    if (mounted) {
      setState(() {
        _allVerses = verses;
        _stats = stats;
        _loading = false;
        _applyFilter();
      });
    }

    // Refresh from Sanity in background
    _repo.refreshFromSanity().then((fresh) async {
      if (mounted) {
        final updatedStats = await db.getStats();
        setState(() {
          _allVerses = fresh;
          _stats = updatedStats;
          _applyFilter();
        });
      }
    });
  }

  Future<void> _onRefresh() async {
    final fresh = await _repo.refreshFromSanity();
    final db = await MemorizeDb.open();
    final stats = await db.getStats();
    if (mounted) {
      setState(() {
        _allVerses = fresh;
        _stats = stats;
        _applyFilter();
      });
    }
  }

  void _applyFilter() {
    var list = _allVerses;

    // Apply text search
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((v) {
        return v.title.toLowerCase().contains(q) ||
            v.verse.toLowerCase().contains(q) ||
            (v.category?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    // Apply status filter
    switch (_selectedFilter) {
      case 'due':
        list = list.where((v) => v.isDue).toList();
        break;
      case 'learning':
        list = list.where((v) => v.state == SrsState.learning).toList();
        break;
      case 'mastered':
        list = list.where((v) => v.state == SrsState.mastered).toList();
        break;
      case 'voice':
        list = list.where((v) => v.hasVoice).toList();
        break;
      case 'all':
      default:
        break;
    }

    setState(() {
      _filteredVerses = list;
    });
  }

  void _startReviewSession() async {
    final dueVerses = _allVerses.where((v) => v.isDue).toList();
    if (dueVerses.isEmpty) return;

    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PracticeFlowScreen(
          verses: dueVerses,
          isSession: true,
        ),
      ),
    );

    if (updated == true || mounted) {
      _loadData();
    }
  }

  void _openPracticeSingle(MemorizeVerse verse) async {
    final index = _allVerses.indexWhere((v) => v.id == verse.id);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PracticeFlowScreen(
          verses: _allVerses,
          initialIndex: index >= 0 ? index : 0,
        ),
      ),
    );
    _loadData();
  }

  void _openAddVerse() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddVerseSheet(),
    );

    if (added == true) {
      _loadData();
    }
  }

  void _openPlaylist([int initialIndex = 0]) {
    final voiceVerses = _allVerses.where((v) => v.hasVoice).toList();
    if (voiceVerses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لم تقم بتسجيل فويس لأي آية بعد. سجّل صوته أولاً! 🎙️'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AudioPlaylistScreen(
          verses: voiceVerses,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('حفظ الآيات'),
        actions: [
          IconButton(
            tooltip: 'مشغل الفويسات المتتابع',
            icon: const Icon(Icons.playlist_play_rounded),
            onPressed: () => _openPlaylist(),
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddVerse,
        icon: const Icon(Icons.add),
        label: const Text('إضافة آية'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildMyDeckTab(),
    );
  }

  Widget _buildMyDeckTab() {
    final voiceCount = _allVerses.where((v) => v.hasVoice).length;

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Anki Statistics Card & Start Session Button
          SrsStatCard(
            stats: _stats,
            onStartReview: _startReviewSession,
          ),
          const SizedBox(height: 16),

          // Search Field
          TextField(
            decoration: InputDecoration(
              hintText: 'ابحث في الآيات المحفوظة...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchQuery = '';
                        _applyFilter();
                      },
                    )
                  : null,
            ),
            onChanged: (val) {
              _searchQuery = val;
              _applyFilter();
            },
          ),
          const SizedBox(height: 12),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('all', 'الكل (${_allVerses.length})'),
                _buildFilterChip('due', 'مستحقة (${_stats.dueCount})'),
                _buildFilterChip('learning', 'قيد الحفظ (${_stats.learningCount})'),
                _buildFilterChip('mastered', 'تم الحفظ (${_stats.masteredCount})'),
                _buildFilterChip('voice', 'مسجل صوت ($voiceCount 🎙️)'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Verses List
          if (_allVerses.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_outlined,
                      size: 60,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'لا توجد آيات للحفظ في Sanity بعد',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'اضغط على زر (+) لإضافة أول آية للحفظ.\nستُحفظ سحابياً في Sanity فوراً وتعمل بدون إنترنت!',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else if (_filteredVerses.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(
                    Icons.filter_list_off_rounded,
                    size: 48,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  const Text('لا توجد آيات مطابقة للبحث أو الفلتر.'),
                ],
              ),
            )
          else
            ..._filteredVerses.map((verse) {
              return VerseItemTile(
                verse: verse,
                onTap: () => _openPracticeSingle(verse),
                onDelete: () async {
                  await _repo.removeVerse(verse.id);
                  _loadData();
                },
                onRecordVoice: () => _openPracticeSingle(verse),
                onToggleMastered: () async {
                  await _repo.toggleMastered(verse);
                  await _loadData();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          verse.state == SrsState.mastered
                              ? 'تمت إعادة الآية إلى التدريب والمراجعة 🔄'
                              : 'مبروك! تم تعليم الآية بأنها "تم حفظها" بنجاح 🎉',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              );
            }),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedFilter == key;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (val) {
          setState(() {
            _selectedFilter = key;
            _applyFilter();
          });
        },
      ),
    );
  }
}

