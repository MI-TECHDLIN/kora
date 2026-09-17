# Frontend Developer Guide: Voice Change Implementation

## Overview

This guide explains how to implement immediate voice changes in the Flutter frontend without requiring app restart. The backend now supports dynamic voice changes through WebSocket reconnection.

## Backend Changes Completed

### 1. WebSocket Endpoint
- **Path:** `WS /ws/voice/{shift_id}?voice={voice_id}`
- **Parameter:** `voice` (optional) - Co-rider voice ID
- **Allowlist:** `alba, eve, george, jane, jean, mary, michael, anna, charles, paul, vera`
- **Default:** `anna` if missing, empty, or unrecognized

### 2. New Client Event
- **Event:** `change_voice`
- **Shape:** `{"event": "change_voice", "voice": "michael"}`
- **Purpose:** Request voice change during active session

### 3. New Server Events
- **`voice_change_accepted`**: Voice change accepted, reconnection required
  ```json
  {
    "event": "voice_change_accepted",
    "voice": "michael",
    "message": "Voice will change to michael. Reconnecting..."
  }
  ```
- **`voice_unchanged`**: Voice already set to requested value
  ```json
  {
    "event": "voice_unchanged",
    "voice": "anna",
    "message": "Voice is already set to anna"
  }
  ```

## Frontend Implementation Steps

### Step 1: Update Voice Selection Handler

When the user selects a new voice in the settings UI, send a `change_voice` event instead of just storing the preference locally.

```dart
// In your voice selection handler
Future<void> onVoiceSelected(String newVoice) async {
  // Send voice change request to backend
  try {
    final voiceSocket = voiceSessionProvider.voiceSocket;
    if (voiceSocket != null) {
      await voiceSocket.send(json.encode({
        'event': 'change_voice',
        'voice': newVoice,
      }));
    }
  } catch (e) {
    // Handle error
    print('Failed to send voice change: $e');
  }
}
```

### Step 2: Handle Voice Change Events

Add handlers for the new server events in your WebSocket message processing.

```dart
// In your WebSocket message handler
void handleServerEvent(Map<String, dynamic> event) {
  final eventType = event['event'];
  
  switch (eventType) {
    case 'voice_change_accepted':
      _handleVoiceChangeAccepted(event);
      break;
    case 'voice_unchanged':
      _handleVoiceUnchanged(event);
      break;
    // ... existing event handlers
  }
}

void _handleVoiceChangeAccepted(Map<String, dynamic> event) {
  final newVoice = event['voice'] as String;
  final message = event['message'] as String;
  
  // Update local voice preference
  coRiderVoiceProvider.setVoice(newVoice);
  
  // Show confirmation to user
  showSnackBar(message);
  
  // Trigger reconnection with new voice
  _reconnectWithNewVoice(newVoice);
}

void _handleVoiceUnchanged(Map<String, dynamic> event) {
  final currentVoice = event['voice'] as String;
  final message = event['message'] as String;
  
  // Show info message to user
  showSnackBar(message);
}

void _reconnectWithNewVoice(String newVoice) async {
  // Close current WebSocket connection
  await voiceSessionProvider.disconnect();
  
  // Reconnect with new voice parameter
  await voiceSessionProvider.connect(
    shiftId: currentShiftId,
    voice: newVoice, // Pass the new voice parameter
  );
}
```

### Step 3: Update WebSocket Connection Method

Ensure your WebSocket connection method accepts and uses the voice parameter.

```dart
// In your voice session provider
Future<void> connect({
  required String shiftId,
  String? voice, // Add voice parameter
}) async {
  // Build WebSocket URI with voice parameter
  final uri = Uri.parse(
    '${backendConfig.voiceSocketUri}/$shiftId'
    '${voice != null ? '?voice=$voice' : ''}'
  );
  
  // Store current voice for reconnection
  _currentVoice = voice ?? 'anna';
  
  // Connect to WebSocket
  await _connectWebSocket(uri);
}
```

### Step 4: Update Voice Persistence

Ensure the selected voice is persisted locally and used for initial connections.

