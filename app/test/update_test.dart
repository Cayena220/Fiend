import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fiend/core/fake_bridge.dart';
import 'package:fiend/core/release.dart';
import 'package:fiend/state/app_state.dart';
import 'package:fiend/state/update_state.dart';
import 'package:fiend/theme/theme.dart';
import 'package:fiend/ui/widgets/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves a release.json and an installer from loopback, like the website does.
class FakeSite {
  late HttpServer server;
  List<int> installer = utf8.encode('MZ pretend Fiend installer');
  late Map<String, dynamic> release;

  String get feed => 'http://127.0.0.1:${server.port}/downloads/release.json';

  Future<void> start({String version = '1.2.0', String? sha}) async {
    release = {
      'version': version,
      'built': '2026-10-21',
      'notes': ['Updates install themselves', 'A second note'],
      'installer': {
        'file': 'Fiend-$version-setup.exe',
        'size': installer.length,
        'sha256': sha ?? sha256.convert(installer).toString(),
      },
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      if (req.uri.path.endsWith('release.json')) {
        req.response.write(jsonEncode(release));
      } else if (req.uri.path.endsWith('-setup.exe')) {
        req.response.add(installer);
      } else {
        req.response.statusCode = 404;
      }
      req.response.close();
    });
  }

  Future<void> stop() => server.close(force: true);
}

Future<AppState> readyApp(FakeBridge bridge) async {
  final app = AppState(bridge);
  await app.init();
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('versions compare numerically', () {
    expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
    expect(compareVersions('1.2', '1.2.0'), 0);
    expect(compareVersions('1.2.0+3', '1.2.0'), 0);
    expect(compareVersions('1.1.0', '1.2.0'), lessThan(0));
    expect(compareVersions('2.0.0', '1.99.99'), greaterThan(0));
  });

  test('release.json is parsed and the installer URL sits next to it', () {
    final feed = Uri.parse('https://example.com/downloads/release.json');
    final r = Release.parse({
      'version': '1.2.0',
      'notes': ['a', ' '],
      'installer': {'file': 'Fiend-1.2.0-setup.exe', 'size': 10, 'sha256': 'A' * 64},
    }, feed)!;
    expect(r.installer.url.toString(), 'https://example.com/downloads/Fiend-1.2.0-setup.exe');
    expect(r.installer.sha256, 'a' * 64);
    expect(r.notes, ['a']);
    // The 1.0 format had no installer, and anything that isn't a Fiend installer is refused.
    expect(Release.parse({'version': '1.0.0', 'file': 'Fiend-1.0.0-win-x64.zip'}, feed), isNull);
    expect(Release.parse({'version': '9', 'installer': {'file': '../evil.exe', 'sha256': 'a' * 64}}, feed), isNull);
    expect(Release.parse({'version': '9', 'installer': {'file': 'Fiend-9-setup.exe', 'sha256': 'nope'}}, feed), isNull);
  });

  group('updater', () {
    late FakeSite site;
    // flutter_test answers every HTTP request with 400 by default; these talk to a real loopback server.
    setUp(() => HttpOverrides.global = null);
    tearDown(() => site.stop());

    test('offers a newer version and stays quiet when up to date', () async {
      site = FakeSite();
      await site.start(version: '1.2.0');
      final app = await readyApp(FakeBridge());
      final updates = UpdateState(app, feed: site.feed);
      expect((await updates.check())?.version, '1.2.0');

      site.release['version'] = '1.1.0';
      expect(await updates.check(), isNull, reason: 'demo app is 1.1.0');
    });

    test('a skipped version only shows when the user asks', () async {
      site = FakeSite();
      await site.start(version: '1.2.0');
      final app = await readyApp(FakeBridge());
      final updates = UpdateState(app, feed: site.feed);
      updates.skip((await updates.check())!);
      expect(app.settings.skippedVersion, '1.2.0');
      expect(await updates.check(), isNull);
      expect((await updates.check(manual: true))?.version, '1.2.0');
    });

    test('downloads, verifies and hands the installer to the engine', () async {
      site = FakeSite();
      await site.start();
      final bridge = FakeBridge();
      final app = await readyApp(bridge);
      final updates = UpdateState(app, feed: site.feed);
      final release = (await updates.check())!;

      expect(await updates.install(release), isTrue);
      expect(updates.phase, UpdatePhase.installing);
      expect(bridge.calls.last, 'update.install');
      final saved = File('${Directory.systemTemp.path}${Platform.pathSeparator}Fiend-update${Platform.pathSeparator}Fiend-1.2.0-setup.exe');
      expect(await saved.readAsBytes(), site.installer);
    });

    test('a download that fails its checksum is deleted and never run', () async {
      site = FakeSite();
      await site.start(sha: 'f' * 64);
      final bridge = FakeBridge();
      final app = await readyApp(bridge);
      final updates = UpdateState(app, feed: site.feed);
      final release = (await updates.check())!;

      expect(await updates.install(release), isFalse);
      expect(updates.phase, UpdatePhase.failed);
      expect(updates.error, contains('checksum'));
      expect(bridge.calls, isNot(contains('update.install')));
    });
  });

  testWidgets('popup shows the version, notes and actions; Skip remembers the choice', (tester) async {
    final app = await tester.runAsync(() => readyApp(FakeBridge()));
    final updates = UpdateState(app!);
    final release = Release.parse({
      'version': '1.2.0',
      'notes': ['Updates install themselves'],
      'installer': {'file': 'Fiend-1.2.0-setup.exe', 'size': 11 * 1024 * 1024, 'sha256': 'a' * 64},
    }, Uri.parse(defaultUpdateFeed))!;

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(app.settings),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => showUpdateDialog(context, updates, release), child: const Text('open')),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Fiend 1.2.0 is ready'), findsOneWidget);
    expect(find.text('You have 1.1.0  ·  11.0 MB download'), findsOneWidget);
    expect(find.text('Updates install themselves'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);

    await tester.tap(find.text('Skip this version'));
    await tester.pumpAndSettle();
    expect(find.text('Fiend 1.2.0 is ready'), findsNothing);
    expect(app.settings.skippedVersion, '1.2.0');
  });
}
