import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Static reflection "عمل الصليب" by شادي حبيش (from god-work-on-me.vercel.app).
/// Vibe: quiet, contemplative — Amiri serif, centered, airy — but in the app's
/// palette (not the source's warm/maroon colors). Fully bundled, offline.
class CrossWorkScreen extends StatelessWidget {
  const CrossWorkScreen({super.key});

  static const _meditation = [
    'أنا أعظم فرصة للنهضة، وأنا أكبر خطر على تعثّرها.',
    'أنا المفتاح الذي يفتح خزائن السماء،\nوقد أكون، في الوقت ذاته، السلاسل التي تُغلقها.',
    'أنا الجسر بين السماء والأرض،\nوقد أصير السور الذي يحجب العبور.',
    'أنا قوة الدفع، وأنا العقبة.',
    'أنا الأداة التي تبني،\nوأنا العائق الذي يؤخّر ويهدم.',
    'أنا الصانع،\nوقد أكون الهادم.',
    'أنا الحل و أنا المشكلة…',
    'الأمر معتمد على عمل الصليب في حياتي،، كل يوم',
  ];

  static const _verses = <(String, String)>[
    (
      'لِأَنَّهُ فِي ٱلْمَسِيحِ يَسُوعَ لَيْسَ ٱلْخِتَانُ يَنْفَعُ شَيْئًا وَلَا ٱلْغُرْلَةُ، بَلِ ٱلْخَلِيقَةُ ٱلْجَدِيدَةُ.',
      'غَلَاطِيَّةَ ٦:١٥',
    ),
    (
      'مَعَ ٱلْمَسِيحِ صُلِبْتُ، فَأَحْيَا لَا أَنَا، بَلِ ٱلْمَسِيحُ يَحْيَا فِيَّ. فَمَا أَحْيَاهُ ٱلْآنَ فِي ٱلْجَسَدِ، فَإِنَّمَا أَحْيَاهُ فِي ٱلْإِيمَانِ، إِيمَانِ ٱبْنِ ٱللهِ، ٱلَّذِي أَحَبَّنِي وَأَسْلَمَ نَفْسَهُ لِأَجْلِي.',
      'غَلَاطِيَّةَ ٢:٢٠',
    ),
    (
      '«إِنْ أَرَادَ أَحَدٌ أَنْ يَأْتِيَ وَرَائِي، فَلْيُنْكِرْ نَفْسَهُ وَيَحْمِلْ صَلِيبَهُ كُلَّ يَوْمٍ، وَيَتْبَعْنِي.»',
      'لُوقَا ٩:٢٣',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final muted = theme.colorScheme.onSurfaceVariant;
    // Amiri serif for the contemplative vibe; app colors for identity.
    final serif = GoogleFonts.amiri();

    return Scaffold(
      appBar: AppBar(title: const Text('عمل الصليب')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        children: [
          Text(
            'عمل الصليب',
            textAlign: TextAlign.center,
            style: serif.copyWith(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: primary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 60,
              child: Divider(color: muted.withValues(alpha: 0.4)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'تأمل روحي',
            textAlign: TextAlign.center,
            style: serif.copyWith(fontSize: 15, color: muted),
          ),
          const SizedBox(height: 20),
          Icon(Icons.south, size: 18, color: muted.withValues(alpha: 0.6)),
          const SizedBox(height: 40),
          for (final line in _meditation) ...[
            Text(
              line,
              textAlign: TextAlign.center,
              style: serif.copyWith(
                fontSize: 20,
                height: 2.0,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 28),
          ],
          const SizedBox(height: 12),
          _CrossDivider(color: primary),
          const SizedBox(height: 36),
          for (final v in _verses) ...[
            Text(
              v.$1,
              textAlign: TextAlign.center,
              style: serif.copyWith(
                fontSize: 18,
                height: 2.0,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              v.$2,
              textAlign: TextAlign.center,
              style: serif.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
            const SizedBox(height: 36),
          ],
          const SizedBox(height: 8),
          Divider(
            color: primary.withValues(alpha: 0.3),
            indent: 100,
            endIndent: 100,
          ),
          const SizedBox(height: 16),
          Text(
            'شادي حبيش',
            textAlign: TextAlign.center,
            style: serif.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: primary,
            ),
          ),
          const SizedBox(height: 16),
          Divider(
            color: primary.withValues(alpha: 0.3),
            indent: 100,
            endIndent: 100,
          ),
        ],
      ),
    );
  }
}

/// A "+" flanked by two short rules — the source's cross divider.
class _CrossDivider extends StatelessWidget {
  const _CrossDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 60,
          child: Divider(color: color.withValues(alpha: 0.4)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Icon(Icons.add, size: 22, color: color),
        ),
        SizedBox(
          width: 60,
          child: Divider(color: color.withValues(alpha: 0.4)),
        ),
      ],
    );
  }
}
