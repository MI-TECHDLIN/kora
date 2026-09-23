import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre;
import 'package:voiceops/core/api/voiceops_api.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/features/map/data/location_source.dart';
import 'package:voiceops/features/map/data/map_route.dart';
import 'package:voiceops/features/map/data/mercator.dart';
import 'package:voiceops/features/map/screens/map_screen.dart';
import 'package:voiceops/features/map/widgets/map_markers.dart';
import 'package:voiceops/features/map/widgets/map_warmup.dart';
import 'package:voiceops/features/map/widgets/openfreemap_layer.dart';
import 'package:voiceops/features/settings/screens/settings_screen.dart';
import 'package:voiceops/providers/auth_provider.dart';
import 'package:voiceops/providers/co_rider_voice_provider.dart';
import 'package:voiceops/providers/map_route_provider.dart';
import 'package:voiceops/providers/map_style_provider.dart';
import 'package:voiceops/providers/notification_preferences_provider.dart';
import 'package:voiceops/providers/vehicle_mode_provider.dart';
import 'package:voiceops/providers/wake_word_provider.dart';

import 'fake_auth.dart';
import 'fake_map_controller.dart';
import 'fake_voice.dart';
import 'map_route_test.dart' show noRoadMapRoute, sampleMapRoute;
import 'test_fonts.dart';

/// Near the sample route's stops on Lagos Island.
const _nearStops = LatLng(6.4600, 3.3900);
const _furtherOn = LatLng(6.4620, 3.3920);

