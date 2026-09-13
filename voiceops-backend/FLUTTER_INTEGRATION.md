# Flutter Integration Guide for VoiceOps WebSocket Voice Agent

## Overview

This guide shows how to integrate the VoiceOps WebSocket voice agent into your Flutter mobile application for real-time voice interaction.

## Prerequisites

- Flutter SDK (3.0+)
- Dart SDK
- Dependencies: `web_socket_channel`, `audio_waveforms`, `permission_handler`

## Dependencies

Add these to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # WebSocket communication
  web_socket_channel: ^2.4.0
  
  # Audio recording and playback
  audio_waveforms: ^1.0.0
  permission_handler: ^11.0.0
  
  # Base64 encoding
  convert: ^3.1.1
  
  # State management
  provider: ^6.0.0
```

## Implementation

### 1. Voice Agent Service

Create `lib/services/voice_agent_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:convert/convert.dart';
import 'package:audio_waveforms/audio_waveforms.dart';

class VoiceAgentService {
  late WebSocketChannel _channel;
  final String driverId;
  final String wsUrl;
  bool _isConnected = false;
  final StreamController<String> _messageController = StreamController<String>.broadcast();
  final StreamController<String> _transcriptController = StreamController<String>.broadcast();
  
  // Audio recording
  RecorderController? _recorderController;
  bool _isRecording = false;
  
  VoiceAgentService({
    required this.driverId,
    this.wsUrl = 'ws://localhost:8000/ws/voice-agent',
  });
  
  // Streams for UI to listen to
  Stream<String> get messages => _messageController.stream;
  Stream<String> get transcripts => _transcriptController.stream;
  bool get isConnected => _isConnected;
  bool get isRecording => _isRecording;
  
  Future<void> connect() async {
    try {
      final uri = Uri.parse('$wsUrl/$driverId');
      _channel = WebSocketChannel.connect(uri);
      
      _channel.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onError: (error) {
          print('WebSocket error: $error');
          _isConnected = false;
          _messageController.add('ERROR: $error');
        },
        onDone: () {
          print('WebSocket connection closed');
          _isConnected = false;
          _messageController.add('DISCONNECTED');
        },
      );
      
      _isConnected = true;
      print('Voice agent connected');
    } catch (e) {
      print('Connection error: $e');
      _isConnected = false;
      _messageController.add('CONNECTION_ERROR: $e');
    }
  }
  
  void _handleMessage(dynamic message) {
    try {
      if (message is String) {
        final data = json.decode(message);
        final messageType = data['type'];
        
        switch (messageType) {
          case 'session_ready':
            print('Session ready: ${data['session_id']}');
            _messageController.add('SESSION_READY');
            break;
            
          case 'assemblyai_ready':
            print('AssemblyAI connection ready');
            _messageController.add('ASSEMBLYAI_READY');
            break;
            
          case 'agent_audio':
            print('Received agent audio');
            _playAgentAudio(data['audio']);
            break;
            
          case 'agent_text':
            final text = data['text'];
            print('Agent: $text');
            _transcriptController.add('Agent: $text');
            _messageController.add('AGENT_RESPONSE: $text');
            break;
            
          case 'error':
            final error = data['message'];
            print('Error: $error');
            _messageController.add('ERROR: $error');
            break;
            
          case 'pong':
            print('Pong received');
            break;
            
          default:
            print('Unknown message type: $messageType');
        }
      }
    } catch (e) {
      print('Error handling message: $e');
    }
  }
  
  Future<void> _playAgentAudio(String audioBase64) async {
    try {
      // Decode base64 audio
      final audioBytes = base64.decode(audioBase64);
      
      // Play audio (you'll need to implement audio playback)
      // This depends on your audio playback library
      print('Playing ${audioBytes.length} bytes of audio');
      
      // Example using audio_waveforms:
      // await _playerController.startPlayerFromBytes(audioBytes);
      
    } catch (e) {
      print('Error playing audio: $e');
    }
  }
  
  Future<void> startRecording() async {
    try {
      // Request microphone permission
      // Permission handling code here
      
      _recorderController = RecorderController();
      await _recorderController.record();
      _isRecording = true;
      print('Recording started');
    } catch (e) {
      print('Error starting recording: $e');
    }
  }
  
  Future<void> stopRecording() async {
    if (_recorderController == null || !_isRecording) return;
    
    try {
      final audioBytes = await _recorderController.stop();
      _isRecording = false;
      
      if (audioBytes != null) {
        // Send audio to server
        await sendAudioChunk(audioBytes);
      }
    } catch (e) {
      print('Error stopping recording: $e');
    }
  }
  
  Future<void> sendAudioChunk(List<int> audioBytes) async {
    if (!_isConnected) {
      print('Not connected to voice agent');
      return;
    }
    
    try {
      final audioBase64 = base64.encode(audioBytes);
      final message = {
        'type': 'audio_chunk',
        'audio': audioBase64,
      };
      
      _channel.sink.add(json.encode(message));
      print('Audio chunk sent');
    } catch (e) {
      print('Error sending audio: $e');
    }
  }
  
  Future<void> sendText(String text) async {
    if (!_isConnected) {
      print('Not connected to voice agent');
      return;
    }
    
    try {
      final message = {
        'type': 'text_input',
        'text': text,
      };
      
      _channel.sink.add(json.encode(message));
      print('Text sent: $text');
    } catch (e) {
      print('Error sending text: $e');
    }
  }
  
  void sendPing() {
    if (_isConnected) {
      _channel.sink.add(json.encode({'type': 'ping'}));
    }
  }
  
  void disconnect() {
    _channel.sink.close();
    _isConnected = false;
    _messageController.close();
    _transcriptController.close();
    print('Voice agent disconnected');
  }
  
  void dispose() {
    disconnect();
    _recorderController?.dispose();
  }
}
```

### 2. Voice Interface Screen

Create `lib/screens/voice_interface_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/voice_agent_service.dart';

