import 'dart:ui';

import 'package:flutter/material.dart';

ThemeData safeGuardTheme({required bool parent}) {
  final accent = parent ? const Color(0xff8be9df) : const Color(0xffbdb4ff);
  final colors = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: accent,
    onPrimary: const Color(0xff121d31),
    onSurface: const Color(0xfff1f5ff),
    onSurfaceVariant: const Color(0xffc2cde6),
  );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: const BorderSide(color: Color(0x42ffffff)),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Color(0xfff1f5ff),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Color(0xfff1f5ff),
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: const Color(0x34101b33),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        side: const BorderSide(color: Color(0x54ffffff)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: accent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

class GlassScaffold extends StatelessWidget {
  const GlassScaffold({super.key, required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff121a32), Color(0xff17264a), Color(0xff10172b)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -115,
            right: -120,
            child: _Glow(size: 420, color: accent.withValues(alpha: .42)),
          ),
          const Positioned(
            bottom: -145,
            left: -150,
            child: _Glow(size: 460, color: Color(0x88766afb)),
          ),
          const Positioned(
            bottom: 40,
            right: -175,
            child: _Glow(size: 340, color: Color(0x5521a0ce)),
          ),
          Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .12),
                      border: Border.all(color: accent.withValues(alpha: .55)),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      'RDX',
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'About SafeGuard',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => showAboutDialog(
                    context: context,
                    applicationName: 'RDX SafeGuard',
                    applicationIcon: Icon(Icons.shield_outlined, color: accent, size: 32),
                    children: const [Text('Created by Rahul Pipliwal')],
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: body,
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(28);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: const Color(0x45ffffff)),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0x32ffffff), Color(0x16bbcffe)],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
