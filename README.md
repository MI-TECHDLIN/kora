# VoiceOps Backend

FastAPI backend for VoiceOps - a voice-first logistics driver companion powered by AssemblyAI Voice Agent API.

## Features

- **AssemblyAI Voice Agent Integration**: Real-time WebSocket relay for voice conversations
- **Parallel Tool Execution**: asyncio.gather() for sub-500ms multi-tool dispatch
- **Authentication**: Supabase phone OTP authentication
- **Logistics Adapters**: Mock adapter for demo, Onfleet adapter for production
- **Navigation**: Google Maps integration for route optimization
- **Communication**: Twilio integration for calls and SMS
- **Post-Shift Intelligence**: AssemblyAI Speech Understanding + LeMUR analysis
- **n8n Workflows**: Async workflow automation for operator notifications

## Tech Stack

- **Runtime**: Python 3.11+
- **Framework**: FastAPI 0.104.1
- **Database**: Supabase (PostgreSQL)
- **Auth**: Supabase Auth (phone OTP)
- **Voice**: AssemblyAI Voice Agent API
- **Intelligence**: AssemblyAI Speech Understanding + LeMUR
- **Maps**: Google Maps Directions API
- **Communication**: Twilio
- **Workflows**: n8n
- **Hosting**: Railway

## Setup

### Prerequisites

- Python 3.11+
- Supabase project
- AssemblyAI API key
- (Optional) Twilio account
- (Optional) Google Maps API key
- (Optional) n8n instance

### Installation

```bash
# Clone repository
git clone https://github.com/voiceops-team/voiceops-backend
cd voiceops-backend

# Create virtual environment
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Create .env file
cp .env.example .env
# Fill in all required values
```

### Database Setup

1. Create a Supabase project at https://supabase.com
2. Run the schema SQL in Supabase SQL Editor:
   ```bash
   cat supabase_schema.sql
   ```
3. Enable phone authentication in Supabase Dashboard → Authentication → Providers → Phone

### Environment Variables

Required variables in `.env`:

```env
# AssemblyAI
ASSEMBLYAI_API_KEY=your_assemblyai_api_key

# Supabase
SUPABASE_URL=your_supabase_project_url
SUPABASE_SERVICE_KEY=your_supabase_service_role_key

# Twilio (optional)
TWILIO_ACCOUNT_SID=your_twilio_account_sid
TWILIO_AUTH_TOKEN=your_twilio_auth_token
TWILIO_PHONE_NUMBER=your_twilio_phone_number

# Google Maps (optional)
GOOGLE_MAPS_API_KEY=your_google_maps_api_key

# Onfleet (optional)
ONFLEET_API_KEY=your_onfleet_api_key

# n8n (optional)
N8N_SHIFT_WEBHOOK_URL=https://your-n8n-instance.com/webhook/shift-end
N8N_DRIVER_SIGNUP_WEBHOOK_URL=https://your-n8n-instance.com/webhook/driver-signup

# Environment
ENVIRONMENT=development
```

### Running Locally

```bash
uvicorn app.main:app --reload --port 8000
```

The API will be available at `http://localhost:8000`

### Testing WebSocket

```bash
# Install wscat
npm install -g wscat

# Connect to AssemblyAI directly (for testing)
wscat -c wss://agents.assemblyai.com/v1/ws -H "Authorization: Bearer YOUR_API_KEY"

# Test backend WebSocket (requires valid JWT)
wscat -c ws://localhost:8000/ws/voice/test-shift?token=YOUR_JWT
```

## API Endpoints

### REST API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/v1/auth/otp/send` | POST | Send OTP to phone |
| `/v1/auth/otp/verify` | POST | Verify OTP → JWT |
| `/v1/driver/profile` | GET | Get driver profile |
| `/v1/driver/profile` | PUT | Update driver profile |
| `/v1/driver/connect` | POST | Connect logistics platform |
| `/v1/deliveries` | GET | Get shift deliveries |
| `/v1/deliveries/{id}/status` | PUT | Update delivery status |
| `/v1/deliveries/{id}/notify` | POST | Send customer notification |
| `/v1/deliveries/location` | POST | Save GPS ping |
| `/v1/shift/start` | POST | Start new shift |
| `/v1/shift/{id}/end` | POST | End shift + trigger intelligence |
| `/v1/shift/{id}/report` | GET | Get intelligence report |
| `/v1/shift/{id}/stats` | GET | Get shift statistics |

### WebSocket

| Endpoint | Description |
|----------|-------------|
| `/ws/voice/{shift_id}?token={jwt}` | Voice agent session |

## Architecture

### Real-Time Voice Path

```
Flutter App
  │ WebSocket (PCM16 audio, 24kHz)
  ▼
FastAPI WebSocket Relay
  │ Base64-encode + forward
  ▼
AssemblyAI Voice Agent API
  │ tool_call events
  ▼
Tool Orchestrator (asyncio.gather)
  ├── Delivery tools → Supabase + Onfleet/Mock
  ├── Navigation tools → Google Directions
  └── Communication tools → Twilio
  │ tool_results
  ▼
AssemblyAI TTS audio
  │ Base64-decode
  ▼
Flutter audio player
```

