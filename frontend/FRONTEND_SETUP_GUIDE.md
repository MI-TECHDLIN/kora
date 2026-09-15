# Flutter Frontend Setup & Live Testing Guide

## Prerequisites

- Flutter SDK installed (check with `flutter --version`)
- Android Studio or Xcode for mobile development
- Physical Android/iOS device OR emulator/simulator
- Backend running on http://localhost:8000 (or LAN IP)
- Supabase project with anon key

## Step 1: Configure Backend for Network Access

The backend must be accessible from your mobile device on the same network.

### Get Your LAN IP Address
```powershell
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -like "*WiFi*" } | Select-Object IPAddress
```

Your LAN IP: **192.168.18.13** (based on your system)

### Start Backend with Network Access
```powershell
cd voiceops-backend/voiceops-backend
$env:TOMTOM_API_KEY="APxy4OvkI63alJEX8TQihGVO8NScCixb"
py -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

**⚠️ IMPORTANT:** Use `--host 0.0.0.0` to allow external network access, not just localhost.

## Step 2: Configure Flutter App

### Create Supabase Config File
```powershell
cd voiceops-backend/frontend
Copy-Item config/supabase.prod.json.example config/supabase.prod.json
```

### Edit config/supabase.prod.json
Update with your actual Supabase anon key and backend URL:

```json
{
  "SUPABASE_URL": "https://hihvtftdjxvnxvuwptnb.supabase.co",
  "SUPABASE_ANON_KEY": "your-actual-supabase-anon-key-here",
  "VOICEOPS_API_URL": "http://192.168.18.13:8000"
}
```

**⚠️ SECURITY:** Never commit `config/supabase.prod.json` - it's in `.gitignore`.

### Get Supabase Anon Key
1. Go to https://supabase.com/dashboard
2. Select your project: `hihvtftdjxvnxvuwptnb`
3. Go to Settings → API
4. Copy the "anon public" key (NOT the service_role key)
5. Paste it into `config/supabase.prod.json`

## Step 3: Install Flutter Dependencies

```powershell
cd voiceops-backend/frontend
flutter pub get
```

## Step 4: Choose Your Target Device

### Option A: Physical Android Device (Recommended)
1. Enable Developer Options on your phone
2. Enable USB Debugging
3. Connect via USB to your computer
4. Ensure both are on the same WiFi network

### Option B: Android Emulator
```powershell
flutter emulators
flutter emulators --launch <emulator-id>
```

### Option C: iOS Simulator (Mac only)
```powershell
open -a Simulator
```

### Option D: Web Browser (For basic testing)
```powershell
flutter run -d chrome
```

## Step 5: Run the Flutter App

### With Config File
```powershell
cd voiceops-backend/frontend
flutter run --dart-define-from-file=config/supabase.prod.json
```

### With Manual Dart Defines (Alternative)
```powershell
flutter run --dart-define=SUPABASE_URL=https://hihvtftdjxvnxvuwptnb.supabase.co --dart-define=SUPABASE_ANON_KEY=your-anon-key --dart-define=VOICEOPS_API_URL=http://192.168.18.13:8000
```

### Specific Device
```powershell
flutter devices  # List available devices
flutter run -d <device-id> --dart-define-from-file=config/supabase.prod.json
```

## Step 6: Test Connection

### Check Backend Health
In the app, navigate to any screen that requires backend connectivity. If the backend is working:
- Voice agent should connect successfully
- GPS pings should work
- WebSocket should establish connection

### Verify Backend Logs
The backend should show:
```
INFO:     Connection accepted from 192.168.18.x:xxxxx
```

## Step 7: Live Testing Traffic Routing Features

### Test Traffic-Aware ETA
1. Open the Flutter app and start a shift
2. Trigger GPS pings by moving around (or use the map simulation)
3. Monitor backend logs for:
   ```
   [TrafficRouting] Traffic-aware ETA: X minutes (delay: Y mins)
   ```

### Test Order Offers with Traffic Stats
1. Wait for or trigger a new order offer
2. Check the order offer card displays:
   - ETA with traffic consideration
   - Traffic delay information

### Test ROUTE_DEVIATION Alerts
1. Create a delivery scenario with tight time window
2. Simulate traffic conditions (choose routes with known delays)
3. Monitor for proactive alerts:
   ```
   [RiskEngine] ROUTE_DEVIATION risk detected: saves X minutes
   [AlertService] PROACTIVE_ALERT dispatched: ROUTE_DEVIATION
   ```

### Test accept_reroute Voice Command
1. When a route suggestion appears, say:
   - "Yes, take that route"
   - "Accept reroute"
   - "Use the alternate route"
2. The voice agent should call `accept_reroute` tool
3. Map should update with the new route

## Troubleshooting

### Backend Not Accessible from Phone
**Problem:** Phone can't connect to backend
**Solution:**
- Ensure backend is running with `--host 0.0.0.0`
- Check firewall settings on your computer
- Verify both devices are on the same WiFi network
- Test with browser on phone: `http://192.168.18.13:8000/health`

