import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../state/app_state.dart';
import '../state/shield_state.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import 'screens/cleaner.dart';
import 'screens/dashboard.dart';
import 'screens/disk.dart';
import 'screens/quarantine.dart';
import 'screens/settings.dart';
import 'screens/shield.dart';
import 'widgets/common.dart';
import 'widgets/sigil.dart';

class Shell extends StatelessWidget {
  const Shell({super.key, this.desktop = true});

  /// False in tests, where there is no native window to control.
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final fx = Fx.of(context);
    return Scaffold(
      backgroundColor: fx.bg,
      body: Column(
        children: [
          if (desktop) const _TitleBar(),
          Expanded(
            child: Row(
              children: [
                const _Sidebar(),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: fx.motion,
                    child: KeyedSubtree(
                      key: ValueKey(app.section),
                      child: switch (app.section) {
                        Section.dashboard => const DashboardScreen(),
                        Section.cleaner => const CleanerScreen(),
                        Section.disk => const DiskScreen(),
                        Section.shield => const ShieldScreen(),
                        Section.quarantine => const QuarantineScreen(),
                        Section.settings => const SettingsScreen(),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrollable page body with the standard gutters.
class ScreenBody extends StatelessWidget {
  const ScreenBody({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    return Scrollbar(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(36, fx.compact ? 20 : 28, 36, 40),
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) SizedBox(height: fx.gap + 6),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final shield = context.watch<ShieldState>();
    final fx = Fx.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 1120;

    Widget item(Section s, IconData icon, String label, {int badge = 0, Color? badgeColor}) {
      final active = app.section == s;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: _MaybeTooltip(
          message: wide ? null : label,
          child: Material(
            color: active ? fx.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(fx.radius),
            child: InkWell(
              borderRadius: BorderRadius.circular(fx.radius),
              onTap: () => app.go(s),
              child: Container(
                height: 42,
                padding: EdgeInsets.symmetric(horizontal: wide ? 12 : 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(fx.radius),
                  border: Border.all(color: active ? fx.border : Colors.transparent),
                ),
                child: Row(
                  mainAxisAlignment: wide ? MainAxisAlignment.start : MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 20, color: active ? fx.accent : fx.muted),
                    if (wide) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(label,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                              color: active ? fx.text : fx.muted,
                            )),
                      ),
                      if (badge > 0) Pill('$badge', color: badgeColor ?? fx.accent),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final high = shield.report?.count('high') ?? 0;
    return Container(
      width: wide ? 232 : 76,
      decoration: BoxDecoration(
        color: fx.surface,
        border: Border(right: BorderSide(color: fx.border)),
      ),
      padding: EdgeInsets.fromLTRB(wide ? 16 : 12, 22, wide ? 16 : 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: wide ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(left: wide ? 6 : 0),
                child: Sigil(size: 30, color: fx.accent, glow: fx.glow),
              ),
              if (wide) ...[
                const SizedBox(width: 12),
                Text('FIEND',
                    style: TextStyle(
                      fontFamily: displayFont,
                      fontFamilyFallback: fontFallback,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 5,
                      color: fx.text,
                    )),
              ],
            ],
          ),
          const SizedBox(height: 30),
          item(Section.dashboard, Icons.blur_on_rounded, 'Overview'),
          item(Section.cleaner, Icons.cleaning_services_outlined, 'Cleaner'),
          item(Section.disk, Icons.donut_large_rounded, 'Disk'),
          item(Section.shield, Icons.shield_outlined, 'Shield',
              badge: shield.openFindings, badgeColor: high > 0 ? dangerColor : warnColor),
          item(Section.quarantine, Icons.lock_outline_rounded, 'Quarantine', badge: app.quarantine.length, badgeColor: fx.muted),
          const Spacer(),
          item(Section.settings, Icons.tune_rounded, 'Customize'),
          const SizedBox(height: 10),
          if (wide) _AdminCard(app: app),
        ],
      ),
    );
  }
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    final t = Theme.of(context).textTheme;
    if (app.isAdmin) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          const Icon(Icons.verified_user_outlined, size: 15, color: safeColor),
          const SizedBox(width: 8),
          Text('Running as administrator', style: t.bodySmall),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fx.surface2,
        borderRadius: BorderRadius.circular(fx.radius),
        border: Border.all(color: fx.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Standard mode', style: t.titleSmall),
          const SizedBox(height: 3),
          Text('System caches and some startup items need administrator rights.', style: t.bodySmall),
          const SizedBox(height: 10),
          FButton('Restart as admin', icon: Icons.admin_panel_settings_outlined, dense: true, onPressed: () async {
            if (await app.relaunchAsAdmin()) {
              await windowManager.destroy();
              exit(0);
            }
          }),
        ],
      ),
    );
  }
}

class _TitleBar extends StatefulWidget {
  const _TitleBar();

  @override
  State<_TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<_TitleBar> with WindowListener {
  bool maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((m) => mounted ? setState(() => maximized = m) : null);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => maximized = false);

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    return Container(
      height: 36,
      color: fx.surface,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 14),
                child: Text('Fiend', style: TextStyle(fontSize: 12, color: fx.faint, fontWeight: FontWeight.w500)),
              ),
            ),
          ),
          _WinButton(icon: Icons.remove_rounded, onTap: windowManager.minimize),
          _WinButton(
            icon: maximized ? Icons.filter_none_rounded : Icons.crop_square_rounded,
            iconSize: maximized ? 13 : 15,
            onTap: () async => maximized ? windowManager.unmaximize() : windowManager.maximize(),
          ),
          _WinButton(icon: Icons.close_rounded, onTap: windowManager.close, danger: true),
        ],
      ),
    );
  }
}

class _WinButton extends StatefulWidget {
  const _WinButton({required this.icon, required this.onTap, this.danger = false, this.iconSize = 16});
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;
  final double iconSize;

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final fx = Fx.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 36,
          color: hover ? (widget.danger ? const Color(0xFFC42B1C) : fx.surface2) : Colors.transparent,
          child: Icon(widget.icon, size: widget.iconSize, color: hover && widget.danger ? Colors.white : fx.muted),
        ),
      ),
    );
  }
}

class _MaybeTooltip extends StatelessWidget {
  const _MaybeTooltip({required this.message, required this.child});
  final String? message;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      message == null ? child : Tooltip(message: message!, child: child);
}