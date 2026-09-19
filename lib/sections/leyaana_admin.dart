import 'package:flutter/material.dart';
import '../leyaana_content.dart';

/// Add / edit / delete ليا انا content. Writes go straight to Sanity via the
/// mutate API (token in leyaana_content.dart). Mirrors leyaana's ContentManager.
class LeyaanaAdminScreen extends StatelessWidget {
  const LeyaanaAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!leyaanaCanEdit) {
      return Scaffold(
        appBar: AppBar(title: const Text('إدارة المحتوى')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'علشان تعدّل، حط Sanity write token في الإعدادات.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة المحتوى'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'الآيات'),
              Tab(text: 'أسماء الله'),
              Tab(text: 'البركات'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _ManagerTab(type: 'verse'),
            _ManagerTab(type: 'godName'),
            _ManagerTab(type: 'heavenlyBlessing'),
          ],
        ),
      ),
    );
  }
}

class _Field {
  const _Field(this.key, this.label, {this.required = false, this.multiline = false, this.number = false});
  final String key;
  final String label;
  final bool required;
  final bool multiline;
  final bool number;
}

const _fieldsByType = <String, List<_Field>>{
  'verse': [
    _Field('title', 'العنوان (اختياري)'),
    _Field('verse', 'نص الآية', required: true, multiline: true),
    _Field('order', 'الترتيب', number: true),
  ],
  'godName': [
    _Field('name', 'الاسم', required: true),
    _Field('mean', 'المعنى'),
    _Field('content', 'المحتوى', multiline: true),
    _Field('order', 'الترتيب', number: true),
  ],
  'heavenlyBlessing': [
    _Field('name', 'اسم البركة', required: true),
    _Field('mean', 'الآية أو الملخص'),
    _Field('content', 'المحتوى', multiline: true),
    _Field('order', 'الترتيب', number: true),
  ],
};

class _ManagerTab extends StatefulWidget {
  const _ManagerTab({required this.type});
  final String type;

  @override
  State<_ManagerTab> createState() => _ManagerTabState();
}

class _ManagerTabState extends State<_ManagerTab> {
  List<_Field> get _fields => _fieldsByType[widget.type]!;
  final _controllers = <String, TextEditingController>{};
  String? _editingId;
  bool _busy = false;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    for (final f in _fields) {
      _controllers[f.key] = TextEditingController();
    }
    _future = fetchRawForEdit(widget.type);
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = fetchRawForEdit(widget.type);
    });
  }

  void _resetForm() {
    for (final c in _controllers.values) {
      c.clear();
    }
    setState(() => _editingId = null);
  }

  void _startEdit(Map<String, dynamic> item) {
    for (final f in _fields) {
      _controllers[f.key]!.text = (item[f.key] ?? '').toString();
    }
    setState(() => _editingId = item['_id'] as String?);
  }

  Map<String, dynamic> _buildPayload() {
    final data = <String, dynamic>{};
    for (final f in _fields) {
      final raw = _controllers[f.key]!.text.trim();
      if (f.number) {
        data[f.key] = int.tryParse(raw) ?? 0;
      } else if (raw.isNotEmpty) {
        data[f.key] = raw;
      }
    }
    return data;
  }

  Future<void> _submit() async {
    // Required-field check.
    for (final f in _fields) {
      if (f.required && _controllers[f.key]!.text.trim().isEmpty) {
        _snack('${f.label} مطلوب.');
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final payload = _buildPayload();
      if (_editingId != null) {
        await updateDoc(_editingId!, payload);
        _snack('تم التحديث.');
      } else {
        await createDoc(widget.type, payload);
        _snack('تمت الإضافة.');
      }
      _resetForm();
      _reload();
    } catch (e) {
      _snack('خطأ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: const Text('متأكد إنك عايز تحذف العنصر ده؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لأ')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('احذف')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await deleteDoc(id);
      if (_editingId == id) _resetForm();
      _snack('تم الحذف.');
      _reload();
    } catch (e) {
      _snack('خطأ: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _titleOf(Map<String, dynamic> item) {
    final s = (item['name'] ?? item['title'] ?? item['verse'] ?? 'عنصر').toString();
    return s.length > 40 ? '${s.substring(0, 40)}…' : s;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Form
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in _fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _controllers[f.key],
                      maxLines: f.multiline ? null : 1,
                      minLines: f.multiline ? 4 : 1,
                      keyboardType: f.number ? TextInputType.number : TextInputType.multiline,
                      decoration: InputDecoration(
                        labelText: f.label,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(_editingId != null ? 'حفظ التعديل' : 'إضافة'),
                      ),
                    ),
                    if (_editingId != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _busy ? null : _resetForm,
                        child: const Text('إلغاء'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // List
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return Text('تعذر التحميل: ${snap.error}');
            }
            final items = snap.data ?? const [];
            if (items.isEmpty) return const Text('لا توجد عناصر.');
            return Column(
              children: [
                for (final item in items)
                  Card(
                    child: ListTile(
                      title: Text(_titleOf(item),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        (item['mean'] ?? item['content'] ?? item['title'] ?? '').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: _busy ? null : () => _startEdit(item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            color: Theme.of(context).colorScheme.error,
                            onPressed: _busy
                                ? null
                                : () => _delete(item['_id'] as String),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
