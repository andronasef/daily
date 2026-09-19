import 'package:flutter/material.dart';

import 'settings_screen.dart';
import 'sections/cross_work.dart';
import 'sections/leyaana.dart';
import 'sections/just_for_today.dart';
import 'sections/intercede.dart';
// import 'sections/journal.dart';

class _Section {
  const _Section(this.title, this.subtitle, this.icon, this.builder);
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget Function() builder;
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static final _sections = <_Section>[
    _Section('عمل الصليب', 'تأمل روحي يومي', Icons.add, () => const CrossWorkScreen()),
    _Section('ليا انا', 'آية النهارده واسم من أسماء الله', Icons.auto_awesome,
        () => const LeyaanaScreen()),
    _Section('لليوم فقط', 'قراءة النهارده بالمصري', Icons.wb_sunny_outlined,
        () => const JustForTodayScreen()),
    _Section('تشفع', 'اللي بتصليلهم', Icons.volunteer_activism_outlined,
        () => const IntercedeScreen()),
    // Hidden for now (code kept in sections/journal.dart); restore the import too.
    // _Section('مسلم', 'سلّم يومك واكتب للروح القدس', Icons.edit_note,
    //     () => const JournalScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('يومي'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _sections.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final s = _sections[i];
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.primaryContainer,
                child: Icon(s.icon,
                    color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
              title: Text(s.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              subtitle: Text(s.subtitle),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => s.builder()),
              ),
            ),
          );
        },
      ),
    );
  }
}
