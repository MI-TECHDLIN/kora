import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../core/theme/tokens.dart';
import '../core/widgets/glass_card.dart';

/// Frame for the four main tabs. go_router's [StatefulShellRoute] keeps each
/// tab's navigator alive; this widget only lays out the active branch and
/// the bottom nav.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Transparent so the shared GradientOrbBackground shows through.
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: _VoiceOpsBottomNav(
        currentIndex: navigationShell.currentIndex,
        // Re-tapping the active tab pops it back to its root.
        onSelect: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

class _VoiceOpsBottomNav extends StatelessWidget {
  const _VoiceOpsBottomNav({
    required this.currentIndex,
    required this.onSelect,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  // Order matches the shell branches / MainTab.
  static const _items = [
    (icon: TablerIcons.microphone, label: 'Voice'),
    (icon: TablerIcons.map2, label: 'Map'),
    (icon: TablerIcons.chartBar, label: 'Summary'),
    (icon: TablerIcons.settings, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        KoraSpacing.gutter,
        0,
        KoraSpacing.gutter,
        KoraSpacing.lg,
      ),
      child: GlassCard(
        borderRadius: KoraRadius.sheet,
        fill: KoraColors.raised.withValues(alpha: 0.72),
        padding: const EdgeInsets.symmetric(
          vertical: KoraSpacing.xs,
          horizontal: KoraSpacing.sm,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < _items.length; i++)
              _NavItem(
                icon: _items[i].icon,
                label: _items[i].label,
                active: i == currentIndex,
                onTap: () => onSelect(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: KoraMotion.base,
          curve: KoraMotion.standard,
          constraints: const BoxConstraints(
            minWidth: KoraSize.touchTarget + KoraSpacing.lg,
            minHeight: KoraSize.touchTarget,
          ),
          decoration: BoxDecoration(
            color: active ? KoraColors.primaryTint : Colors.transparent,
            borderRadius: BorderRadius.circular(KoraRadius.pill),
          ),
          child: Icon(
            icon,
            size: KoraSize.iconLg,
            color: active
                ? KoraColors.primaryLight
                : KoraColors.textFaint,
          ),
        ),
      ),
    );
  }
}
