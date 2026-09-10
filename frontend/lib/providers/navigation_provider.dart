import 'package:flutter_riverpod/flutter_riverpod.dart';

final navigationProvider = StateNotifierProvider<NavigationNotifier, int>((
  ref,
) {
  return NavigationNotifier();
});

class NavigationNotifier extends StateNotifier<int> {
  NavigationNotifier() : super(0);

  static const voice = 0;
  static const map = 1;
  static const summary = 2;
  static const settings = 3;

  void setTab(int index) => state = index;

  void navigateForAgent(String screenKey) {
    switch (screenKey) {
      case 'map':
        state = map;
        break;
      case 'summary':
        state = summary;
        break;
      case 'settings':
        state = settings;
        break;
      case 'voice':
      default:
        state = voice;
        break;
    }
  }
}
