import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set when something outside the Summary tab (Home's Next Orders card) asks
/// to land on the full order queue. The Summary tab scrolls the queue into
/// view and clears it. It is a flag rather than an event because the tab
/// may not be built yet when the request is made.
final queueFocusRequestProvider = StateProvider<bool>((ref) => false);
