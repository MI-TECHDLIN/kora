import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:voiceops/core/api/voiceops_api.dart';
import 'package:voiceops/core/theme/tokens.dart';
import 'package:voiceops/features/map/data/location_source.dart';
import 'package:voiceops/features/map/data/map_route.dart';
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
  late FakeHeadingSource heading;
  late FakeVehicleModeStore vehicleModeStore;
  late FakeMapStyleStore mapStyleStore;
  late FakeCoRiderVoiceStore voiceStore;
  late FakeNotificationPreferencesStore notificationPreferencesStore;
  late FakeKoraApi api;
  late ProviderContainer container;

  setUp(() {
    location = FakeLocationSource();
    heading = FakeHeadingSource();
    vehicleModeStore = FakeVehicleModeStore();
    mapStyleStore = FakeMapStyleStore();
    voiceStore = FakeCoRiderVoiceStore();
    notificationPreferencesStore = FakeNotificationPreferencesStore();
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
          coRiderVoiceStore: voiceStore,
          api: api,
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

  MapCamera camera(WidgetTester tester) =>
      MapCamera.of(tester.element(find.byType(MarkerLayer).first));

  /// [point] is on screen, below the top controls and clear of the bottom
  /// route card, where the driver can actually see it.
  void expectInClearView(WidgetTester tester, LatLng point) {
    final onScreen = camera(tester).latLngToScreenPoint(point);
    final sheetTop = tester
        .getRect(find.byKey(const Key('map-bottom-sheet')))
        .top;
    final width = tester.view.physicalSize.width;
    expect(onScreen.x, inInclusiveRange(0, width), reason: '$point x');
    expect(
      onScreen.y,
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
    expect(find.byType(PolylineLayer), findsNothing);
    expect(find.byType(PositionMarker), findsNothing);
    expect(find.textContaining('OpenFreeMap'), findsNothing);
    // Vehicle from GET /v1/driver/profile (faked).
    expect(find.text('Ada Obi'), findsOneWidget);
    expect(find.text('Motorbike'), findsOneWidget);
    expect(api.profileCalls, 1);

    location.emit(const LocationFix(_nearStops));
    await settle(tester);
    expect(find.text('Finding your location…'), findsNothing);
    expect(find.byType(PositionMarker), findsOneWidget);
    expectInClearView(tester, _nearStops);
    expect(camera(tester).zoom, KoraMap.followZoom);

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
      expect(camera(tester).zoom, lessThanOrEqualTo(KoraMap.maxFitZoom));

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
    expect(camera(tester).zoom, KoraMap.maxFitZoom);
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
    expect(camera(tester).zoom, KoraMap.followZoom);
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

    container.invalidate(vehicleModeProvider);
    await settle(tester);
    expect(container.read(vehicleModeProvider), VehicleMode.bicycle);
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

  testWidgets('map dependencies warm before the Map tab is built', (
    tester,
  ) async {
    final requested = <MapStyle>[];
    final waiting = Completer<Style>();

    Future<Style> loadStyle(MapStyle style) {
      requested.add(style);
      return waiting.future;
    }

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
          openFreeMapStyleLoaderProvider.overrideWithValue(loadStyle),
        ],
        child: const MaterialApp(home: MapWarmup(child: Text('App started'))),
      ),
    );
    await tester.pump();

    expect(find.byType(MapScreen), findsNothing);
    expect(find.text('App started'), findsOneWidget);
    // The driver's saved style is the one warm when the Map tab opens.
    expect(requested.last, MapStyle.detailed);
    expect(location.watches, 1);
    expect(heading.watches, 1);
  });

  testWidgets('map style loading uses a skeleton and Retry reloads it', (
    tester,
  ) async {
    var attempts = 0;
    final waiting = Completer<Style>();

    Future<Style> loadStyle(MapStyle style) {
      attempts++;
      if (attempts == 1) return Future.error(StateError('offline'));
      return waiting.future;
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapStyleStoreProvider.overrideWithValue(mapStyleStore),
          openFreeMapStyleLoaderProvider.overrideWithValue(loadStyle),
        ],
        child: MaterialApp(
          theme: buildKoraTheme(),
          home: const Scaffold(body: OpenFreeMapLayer()),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    expect(attempts, 1);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(attempts, 2);
    expect(find.byKey(const Key('map-loading-skeleton')), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('the loading skeleton is painted in the chosen map palette', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        mapStyleStoreProvider.overrideWithValue(mapStyleStore),
        openFreeMapStyleLoaderProvider.overrideWithValue(
          (_) => Completer<Style>().future,
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OpenFreeMapLayer()),
      ),
    );
    await tester.pump();

    Color skeleton() => tester
        .widget<ColoredBox>(find.byKey(const Key('map-loading-skeleton')))
        .color;
    expect(skeleton(), KoraColors.mapGroundDark);

    container.read(mapStyleProvider.notifier).select(MapStyle.light);
    await tester.pump();
    // No dark placeholder flashing ahead of a light map.
    expect(skeleton(), KoraColors.mapGroundLight);
  });

  group('live tiles', () {
    late HttpServer server;
    late Style style;

    setUp(() async {
      // A real Style parsed from a tiny style served on loopback: nothing
      // leaves the machine, and tile loading stalls on the cache folder
      // below before any tile is requested.
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'version': 8,
              'sources': {
                'openmaptiles': {
                  'type': 'vector',
                  'tiles': [
                    'http://127.0.0.1:${server.port}/tiles/{z}/{x}/{y}.pbf',
                  ],
                },
              },
              'layers': [
                {
                  'id': 'background',
                  'type': 'background',
                  'paint': {'background-color': '#0c0c0c'},
                },
                {
                  'id': 'water',
                  'type': 'fill',
                  'source': 'openmaptiles',
                  'source-layer': 'water',
                  'paint': {'fill-color': '#1c2b3a'},
                },
              ],
            }),
          )
          ..close();
      });
      style = await HttpOverrides.runWithHttpOverrides(
        () => StyleReader(uri: 'http://127.0.0.1:${server.port}/style').read(),
        _RealHttp(),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) => Completer<Object?>().future,
          );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await server.close(force: true);
    });

    testWidgets('switching the map style swaps in a fresh tile layer', (
      tester,
    ) async {
      final requested = <MapStyle>[];
      final container = ProviderContainer(
        overrides: [
          mapStyleStoreProvider.overrideWithValue(mapStyleStore),
          openFreeMapStyleLoaderProvider.overrideWithValue((mapStyle) async {
            requested.add(mapStyle);
            return style;
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: FlutterMap(
              options: const MapOptions(
                initialCenter: MapScreen.fallbackCenter,
                initialZoom: KoraMap.followZoom,
              ),
              children: const [OpenFreeMapLayer()],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      VectorTileLayer layer() => tester.widget(find.byType(VectorTileLayer));
      Color ground() =>
          tester.widget<ColoredBox>(find.byKey(const Key('map-ground'))).color;

      expect(requested, [MapStyle.dark]);
      expect(layer().theme.id, openFreeMapThemeId(MapStyle.dark));
      expect(layer().layerMode, VectorTileLayerMode.raster);
      expect(ground(), KoraColors.mapGroundDark);
      // Under live tiles there is only the style's ground: no fake streets
      // to show through a tile that is still rendering.
      expect(find.byKey(const Key('map-loading-skeleton')), findsNothing);
      final darkTiles = tester.state(find.byType(TileLayer));

      container.read(mapStyleProvider.notifier).select(MapStyle.light);
      await tester.pump();
      await tester.pump();

      expect(requested, [MapStyle.dark, MapStyle.light]);
      expect(MapStyle.light.url, endsWith('/styles/positron'));
      expect(layer().theme.id, openFreeMapThemeId(MapStyle.light));
      expect(ground(), KoraColors.mapGroundLight);
      // A new tile layer, so no tile rendered in the dark style lingers.
      expect(tester.state(find.byType(TileLayer)), isNot(same(darkTiles)));

      // Unmount, then let vector_map_tiles' cache housekeeping timer run.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });
  });

  test('each map style has its own OpenFreeMap style and cache identity', () {
    expect(MapStyle.dark.url, 'https://tiles.openfreemap.org/styles/dark');
    expect(MapStyle.light.url, 'https://tiles.openfreemap.org/styles/positron');
    expect(
      MapStyle.detailed.url,
      'https://tiles.openfreemap.org/styles/liberty',
    );
    // vector_map_tiles keys its rendered-tile disk cache by theme id; every
    // OpenFreeMap style parses as "default", which would mix styles' tiles.
    final ids = MapStyle.values.map(openFreeMapThemeId).toSet();
    expect(ids, hasLength(MapStyle.values.length));
    expect(ids, isNot(contains('default')));
    // Raster mode: smooth pinch zoom (vector mode re-renders every frame).
    expect(openFreeMapLayerMode, VectorTileLayerMode.raster);
  });
}

class _RealHttp extends HttpOverrides {}
