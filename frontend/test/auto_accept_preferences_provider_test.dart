import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/api/voiceops_api.dart';
import 'package:voiceops/providers/auto_accept_preferences_provider.dart';

import 'fake_voice.dart';

/// The provider is the one source of truth voice tools and this Settings
/// screen both read/write (`app/agents/tools/preferences.py` and
/// `app/api/routes/preferences.py` share the same `driver_preferences` keys),
/// so every key and value shape here must match the backend exactly.
void main() {
  late FakeKoraApi api;
  late ProviderContainer container;

  setUp(() {
    api = FakeKoraApi();
    container = ProviderContainer(
      overrides: [koraApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
  });

  /// The constructor fires its own `reload()` in the background
  /// (`unawaited`). Awaiting one explicitly before a test drives writes
  /// settles that race deterministically, so a later assertion never catches
  /// the in-flight initial load clobbering a write made in the same tick.
  Future<AutoAcceptPreferencesController> controller() async {
    final notifier = container.read(autoAcceptPreferencesProvider.notifier);
    await notifier.reload();
    return notifier;
  }

  test('defaults to off with nothing set on the backend', () async {
    await controller();
    final prefs = container.read(autoAcceptPreferencesProvider);
    expect(prefs.enabled, isFalse);
    expect(prefs.maxDistanceKm, isNull);
    expect(prefs.zones, isEmpty);
    expect(prefs.acceptedCategories, isEmpty);
  });

  test('reload reads what voice already set on the backend', () async {
    api.preferences.addAll({
      'auto_accept_orders': 'true',
      'max_order_distance_km': '4.5',
      'geographic_zones': '[{"name":"Downtown","center_lat":30.1,"center_lng":-97.7,'
          '"radius_km":2.0,"zone_type":"preferred"}]',
      'order_type_prefs': '{"accepted_categories":["Food","Documents"]}',
    });

    await controller();

    final prefs = container.read(autoAcceptPreferencesProvider);
    expect(prefs.enabled, isTrue);
    expect(prefs.maxDistanceKm, 4.5);
    expect(prefs.zones, hasLength(1));
    expect(prefs.zones.single.name, 'Downtown');
    expect(prefs.zones.single.avoided, isFalse);
    expect(prefs.zones.single.radiusKm, 2.0);
    expect(prefs.acceptedCategories, ['Food', 'Documents']);
  });

  test('setEnabled writes the exact key voice uses', () async {
    final notifier = await controller();

    await notifier.setEnabled(true);
    expect(container.read(autoAcceptPreferencesProvider).enabled, isTrue);
    expect(api.preferenceWrites, [('auto_accept_orders', 'true')]);

    await notifier.setEnabled(false);
    expect(api.preferenceWrites.last, ('auto_accept_orders', 'false'));
  });

  test('setMaxDistanceKm writes and clears max_order_distance_km', () async {
    final notifier = await controller();

    await notifier.setMaxDistanceKm(3.0);
    expect(container.read(autoAcceptPreferencesProvider).maxDistanceKm, 3.0);
    expect(api.preferenceWrites, [('max_order_distance_km', '3.0')]);

    await notifier.setMaxDistanceKm(null);
    expect(container.read(autoAcceptPreferencesProvider).maxDistanceKm, isNull);
    expect(api.preferences.containsKey('max_order_distance_km'), isFalse);
  });

  test('addZone/removeZone round-trip through geographic_zones as GeoZone JSON', () async {
    final notifier = await controller();

    await notifier.addZone(const AutoAcceptZone(
      name: 'East Riverside',
      avoided: true,
      radiusKm: 1.5,
      centerLat: 30.25,
      centerLng: -97.73,
    ));

    final stored = api.preferences['geographic_zones'];
    expect(stored, isNotNull);
    expect(stored, contains('"zone_type":"avoided"'));
    expect(stored, contains('"name":"East Riverside"'));
    expect(container.read(autoAcceptPreferencesProvider).zones, hasLength(1));

    await notifier.removeZone('East Riverside');
    expect(container.read(autoAcceptPreferencesProvider).zones, isEmpty);
    expect(api.preferences.containsKey('geographic_zones'), isFalse); // cleared, not left dangling
  });

  test('addCategory/removeCategory round-trip through order_type_prefs', () async {
    final notifier = await controller();

    await notifier.addCategory('Food');
    await notifier.addCategory('Food'); // no duplicate

    expect(container.read(autoAcceptPreferencesProvider).acceptedCategories, ['Food']);
    expect(api.preferences['order_type_prefs'], '{"accepted_categories":["Food"]}');

    await notifier.removeCategory('Food');
    expect(container.read(autoAcceptPreferencesProvider).acceptedCategories, isEmpty);
    expect(api.preferences.containsKey('order_type_prefs'), isFalse);
  });

  test('a failed reload leaves auto-accept off rather than crashing', () async {
    api.preferencesFailure = const ApiException('offline');
    await controller();
    expect(container.read(autoAcceptPreferencesProvider).enabled, isFalse);
  });
}
