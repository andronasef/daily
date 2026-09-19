import 'package:flutter/material.dart';
import '../../core/settings.dart';
import '../home/home_screen.dart';
import '../leyaana/data/verse_surfaces.dart';

/// First-run: collects first name + gender (needed for section 2 personalization).
/// Mirrors temp/leyaana/src/routes/Welcome.tsx — first name only, no spaces.
class Onboarding extends StatefulWidget {
  const Onboarding({super.key});

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  final _controller = TextEditingController();
  bool _isMale = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    if (name.contains(' ')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مش قولنا ندخل الاسم الاول بس 😒')),
      );
      return;
    }
    Settings.instance
      ..name = name
      ..isMale = _isMale
      ..onboarded = true;
    refreshVerseSurfaces(); // name/gender change which verse + text the widget/notifications use
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                'اهلا بيك! 👋',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'المكان ده ليك انت — بتصلي وبتفتكر ان الله عمل حاجات جميلة كتير علشانك. '
                'قبل ما نبدأ دخّل اسمك ونوعك.',
                style: TextStyle(height: 1.7, fontSize: 16),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _start(),
                decoration: const InputDecoration(
                  labelText: 'اسمك ايه؟ (الاول بس)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('👦 ولد')),
                  ButtonSegment(value: false, label: Text('👧 بنت')),
                ],
                selected: {_isMale},
                onSelectionChanged: (s) => setState(() => _isMale = s.first),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _start,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('اتفضل 🚀', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