### Post-Shift Intelligence Path

```
Shift ends
  │
FastAPI BackgroundTask
  │
  ▼
Intelligence Pipeline
  ├── Fetch voice sessions from Supabase
  ├── Combine transcripts
  ├── AssemblyAI Speech Understanding
  ├── LeMUR analysis (3 prompts)
  ├── Generate report
  └── Store in Supabase
  │
  ▼ (optional)
n8n Workflow
  ├── Operator email notification
  └── Slack notification
```

## Tool Registry

The voice agent has 10 tools available:

1. **get_next_delivery** - Get next pending delivery
2. **update_delivery_status** - Mark delivered/failed/rescheduled
3. **log_exception** - Log delivery exception
4. **get_best_route** - Get optimal route with traffic
5. **start_navigation** - Open Google Maps navigation
6. **call_customer** - Call customer via Twilio
7. **notify_customer** - Send SMS to customer
8. **get_next_order** - Get next queued order
9. **get_shift_summary** - Get shift statistics
10. **alert_dispatcher** - Alert dispatcher about issues

## Logistics Adapters

### Mock Adapter (Default)

Hardcoded Nigerian delivery data for demo/testing. Includes 7 realistic Lagos deliveries with one prior failure.

### Onfleet Adapter

Real Onfleet integration. Requires `ONFLEET_API_KEY` in environment.

## n8n Workflows

Workflow JSON exports are in `n8n/workflows/`:

- `post_shift_intelligence.json` - Post-shift analysis and operator notification
- `driver_welcome.json` - New driver welcome SMS

Import these into your n8n instance and configure credentials.

## Deployment

### Railway

```bash
# Install Railway CLI
npm install -g @railway/cli

# Login
railway login

# Initialize
railway init

# Add environment variables
railway variables set ASSEMBLYAI_API_KEY=your_key
railway variables set SUPABASE_URL=your_url
# ... set all other variables

# Deploy
railway up
```

### Environment Variables in Railway

Set all variables from `.env.example` in Railway dashboard.

## Project Structure

```
voiceops-backend/
├── app/
│   ├── agents/
│   │   ├── orchestrator.py       # Parallel tool execution
│   │   ├── tool_registry.py      # Tool definitions + system prompt
│   │   └── tools/
│   │       ├── delivery.py       # Delivery tools
│   │       ├── navigation.py     # Navigation tools
│   │       └── communication.py  # Communication tools
│   ├── api/
│   │   ├── routes/
│   │   │   ├── auth.py          # Authentication endpoints
│   │   │   ├── driver.py        # Driver profile endpoints
│   │   │   ├── deliveries.py    # Delivery endpoints
│   │   │   ├── shift.py         # Shift endpoints
│   │   │   └── health.py        # Health check
│   │   └── websocket/
│   │       └── voice.py         # AssemblyAI WebSocket relay
│   ├── db/
│   │   ├── client.py            # Supabase client
│   │   └── queries.py           # Database query helpers
│   ├── intelligence/
│   │   ├── assemblyai_batch.py  # AssemblyAI batch processing
│   │   ├── pipeline.py          # Intelligence pipeline
│   │   └── report_generator.py  # Report generation
│   ├── integrations/
│   │   ├── base.py             # Logistics adapter base + factory
│   │   ├── google_maps.py      # Google Maps API
│   │   ├── n8n_client.py        # n8n webhook client
│   │   └── twilio_client.py     # Twilio client
│   ├── config.py                # Pydantic settings
│   ├── dependencies.py          # FastAPI dependencies
│   ├── main.py                  # FastAPI app
│   └── models/
│       └── schemas.py           # Pydantic models
├── n8n/
│   └── workflows/               # n8n workflow exports
├── requirements.txt
├── .env.example
├── Procfile
├── supabase_schema.sql
└── README.md
```

## Important Notes

### Audio Format

- **Flutter → FastAPI**: Raw PCM16 bytes (24kHz recommended per AssemblyAI spec)
- **FastAPI → AssemblyAI**: Base64-encoded audio in JSON messages
- **AssemblyAI → FastAPI**: Base64-encoded audio chunks
- **FastAPI → Flutter**: Raw bytes (decoded from base64)

### Tool Execution Timing

- Tools execute immediately when `tool.call` event received
- Tool results sent after `reply.done` event (allows agent to speak filler)
- Multiple tools execute in parallel via `asyncio.gather()`

### n8n Architecture

- n8n is **never** used in real-time voice path (HTTP latency unacceptable)
- n8n is **only** used for async post-shift workflows
- n8n triggers are fire-and-forget (never await in response path)

## Testing

```bash
# Run health check
curl http://localhost:8000/health

# Test with real JWT (after auth)
curl -H "Authorization: Bearer YOUR_JWT" http://localhost:8000/v1/driver/profile
```

## License

MIT License - See LICENSE file for details
