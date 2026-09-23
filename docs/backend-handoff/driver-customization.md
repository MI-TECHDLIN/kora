# Driver Customization Feature - Implementation Plan

## Overview

Allow drivers to customize their co-rider's behavior through voice commands. Preferences are saved and the agent automatically follows them in future interactions.

## Example Use Cases

1. **Order Handling**
   - "Always accept orders automatically"
   - "Never accept orders on this shift"
   - "Only accept orders within 5 km"

2. **Route Preferences**
   - "Avoid highways"
   - "Prefer residential areas"
   - "Avoid downtown during rush hour"

3. **Communication**
   - "Always call customers before delivery"
   - "Never call customers"
   - "Send SMS notification on delivery"

4. **Shift Behavior**
   - "End shift after 10 deliveries"
   - "Auto-announce next stop after each delivery"
   - "Proactive alerts for traffic"

## Technical Architecture

### 1. Data Model

**Preference Schema (Supabase table: `driver_preferences`)**

```sql
CREATE TABLE driver_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id UUID NOT NULL REFERENCES drivers(id),
    preference_key VARCHAR(100) NOT NULL,
    preference_value TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(driver_id, preference_key)
);
```

**Preference Keys:**
- `auto_accept_orders` (boolean)
- `auto_decline_orders` (boolean)
- `max_order_distance_km` (float)
- `avoid_highways` (boolean)
- `prefer_residential` (boolean)
- `always_call_before_delivery` (boolean)
- `never_call_customer` (boolean)
- `always_send_sms` (boolean)
- `max_deliveries_per_shift` (int)
- `auto_announce_next_stop` (boolean)
- `proactive_traffic_alerts` (boolean)
- `avoid_areas` (json array of area names/coordinates)

### 2. Backend Components

#### A. Preference Service (`app/services/preference_service.py`)
- CRUD operations for preferences
- Get all preferences for a driver
- Get specific preference by key
- Set/update preference
- Clear preference

#### B. Preference API Routes (`app/api/routes/preferences.py`)
- `GET /v1/driver/{driver_id}/preferences` - Get all preferences
- `GET /v1/driver/{driver_id}/preferences/{key}` - Get specific preference
- `PUT /v1/driver/{driver_id}/preferences/{key}` - Set preference
- `DELETE /v1/driver/{driver_id}/preferences/{key}` - Clear preference

#### C. Voice Tools for Preferences (`app/agents/tools/preferences.py`)
- `get_preferences` - List current preferences
- `set_preference` - Set a preference by key/value
- `clear_preference` - Clear a preference
- `reset_preferences` - Reset all to defaults

#### D. Agent Integration
- Modify tool orchestrator to check preferences before actions
- Order dispatch checks `auto_accept_orders`, `auto_decline_orders`, `max_order_distance_km`
- Routing tools check `avoid_highways`, `prefer_residential`
- Communication tools check `always_call_before_delivery`, `never_call_customer`, `always_send_sms`
- Shift logic checks `max_deliveries_per_shift`, `auto_announce_next_stop`

### 3. Voice Command Parsing

**Natural Language to Preference Mapping:**

```
"Always accept orders" → auto_accept_orders = true
"Never accept orders" → auto_decline_orders = true
"Only accept orders within 5 km" → max_order_distance_km = 5.0
"Avoid highways" → avoid_highways = true
"Prefer residential areas" → prefer_residential = true
"Always call customers" → always_call_before_delivery = true
"Never call customers" → never_call_customer = true
"Send SMS when I deliver" → always_send_sms = true
"End shift after 10 deliveries" → max_deliveries_per_shift = 10
"Tell me my preferences" → get_preferences tool
"Reset my preferences" → reset_preferences tool
```

### 4. Implementation Order

1. **Database Schema** - Create Supabase table
2. **Preference Service** - Backend service layer
3. **API Routes** - REST endpoints
4. **Agent Tools** - Voice command tools
5. **Agent Integration** - Hook into decision logic
6. **Tests** - Unit and integration tests
7. **Documentation** - Update docs

