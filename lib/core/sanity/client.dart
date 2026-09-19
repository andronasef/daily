import 'dart:convert';
import 'package:http/http.dart' as http;

import '../settings.dart';

const sanityProjectId = 'kfme7y2v';
const sanityDataset = 'production';
const sanityApiVersion = 'v2024-01-01';

const _envToken = String.fromEnvironment(
  'SANITY_WRITE_TOKEN',
  defaultValue: '',
);

String get sanityWriteToken {
  final t = Settings.instance.sanityToken;
  return t.isNotEmpty ? t : _envToken;
}

bool get sanityCanWrite => sanityWriteToken.isNotEmpty;

Future<List<Map<String, dynamic>>> sanityQuery(
  String groq, {
  bool cdn = false,
}) async {
  final host = cdn
      ? '$sanityProjectId.apicdn.sanity.io'
      : '$sanityProjectId.api.sanity.io';
  final uri = Uri.parse(
    'https://$host/$sanityApiVersion/data/query/$sanityDataset',
  ).replace(queryParameters: {'query': groq});
  final res = await http.get(uri).timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) throw Exception('Sanity ${res.statusCode}');
  final result = (jsonDecode(res.body)['result'] as List)
      .cast<Map<String, dynamic>>();
  return result;
}

Future<void> sanityMutate(
  List<Map<String, dynamic>> mutations, {
  bool returnIds = true,
}) async {
  if (sanityWriteToken.isEmpty) {
    throw Exception('مفيش Sanity write token متظبط.');
  }
  final endpoint = returnIds
      ? 'https://$sanityProjectId.api.sanity.io/$sanityApiVersion/data/mutate/$sanityDataset?returnIds=true'
      : 'https://$sanityProjectId.api.sanity.io/$sanityApiVersion/data/mutate/$sanityDataset';
  final uri = Uri.parse(endpoint);
  final res = await http
      .post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $sanityWriteToken',
        },
        body: jsonEncode({'mutations': mutations}),
      )
      .timeout(const Duration(seconds: 20));
  if (res.statusCode != 200) {
    throw Exception('Sanity ${res.statusCode}: ${res.body}');
  }
}
