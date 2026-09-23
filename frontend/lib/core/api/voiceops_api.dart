import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../features/auth/data/auth_repository.dart';
import '../../features/summary/data/shift_report.dart';
import '../../providers/auth_provider.dart';
import '../config/backend_config.dart';

/// The signed-in driver's `drivers` row, as `GET /v1/driver/profile` returns
/// it (docs/contracts/interface.md §2). Only the fields the app shows.
class DriverProfile {
  const DriverProfile({
    required this.id,
    this.name,
    this.vehicleType,
    this.phone,
    this.createdAt,
  });

  factory DriverProfile.fromJson(Map<String, dynamic> json) => DriverProfile(
    id: json['id'] as String? ?? '',
    name: _blankToNull(json['name']),
    vehicleType: _blankToNull(json['vehicle_type']),
    phone: _blankToNull(json['phone']),
    createdAt: switch (json['created_at']) {
      final String value => DateTime.tryParse(value),
      _ => null,
    },
  );

  final String id;
  final String? name;

  /// Free text on the driver row (e.g. "Motorbike", "Van"); null until set.
  final String? vehicleType;

  /// The sign-up number. Read-only in the app: it identifies the driver.
  final String? phone;

  /// When the driver row was created, i.e. when they joined Kora.
  final DateTime? createdAt;
}

/// The company link `POST /v1/driver/connect` created from a connect code.
/// The response carries the `platform_connections` row, which names the
/// platform but not the operator's company.
class PlatformConnection {
  const PlatformConnection({required this.platform, this.connectedAt});

  final String platform;
  final DateTime? connectedAt;
}

/// One GPS ping for `POST /v1/locations/ping`, in the units the backend's
/// `LocationPingRequest` validates: km/h, degrees, metres. Out-of-range
/// values are clamped here rather than rejected by the server as a 422.
class LocationPing {
  factory LocationPing({
    required double latitude,
    required double longitude,
    double speedKmh = 0,
    double heading = 0,
    double accuracyMetres = 0,
    String? shiftId,
  }) => LocationPing._(
    latitude: latitude.clamp(-90, 90).toDouble(),
    longitude: longitude.clamp(-180, 180).toDouble(),
    speedKmh: speedKmh.isFinite ? speedKmh.clamp(0, 300).toDouble() : 0,
    heading: heading.isFinite ? heading.clamp(0, 360).toDouble() : 0,
    accuracyMetres: accuracyMetres.isFinite && accuracyMetres > 0
        ? accuracyMetres
        : 0,
    shiftId: shiftId,
  );

  const LocationPing._({
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.heading,
    required this.accuracyMetres,
    required this.shiftId,
  });

  final double latitude;
  final double longitude;
  final double speedKmh;
  final double heading;
  final double accuracyMetres;

  /// The shift the ping belongs to; the backend falls back to the driver's
  /// current shift when it is absent.
  final String? shiftId;

  Map<String, Object?> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'speed': speedKmh,
    'heading': heading,
    'accuracy': accuracyMetres,
    if (shiftId != null) 'shift_id': shiftId,
  };
}

