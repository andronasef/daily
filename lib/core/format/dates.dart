String relativeDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);

  if (diff.inMinutes < 1) return 'دلوقتي';
  if (diff.inMinutes < 60) return 'من ${diff.inMinutes} دقيقة';
  if (diff.inHours < 24) return 'من ${diff.inHours} ساعة';
  if (diff.inDays == 1) return 'من إمبارح';
  if (diff.inDays < 7) return 'من ${diff.inDays} أيام';
  if (diff.inDays < 30) return 'من ${diff.inDays ~/ 7} أسبوع';
  if (diff.inDays < 365) return 'من ${diff.inDays ~/ 30} شهر';
  return 'من ${diff.inDays ~/ 365} سنة';
}

String durationSpan(DateTime start) {
  final diff = DateTime.now().difference(start);
  if (diff.inDays < 7) return '${diff.inDays} أيام';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7} أسابيع';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30} شهور';
  return '${diff.inDays ~/ 365} سنين';
}

String formatShortDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

String formatFullDate(DateTime d) =>
    '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
