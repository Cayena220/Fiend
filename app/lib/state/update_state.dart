import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../core/format.dart';
import '../core/release.dart';
import 'app_state.dart';

enum UpdatePhase { idle, checking, downloading, verifying, installing, failed }

/// Finds newer releases, downloads the installer, checks its SHA-256 and hands it to the
/// engine, which runs it silently once Fiend has closed.
class UpdateState extends ChangeNotifier {
  UpdateState(this.app, {String? feed}) : feed = Uri.parse(feed ?? defaultUpdateFeed);

  final AppState app;
  final Uri feed;

  Release? available;
  UpdatePhase phase = UpdatePhase.idle;
  String? error;
  int received = 0;
  int total = 0;

  String get current => app.system?.appVersion ?? '0.0.0';
  bool get busy => phase != UpdatePhase.idle && phase != UpdatePhase.failed;
  double? get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : null;

  /// True when this copy runs from the installed location, so the installer updates it in place.
  bool get installedCopy {
    final exe = app.system?.exePath.toLowerCase() ?? '';
    final local = (Platform.environment['LOCALAPPDATA'] ?? '').toLowerCase();
    return local.isNotEmpty && exe.startsWith('$local\\programs\\fiend\\');
  }

  void _set(UpdatePhase p, {String? err}) {
    phase = p;
    error = err;
    notifyListeners();
  }

  /// Returns the newer release, or null when Fiend is up to date. A skipped version only
  /// counts when [manual] is true (the user asked).
  Future<Release?> check({bool manual = false}) async {
    if (busy) return available;
    _set(UpdatePhase.checking);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(feed);
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final body = await res.transform(utf8.decoder).join();
      final release = Release.parse(jsonDecode(body) as Map<String, dynamic>, feed);
      final newer = release != null && compareVersions(release.version, current) > 0;
      final skipped = release != null && !manual && app.settings.skippedVersion == release.version;
      available = newer && !skipped ? release : null;
      _set(UpdatePhase.idle);
    } catch (e) {
      available = null;
      _set(manual ? UpdatePhase.failed : UpdatePhase.idle,
          err: manual ? 'Couldn\'t check for updates. Check your internet connection and try again.' : null);
    } finally {
      client.close(force: true);
    }
    return available;
  }

  /// Hides this version's popup until a newer one comes out.
  void skip(Release r) {
    app.updateSettings((s) => s.set('updates', 'skipped_version', r.version));
    available = null;
    notifyListeners();
  }

  /// Downloads and verifies the installer, then starts it. Returns true when the app should
  /// close so the installer can replace it.
  Future<bool> install(Release r) async {
    if (busy) return false;
    final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}Fiend-update');
    final file = File('${dir.path}${Platform.pathSeparator}${r.installer.file}');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      received = 0;
      total = r.installer.size;
      _set(UpdatePhase.downloading);
      await dir.create(recursive: true);
      final req = await client.getUrl(r.installer.url);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('The download failed (HTTP ${res.statusCode}).');
      }
      if (res.contentLength > 0) total = res.contentLength;
      final sink = file.openWrite();
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          received += chunk.length;
          notifyListeners();
        }
      } finally {
        await sink.close();
      }

      _set(UpdatePhase.verifying);
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != r.installer.sha256) {
        await file.delete();
        throw const FormatException('The download didn\'t match its published checksum, so Fiend deleted it.');
      }

      _set(UpdatePhase.installing);
      await app.flushSettings();
      await app.bridge.call('update.install', {'path': file.path});
      return true;
    } on FormatException catch (e) {
      _set(UpdatePhase.failed, err: e.message);
    } on HttpException catch (e) {
      _set(UpdatePhase.failed, err: e.message);
    } catch (e) {
      _set(UpdatePhase.failed, err: 'The update didn\'t finish: $e');
    } finally {
      client.close(force: true);
    }
    return false;
  }

  String get progressLabel => total > 0 ? 'Downloading ${fmtBytes(received)} of ${fmtBytes(total)}' : 'Downloading ${fmtBytes(received)}';
}
