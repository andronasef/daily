import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import 'prayer_editor_page.dart';

/// The "⋯" sheet on a [PrayerCard]: edit, complete or delete one prayer.
/// Shared by the daily list and a person's page; [onChanged] reloads the caller.
void showPrayerMenu(BuildContext context, Prayer p, VoidCallback onChanged) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) {
      final error = Theme.of(ctx).colorScheme.error;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('تعديل'),
              onTap: () {
                Navigator.pop(ctx);
                _edit(context, p, onChanged);
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('إكمال'),
              onTap: () {
                Navigator.pop(ctx);
                _complete(context, p, onChanged);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: error),
              title: Text('حذف', style: TextStyle(color: error)),
              onTap: () {
                Navigator.pop(ctx);
                _delete(context, p, onChanged);
              },
            ),
          ],
        ),
      );
    },
  );
}

void _snack(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

Future<void> _edit(BuildContext context, Prayer p, VoidCallback done) async {
  final draft = await Navigator.of(context).push<PrayerDraft>(
    MaterialPageRoute(
      builder: (_) =>
          PrayerEditorPage(heading: 'تعديل الصلاة', initialText: p.title),
    ),
  );
  if (draft == null) return;
  try {
    await editPrayer(p.id, draft.text);
    done();
  } catch (e) {
    if (context.mounted) _snack(context, 'خطأ: $e');
  }
}

Future<void> _complete(
  BuildContext context,
  Prayer p,
  VoidCallback done,
) async {
  final outcomeC = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('اتستجابت؟ إيه اللي حصل؟'),
      content: TextField(
        controller: outcomeC,
        decoration: const InputDecoration(
          labelText: 'النتيجة (اختياري)',
          border: OutlineInputBorder(),
        ),
        maxLines: 3,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('إكمال'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await completePrayer(
      p.id,
      outcome: outcomeC.text.trim().isEmpty ? null : outcomeC.text.trim(),
    );
    done();
  } catch (e) {
    if (context.mounted) _snack(context, 'خطأ: $e');
  }
}

Future<void> _delete(BuildContext context, Prayer p, VoidCallback done) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text('متأكد إنك عايز تحذف "${p.title}"؟'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('لأ'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('احذف'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await deletePrayer(p.id);
    done();
  } catch (e) {
    if (context.mounted) _snack(context, 'خطأ: $e');
  }
}
