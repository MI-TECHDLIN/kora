import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/map/data/map_route.dart';

/// The route on the Map tab, set by the voice session's `map_route` events.
/// Null until the co-rider draws one.
final mapRouteProvider = StateNotifierProvider<MapRouteNotifier, MapRoute?>(
  (ref) => MapRouteNotifier(),
);

class MapRouteNotifier extends StateNotifier<MapRoute?> {
  MapRouteNotifier() : super(null);
  void show(MapRoute route) => state = route;
  void clear() => state = null;
}

enum MapFocusTarget { driver, route }

/// What the Map tab's camera frames: the driver (following their live
/// position) or the route. [serial] changes on every request, so asking
/// again ("where am I?" twice) re-centres even when the target is the same.
class MapFocus {
  const MapFocus(this.target, this.serial);
  final MapFocusTarget target;
  final int serial;
}

/// Set by the voice session (a `map_route` frames the route; a bare
/// `screen_navigate: map` follows the driver) and by the map's own
/// recenter button. The map screen applies it when it shows.
final mapFocusProvider = StateNotifierProvider<MapFocusNotifier, MapFocus>(
  (ref) => MapFocusNotifier(),
);

class MapFocusNotifier extends StateNotifier<MapFocus> {
  MapFocusNotifier() : super(const MapFocus(MapFocusTarget.driver, 0));

  void followDriver() =>
      state = MapFocus(MapFocusTarget.driver, state.serial + 1);

  void frameRoute() => state = MapFocus(MapFocusTarget.route, state.serial + 1);
}
