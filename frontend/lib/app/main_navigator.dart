import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/tokens.dart';
import '../features/map/screens/map_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/summary/screens/summary_screen.dart';
import '../features/voice/screens/voice_screen.dart';
import '../providers/navigation_provider.dart';

class MainNavigator extends ConsumerWidget {
  const MainNavigator({super.key});

  static const _screens = [
    VoiceScreen(),
    MapScreen(),
    SummaryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(navigationProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: IndexedStack(index: currentTab, children: _screens),
      bottomNavigationBar: _VoiceOpsBottomNav(currentTab: currentTab),
    );
  }
}

class _VoiceOpsBottomNav extends ConsumerWidget {
  const _VoiceOpsBottomNav({required this.currentTab});
  final int currentTab;

  static const _items = [
    (icon: Icons.mic_rounded, label: 'Voice'),
    (icon: Icons.map_rounded, label: 'Map'),
    (icon: Icons.bar_chart_rounded, label: 'Summary'),
    (icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: VoiceOpsColors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: VoiceOpsColors.primary.withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_items.length, (i) {
          final active = i == currentTab;
          final item = _items[i];
          return GestureDetector(
            onTap: () => ref.read(navigationProvider.notifier).setTab(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active
                    ? VoiceOpsColors.primary.withOpacity(0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                item.icon,
                size: 22,
                color: active
                    ? VoiceOpsColors.primary
                    : VoiceOpsColors.textFaint,
              ),
            ),
          );
        }),
      ),
    );
  }
}
