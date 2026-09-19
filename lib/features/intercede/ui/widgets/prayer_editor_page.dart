import 'package:flutter/material.dart';

import '../../data/models.dart';

/// A page, not a dialog: prayers are sentences, not labels, and the cramped
/// single-line field made you edit a paragraph through a slot.
class PrayerEditorPage extends StatefulWidget {
  const PrayerEditorPage({
    super.key,
    required this.heading,
    this.initialText = '',
    this.pickFrom,
    this.initialEntityId,
  });

  final String heading;
  final String initialText;

  /// When present the editor also asks who the prayer is for.
  final List<Entity>? pickFrom;
  final String? initialEntityId;

  @override
  State<PrayerEditorPage> createState() => _PrayerEditorPageState();
}

class PrayerDraft {
  PrayerDraft(this.text, this.entityId);
  final String text;
  final String? entityId;
}

class _PrayerEditorPageState extends State<PrayerEditorPage> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initialText,
  );
  late String? _entityId = widget.initialEntityId ?? widget.pickFrom?.first.id;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(PrayerDraft(text, _entityId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.heading),
        actions: [
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _c,
            builder: (context, value, _) => TextButton(
              onPressed: value.text.trim().isEmpty ? null : _save,
              child: const Text('حفظ'),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.pickFrom != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: DropdownButtonFormField<String>(
                  initialValue: _entityId,
                  decoration: const InputDecoration(
                    labelText: 'لمين؟',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    for (final e in widget.pickFrom!)
                      DropdownMenuItem(value: e.id, child: Text(e.name)),
                  ],
                  onChanged: (v) => setState(() => _entityId = v ?? _entityId),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: TextField(
                  controller: _c,
                  autofocus: true,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: theme.textTheme.titleMedium?.copyWith(height: 1.6),
                  decoration: InputDecoration(
                    hintText: 'بتصلي لإيه؟',
                    border: InputBorder.none,
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
