import 'dart:ui';

import 'package:flutter/material.dart';

ThemeData safeGuardTheme({required bool parent}) {
  final accent = parent ? const Color(0xffc8b8ff) : const Color(0xffbdb4ff);
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
  const GlassScaffold({
    super.key,
    required this.title,
    required this.body,
    this.animateColors = false,
  });

  final String title;
  final Widget body;
  final bool animateColors;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: animateColors
              ? const [Color(0xff111023), Color(0xff1c1536), Color(0xff121528)]
              : const [Color(0xff121a32), Color(0xff17264a), Color(0xff10172b)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: _GlassLighting(accent: accent, animated: animateColors),
              ),
            ),
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

class _GlassLighting extends StatefulWidget {
  const _GlassLighting({required this.accent, required this.animated});

  final Color accent;
  final bool animated;

  @override
  State<_GlassLighting> createState() => _GlassLightingState();
}

class _GlassLightingState extends State<_GlassLighting>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void didUpdateWidget(covariant _GlassLighting oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateMotion();
  }

  void _updateMotion() {
    if (widget.animated && !MediaQuery.disableAnimationsOf(context)) {
      if (!_clock.isAnimating) _clock.repeat(reverse: true);
    } else {
      _clock.stop();
      _clock.value = 0;
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        final movement = Curves.easeInOut.transform(_clock.value);
        final upper = widget.animated
            ? Color.lerp(const Color(0xff7958ff), const Color(0xffed529f), movement)!
            : widget.accent;
        final lower = widget.animated
            ? Color.lerp(const Color(0xff25afbe), const Color(0xff766afb), movement)!
            : const Color(0xff766afb);
        return Stack(
          children: [
            Positioned(
              top: -115 + 150 * movement,
              right: -120 + 65 * movement,
              child: _Glow(size: 470, color: upper.withValues(alpha: .56)),
            ),
            Positioned(
              bottom: -145 + 45 * movement,
              left: -150 + 30 * movement,
              child: _Glow(size: 460, color: lower.withValues(alpha: .45)),
            ),
          ],
        );
      },
    ),
  );
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
                colors: [Color(0xc5362a51), Color(0xcf171c33)],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
