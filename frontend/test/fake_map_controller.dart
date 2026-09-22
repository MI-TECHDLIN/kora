import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' hide LatLng, LatLngBounds;
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre show LatLng;
import 'package:voiceops/features/map/data/kora_map_controller.dart';
import 'package:voiceops/features/map/widgets/openfreemap_layer.dart';

/// An in-memory [KoraMapController]: no platform view, no method channel. A
/// real `MapLibreMap` throws in plain `flutter_test` (there is no engine on
/// the other end of its channel on the host/VM test platform), so every Map
/// tab test drives the screen's camera/route-line logic through this fake
/// instead, via [fakeKoraMapViewBuilder] overriding
/// `koraMapViewBuilderProvider`.
class FakeKoraMapController implements KoraMapController {
  FakeKoraMapController({this.onCameraMoved});

  /// Invoked after every [animateCamera], mirroring the real controller's
  /// `onCameraMove` event -- map_screen.dart reads its own camera state (for
  /// marker placement, follow/frame tracking) only from that callback, not
  /// from a return value, so the fake must call it too.
  final ValueChanged<CameraPosition>? onCameraMoved;

  /// Every [CameraUpdate] map_screen.dart has issued, oldest first.
  final cameraUpdates = <CameraUpdate>[];

  @override
  CameraPosition? cameraPosition;

  /// The route line's current geometry, or null while none is set. Mirrors
  /// [KoraMapController.setRouteLine]'s "fewer than two points clears it".
  List<LatLng>? routeLine;

  @override
  Future<void> animateCamera(CameraUpdate update) async {
    cameraUpdates.add(update);
    final position = _apply(update);
    cameraPosition = position;
    onCameraMoved?.call(position);
  }

  @override
  Future<void> setRouteLine(List<LatLng> coordinates) async {
    routeLine = coordinates.length < 2 ? null : coordinates;
  }

  /// map_screen.dart only ever issues `CameraUpdate.newLatLngZoom` (see
  /// `_centerInClearArea`); decodes that one shape from `CameraUpdate`'s
  /// opaque `toJson()` payload, the only way to read it back.
  CameraPosition _apply(CameraUpdate update) {
    final json = update.toJson() as List<dynamic>;
    if (json[0] != 'newLatLngZoom') {
      throw UnsupportedError(
        'FakeKoraMapController only understands newLatLngZoom, got: $json',
      );
    }
    final target = json[1] as List<dynamic>;
    return CameraPosition(
      target: maplibre.LatLng(
        (target[0] as num).toDouble(),
        (target[1] as num).toDouble(),
      ),
      zoom: (json[2] as num).toDouble(),
    );
  }
}

/// A [KoraMapViewBuilder] that stands in a [FakeKoraMapController] instead
/// of mounting a real `MapLibreMap`. Pass [onControllerCreated] to capture
/// the controller a test needs to inspect or drive further.
KoraMapViewBuilder fakeKoraMapViewBuilder({
  ValueChanged<FakeKoraMapController>? onControllerCreated,
}) {
  return ({
    required style,
    required initialCenter,
    required initialZoom,
    required onMapCreated,
    required onStyleLoaded,
    required onCameraMove,
  }) {
    return _FakeKoraMapView(
      onMapCreated: onMapCreated,
      onStyleLoaded: onStyleLoaded,
      onCameraMove: onCameraMove,
      onControllerCreated: onControllerCreated,
    );
  };
}

class _FakeKoraMapView extends StatefulWidget {
  const _FakeKoraMapView({
    required this.onMapCreated,
    required this.onStyleLoaded,
    required this.onCameraMove,
    this.onControllerCreated,
  });

  final KoraMapCreatedCallback onMapCreated;
  final VoidCallback onStyleLoaded;
  final ValueChanged<CameraPosition> onCameraMove;
  final ValueChanged<FakeKoraMapController>? onControllerCreated;

  @override
  State<_FakeKoraMapView> createState() => _FakeKoraMapViewState();
}

class _FakeKoraMapViewState extends State<_FakeKoraMapView> {
  late final controller = FakeKoraMapController(
    onCameraMoved: widget.onCameraMove,
  );

  @override
  void initState() {
    super.initState();
    widget.onControllerCreated?.call(controller);
    // Mirrors the real plugin's onMapCreated/onStyleLoadedCallback firing
    // after the platform view has stood up, not synchronously with build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onMapCreated(controller);
      widget.onStyleLoaded();
    });
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox.shrink(key: Key('fake-map-view'));
}
