# Simulated Customer Call Demo

## Overview

This feature adds a simulated customer call path for demo purposes. When enabled, the `call_customer` tool runs a pretend call without actually dialing anyone or using any carrier. The driver hears a simulated response from the "customer" after a short delay.

## Motivation

Real customer calls for demos face significant challenges:
- **Twilio**: Trial accounts can only call verified numbers; calling real customers requires an upgraded account with billing and payment card
- **Plivo**: Restricted in some regions and requires identity verification and payment
- **No genuinely free carrier**: No provider allows unlimited outbound calls at no cost
- **Web page alternative**: Too complex for a demo
- **AssemblyAI dual sessions**: Not documented for safe concurrent use

The simulation provides a deterministic, cost-free demo path that showcases the voice agent's capabilities without these barriers.

## How It Works

### Driver Experience

1. Driver says: "Call the customer"
2. App shows normal call screen (`call_started` event)
3. After ~1.5 seconds, call screen closes (`call_ended` event)
4. Kora announces: "The simulated customer said [outcome]"

### Scenarios

Four possible outcomes, each using the recipient's name and ETA:

| Scenario | Response |
|----------|----------|
| `home` | "{name} is home and will answer the door when you arrive in about {eta} minutes." |
| `neighbour` | "Please leave the package with the neighbour, as {name} is not home right now." |
| `gate_code` | "The gate code is 2468. {name} will answer the door when you arrive in about {eta} minutes." |
| `reschedule` | "{name} asks if you can reschedule the delivery for the 4 to 6 PM window today." |

## Configuration

### Environment Variables

Add to `.env`:

```bash
# Enable simulated customer calls for demo
DEMO_SIMULATED_CUSTOMER=true

# Optional: Pin a specific scenario (defaults to random if omitted)
DEMO_SIMULATED_CUSTOMER_SCENARIO=home  # Options: home | neighbour | gate_code | reschedule
```

### Default Behavior

- When `DEMO_SIMULATED_CUSTOMER=false` (default): `call_customer` behaves normally (Twilio or existing mock fallback)
- When `DEMO_SIMULATED_CUSTOMER=true` without scenario: Random scenario selected each call
- When `DEMO_SIMULATED_CUSTOMER=true` with scenario: Same scenario used for all calls
- Unknown scenario names: Logged and fall back to random

## Implementation Details

### Files Modified

1. **app/config.py**
   - Added `demo_simulated_customer: bool = False`
   - Added `demo_simulated_customer_scenario: Optional[str] = None`

2. **app/agents/tools/communication.py**
   - Modified `call_customer()` to check demo flag
   - Added `_simulated_customer_call()` helper function
   - Stores outcome in session context for relay to announce
   - Logs interaction with `[SIMULATED]` label

3. **app/api/websocket/voice.py**
   - Added `DEMO_SIMULATED_CALL_SECONDS = 1.5` constant
   - Modified `_is_mock_call()` to include `demo-` prefix
   - Added `_simulated_call_timer` to `VoiceSession` class
   - Added `_run_simulated_call()` method for timer-based call simulation
   - Modified `_emit_tool_events()` to handle demo calls
   - Updated `_close()` and `_end_call()` for cleanup

### Call ID Format

- Demo calls use ID format: `demo-{scenario}-{random_number}`
- Example: `demo-home-4231`
- Treated like existing `mock-` calls: no provider polling or hang-up

### Announcement Path

The simulated outcome is announced via the existing unprompted announcement mechanism:
1. Outcome stored in `context["simulated_customer_outcome"]`
2. Timer fires → `call_ended` event
3. Relay queues announcement with `_announce()`
4. Announcement spoken at next quiet moment via `reply.create`

### Cleanup

- Timer cancelled on session end or driver-ended call
- Outcome removed from context on cleanup
- No background tasks left running

## Testing

### Test Files

1. **tests/test_simulated_customer_demo.py** (new)
   - Tests all four scenarios
   - Tests random scenario selection
   - Tests invalid scenario fallback
   - Tests ETA fallback (10 minutes default)
   - Tests flag off behavior unchanged
   - Tests no network calls made

2. **tests/test_voice_ws.py** (one new test)
   - Full lifecycle test: `call_started`, `call_ended`, cleanup
   - Verifies demo call ID format
   - Verifies no provider interactions

### Running Tests

```bash
cd voiceops-backend
pytest tests/test_simulated_customer_demo.py
pytest tests/test_voice_ws.py::test_simulated_customer_call_full_lifecycle
```

### Expected Results

- `test_simulated_customer_demo.py`: 12 tests pass
- `test_voice_ws.py`: All existing tests pass + new lifecycle test passes
- Total: 60+ tests pass in default suite

## Future: Real Customer Calls

To implement real customer calls later:

1. Keep the provider-neutral `call_customer` result structure
2. Add a carrier adapter behind the tool (similar to `LogisticsAdapter`)
3. Test two-way audio on a real device before enabling
4. Keep the simulation flag as deterministic demo and development fallback

## Constraints & Safety

- **No contract changes**: Uses existing `call_started`/`call_ended` events
- **No WebSocket changes**: No new event types
- **No interface.md changes**: Existing contract remains valid
- **Safe default**: OFF by default; requires explicit opt-in
- **Clear labeling**: Always starts with "The simulated customer said"
- **No secrets needed**: No Twilio credentials required when enabled
- **Cleanup guaranteed**: Timer and outcome cleaned up on session end

## Rollback

To disable the feature:
1. Set `DEMO_SIMULATED_CUSTOMER=false` in `.env`
2. `call_customer` reverts to existing behavior (Twilio or mock)
3. No code changes required

## Notes

- This is a demo-only feature and should not be used in production
- The 1.5-second delay is configurable via `DEMO_SIMULATED_CALL_SECONDS`
- Simulated calls are logged to `customer_interactions` table with `[SIMULATED]` prefix
- The feature is completely additive and does not modify existing call paths
