import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../settings.dart';

/// "لليوم فقط" — fully in-app: fetch jftna.org, translate to Egyptian Arabic
/// via Gemini, render natively. Cached once per day.
/// Gemini key is entered in Settings (stored on-device).
String get _geminiKey => Settings.instance.geminiKey;
const _model = 'gemini-3-flash-preview';

class Jft {
  Jft({required this.title, required this.date, required this.quote, required this.paragraphs, required this.justForToday});
  final String title;
  final String date;
  final String quote;
  final List<String> paragraphs;
  final String justForToday;

  factory Jft.fromJson(Map<String, dynamic> j) => Jft(
        title: (j['title'] ?? '').toString(),
        date: (j['date'] ?? '').toString(),
        quote: (j['quote'] ?? '').toString(),
        paragraphs:
            (j['paragraphs'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        justForToday: (j['justForToday'] ?? '').toString(),
      );
}

Future<String> _fetchSource() async {
  final res = await http
      .get(Uri.parse('https://www.jftna.org/jft/'))
      .timeout(const Duration(seconds: 20));
  var text = utf8.decode(res.bodyBytes, allowMalformed: true);
  text = text.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '');
  text = text.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '');
  text = text.replaceAll(RegExp(r'<[^>]+>'), '\n');
  text = text.replaceAll(RegExp(r'\n\s*\n'), '\n');
  return text.trim();
}

Future<Jft> _translate(String source) async {
  const prompt = '''
Role: You are an experienced Egyptian sponsor in Narcotics Anonymous (NA).
Task: Translate the "Just For Today" text into Egyptian Colloquial Arabic (Masri).
Tone: natural Egyptian ammiya, warm, heart-to-heart, address the reader as "enta".
Keep NA terms simple: Higher Power -> "ربنا زي ما بنفهمه", Addict -> "مدمن", Recovery -> "تعافي".

Return ONLY valid minified JSON (no markdown, no code fences) with EXACTLY these keys:
{"title": string, "date": string, "quote": string, "paragraphs": string[], "justForToday": string}

Text to translate:
''';

  final body = source.length > 8000 ? source.substring(0, 8000) : source;
  final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_geminiKey');
  final res = await http
      .post(uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {'parts': [{'text': '$prompt$body'}]}
            ]
          }))
      .timeout(const Duration(seconds: 40));
  if (res.statusCode != 200) {
    throw Exception('Gemini ${res.statusCode}: ${res.body}');
  }
  final data = jsonDecode(utf8.decode(res.bodyBytes));
  var raw = (data['candidates'][0]['content']['parts'][0]['text'] as String)
      .replaceAll('```json', '')
      .replaceAll('```', '')
      .trim();
  // Extract the JSON object if the model added stray text.
  if (!raw.startsWith('{')) {
    final s = raw.indexOf('{'), e = raw.lastIndexOf('}');
    if (s >= 0 && e > s) raw = raw.substring(s, e + 1);
  }
  return Jft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

class JustForTodayScreen extends StatefulWidget {
  const JustForTodayScreen({super.key});

  @override
  State<JustForTodayScreen> createState() => _JustForTodayScreenState();
}

class _JustForTodayScreenState extends State<JustForTodayScreen> {
  late Future<Jft> _future;

  String get _todayKey {
    final n = DateTime.now();
    return 'jft:${n.year}-${n.month}-${n.day}';
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Jft> _load({bool force = false}) async {
    if (!force) {
      final cached = Settings.instance.getCache(_todayKey);
      if (cached != null) return Jft.fromJson(jsonDecode(cached));
    }
    final jft = await _translate(await _fetchSource());
    await Settings.instance.setCache(
        _todayKey,
        jsonEncode({
          'title': jft.title,
          'date': jft.date,
          'quote': jft.quote,
          'paragraphs': jft.paragraphs,
          'justForToday': jft.justForToday,
        }));
    return jft;
  }

  void _refresh() => setState(() => _future = _load(force: true));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('لليوم فقط'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<Jft>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('تعذر تحميل قراءة النهارده.'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _refresh, child: const Text('إعادة المحاولة')),
                ],
              ),
            );
          }
          final d = snap.data!;
          final primary = theme.colorScheme.primary;
          // JFT vibe: one card with a colored top border, centered title,
          // side-bordered quote, and an emphasized closing box.
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border(top: BorderSide(color: primary, width: 6)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(d.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold, color: primary)),
                    if (d.date.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(d.date,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                    if (d.quote.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border(
                            right: BorderSide(color: primary, width: 4),
                          ),
                        ),
                        child: Text(d.quote,
                            style: theme.textTheme.titleMedium?.copyWith(height: 1.7)),
                      ),
                    ],
                    const SizedBox(height: 24),
                    for (final p in d.paragraphs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Text(p,
                            style: theme.textTheme.bodyLarge?.copyWith(height: 1.95)),
                      ),
                    if (d.justForToday.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(d.justForToday,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold, height: 1.7)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('الترجمة بالذكاء الاصطناعي عشان توصل بالمصري • المصدر jftna.org',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          );
        },
      ),
    );
  }
}