void main() {
  setUpAll(disableGoogleFontsFetching);

  late FakeLocationSource location;
  late FakeHeadingSource heading;
  late FakeVehicleModeStore vehicleModeStore;
  late FakeMapStyleStore mapStyleStore;
  late FakeCoRiderVoiceStore voiceStore;
  late FakeNotificationPreferencesStore notificationPreferencesStore;
  late FakeWakeWordPreferencesStore wakeWordPreferencesStore;
  late FakeKoraApi api;
  late ProviderContainer container;
  late FakeKoraMapController mapController;

  setUp(() {
    location = FakeLocationSource();
    heading = FakeHeadingSource();
    vehicleModeStore = FakeVehicleModeStore();
    mapStyleStore = FakeMapStyleStore();
    voiceStore = FakeCoRiderVoiceStore();
    notificationPreferencesStore = FakeNotificationPreferencesStore();
    wakeWordPreferencesStore = FakeWakeWordPreferencesStore();
    api = FakeKoraApi(
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
        ...offlineOverrides(
          location: location,
          heading: heading,
          vehicleModeStore: vehicleModeStore,
          mapStyleStore: mapStyleStore,
          notificationPreferencesStore: notificationPreferencesStore,
          wakeWordPreferencesStore: wakeWordPreferencesStore,
          coRiderVoiceStore: voiceStore,
          api: api,
          onMapControllerCreated: (c) => mapController = c,
        ),
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
          theme: buildKoraTheme(),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pump();
  }

  /// Lets the card finish resizing and the camera re-frame after it.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(KoraMotion.slow);
    await tester.pump();
  }

  /// Where [point] renders given the map's current camera -- MapLibre draws
  /// the camera on the platform side, invisible to the widget tree, so this
  /// uses the same projection map_screen.dart itself uses to place markers
  /// (mercator.dart), fed by the fake controller's recorded camera state.
  Offset screenPoint(WidgetTester tester, LatLng point) {
    final camera = mapController.cameraPosition!;
    return MercatorProjection.project(
      point,
      center: LatLng(camera.target.latitude, camera.target.longitude),
      zoom: camera.zoom,
      viewportSize: tester.view.physicalSize / tester.view.devicePixelRatio,
    );
  }

  /// [point] is on screen, below the top controls and clear of the bottom
  /// route card, where the driver can actually see it.
  void expectInClearView(WidgetTester tester, LatLng point) {
    final onScreen = screenPoint(tester, point);
    final sheetTop = tester
        .getRect(find.byKey(const Key('map-bottom-sheet')))
        .top;
    final width = tester.view.physicalSize.width;
    expect(onScreen.dx, inInclusiveRange(0, width), reason: '$point x');
    expect(
      onScreen.dy,
      inInclusiveRange(KoraSize.touchTarget, sheetTop),
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
    expect(mapController.routeLine, isNull);
    expect(find.byType(PositionMarker), findsNothing);
    // Vehicle from GET /v1/driver/profile (faked).
    expect(find.text('Ada Obi'), findsOneWidget);
    expect(find.text('Motorbike'), findsOneWidget);
    expect(api.profileCalls, 1);

    location.emit(const LocationFix(_nearStops));
    await settle(tester);
    expect(find.text('Finding your location…'), findsNothing);
    expect(find.byType(PositionMarker), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(PositionMarker),
        matching: find.byType(AnimatedPositioned),
      ),
      findsOneWidget,
    );
    expectInClearView(tester, _nearStops);
    expect(mapController.cameraPosition!.zoom, KoraMap.followZoom);
    expect(mapController.cameraDurations.last, KoraMotion.followCamera);

    // A moving position, not a static pin.
    location.emit(const LocationFix(_furtherOn, heading: 90));
    await settle(tester);
    expectInClearView(tester, _furtherOn);
    expect(
      tester.widget<PositionMarker>(find.byType(PositionMarker)).heading,
      90,
    );

    // Turning the phone while stopped updates the marker independently of
    // the GPS course.
    heading.emit(225);
    await settle(tester);
    expect(
      tester.widget<PositionMarker>(find.byType(PositionMarker)).heading,
      225,
    );

    container.read(vehicleModeProvider.notifier).select(VehicleMode.bicycle);
    await settle(tester);
    expect(
      tester.widget<PositionMarker>(find.byType(PositionMarker)).vehicleMode,
      VehicleMode.bicycle,
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
      expect(mapController.routeLine, isNotNull);
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
      expect(
        mapController.cameraPosition!.zoom,
        lessThanOrEqualTo(KoraMap.maxFitZoom),
      );
      expect(mapController.cameraDurations.last, KoraMotion.routeCamera);

      // The camera stays on the route while the driver moves.
      final framed = mapController.cameraPosition!.target;
      location.emit(const LocationFix(_furtherOn));
      await settle(tester);
      expect(mapController.cameraPosition!.target, framed);

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

  testWidgets('pins glide to their new projection as the camera moves', (
    tester,
  ) async {
    await pump(tester, const MapScreen());
    showRoute(sampleMapRoute());
    await settle(tester);

    final route = MapRoute.fromJson(sampleMapRoute());
    final pin = find.byType(StopPin).first;
    final start = tester.getCenter(pin);
    final camera = mapController.cameraPosition!;
    await mapController.animateCamera(
      maplibre.CameraUpdate.newLatLngZoom(
        maplibre.LatLng(
          camera.target.latitude,
          camera.target.longitude + 0.002,
        ),
        camera.zoom,
      ),
      duration: KoraMotion.followCamera,
    );
    await tester.pump();

    // AnimatedPositioned retains the rendered location on the first frame,
    // advances through an in-between projection, then lands exactly on the
    // projection for the new native camera position.
    expect(tester.getCenter(pin), start);
    await tester.pump(
      Duration(milliseconds: KoraMotion.markerGlide.inMilliseconds ~/ 2),
    );
    final midway = tester.getCenter(pin);
    final destination = screenPoint(tester, route.stops.first.point);
    expect(
      (midway - destination).distance,
      lessThan((start - destination).distance),
    );
    expect((midway - destination).distance, greaterThan(0.1));

    await tester.pump(KoraMotion.markerGlide);
    expect(tester.getCenter(pin).dx, closeTo(destination.dx, 0.01));
    expect(tester.getCenter(pin).dy, closeTo(destination.dy, 0.01));
  });

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
    expect(mapController.routeLine, isNull);
    expect(find.byType(StopPin), findsOneWidget);
    expect(find.text('Amara Johnson'), findsOneWidget);
    expect(find.byKey(const Key('no-road-route')), findsOneWidget);
    expect(find.text('11 mins'), findsNothing);
    expect(find.text('Distance'), findsNothing);
    expectInClearView(
      tester,
      MapRoute.fromJson(noRoadMapRoute()).target!.point,
    );
    expect(mapController.cameraPosition!.zoom, KoraMap.maxFitZoom);
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
    expect(mapController.cameraPosition!.zoom, KoraMap.followZoom);
    expect(mapController.routeLine, isNotNull);
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
          theme: buildKoraTheme(),
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

  testWidgets('a driver who skipped location in onboarding can allow it', (
    tester,
  ) async {
    location.problem = LocationProblem.denied;
    await pump(tester, const MapScreen());
    await settle(tester);
    expect(location.permissionRequests, 0); // the map never asks by itself
    expect(
      find.text(const LocationUnavailable(LocationProblem.denied).message),
      findsOneWidget,
    );
    await tester.tap(find.text('Allow'));
    await settle(tester);
    expect(location.permissionRequests, 1);
    expect(location.opened, isEmpty);
    expect(location.watches, 2); // started again once allowed
  });

  testWidgets('the vehicle card retries a failed profile load', (tester) async {
    api.profileFailure = const ApiException("Can't reach Kora right now.");
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
    expect(find.byKey(const Key('map-source-credit')), findsOneWidget);
    expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);
    expect(find.byKey(const Key('vehicle-mode-selector')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Bicycle'));
    await settle(tester);
    expect(container.read(vehicleModeProvider), VehicleMode.bicycle);
    expect(vehicleModeStore.value, VehicleMode.bicycle);
    // The backend times ETAs from the stored vehicle, so the pick is synced.
    expect(api.vehicleUpdates, ['bicycle']);

    container.invalidate(vehicleModeProvider);
    await settle(tester);
    expect(container.read(vehicleModeProvider), VehicleMode.bicycle);
  });

  testWidgets('the driver can pick walking in Settings', (tester) async {
    await pump(tester, const SettingsScreen());
    await settle(tester);

    await tester.tap(find.bySemanticsLabel('Walking'));
    await settle(tester);
    expect(container.read(vehicleModeProvider), VehicleMode.walking);
    expect(vehicleModeStore.value, VehicleMode.walking);
    expect(api.vehicleUpdates, ['walking']);
  });

  test('fromProfile recognises walking and its common spellings', () {
    for (final text in ['walking', 'Walk', 'on foot', 'FOOT', 'Pedestrian']) {
      expect(VehicleMode.fromProfile(text), VehicleMode.walking, reason: text);
    }
    expect(VehicleMode.fromProfile('Motorbike'), VehicleMode.motorbike);
    expect(VehicleMode.fromProfile('Bicycle'), VehicleMode.bicycle);
    expect(VehicleMode.fromProfile('Sedan'), VehicleMode.car);
    expect(VehicleMode.fromProfile(null), VehicleMode.car);
  });

  testWidgets('the driver picks the map style in Settings', (tester) async {
    await pump(tester, const SettingsScreen());
    await settle(tester);
    expect(find.byKey(const Key('map-style-selector')), findsOneWidget);
    // Dark-mode-first until the driver says otherwise.
    expect(container.read(mapStyleProvider), MapStyle.dark);

    await tester.tap(find.bySemanticsLabel('Light'));
    await settle(tester);
    expect(container.read(mapStyleProvider), MapStyle.light);
    expect(mapStyleStore.value, MapStyle.light);

    container.invalidate(mapStyleProvider);
    await settle(tester);
    expect(container.read(mapStyleProvider), MapStyle.light);
  });

  testWidgets('the driver picks the co-rider voice in Settings', (
    tester,
  ) async {
    await pump(tester, const SettingsScreen());
    await settle(tester);
    expect(find.byKey(const Key('co-rider-voice-selector')), findsOneWidget);
    expect(find.text('Your co-rider speaks as Anna.'), findsOneWidget);
    // Nothing saved: Anna, matching the backend's default.
    expect(container.read(coRiderVoiceProvider), CoRiderVoice.anna);

    final michael = find.bySemanticsLabel('Michael');
    await tester.ensureVisible(michael);
    await tester.tap(michael);
    await settle(tester);
    // Only a draft until Save.
    expect(container.read(coRiderVoiceProvider), CoRiderVoice.anna);
    expect(voiceStore.value, isNull);
    final save = find.byKey(const Key('co-rider-voice-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await settle(tester);
    expect(container.read(coRiderVoiceProvider), CoRiderVoice.michael);
    expect(voiceStore.value, CoRiderVoice.michael);

    container.invalidate(coRiderVoiceProvider);
    await settle(tester);
    expect(container.read(coRiderVoiceProvider), CoRiderVoice.michael);
  });

  testWidgets('notification toggles persist the driver choices', (
    tester,
  ) async {
    await pump(tester, const SettingsScreen());
    await settle(tester);

    expect(find.byKey(const Key('notification-preferences')), findsOneWidget);
    expect(
      container.read(notificationPreferencesProvider).proactiveAlertsEnabled,
      isTrue,
    );
    expect(
      container.read(notificationPreferencesProvider).shiftSummaryReadyEnabled,
      isTrue,
    );

    final proactiveAlerts = find.descendant(
      of: find.byKey(const Key('proactive-alerts-toggle')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(proactiveAlerts);
    await tester.tap(proactiveAlerts);
    final shiftSummary = find.descendant(
      of: find.byKey(const Key('shift-summary-ready-toggle')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(shiftSummary);
    await tester.tap(shiftSummary);
    await settle(tester);

    expect(notificationPreferencesStore.value.proactiveAlertsEnabled, isFalse);
    expect(
      notificationPreferencesStore.value.shiftSummaryReadyEnabled,
      isFalse,
    );

    container.invalidate(notificationPreferencesProvider);
    await settle(tester);
    final restored = container.read(notificationPreferencesProvider);
    expect(restored.proactiveAlertsEnabled, isFalse);
    expect(restored.shiftSummaryReadyEnabled, isFalse);
  });

  testWidgets('wake-word switch persists the driver choice', (tester) async {
    await pump(tester, const SettingsScreen());
    await settle(tester);

    final wakeWord = find.descendant(
      of: find.byKey(const Key('wake-word-toggle')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(wakeWord);
    await tester.tap(wakeWord);
    await settle(tester);

    expect(wakeWordPreferencesStore.enabled, isFalse);
    container.invalidate(wakeWordEnabledProvider);
    await settle(tester);
    expect(container.read(wakeWordEnabledProvider), isFalse);
  });

  testWidgets('map dependencies warm before the Map tab is built', (
    tester,
  ) async {
    mapStyleStore.value = MapStyle.detailed;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...offlineOverrides(
            location: location,
            heading: heading,
            vehicleModeStore: vehicleModeStore,
            mapStyleStore: mapStyleStore,
            api: api,
          ),
        ],
        child: const MaterialApp(home: MapWarmup(child: Text('App started'))),
      ),
    );
    await tester.pump();

    expect(find.byType(MapScreen), findsNothing);
    expect(find.text('App started'), findsOneWidget);
    expect(location.watches, 1);
    expect(heading.watches, 1);
  });

  testWidgets('the loading skeleton is painted in the chosen map palette', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: MapLoadingSkeleton(style: MapStyle.dark)),
    );
    Color skeleton() => tester
        .widget<ColoredBox>(find.byKey(const Key('map-loading-skeleton')))
        .color;
    expect(skeleton(), KoraColors.mapGroundDark);

    await tester.pumpWidget(
      const MaterialApp(home: MapLoadingSkeleton(style: MapStyle.light)),
    );
    expect(skeleton(), KoraColors.mapGroundLight);
  });

  test('each map style has its own OpenFreeMap style URL', () {
    expect(MapStyle.dark.url, 'https://tiles.openfreemap.org/styles/dark');
    expect(MapStyle.light.url, 'https://tiles.openfreemap.org/styles/positron');
    expect(
      MapStyle.detailed.url,
      'https://tiles.openfreemap.org/styles/liberty',
    );
  });
}
