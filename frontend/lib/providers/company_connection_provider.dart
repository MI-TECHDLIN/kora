import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/voiceops_api.dart';

/// Where the driver's company link is remembered on this device. There is
/// no backend read for an existing `platform_connections` row yet, so the
/// app keeps what a successful `POST /v1/driver/connect` returned, per
/// driver so a shared phone never shows another driver's company.
abstract interface class CompanyConnectionStore {
  Future<PlatformConnection?> load(String driverId);
  Future<void> save(String driverId, PlatformConnection connection);
}

class SharedPreferencesCompanyConnectionStore
    implements CompanyConnectionStore {
  const SharedPreferencesCompanyConnectionStore();

  static String _key(String driverId) => 'company_connection_$driverId';

  @override
  Future<PlatformConnection?> load(String driverId) async {
    final raw = (await SharedPreferences.getInstance()).getString(
      _key(driverId),
    );
    if (raw == null) return null;
    try {
      if (jsonDecode(raw) case {
        'platform': final String platform,
        'connected_at': final Object? connectedAt,
      }) {
        return PlatformConnection(
          platform: platform,
          connectedAt: connectedAt is String
              ? DateTime.tryParse(connectedAt)
              : null,
        );
      }
    } on FormatException {
      // A corrupt entry reads as no link; the next connect overwrites it.
    }
    return null;
  }

  @override
  Future<void> save(String driverId, PlatformConnection connection) async {
    await (await SharedPreferences.getInstance()).setString(
      _key(driverId),
      jsonEncode({
        'platform': connection.platform,
        'connected_at': connection.connectedAt?.toIso8601String(),
      }),
    );
  }
}

final companyConnectionStoreProvider = Provider<CompanyConnectionStore>(
  (ref) => const SharedPreferencesCompanyConnectionStore(),
);

/// The company link remembered for [driverId]; null until they connect.
/// Invalidate it after saving a new link.
final companyConnectionProvider =
    FutureProvider.family<PlatformConnection?, String>(
      (ref, driverId) =>
          ref.watch(companyConnectionStoreProvider).load(driverId),
    );
