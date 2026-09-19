import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _repo = 'andronasef/daily';

/// A newer GitHub release than the installed build.
class AppUpdate {
  AppUpdate(this.version, this.apkUrl);
  final String version;
  final String apkUrl;
}

List<int> _parts(String v) =>
    v.replaceFirst(RegExp(r'^v'), '').split('+').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();

bool _isNewer(String a, String b) {
  final x = _parts(a), y = _parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d > 0;
  }
  return false;
}

/// Latest GitHub release if newer than this build, else null.
Future<AppUpdate?> checkForUpdate() async {
  final res = await http
      .get(Uri.parse('https://api.github.com/repos/$_repo/releases/latest'))
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) throw Exception('GitHub ${res.statusCode}');
  final json = jsonDecode(res.body) as Map<String, dynamic>;
  final tag = json['tag_name'] as String;
  final current = (await PackageInfo.fromPlatform()).version;
  if (!_isNewer(tag, current)) return null;
  final assets = (json['assets'] as List).cast<Map<String, dynamic>>();
  final apk = assets.firstWhere((a) => (a['name'] as String).endsWith('.apk'));
  return AppUpdate(tag.replaceFirst('v', ''), apk['browser_download_url'] as String);
}

Stream<OtaEvent> installUpdate(AppUpdate u) =>
    OtaUpdate().execute(u.apkUrl, destinationFilename: 'daily-${u.version}.apk');
