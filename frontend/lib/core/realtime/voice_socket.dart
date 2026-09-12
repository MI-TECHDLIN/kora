import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// One open voice socket: JSON text frames and binary PCM16 audio frames
/// both ways (docs/contracts/interface.md §1). Only the voice session
/// provider opens one; widgets never do (frontend rules).
abstract interface class VoiceSocket {
  /// Completes when the upgrade succeeds; errors if it fails.
  Future<void> get ready;

  /// Incoming frames: [String] for events, `List<int>` for audio. Closes
  /// when the socket closes, after an error event if it failed.
  Stream<Object?> get frames;

  void sendText(String json);
  void sendAudio(Uint8List pcm);
  Future<void> close();
}

/// Opens a socket to [uri] with [headers] on the upgrade request.
typedef VoiceSocketConnector =
    VoiceSocket Function(Uri uri, Map<String, String> headers);

/// Tests override this with a fake so no socket leaves the machine.
final voiceSocketConnectorProvider = Provider<VoiceSocketConnector>(
  (ref) => WebSocketVoiceSocket.connect,
);

class WebSocketVoiceSocket implements VoiceSocket {
  WebSocketVoiceSocket._(this._channel);

  /// dart:io's client, because the contract puts the token in an
  /// `Authorization` header, which browser sockets can't set.
  static VoiceSocket connect(Uri uri, Map<String, String> headers) =>
      WebSocketVoiceSocket._(
        IOWebSocketChannel.connect(
          uri,
          headers: headers,
          connectTimeout: const Duration(seconds: 10),
          pingInterval: const Duration(seconds: 20),
        ),
      );

  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<Object?> get frames => _channel.stream;

  @override
  void sendText(String json) => _channel.sink.add(json);

  @override
  void sendAudio(Uint8List pcm) => _channel.sink.add(pcm);

  @override
  Future<void> close() async => _channel.sink.close();
}
