import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/bridge.dart';
import 'core/fake_bridge.dart';
import 'core/native_bridge.dart';
import 'state/app_state.dart';

/// Command line:
///   `--demo`             run on sample data instead of this PC (for screenshots and tours)
///   `--section=NAME`     open on overview, cleaner, disk, health, shield, quarantine or settings
///   `--accent=NAME`      demo only: start with hellfire, ember, toxic, spectral or ice
///   `--update-feed=URL`  check this release.json for updates instead of the website's
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  String? arg(String name) =>
      args.where((a) => a.startsWith('--$name=')).map((a) => a.substring(name.length + 3)).firstOrNull;
  final demo = args.contains('--demo');
  final wanted = switch (arg('section')) { 'overview' => 'dashboard', 'health' => 'disk', final s => s };
  final section = Section.values.where((s) => s.name == wanted).firstOrNull;

  FiendBridge bridge = NativeBridge();
  if (demo) {
    final fake = FakeBridge();
    final accent = arg('accent');
    if (accent != null) {
      fake.savedSettings = {
        'appearance': {'accent': accent},
      };
    }
    bridge = fake;
  }

  const options = WindowOptions(
    title: 'Fiend',
    size: Size(1320, 860),
    minimumSize: Size(1040, 680),
    center: true,
    backgroundColor: Color(0xFF0B0A10),
    titleBarStyle: TitleBarStyle.hidden,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final feed = arg('update-feed');
  runApp(FiendApp(
    bridge: bridge,
    startAt: section,
    startOnHealth: arg('section') == 'health',
    // Demo runs stay offline unless a test feed is given.
    checkUpdates: !demo || feed != null,
    updateFeed: feed,
  ));
}
