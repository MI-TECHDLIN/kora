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

  Future<Map<String, dynamic>> _send(String method, String path) async {
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
