# VoiceOps Tool Testing Guide

This guide provides test phrases to trigger each of the 10 VoiceOps tools during live interaction with the AssemblyAI Voice Agent.

## How to Test

1. Start the server:
   ```bash
   uvicorn app.main:app --reload --port 8000
   ```

2. Run live interaction:
   ```bash
   python tests/live_interaction.py
   ```

3. Speak one of the phrases below to trigger the corresponding tool

---

## Tool Test Phrases

### 1. get_next_delivery
**Purpose**: Get the next delivery in the current shift

**Trigger Phrases**:
- "What's my next stop?"
- "Where to next?"
- "Next delivery"
- "What's my next drop?"
- "Where am I going next?"

**Expected Response**:
Agent will tell you about the next delivery with recipient name, address, notes, and time window.

**Platform**: Supabase (internal DB) + Onfleet/Mock adapter

---

### 2. update_delivery_status
**Purpose**: Update delivery status to delivered, failed, or rescheduled

**Trigger Phrases**:
- "Mark as delivered"
- "Done"
- "Package delivered"
- "Delivered successfully"
- "Failed delivery"
- "Nobody home"
- "Package not delivered"

**Expected Response**:
Agent will confirm the status update and sync to platform.

**Platform**: Supabase + Onfleet/Mock adapter

---

### 3. log_exception
**Purpose**: Log a delivery exception with reason and resolution

**Trigger Phrases**:
- "Failed delivery - wrong address"
- "Gate locked, can't get in"
- "Package damaged"
- "Customer not available"
- "Can't access the building"

**Expected Response**:
Agent will log the exception and suggest resolution options.

**Platform**: Supabase + Onfleet/Mock adapter

---

### 4. get_best_route
**Purpose**: Get the best route with traffic information

**Trigger Phrases**:
- "Best route"
- "Any traffic?"
- "Check my route"
- "Faster way"
- "Is there a better route?"
- "Traffic update"

**Expected Response**:
Agent will provide the best route with distance, duration, and time saved compared to current route.

**Platform**: Google Directions API

---

### 5. start_navigation
**Purpose**: Start navigation to delivery location using Google Maps

**Trigger Phrases**:
- "Navigate"
- "Take me there"
- "Get directions"
- "Start navigation"
- "Navigate to the delivery"

**Expected Response**:
Agent will provide a Google Maps navigation link to open in your browser/phone.

**Platform**: Google Maps deeplink

---

### 6. call_customer
**Purpose**: Call the customer via Twilio Voice

**Trigger Phrases**:
- "Call the customer"
- "Ring the customer"
- "Call them"
- "Phone the customer"
- "I need to call the customer"

**Expected Response**:
Agent will initiate a phone call to the customer via Twilio Voice.

**Platform**: Twilio Voice API

---

### 7. notify_customer
**Purpose**: Send SMS notification to customer via Twilio

**Trigger Phrases**:
- "Message the customer"
- "Tell customer I'm close"
- "Send ETA"
- "I'm 5 minutes away"
- "Text the customer"
- "Notify the customer"

**Expected Response**:
Agent will send an SMS to the customer with your message.

**Platform**: Twilio Messages API

---

### 8. get_next_order
**Purpose**: Get the next order in the queue from Onfleet

**Trigger Phrases**:
- "Next order in queue"
- "What's coming after this?"
- "Next job"
- "What's next in the queue?"
- "Next pickup"

**Expected Response**:
Agent will tell you about the next order in the unassigned task queue.

**Platform**: Onfleet/Mock adapter

---

### 9. get_shift_summary
**Purpose**: Get shift statistics and progress

**Trigger Phrases**:
- "How am I doing?"
- "How many left?"
- "My progress"
- "Shift summary"
- "How many deliveries left?"
- "What's my progress?"

**Expected Response**:
Agent will provide total deliveries, delivered count, failed count, remaining, success rate, and average time per stop.

**Platform**: Supabase

---

### 10. alert_dispatcher
**Purpose**: Alert dispatcher with priority message

**Trigger Phrases**:
- "Alert the dispatcher"
- "Contact dispatch"
- "I need help"
- "Call dispatch"
- "Emergency - need dispatcher"

**Expected Response**:
Agent will send an alert to the dispatcher with your message and priority level.

**Platform**: Supabase + optional n8n webhook

---

## Parallel Execution Test

To test parallel tool execution (multiple tools at once), say:

**"Call the customer, check best route, and get my next order"**

This will trigger:
1. `call_customer` - Phone the customer
2. `get_best_route` - Check traffic and best route
3. `get_next_order` - Get next order in queue

The agent will execute all 3 tools simultaneously and provide a unified response.

---

## Notes

- **Current Status**: All tools are implemented with mock data since database connections are not yet set up
- **Credentials Required**:
  - AssemblyAI: ✅ Configured
  - Supabase: ✅ Configured
  - Twilio: ✅ Configured (Calls & SMS)
  - Google Maps: ⚠️ Placeholder (using mock data)
  - Onfleet: ⚠️ Placeholder (using mock data)
  - n8n: ✅ Integrated (Dispatcher alert workflow connected via webhook)

- **To Use Real APIs**: Add the respective API keys to `.env` file

- **Debug Logs**: The server will print detailed logs showing:
  - Which tool was triggered
  - Parameters passed
  - Tool execution result
  - Agent's response

---

## Quick Test Sequence

For a quick test of all tools, speak these phrases in order:

1. "How am I doing?" (get_shift_summary)
2. "What's my next stop?" (get_next_delivery)
3. "Best route" (get_best_route)
4. "Navigate" (start_navigation)
5. "Message the customer" (notify_customer)
6. "Call the customer" (call_customer)
7. "Mark as delivered" (update_delivery_status)
8. "What's next in the queue?" (get_next_order)
9. "Failed delivery - gate locked" (log_exception)
10. "Alert the dispatcher - I need help" (alert_dispatcher)