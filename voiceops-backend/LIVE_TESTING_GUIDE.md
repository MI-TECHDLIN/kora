# Live Voice Agent Testing Guide for Traffic Routing Features

## Overview
This guide helps you test the new traffic-aware routing and proactive reroute features with live voice agent interaction.

## Prerequisites
- ✅ Backend running on `http://localhost:8000`
- ✅ TomTom API key configured
- ✅ Flutter app connected to voice agent
- ✅ Valid driver authentication (JWT token)

## Step 1: Start the Backend
```bash
cd voiceops-backend/voiceops-backend
$env:TOMTOM_API_KEY="APxy4OvkI63alJEX8TQihGVO8NScCixb"
uvicorn app.main:app --reload
```

## Step 2: Run Basic Tests
```bash
# PowerShell
powershell -ExecutionPolicy Bypass -File test_traffic_routing_fixed.ps1

# Or Bash
bash curl_tests.sh
```

Expected results:
- ✅ TomTom API working
- ✅ Backend healthy
- ✅ Tool registry has accept_reroute
- ✅ Risk engine has ROUTE_DEVIATION detection
- ✅ ETA service with traffic capabilities

## Step 3: Test Traffic-Aware ETA via GPS Pings

### Trigger GPS Ping
```bash
curl -X POST http://localhost:8000/v1/locations/ping \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "latitude": 30.2672,
    "longitude": -97.7431,
    "speed": 25.0,
    "heading": 45.0,
    "accuracy": 10.0,
    "shift_id": "your_shift_id"
  }'
```

What happens in the backend:
1. **Traffic-Aware ETA Calculation**: Uses TomTom API with real-time traffic
2. **Risk Engine Evaluation**: Checks for time window risks and idle time
3. **Reroute Detection**: If MEDIUM+ risk, checks for alternate routes
4. **Proactive Alerts**: Sends alerts via WebSocket if conditions met

Expected response:
```json
{
  "success": true,
  "driver_id": "your_driver_id",
  "events_emitted": [...],
  "risks_detected": [...],
  "alerts_dispatched": [...]
}
```

## Step 4: Test Order Offer with Traffic Stats

When a new order comes in, the offer will include:
```json
{
  "event": "order_offer",
  "order_id": "...",
  "area": "Lavaca St, Austin",
  "latitude": 30.271,
  "longitude": -97.746,
  "distance_km": 0.51,
  "eta_minutes": 12,           // NEW: Traffic-aware ETA
  "traffic_delay_minutes": 4,  // NEW: Traffic delay
  "time_window": "3:00 PM – 5:00 PM",
  "package_count": 2,
  "expires_in_s": 75
}
```

## Step 5: Test ROUTE_DEVIATION Proactive Alerts

### Create a Test Scenario
1. Create a delivery with tight time window
2. Simulate traffic conditions by choosing route with known delays
3. Trigger GPS pings to trigger risk evaluation

### Expected WebSocket Alert
```json
{
  "type": "PROACTIVE_ALERT",
  "severity": "HIGH",
  "risk_type": "ROUTE_DEVIATION",
  "message": "Traffic ahead adds about 8 minutes on your current route. Want me to reroute?",
  "delivery_id": "...",
  "route_suggestion": {
    "eta_minutes": 12,
    "current_eta_minutes": 20,
    "geometry": "route_geometry_string"
  }
}
```

## Step 6: Test accept_reroute Voice Command

### Voice Commands to Test
- "Yes, take that route"
- "Accept reroute"
- "Use the alternate route"
- "I'll take the new route"

### What Happens
1. Voice agent recognizes the command
2. Calls `accept_reroute` tool with route parameters
3. Backend sets the alternate route as active navigation
4. Flutter app displays the new route on the map