```dart
// In your co-rider voice provider
class CoRiderVoiceProvider extends ChangeNotifier {
  String _currentVoice = 'anna'; // Default voice
  
  String get currentVoice => _currentVoice;
  
  Future<void> loadVoicePreference() async {
    // Load from local storage
    final prefs = await SharedPreferences.getInstance();
    _currentVoice = prefs.getString('co_rider_voice') ?? 'anna';
    notifyListeners();
  }
  
  Future<void> setVoice(String voice) async {
    _currentVoice = voice;
    
    // Save to local storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('co_rider_voice', voice);
    
    notifyListeners();
  }
  
  // Get voice for WebSocket connection
  String get voiceForConnection => _currentVoice;
}
```

### Step 5: Update UI Feedback

Provide user feedback during voice changes.

```dart
// In your voice selection UI
ElevatedButton(
  onPressed: () async {
    setState(() => _isChangingVoice = true);
    
    await onVoiceSelected(selectedVoice);
    
    setState(() => _isChangingVoice = false);
  },
  child: _isChangingVoice
    ? CircularProgressIndicator()
    : Text('Apply Voice'),
)
```

## Implementation Checklist

- [ ] Update voice selection handler to send `change_voice` event
- [ ] Add handler for `voice_change_accepted` event
- [ ] Add handler for `voice_unchanged` event
- [ ] Implement reconnection logic with new voice parameter
- [ ] Update WebSocket connection to accept voice parameter
- [ ] Ensure voice preference is persisted locally
- [ ] Add UI feedback during voice change process
- [ ] Test voice change during active session
- [ ] Test voice change when no active session
- [ ] Test invalid voice IDs (should fall back to current)

## Testing Scenarios

### 1. Voice Change During Active Session
1. Start voice session with default voice (anna)
2. Open settings and select different voice (michael)
3. Verify `change_voice` event is sent
4. Verify `voice_change_accepted` event is received
5. Verify session reconnects with new voice
6. Verify new voice is used for subsequent responses

### 2. Voice Change When No Active Session
1. Ensure no active voice session
2. Open settings and select different voice
3. Verify voice preference is saved locally
4. Start new voice session
5. Verify new voice is used from connection start

### 3. Voice Unchanged
1. Start voice session with specific voice (michael)
2. Open settings and select same voice (michael)
3. Verify `voice_unchanged` event is received
4. Verify no reconnection occurs
5. Verify user sees appropriate message

### 4. Invalid Voice ID
1. Try to select invalid voice ID
2. Verify backend falls back to current voice
3. Verify `voice_unchanged` event is received
4. Verify session continues normally

## Error Handling

```dart
// Add error handling for voice change failures
void _handleVoiceChangeAccepted(Map<String, dynamic> event) {
  try {
    final newVoice = event['voice'] as String;
    
    // Validate voice against your local enum
    if (!CoRiderVoice.values.any((v) => v.name == newVoice)) {
      showSnackBar('Invalid voice received from server');
      return;
    }
    
    // Proceed with reconnection
    _reconnectWithNewVoice(newVoice);
    
  } catch (e) {
    showSnackBar('Failed to change voice: $e');
    // Optionally reconnect with current voice
    _reconnectWithCurrentVoice();
  }
}
```

## User Experience Flow

1. **User opens settings** → Sees current voice selection
2. **User selects new voice** → UI shows loading state
3. **Frontend sends `change_voice`** → Backend validates and processes
4. **Backend responds** → `voice_change_accepted` or `voice_unchanged`
5. **Frontend handles response** → Updates local preference
6. **If changed** → Frontend reconnects with new voice parameter
7. **New session starts** → Uses selected voice from connection start
8. **User hears new voice** → Change confirmed without app restart

## Notes

- Voice changes only take effect on new WebSocket connections
- The backend closes the current session to force reconnection
- The frontend should automatically reconnect with the new voice parameter
- Voice preference should be persisted locally for future sessions
- Invalid voice IDs fall back to the current voice silently
- The allowlist is enforced on both frontend and backend

## Backend Support

The backend handles:
- Voice validation against allowlist
- Session reconnection triggers
- Graceful fallback for invalid voices
- Appropriate event responses

The frontend needs to handle:
- Sending voice change requests
- Processing backend responses
- Managing reconnection flow
- Providing user feedback
- Persisting voice preferences