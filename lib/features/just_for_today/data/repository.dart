import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/settings.dart';

/// "لليوم فقط" — fully in-app: fetch jftna.org, translate to Egyptian Arabic
/// via Gemini, render natively. Cached once per day.
/// Gemini key is entered in Settings (stored on-device).
String get _geminiKey => Settings.instance.geminiKey;
const _model = 'gemini-3-flash-preview';

class Jft {
  Jft({
    required this.title,
    required this.date,
    required this.quote,
    required this.paragraphs,
    required this.justForToday,
  });
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
        (j['paragraphs'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
    justForToday: (j['justForToday'] ?? '').toString(),
  );
}

Future<String> fetchSource() async {
  final res = await http
      .get(Uri.parse('https://www.jftna.org/jft/'))
      .timeout(const Duration(seconds: 20));
  var text = utf8.decode(res.bodyBytes, allowMalformed: true);
  text = text.replaceAll(
    RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
    '',
  );
  text = text.replaceAll(
    RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
    '',
  );
  text = text.replaceAll(RegExp(r'<[^>]+>'), '\n');
  text = text.replaceAll(RegExp(r'\n\s*\n'), '\n');
  return text.trim();
}

Future<Jft> translate(String source) async {
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
    'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_geminiKey',
  );
  final res = await http
      .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': '$prompt$body'},
              ],
            },
          ],
        }),
      )
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

String _todayKey() {
  final n = DateTime.now();
  return 'jft:${n.year}-${n.month}-${n.day}';
}

/// Fetch + translate today's reading, or return the cached copy. Top-level so
/// the daily background task (lib/background.dart) can warm the cache without
/// a widget tree.
Future<Jft> loadJft({bool force = false}) async {
  final key = _todayKey();
  if (!force) {
    final cached = Settings.instance.getCache(key);
    if (cached != null) return Jft.fromJson(jsonDecode(cached));
  }
  final jft = await translate(await fetchSource());
  await Settings.instance.setCache(
    key,
    jsonEncode({
      'title': jft.title,
      'date': jft.date,
      'quote': jft.quote,
      'paragraphs': jft.paragraphs,
      'justForToday': jft.justForToday,
    }),
  );
  return jft;
}

/// True when today's reading is already cached — nothing to fetch.
bool jftCachedForToday() => Settings.instance.getCache(_todayKey()) != null;