### Flutter Can't Find Device
**Problem:** `flutter devices` shows no devices
**Solution:**
- For Android: Enable USB debugging in Developer Options
- Try `flutter doctor` to diagnose issues
- For iOS: Ensure Xcode command-line tools are installed

### Supabase Auth Fails
**Problem:** App shows auth errors
**Solution:**
- Verify you're using the anon key, not service_role key
- Check Supabase project is active
- Ensure email authentication is enabled in Supabase

### WebSocket Connection Fails
**Problem:** Voice agent won't connect
**Solution:**
- Check backend is running
- Verify VOICEOPS_API_URL is correct
- Check backend logs for WebSocket connection attempts
- Ensure JWT token is valid

### GPS Not Working
**Problem:** App can't get location
**Solution:**
- Grant location permissions to the app
- Enable location services on device
- For Android: Check location permission in app settings
- For iOS: Check "When in Use" location permission

## Debug Mode

### Enable Flutter Debug Logging
```powershell
flutter run --dart-define-from-file=config/supabase.prod.json --verbose
```

### View Backend Logs
```powershell
# Backend should be running in background with shell ID
# Use get_output to see latest logs
```

### Network Debugging
Use Charles Proxy or Fiddler to inspect HTTP traffic between app and backend.

## Performance Testing

### Test on Real Device
- Real GPS provides better accuracy
- Network latency more realistic
- Voice recognition works better

### Test Flight/Build
For production-like testing:
```powershell
flutter build apk --release
flutter build ios --release
```

## Hot Reload During Testing

While the app is running:
- Press `r` in terminal for hot reload
- Press `R` for hot restart
- Press `q` to quit

Backend changes don't require app restart, but frontend changes do.

## Current Status

✅ Backend: Running on http://192.168.18.13:8000
✅ TomTom API: Configured
✅ Flutter Config: Created (needs anon key)
✅ Network: WiFi IP detected

## Next Steps

1. **Get Supabase Anon Key** from dashboard
2. **Update config/supabase.prod.json** with real anon key
3. **Connect physical device** or start emulator
4. **Run Flutter app** with config file
5. **Test voice agent** and traffic routing features
6. **Monitor backend logs** for traffic routing activity

## Quick Reference Commands

```powershell
# Backend (run in separate terminal)
cd voiceops-backend/voiceops-backend
$env:TOMTOM_API_KEY="APxy4OvkI63alJEX8TQihGVO8NScCixb"
py -m uvicorn app.main:app --host 0.0.0.0 --port 8000

# Flutter (run in separate terminal)
cd voiceops-backend/frontend
flutter run --dart-define-from-file=config/supabase.prod.json

# Check devices
flutter devices

# Check backend health
curl http://192.168.18.13:8000/health

# Run tests
flutter test
flutter analyze
```