## Implementation Steps

### Step 1: Database Schema

```sql
-- Run in Supabase SQL editor
CREATE TABLE driver_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
    preference_key VARCHAR(100) NOT NULL,
    preference_value TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(driver_id, preference_key)
);

CREATE INDEX idx_driver_preferences_driver_id ON driver_preferences(driver_id);
```

### Step 2: Preference Service

Create `app/services/preference_service.py` with:
- `get_preferences(driver_id: str) -> Dict[str, Any]`
- `get_preference(driver_id: str, key: str) -> Any`
- `set_preference(driver_id: str, key: str, value: Any) -> None`
- `clear_preference(driver_id: str, key: str) -> None`
- `reset_preferences(driver_id: str) -> None`

### Step 3: API Routes

Create `app/api/routes/preferences.py` with:
- GET `/v1/driver/{driver_id}/preferences`
- GET `/v1/driver/{driver_id}/preferences/{key}`
- PUT `/v1/driver/{driver_id}/preferences/{key}`
- DELETE `/v1/driver/{driver_id}/preferences/{key}`

### Step 4: Agent Tools

Create `app/agents/tools/preferences.py` with tools:
- `get_preferences` - Returns dict of all preferences
- `set_preference(key, value)` - Sets a preference
- `clear_preference(key)` - Clears a preference
- `reset_preferences` - Resets all to defaults

### Step 5: Agent Integration

Modify existing tools to check preferences:
- `accept_order` - Check `auto_decline_orders`, `max_order_distance_km`
- `decline_order` - Check `auto_accept_orders`
- `get_best_route` - Check `avoid_highways`, `prefer_residential`
- `call_customer` - Check `never_call_customer`, `always_call_before_delivery`
- `notify_customer` - Check `always_send_sms`
- Shift summary - Check `max_deliveries_per_shift`

### Step 6: Tests

Create `tests/test_preferences.py`:
- Test preference CRUD operations
- Test preference tools
- Test agent integration with preferences
- Test voice command parsing

## Testing Strategy

### Unit Tests
1. Preference service CRUD operations
2. API routes authentication and validation
3. Preference tool logic
4. Preference validation and parsing

### Integration Tests
1. Set preference via voice → verify saved in DB
2. Set preference → verify agent follows it in next action
3. Reset preferences → verify default behavior restored
4. Invalid preference values → proper error handling

### Manual Testing Scenarios
1. Driver says "Always accept orders" → next order auto-accepted
2. Driver says "Only accept within 5 km" → order 10km away declined
3. Driver says "Never call customers" → call_customer tool not called
4. Driver says "Tell me my preferences" → list shown
5. Driver says "Reset preferences" → all cleared

## Files to Create/Modify

### New Files
- `app/services/preference_service.py`
- `app/api/routes/preferences.py`
- `app/agents/tools/preferences.py`
- `tests/test_preferences.py`

### Modified Files
- `app/api/routes/__init__.py` - Add preferences router
- `app/main.py` - Include preferences router
- `app/agents/tool_registry.py` - Add preference tools
- `app/dispatch/order_dispatch.py` - Check preferences on order offers
- `app/agents/tools/delivery.py` - Check preferences for order acceptance
- `app/agents/tools/navigation.py` - Check preferences for routing
- `app/agents/tools/communication.py` - Check preferences for communication

## Dependencies

No new dependencies required. Uses existing:
- Supabase for storage
- FastAPI for API
- Pydantic for validation

## Security Considerations

1. Drivers can only set their own preferences (auth check)
2. Preferences are not exposed to other drivers
3. Preference values are validated before saving
4. No sensitive data in preferences (just behavioral settings)

## Performance Considerations

1. Preferences cached in memory for fast access
2. Cache invalidated on update
3. Simple key-value lookup - very fast
4. No performance impact on existing features

## Rollout Plan

1. Deploy database schema change
2. Deploy backend code changes
3. Test in staging environment
4. Deploy to production
5. Update agent system prompt to explain feature to drivers