String? _blankToNull(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

/// A backend call failed. [message] is safe to show a driver.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// The backend REST endpoints the app uses (contract §2). Every call carries
/// the §4 `Authorization: Bearer` header.
abstract interface class KoraApi {
  /// `POST /v1/driver/ensure-profile`; idempotently creates the signed-in
  /// driver's `drivers` row on the backend if it doesn't exist yet. Safe to
  /// call repeatedly — on every sign-in and on session restore, not just
  /// once — since it always returns the row, new or existing.
  Future<DriverProfile> ensureDriverProfile();

  Future<DriverProfile> fetchDriverProfile();

  /// `PUT /v1/driver/profile` with a new name; returns the updated row.
  Future<DriverProfile> updateDriverName(String name);

  /// `POST /v1/driver/connect` with the connect code an operator gave the
  /// driver. A code the backend doesn't recognise throws [ApiException]
  /// with status 400.
  Future<PlatformConnection> connectWithCode(String code);

  /// `POST /v1/shift/start`; returns the new shift's id.
  Future<String> startShift();

  /// `POST /v1/shift/{shift_id}/end`. Marks the shift complete and triggers
  /// post-shift report generation. The voice tool `end_shift` is the
  /// primary way a driver reaches this; this method exists for a future
  /// UI affordance to call the same endpoint.
  Future<void> endShift(String shiftId);

  /// `POST /v1/locations/ping`. This is what feeds the backend's proactive
  /// risk engine, which runs on every ping and is the only thing that can
  /// raise a `PROACTIVE_ALERT`.
  Future<void> sendLocationPing(LocationPing ping);

  /// `GET /v1/shift/{shift_id}/report`; null while the report is still
  /// being generated (`{"status": "processing"}`).
  Future<ShiftReport?> fetchShiftReport(String shiftId);

  /// `GET /v1/driver/preferences`: every preference the driver has set, by
  /// either voice or this Settings screen, as raw stored strings (the same
  /// `driver_preferences` table `app/agents/tools/preferences.py` writes to).
  /// A key with no row set is simply absent.
  Future<Map<String, String>> fetchDriverPreferences();

  /// `PUT /v1/driver/preferences/{key}`. Voice tools write the exact same
  /// keys, so this is the one place either surface changes driver state.
  Future<void> setDriverPreference(String key, Object value);

  /// `DELETE /v1/driver/preferences/{key}`: back to "not set".
  Future<void> clearDriverPreference(String key);
}

/// The backend base URL ([BackendConfig.baseUri]); production by default.
final backendUriProvider = Provider<Uri?>((ref) => BackendConfig.baseUri);

final _koraHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final koraApiProvider = Provider<KoraApi>((ref) {
  return HttpKoraApi(
    baseUri: ref.watch(backendUriProvider),
    auth: ref.watch(authRepositoryProvider),
    client: ref.watch(_koraHttpClientProvider),
  );
});

class HttpKoraApi implements KoraApi {
  HttpKoraApi({
    required this.baseUri,
    required AuthRepository auth,
    required http.Client client,
  }) : _auth = auth,
       _client = client;

  final Uri? baseUri;
  final AuthRepository _auth;
  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

  @override
  Future<DriverProfile> ensureDriverProfile() async => DriverProfile.fromJson(
    await _send('POST', 'v1/driver/ensure-profile'),
  );

  @override
  Future<DriverProfile> fetchDriverProfile() async =>
      DriverProfile.fromJson(await _send('GET', 'v1/driver/profile'));

  @override
  Future<DriverProfile> updateDriverName(String name) async =>
      DriverProfile.fromJson(
        await _send('PUT', 'v1/driver/profile', body: {'name': name}),
      );

  @override
  Future<PlatformConnection> connectWithCode(String code) async {
    final Map<String, dynamic> response;
    try {
      response = await _send(
        'POST',
        'v1/driver/connect',
        // `platform` is required by the request model, but the backend
        // replaces it with the platform the code resolves to.
        body: {'platform': 'connect_code', 'connect_code': code},
      );
    } on ApiException catch (e) {
      if (e.statusCode != 400) rethrow;
      throw const ApiException(
        "That code didn't work. Check it with your dispatcher and try again.",
        statusCode: 400,
      );
    }
    final connection = response['connection'];
    final platform = connection is Map<String, dynamic>
        ? _blankToNull(connection['platform'])
        : null;
    if (connection is! Map<String, dynamic> || platform == null) {
      throw const ApiException(_serverMessage);
    }
    return PlatformConnection(
      platform: platform,
      connectedAt: switch (connection['connected_at']) {
        final String value => DateTime.tryParse(value),
        _ => null,
      },
    );
  }

  @override
  Future<String> startShift() async {
    final shiftId = (await _send('POST', 'v1/shift/start'))['shift_id'];
    if (shiftId is! String || shiftId.isEmpty) {
      throw const ApiException(_serverMessage);
    }
    return shiftId;
  }

  @override
  Future<void> endShift(String shiftId) async =>
      _send('POST', 'v1/shift/${Uri.encodeComponent(shiftId)}/end');

  @override
  Future<void> sendLocationPing(LocationPing ping) async =>
      _send('POST', 'v1/locations/ping', body: ping.toJson());

  @override
  Future<ShiftReport?> fetchShiftReport(String shiftId) async {
    final body = await _send(
      'GET',
      'v1/shift/${Uri.encodeComponent(shiftId)}/report',
    );
    if (body['status'] == 'processing') return null;
    return ShiftReport.fromJson(body);
  }

  @override
  Future<Map<String, String>> fetchDriverPreferences() async {
    final body = await _send('GET', 'v1/driver/preferences');
    if (body['preferences'] case final Map<String, dynamic> raw) {
      return raw.map((key, value) => MapEntry(key, value.toString()));
    }
    return const {};
  }

  @override
  Future<void> setDriverPreference(String key, Object value) async {
    await _send(
      'PUT',
      'v1/driver/preferences/${Uri.encodeComponent(key)}',
      body: {'value': value},
    );
  }

  @override
  Future<void> clearDriverPreference(String key) async {
    await _send('DELETE', 'v1/driver/preferences/${Uri.encodeComponent(key)}');
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final base = baseUri;
    if (base == null) {
      throw const ApiException(BackendConfig.notConfiguredMessage);
    }
    final token = _auth.accessToken;
    if (token == null) {
      throw const ApiException('Sign in again to continue.', statusCode: 401);
    }
    final http.Response response;
    try {
      final request = http.Request(method, restUri(base, path))
        ..headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      );
    } on TimeoutException {
      throw const ApiException(_timeoutMessage);
    } on http.ClientException {
      throw const ApiException(_offlineMessage);
    }
    if (response.statusCode == 401) {
      throw const ApiException('Sign in again to continue.', statusCode: 401);
    }
    if (response.statusCode != 200) {
      throw ApiException(_serverMessage, statusCode: response.statusCode);
    }
    try {
      if (jsonDecode(response.body) case final Map<String, dynamic> body) {
        return body;
      }
    } on FormatException {
      // Falls through to the same failure as a non-object body.
    }
    throw const ApiException(_serverMessage);
  }

  static const _offlineMessage =
      "Can't reach Kora right now. Check your connection and try again.";
  static const _timeoutMessage =
      'Kora is taking longer than usual. Try again in a moment.';
  static const _serverMessage = 'Kora had a problem. Try again.';
}
