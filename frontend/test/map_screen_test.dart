import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:voiceops/core/api/voiceops_api.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/features/map/data/location_source.dart';
import 'package:voiceops/features/map/data/map_route.dart';
import 'package:voiceops/features/map/screens/map_screen.dart';
import 'package:voiceops/features/map/widgets/map_markers.dart';
import 'package:voiceops/features/settings/screens/settings_screen.dart';
import 'package:voiceops/providers/auth_provider.dart';
import 'package:voiceops/providers/map_route_provider.dart';

import 'fake_auth.dart';
import 'fake_voice.dart';
import 'map_route_test.dart' show noRoadMapRoute, sampleMapRoute;
import 'test_fonts.dart';

/// Near the sample route's stops on Lagos Island.
const _nearStops = LatLng(6.4600, 3.3900);
const _furtherOn = LatLng(6.4620, 3.3920);

void main() {
  setUpAll(disableGoogleFontsFetching);

  late FakeLocationSource location;
  late FakeVoiceOpsApi api;
  late ProviderContainer container;

  setUp(() {
    location = FakeLocationSource();
    api = FakeVoiceOpsApi(
      profile: const DriverProfile(
        id: 'driver-1',
        name: 'Ada Obi',
        vehicleType: 'Motorbike',
      ),
    );
  });

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container = ProviderContainer(
      overrides: [
        ...offlineOverrides(location: location, api: api),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: true),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildVoiceOpsTheme(),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pump();
  }

  /// Lets the card finish resizing and the camera re-frame after it.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(VoiceOpsMotion.slow);
    await tester.pump();
  }

  MapCamera camera(WidgetTester tester) =>
      MapCamera.of(tester.element(find.byType(MarkerLayer).first));

  /// [point] is on screen, below the top controls and clear of the bottom
  /// sheet (attribution and card), where the driver can actually see it.
  void expectInClearView(WidgetTester tester, LatLng point) {
    final onScreen = camera(tester).latLngToScreenPoint(point);
    final sheetTop = tester.getRect(find.textContaining('OpenFreeMap')).top;
    final width = tester.view.physicalSize.width;
    expect(onScreen.x, inInclusiveRange(0, width), reason: '$point x');
    expect(
      onScreen.y,
      inInclusiveRange(VoiceOpsSize.touchTarget, sheetTop),
      reason: '$point y',
    );
  }

  void showRoute(Map<String, Object?> json) {
    container.read(mapRouteProvider.notifier).show(MapRoute.fromJson(json));
    container.read(mapFocusProvider.notifier).frameRoute();
  }

  testWidgets('before a route: follows the live position, shows the vehicle', (
    tester,
  ) async {
    await pump(tester, const MapScreen());
    expect(find.text('Finding your location…'), findsOneWidget);
    expect(find.text('NO ROUTE YET'), findsOneWidget);
    expect(find.byType(PolylineLayer), findsNothing);
    expect(find.byType(PositionMarker), findsNothing);
    // Vehicle from GET /v1/driver/profile (faked).
    expect(find.text('Ada Obi'), findsOneWidget);
    expect(find.text('Motorbike'), findsOneWidget);
    expect(api.profileCalls, 1);

    location.emit(const LocationFix(_nearStops));
    await settle(tester);
    expect(find.text('Finding your location…'), findsNothing);
    expect(find.byType(PositionMarker), findsOneWidget);
    expectInClearView(tester, _nearStops);
    expect(camera(tester).zoom, VoiceOpsMap.followZoom);

    // A moving position, not a static pin.
    location.emit(const LocationFix(_furtherOn, heading: 90));
    await settle(tester);
    expectInClearView(tester, _furtherOn);
    expect(
      tester.widget<PositionMarker>(find.byType(PositionMarker)).heading,
      90,
    );
  });

  testWidgets(
    'a map_route draws the line, pins and trip card, and frames them',
    (tester) async {
      await pump(tester, const MapScreen());
      location.emit(const LocationFix(_nearStops));
      await settle(tester);

      showRoute(sampleMapRoute());
      await settle(tester);
      expect(find.byType(PolylineLayer), findsOneWidget);
      expect(find.byType(StopPin), findsNWidgets(2));
      expect(find.text('NEXT STOP · 4'), findsOneWidget);
      expect(find.text('Amara Johnson'), findsOneWidget);
      expect(find.text('14 Broad Street, Lagos Island'), findsOneWidget);
      expect(find.text('11 mins'), findsOneWidget);
      expect(find.text('3.2 km'), findsOneWidget);
      expect(find.text('via Victoria Bridge'), findsOneWidget);
      expect(find.text('Motorbike'), findsOneWidget);

      final route = MapRoute.fromJson(sampleMapRoute());
      for (final point in [...route.coordinates, _nearStops]) {
        expectInClearView(tester, point);
      }
      expect(camera(tester).zoom, lessThanOrEqualTo(VoiceOpsMap.maxFitZoom));

      // The camera stays on the route while the driver moves.
      final framed = camera(tester).center;
      location.emit(const LocationFix(_furtherOn));
      await settle(tester);
      expect(camera(tester).center, framed);

      // Tapping another pin shows that stop.
      await tester.tap(find.bySemanticsLabel('Stop 5, Tunde Bakare'));
      await settle(tester);
      expect(find.text('STOP · 5'), findsOneWidget);
      expect(find.text('Tunde Bakare'), findsOneWidget);

      // Folding the card leaves the headline.
      await tester.tap(find.text('Tunde Bakare'));
      await settle(tester);
      expect(find.text('Distance'), findsNothing);
      expect(find.text('Tunde Bakare'), findsOneWidget);
    },
  );

  testWidgets('a short phone folds the card so the route shows', (
    tester,
  ) async {
    await pump(tester, const MapScreen(), size: const Size(320, 568));
    location.emit(const LocationFix(_nearStops));
    await settle(tester);
    showRoute(sampleMapRoute());
    await settle(tester);
    expect(find.text('Amara Johnson'), findsOneWidget);
    expect(find.text('Distance'), findsNothing);
    for (final point in [
      ...MapRoute.fromJson(sampleMapRoute()).coordinates,
      _nearStops,
    ]) {
      expectInClearView(tester, point);
    }

    // The driver can still open the details.
    await tester.tap(find.text('Amara Johnson'));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('Motorbike'), findsOneWidget);
  });

  testWidgets('no road route: the stop pin stays, no line or trip stats', (
    tester,
  ) async {
    await pump(tester, const MapScreen());
    showRoute(noRoadMapRoute());
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(PolylineLayer), findsNothing);
    expect(find.byType(StopPin), findsOneWidget);
    expect(find.text('Amara Johnson'), findsOneWidget);
    expect(find.byKey(const Key('no-road-route')), findsOneWidget);
    expect(find.text('11 mins'), findsNothing);
    expect(find.text('Distance'), findsNothing);
    expectInClearView(
      tester,
      MapRoute.fromJson(noRoadMapRoute()).target!.point,
    );
    expect(camera(tester).zoom, VoiceOpsMap.maxFitZoom);
  });

  testWidgets('"where am I" follows the driver again; the route stays', (
    tester,
  ) async {
    await pump(tester, const MapScreen());
    location.emit(const LocationFix(_nearStops));
    await settle(tester);
    showRoute(sampleMapRoute());
    await settle(tester);

    container.read(mapFocusProvider.notifier).followDriver();
    await settle(tester);
    expectInClearView(tester, _nearStops);
    expect(camera(tester).zoom, VoiceOpsMap.followZoom);
    expect(find.byType(PolylineLayer), findsOneWidget);
    location.emit(const LocationFix(_furtherOn));
    await settle(tester);
    expectInClearView(tester, _furtherOn);

    // The recenter button frames the whole route again.
    await tester.tap(find.bySemanticsLabel('Show the whole route'));
    await settle(tester);
    expect(container.read(mapFocusProvider).target, MapFocusTarget.route);
    for (final point in [
      ...MapRoute.fromJson(sampleMapRoute()).coordinates,
      _furtherOn,
    ]) {
      expectInClearView(tester, point);
    }
  });

  testWidgets('a route that arrived before the map opened is framed on open', (
    tester,
  ) async {
    await pump(tester, const SizedBox.shrink());
    showRoute(sampleMapRoute());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildVoiceOpsTheme(),
          home: const Scaffold(body: MapScreen()),
        ),
      ),
    );
    await settle(tester);
    for (final stop in MapRoute.fromJson(sampleMapRoute()).stops) {
      expectInClearView(tester, stop.point);
    }
  });

  testWidgets('a location problem says what to do and fixes it', (
    tester,
  ) async {
    location.problem = LocationProblem.deniedForever;
    await pump(tester, const MapScreen());
    await settle(tester);
    expect(
      find.text(
        const LocationUnavailable(LocationProblem.deniedForever).message,
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Settings'));
    await settle(tester);
    expect(location.opened, [LocationProblem.deniedForever]);
    expect(location.watches, 2); // asked again after Settings
  });

  testWidgets('the vehicle card retries a failed profile load', (tester) async {
    api.profileFailure = const ApiException("Can't reach VoiceOps right now.");
    await pump(tester, const MapScreen());
    await settle(tester);
    expect(find.text("Couldn't load your vehicle"), findsOneWidget);
    api.profileFailure = null;
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(find.text('Motorbike'), findsOneWidget);
  });

  testWidgets('Settings shows the vehicle ("show my vehicle")', (tester) async {
    await pump(tester, const SettingsScreen());
    await settle(tester);
    final card = find.byKey(const Key('vehicle-card'));
    expect(
      find.descendant(of: card, matching: find.text('Ada Obi')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Motorbike')),
      findsOneWidget,
    );
  });
}
