import 'package:fiend/app.dart';
import 'package:fiend/core/fake_bridge.dart';
import 'package:fiend/core/format.dart';
import 'package:fiend/core/models.dart';
import 'package:fiend/theme/theme.dart';
import 'package:fiend/ui/widgets/treemap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<FakeBridge> pumpFiend(WidgetTester tester, {FakeBridge? bridge}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final b = bridge ?? FakeBridge();
  await tester.pumpWidget(FiendApp(bridge: b, desktop: false));
  await tester.pumpAndSettle();
  return b;
}

void main() {
  group('format', () {
    test('bytes', () {
      expect(fmtBytes(0), '0 B');
      expect(fmtBytes(1536), '1.5 KB');
      expect(fmtBytes(5 * 1024 * 1024 * 1024), '5.0 GB');
      expect(fmtBytes(250 * 1024 * 1024), '250 MB');
    });
    test('counts and plurals', () {
      expect(fmtCount(1234567), '1,234,567');
      expect(plural(1, 'file'), '1 file');
      expect(plural(3, 'entry', 'entries'), '3 entries');
    });
    test('ago', () {
      final now = DateTime(2026, 10, 20, 12);
      int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch ~/ 1000;
      expect(fmtAgo(null), 'never');
      expect(fmtAgo(ago(const Duration(minutes: 5)), now: now), '5 min ago');
      expect(fmtAgo(ago(const Duration(hours: 30)), now: now), 'yesterday');
    });
  });

  test('treemap fills the box without overlap', () {
    const box = Rect.fromLTWH(0, 0, 600, 400);
    final rects = squarify([50, 25, 15, 10], box);
    final area = rects.fold<double>(0, (a, r) => a + r.width * r.height);
    expect(area, closeTo(600 * 400, 0.5));
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        final o = rects[i].intersect(rects[j]);
        expect(o.width <= 0.01 || o.height <= 0.01, isTrue);
      }
    }
  });

  test('settings fall back to defaults and copy deeply', () {
    final s = Settings.defaults();
    expect(s.accent, 'hellfire');
    final c = s.copy()..set('appearance', 'accent', 'toxic');
    expect(s.accent, 'hellfire');
    expect(c.accent, 'toxic');
  });

  testWidgets('overview shows health, drives and reclaimable space', (tester) async {
    await pumpFiend(tester);
    expect(find.text('FIEND'), findsOneWidget);
    expect(find.text('HEALTH'), findsOneWidget);
    expect(find.text('C:'), findsWidgets);
    // Sample caches add up to 6,111 MB; the two admin-only locations are left out.
    expect(find.text('6.0 GB'), findsOneWidget);
  });

  testWidgets('quick scan lists a disguised file and quarantines it', (tester) async {
    final bridge = await pumpFiend(tester);
    await tester.tap(find.text('Shield').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start').first);
    await tester.pumpAndSettle();
    expect(find.text('invoice_0425.pdf.exe'), findsOneWidget);
    expect(find.text('Looks like a .pdf file but runs as .exe'), findsOneWidget);
    final button = find.text('Quarantine').at(1);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(bridge.calls, contains('quarantine.add'));
  });

  testWidgets('changing the accent re-themes the app and saves', (tester) async {
    final bridge = await pumpFiend(tester);
    await tester.tap(find.text('Customize').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Toxic'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.text('Accent'));
    expect(Fx.of(ctx).accent, const Color(0xFF7CE85A));
    expect((bridge.savedSettings!['appearance'] as Map)['accent'], 'toxic');
  });

  testWidgets('engine failure shows a clear error', (tester) async {
    await pumpFiend(tester, bridge: FakeBridge(failWith: 'fiend_core.dll not found'));
    expect(find.text('Fiend\'s engine didn\'t start'), findsOneWidget);
    expect(find.text('fiend_core.dll not found'), findsOneWidget);
  });
}