class VoiceInterfaceScreen extends StatefulWidget {
  final String driverId;
  
  const VoiceInterfaceScreen({
    Key? key,
    required this.driverId,
  }) : super(key: key);
  
  @override
  _VoiceInterfaceScreenState createState() => _VoiceInterfaceScreenState();
}

class _VoiceInterfaceScreenState extends State<VoiceInterfaceScreen> {
  late VoiceAgentService _voiceService;
  List<String> _transcripts = [];
  String _statusMessage = 'Connecting...';
  
  @override
  void initState() {
    super.initState();
    _voiceService = VoiceAgentService(driverId: widget.driverId);
    _initializeVoiceService();
  }
  
  Future<void> _initializeVoiceService() async {
    await _voiceService.connect();
    
    _voiceService.messages.listen((message) {
      setState(() {
        _statusMessage = message;
      });
    });
    
    _voiceService.transcripts.listen((transcript) {
      setState(() {
        _transcripts.add(transcript);
      });
    });
  }
  
  Future<void> _toggleRecording() async {
    if (_voiceService.isRecording) {
      await _voiceService.stopRecording();
    } else {
      await _voiceService.startRecording();
    }
    setState(() {});
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Voice Assistant'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              // Settings
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Status indicator
          Container(
            padding: EdgeInsets.all(16),
            color: _voiceService.isConnected ? Colors.green[100] : Colors.red[100],
            child: Row(
              children: [
                Icon(
                  _voiceService.isConnected ? Icons.wifi : Icons.wifi_off,
                  color: _voiceService.isConnected ? Colors.green : Colors.red,
                ),
                SizedBox(width: 8),
                Text(_statusMessage),
              ],
            ),
          ),
          
          // Transcript display
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: _transcripts.length,
              itemBuilder: (context, index) {
                final transcript = _transcripts[index];
                final isAgent = transcript.startsWith('Agent:');
                
                return Align(
                  alignment: isAgent ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: EdgeInsets.only(bottom: 8),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isAgent ? Colors.blue[100] : Colors.green[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(transcript),
                  ),
                );
              },
            ),
          ),
          
          // Recording controls
          Container(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                // Recording button
                GestureDetector(
                  onTap: _toggleRecording,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _voiceService.isRecording ? Colors.red : Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _voiceService.isRecording ? Icons.stop : Icons.mic,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  _voiceService.isRecording ? 'Tap to stop' : 'Tap to speak',
                  style: TextStyle(fontSize: 16),
                ),
                
                // Quick commands
                SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _QuickCommandButton(
                      label: 'Next Delivery',
                      onTap: () => _voiceService.sendText('What\'s my next delivery?'),
                    ),
                    _QuickCommandButton(
                      label: 'Fastest Route',
                      onTap: () => _voiceService.sendText('Get me the fastest route'),
                    ),
                    _QuickCommandButton(
                      label: 'Call Customer',
                      onTap: () => _voiceService.sendText('Call the customer'),
                    ),
                    _QuickCommandButton(
                      label: 'How am I doing?',
                      onTap: () => _voiceService.sendText('How am I doing?'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _voiceService.dispose();
    super.dispose();
  }
}

class _QuickCommandButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  
  const _QuickCommandButton({
    Key? key,
    required this.label,
    required this.onTap,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      child: Text(label),
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}
```

### 3. Integration in Main App

Update your `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'screens/voice_interface_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoiceOps Driver App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: VoiceInterfaceScreen(
        driverId: 'driver-123', // Replace with actual driver ID
      ),
    );
  }
}
```

## WebSocket Message Protocol

### Client → Server

```json
{
  "type": "audio_chunk",
  "audio": "base64_encoded_audio_data"
}
```

```json
{
  "type": "text_input", 
  "text": "user message"
}
```

```json
{
  "type": "ping"
}
```

### Server → Client

```json
{
  "type": "session_ready",
  "session_id": "ws_xxx",
  "driver_id": "driver-123"
}
```

```json
{
  "type": "assemblyai_ready",
  "session_id": "ws_xxx"
}
```

```json
{
  "type": "agent_audio",
  "audio": "base64_encoded_audio_data"
}
```

```json
{
  "type": "agent_text",
  "text": "Agent response"
}
```

```json
{
  "type": "error",
  "message": "Error message"
}
```

```json
{
  "type": "pong"
}
```

## Testing

1. **Backend must be running**: `uvicorn app.main:app --reload --port 8000`
2. **Update WebSocket URL**: Change `wsUrl` to your backend URL
3. **Handle permissions**: Add microphone permission handling
4. **Test with simulator**: Use Flutter DevTools for debugging

## Features

✅ **Real-time voice interaction** via WebSocket  
✅ **Persistent AssemblyAI session** for continuous conversation  
✅ **Audio streaming** with bidirectional communication  
✅ **Text fallback** for environments without audio  
✅ **Connection management** with auto-reconnection  
✅ **Transcript display** for conversation history  
✅ **Quick commands** for common driver actions  
✅ **Status indicators** for connection state  

## Production Considerations

1. **Security**: Use WSS (WebSocket Secure) in production
2. **Authentication**: Add JWT token to WebSocket connection
3. **Error Handling**: Implement robust reconnection logic
4. **Audio Quality**: Optimize audio compression and bandwidth
5. **Background Mode**: Handle app backgrounding properly
6. **Network Changes**: Handle network state changes gracefully

## Troubleshooting

**Connection fails:**
- Check backend server is running
- Verify WebSocket URL is correct
- Check network connectivity

**Audio not playing:**
- Verify audio permissions are granted
- Check audio format compatibility
- Test with simple audio files first

**High latency:**
- Check network conditions
- Optimize audio chunk size
- Consider audio compression

This implementation provides a solid foundation for real-time voice interaction in your VoiceOps Flutter app with the WebSocket endpoint we just created!