### Tool Response
```json
{
  "success": true,
  "action": "reroute_accepted",
  "route": {
    "summary": "Suggested Reroute",
    "distance_km": 4.5,
    "duration_mins": 12,
    "duration_text": "12 mins",
    "provider": "traffic_reroute",
    "geometry": "route_geometry_string"
  },
  "message": "Rerouting to 22 Victoria Island Drive. Estimated time: 12 mins.",
  "destination_address": "22 Victoria Island Drive"
}
```

## Step 7: Test Fallback Behavior

### Test Without TomTom API Key
```bash
# Temporarily remove TomTom key
$env:TOMTOM_API_KEY=""
uvicorn app.main:app --reload
```

Expected behavior:
- System falls back to haversine calculation
- No traffic delay information
- Reroute suggestions disabled
- Core functionality still works

## Step 8: Monitor System Behavior

### Key Logs to Watch
```
[TrafficRouting] Traffic-aware ETA: 15 minutes (delay: 4 mins)
[RiskEngine] ROUTE_DEVIATION risk detected: saves 8 minutes
[AlertService] PROACTIVE_ALERT dispatched: ROUTE_DEVIATION
[VoiceWS] accept_reroute tool called by driver
```

### Database Updates
- `deliveries.estimated_arrival` - Updated with traffic-aware ETA
- `dispatcher_alerts` - Logs all proactive alerts
- `location_pings` - Records GPS data with traffic context

## Step 9: Test Caching Behavior

### Test Cache Effectiveness
1. Send multiple GPS pings for same delivery
2. TomTom API should only be called once per 75 seconds
3. Subsequent pings use cached ETA

### Monitor Cache Hits
```
[ETAService] Using cached traffic ETA for delivery test-delivery-123
```

## Step 10: Test API Failure Scenarios

### Simulate TomTom API Failure
1. Temporarily invalidate TomTom API key
2. Send GPS ping
3. System should fall back to haversine
4. Core functionality should continue working

## Verification Checklist

- [ ] TomTom API responds correctly
- [ ] Backend loads with TomTom configuration
- [ ] Traffic-aware ETA calculated when TomTom key present
- [ ] Haversine fallback works when TomTom key absent
- [ ] Order offers include traffic stats
- [ ] ROUTE_DEVIATION alerts generated for high-risk scenarios
- [ ] Route suggestions include geometry and time savings
- [ ] accept_reroute tool registered and executable
- [ ] WebSocket messages include route_suggestion for ROUTE_DEVIATION
- [ ] Caching reduces API calls (75-second TTL)
- [ ] System remains functional during API failures

## Troubleshooting

### TomTom API Not Working
```bash
# Test TomTom API directly
curl "https://api.tomtom.com/routing/1/calculateRoute/30.2672,-97.7431:30.2711,-97.7428/json?key=YOUR_KEY&traffic=true&travelMode=car"
```

### Backend Not Loading
```bash
# Check environment variable
$env:TOMTOM_API_KEY="APxy4OvkI63alJEX8TQihGVO8NScCixb"
uvicorn app.main:app --reload
```

### No Traffic Data in Response
- Check TomTom API key is valid
- Verify coordinates are in supported region
- Check for rate limiting
- Monitor logs for API errors

### WebSocket Not Receiving Alerts
- Verify driver WebSocket connection
- Check risk engine is evaluating correctly
- Monitor alert service logs
- Verify cooldown period isn't blocking alerts

## Performance Considerations

- **API Call Rate**: TomTom API is called once per 75 seconds per delivery
- **Cache Hit Rate**: Should be high for frequent GPS pings
- **Fallback Speed**: Haversine calculation is instantaneous
- **Memory Usage**: Cache is in-memory, clears on restart

## Next Steps After Testing

1. **Monitor Production Usage**: Track TomTom API usage
2. **Optimize Cache TTL**: Adjust based on real-world patterns
3. **Refine Reroute Threshold**: Tune 3-minute savings threshold
4. **Add More Traffic Providers**: Consider HERE or Google as backup
5. **Implement Advanced Caching**: Redis for distributed cache