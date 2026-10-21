import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/bridge.dart';
import 'state/app_state.dart';
import 'state/cleaner_state.dart';
import 'state/disk_state.dart';
import 'state/shield_state.dart';
import 'theme/theme.dart';
import 'ui/shell.dart';
import 'ui/widgets/common.dart';
import 'ui/widgets/sigil.dart';

class FiendApp extends StatefulWidget {
  const FiendApp({super.key, required this.bridge, this.desktop = true, this.startAt, this.startOnHealth = false});

  final FiendBridge bridge;

  /// Screen to open first. Shield starts a quick scan and Disk maps the system drive.
  final Section? startAt;

  /// With [startAt] Disk: open the drive health view instead of mapping the system drive.
  final bool startOnHealth;

  /// False in widget tests (no native window).
  final bool desktop;

  @override
  State<FiendApp> createState() => _FiendAppState();
}

class _FiendAppState extends State<FiendApp> {
  late final AppState app = AppState(widget.bridge);
  late final CleanerState cleaner = CleanerState(app);
  late final DiskState disk = DiskState(app);
  late final ShieldState shield = ShieldState(app);

  @override
  void initState() {
    super.initState();
    app.init().then((_) {
      if (!app.ready) return;
      cleaner.analyze();
      final start = widget.startAt;
      if (app.settings.scanOnLaunch || start == Section.shield) shield.scan('quick');
      if (widget.startOnHealth) {
        disk.setView(health: true);
      } else if (start == Section.disk && app.systemDrive != null) {
        disk.open(app.systemDrive!.root);
      }
      if (start != null) app.go(start);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        ChangeNotifierProvider.value(value: cleaner),
        ChangeNotifierProvider.value(value: disk),
        ChangeNotifierProvider.value(value: shield),
      ],
      child: Consumer<AppState>(
        builder: (context, app, _) => MaterialApp(
          title: 'Fiend',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: app.messenger,
          theme: buildTheme(app.settings),
          home: app.fatal != null
              ? _Fatal(message: app.fatal!)
              : app.ready
                  ? Shell(desktop: widget.desktop)
                  : const _Splash(),
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    return Scaffold(
      backgroundColor: fx.bg,
      body: Center(child: Sigil(size: 64, color: fx.accent, glow: fx.glow)),
    );
  }
}

class _Fatal extends StatelessWidget {
  const _Fatal({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: fx.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Panel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Sigil(size: 40, color: fx.muted, glow: false),
                const SizedBox(height: 16),
                Text('Fiend\'s engine didn\'t start', style: t.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Fiend needs fiend_core.dll in the same folder as Fiend.exe. Reinstall Fiend, or rebuild it with '
                  '"cargo build --release" in the core folder.',
                  style: t.bodyMedium!.copyWith(color: fx.muted),
                ),
                const SizedBox(height: 12),
                SelectableText(message, style: mono(context, size: 11.5, color: fx.faint)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
