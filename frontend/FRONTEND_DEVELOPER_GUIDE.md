# Frontend Developer Guide - Local & Production Testing

## Overview
This guide helps frontend developers test the VoiceOps Flutter app with both local and production backend deployments.

---

## Backend Deployments

### Production Backend
- **URL:** https://voiceops-ll41.onrender.com
- **Status:** Live and deployed
- **Environment:** Production
- **Health Check:** https://voiceops-ll41.onrender.com/health

### Local Backend
- **URL:** http://localhost:8000
- **Status:** Runs on your machine
- **Environment:** Development
- **Health Check:** http://localhost:8000/health

---

## Quick Start Commands

### Local Development
```bash
# Start local backend
cd voiceops-backend/voiceops-backend
$env:TOMTOM_API_KEY="your_key"
uvicorn app.main:app --reload

# Run Flutter app with local backend
cd frontend
flutter run --dart-define=VOICEOPS_API_URL=http://localhost:8000
```

### Production Testing
```bash
# Run Flutter app with production backend
cd frontend
flutter run --dart-define=VOICEOPS_API_URL=https://voiceops-ll41.onrender.com
```

---

## Configuration Methods

### Method 1: Command Line (Recommended for Testing)

#### Local Backend:
```bash
flutter run --dart-define=VOICEOPS_API_URL=http://localhost:8000
```

#### Production Backend:
```bash
flutter run --dart-define=VOICEOPS_API_URL=https://voiceops-ll41.onrender.com
```

#### With Emulator/Simulator:
```bash
# Android
flutter run --dart-define=VOICEOPS_API_URL=http://localhost:8000 -d emulator-5554

# iOS
flutter run --dart-define=VOICEOPS_API_URL=http://localhost:8000 -d iPhone-14

# Specific device
flutter devices
flutter run --dart-define=VOICEOPS_API_URL=http://localhost:8000 -d <device-id>
```

---

### Method 2: Configuration File (Recommended for Development)

#### Create/Edit `config/backend.local.json`:
```json
{
  "VOICEOPS_API_URL": "http://localhost:8000"
}
```

#### Create/Edit `config/backend.prod.json`:
```json
{
  "VOICEOPS_API_URL": "https://voiceops-ll41.onrender.com"
}
```

#### Run with config file:
```bash
# Local
flutter run --dart-define-from-file=config/backend.local.json

# Production
flutter run --dart-define-from-file=config/backend.prod.json
```

---

### Method 3: Environment Variables (CI/CD)

```bash
export VOICEOPS_API_URL=http://localhost:8000
flutter run
```

---

## Backend Configuration Updates

### Backend Settings (`app/config.py`)

The backend now supports environment-based configuration:

```python
# Environment variable
ENVIRONMENT=development  # or production

# Backend automatically selects appropriate URL
- Development: http://localhost:8000
- Production: https://voiceops-ll41.onrender.com
```

### Frontend Settings (`lib/core/config/backend_config.dart`)

The frontend now has helper methods:

```dart
// Get appropriate URL based on dart-define
static String get effectiveUrl => isConfigured ? url : localUrl;

// Get base URI for current environment
static Uri? getEffectiveBaseUri() {
  final urlString = effectiveUrl;
  return urlString.isNotEmpty ? Uri.parse(urlString) : null;
}
```

---

## Testing Scenarios

### Scenario 1: Development with Local Backend

**Use Case:** Developing new features with fast iteration

**Steps:**
1. Start local backend:
   ```bash
   cd voiceops-backend/voiceops-backend
   uvicorn app.main:app --reload
   ```

2. Run Flutter with local backend:
   ```bash
   cd frontend
   flutter run --dart-define=VOICEOPS_API_URL=http://localhost:8000
   ```

3. Test features with hot reload

**Advantages:**
- Fast iteration
- Easy debugging
- No network latency
- Full control over backend state

---

### Scenario 2: Testing with Production Backend

**Use Case:** Testing against real data and production configuration

**Steps:**
1. Ensure production backend is running (already deployed)

2. Run Flutter with production backend:
   ```bash
   cd frontend
   flutter run --dart-define=VOICEOPS_API_URL=https://voiceops-ll41.onrender.com
   ```

3. Test with real production data

**Advantages:**
- Real production environment
- Actual data and configuration
- Production-like performance
- End-to-end testing

---

### Scenario 3: Device Testing with Production Backend

**Use Case:** Testing on physical device with production backend

**Steps:**
1. Connect physical device via USB

2. Run Flutter with production backend:
   ```bash
   cd frontend
   flutter run --dart-define=VOICEOPS_API_URL=https://voiceops-ll41.onrender.com
   ```

3. Test with real GPS and network conditions

**Advantages:**
- Real device performance
- Actual GPS accuracy
- Real network conditions
- Production-like user experience

---

### Scenario 4: A/B Testing Both Environments

**Use Case:** Compare local vs production behavior

**Steps:**
1. Test with local backend first
2. Note results
3. Test with production backend
4. Compare results

**Use Cases:**
- Debugging environment-specific issues
- Performance comparison
- Data validation
- Configuration verification

---

## API Endpoints Reference

### Production Base URL
```
https://voiceops-ll41.onrender.com
```

### Local Base URL
```
http://localhost:8000
```

### Key Endpoints

#### Health Check
- **Production:** https://voiceops-ll41.onrender.com/health
- **Local:** http://localhost:8000/health

#### REST API
- **Production:** https://voiceops-ll41.onrender.com/v1/*
- **Local:** http://localhost:8000/v1/*

#### WebSocket (Voice)
- **Production:** wss://voiceops-ll41.onrender.com/ws/voice/{shift_id}
- **Local:** ws://localhost:8000/ws/voice/{shift_id}

