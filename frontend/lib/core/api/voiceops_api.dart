import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../features/auth/data/auth_repository.dart';
import '../../providers/auth_provider.dart';
import '../config/backend_config.dart';

/// The signed-in driver's `drivers` row, as `GET /v1/driver/profile` returns
/// it (docs/contracts/interface.md §2). Only the fields the app shows.
class DriverProfile {
  const DriverProfile({required this.id, this.name, this.vehicleType});

  factory DriverProfile.fromJson(Map<String, dynamic> json) => DriverProfile(
    id: json['id'] as String? ?? '',
    name: _blankToNull(json['name']),
    vehicleType: _blankToNull(json['vehicle_type']),
  );

  final String id;
  final String? name;

  /// Free text on the driver row (e.g. "Motorbike", "Van"); null until set.
  final String? vehicleType;
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
abstract interface class VoiceOpsApi {
  Future<DriverProfile> fetchDriverProfile();

  /// `POST /v1/shift/start`; returns the new shift's id.
  Future<String> startShift();

  /// `POST /v1/locations/ping`. This is what feeds the backend's proactive
  /// risk engine, which runs on every ping and is the only thing that can
  /// raise a `PROACTIVE_ALERT`.
  Future<void> sendLocationPing(LocationPing ping);
}

/// The backend base URL ([BackendConfig.baseUri]); null when unset.
final backendUriProvider = Provider<Uri?>((ref) => BackendConfig.baseUri);

final voiceOpsApiProvider = Provider<VoiceOpsApi>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return HttpVoiceOpsApi(
    baseUri: ref.watch(backendUriProvider),
    auth: ref.watch(authRepositoryProvider),
    client: client,
  );
});

class HttpVoiceOpsApi implements VoiceOpsApi {
  HttpVoiceOpsApi({
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
  Future<DriverProfile> fetchDriverProfile() async =>
      DriverProfile.fromJson(await _send('GET', 'v1/driver/profile'));

  @override
  Future<String> startShift() async {
    final shiftId = (await _send('POST', 'v1/shift/start'))['shift_id'];
    if (shiftId is! String || shiftId.isEmpty) {
      throw const ApiException(_serverMessage);
    }
    return shiftId;
  }

  @override
  Future<void> sendLocationPing(LocationPing ping) async =>
      _send('POST', 'v1/locations/ping', body: ping.toJson());

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
      throw const ApiException(_offlineMessage);
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
      "Can't reach VoiceOps right now. Check your connection and try again.";
  static const _serverMessage = 'VoiceOps had a problem. Try again.';
}