---

## Flutter Configuration File Management

### Create Config Directory Structure
```
frontend/
├── config/
│   ├── backend.local.json.example  # Template for local
│   ├── backend.prod.json.example   # Template for production
│   ├── backend.local.json           # Your local config (gitignored)
│   └── backend.prod.json            # Your production config (gitignored)
```

### Example Config Files

#### `config/backend.local.json.example`
```json
{
  "VOICEOPS_API_URL": "http://localhost:8000",
  "SUPABASE_URL": "https://your-project.supabase.co",
  "SUPABASE_ANON_KEY": "your-anon-key"
}
```

#### `config/backend.prod.json.example`
```json
{
  "VOICEOPS_API_URL": "https://voiceops-ll41.onrender.com",
  "SUPABASE_URL": "https://your-project.supabase.co",
  "SUPABASE_ANON_KEY": "your-anon-key"
}
```

---

## VS Code Launch Configuration

### Create `.vscode/launch.json`
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Flutter (Local Backend)",
      "request": "launch",
      "type": "dart",
      "flutterMode": "debug",
      "args": [
        "--dart-define=VOICEOPS_API_URL=http://localhost:8000"
      ]
    },
    {
      "name": "Flutter (Production Backend)",
      "request": "launch",
      "type": "dart",
      "flutterMode": "debug",
      "args": [
        "--dart-define=VOICEOPS_API_URL=https://voiceops-ll41.onrender.com"
      ]
    }
  ]
}
```

---

## Hot Reload Switching

### Switch Between Local and Production Without Restart

1. **Start with local backend:**
   ```bash
   flutter run --dart-define=VOICEOPS_API_URL=http://localhost:8000
   ```

2. **Make changes, press `r` for hot reload**

3. **To switch to production:**
   - Stop the app (`q`)
   - Restart with production URL:
     ```bash
     flutter run --dart-define=VOICEOPS_API_URL=https://voiceops-ll41.onrender.com
     ```

**Note:** Dart-define values are compile-time constants, so you need to restart to change them.

---

## Debugging Tips

### Check Which Backend is Connected

Add this debug print in your Flutter code:
```dart
import 'package:voiceops/core/config/backend_config.dart';

void main() {
  print('Backend URL: ${BackendConfig.effectiveUrl}');
  print('Base URI: ${BackendConfig.getEffectiveBaseUri()}');
  print('Is Configured: ${BackendConfig.isConfigured}');
  
  runApp(MyApp());
}
```

### Network Debugging

Use Flutter DevTools to inspect network requests:
```bash
flutter pub global activate devtools
flutter pub global run devtools
```

### Backend Health Check

Add health check button in Flutter app:
```dart
ElevatedButton(
  onPressed: () async {
    final response = await http.get(Uri.parse('${BackendConfig.effectiveUrl}/health'));
    print('Health check: ${response.body}');
  },
  child: Text('Check Backend Health'),
)
```

---

## Common Issues and Solutions

### Issue: CORS Errors

**Symptom:** Network requests fail with CORS errors

**Solution:**
- Local backend: Already allows all origins (`*`)
- Production backend: Check Render environment variables
- Ensure backend is running

### Issue: WebSocket Connection Fails

**Symptom:** Voice agent won't connect

**Solution:**
- Check backend URL is correct
- Ensure backend is running
- Check firewall settings
- Verify WebSocket protocol (ws vs wss)

### Issue: "Backend not configured" Error

**Symptom:** App shows backend not configured message

**Solution:**
- Ensure VOICEOPS_API_URL is set
- Check dart-define syntax
- Verify config file is being used

### Issue: Different Data Between Local and Production

**Symptom:** Behavior differs between environments

**Solution:**
- Check environment variables in both backends
- Verify database connections
- Check API keys are the same
- Review configuration differences

---

## Performance Comparison

### Local Backend
- **Latency:** ~0-5ms (localhost)
- **Bandwidth:** Unlimited
- **Reliability:** 100% (if running)
- **Best For:** Development, debugging

### Production Backend
- **Latency:** ~50-200ms (network)
- **Bandwidth:** Render limits
- **Reliability:** 99.9% (Render SLA)
- **Best For:** Production testing, end-to-end validation

---

## Deployment Checklist

### Before Testing with Production Backend
- [ ] Production backend is running and healthy
- [ ] All environment variables configured in Render
- [ ] Database is accessible
- [ ] API keys are valid
- [ ] Health endpoint returns `"status": "ok"`

### Before Testing with Local Backend
- [ ] Local backend is running on port 8000
- [ ] Database connection is configured
- [ ] Required environment variables set
- [ ] Health endpoint returns `"status": "ok"`

---

## Summary

### Quick Reference

| Environment | URL | Command |
|-------------|-----|---------|
| Local | http://localhost:8000 | `flutter run --dart-define=VOICEOPS_API_URL=http://localhost:8000` |
| Production | https://voiceops-ll41.onrender.com | `flutter run --dart-define=VOICEOPS_API_URL=https://voiceops-ll41.onrender.com` |

### Key Points
- **Local:** Fast iteration, easy debugging
- **Production:** Real environment, actual data
- **Switching:** Requires app restart (dart-define is compile-time)
- **Configuration:** Multiple methods available (CLI, file, env vars)
- **Health Check:** Always verify backend is running before testing

### Best Practices
1. Use local backend for development
2. Use production backend for final testing
3. Test with both environments before release
4. Keep configuration files gitignored
5. Document any environment-specific behavior

---

## Support

For issues or questions:
- Check backend logs in Render dashboard
- Check Flutter console for errors
- Verify network connectivity
- Test health endpoint directly in browser
- Review configuration settings