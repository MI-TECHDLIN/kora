"""
REST API endpoint for AssemblyAI Voice Agent interaction.
Follows the exact AssemblyAI Voice Agent protocol for live interaction.

Protocol:
1. Connect with Bearer token
2. Send session.update immediately
3. Wait for session.updated or session.ready
4. Stream audio in chunks (50ms = 2400 bytes at 24kHz)
5. Wait for reply.done before stopping
6. Send session.end on intentional hangup
"""
import base64
import os
import json
import asyncio
import numpy as np
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.config import settings
from app.agents.agent_config import get_session_config
from app.agents.tool_registry import execute_tool
from app.utils.audio_helpers import save_wav, resample_audio
import websockets

# Create audio folders
INPUT_AUDIO_DIR = "recordings/input"
OUTPUT_AUDIO_DIR = "recordings/output"
os.makedirs(INPUT_AUDIO_DIR, exist_ok=True)
os.makedirs(OUTPUT_AUDIO_DIR, exist_ok=True)

router = APIRouter()

TARGET_SAMPLE_RATE = 24000  # Voice Agent API's fixed audio format
CHUNK_MS = 50  # 50ms chunks as recommended
CHUNK_SIZE = (TARGET_SAMPLE_RATE * 2 * CHUNK_MS) // 1000  # 2400 bytes at 24kHz


class AudioRequest(BaseModel):
    """Request model for audio input."""
    audio: str  # Base64 encoded PCM16 audio
    sample_rate: int = 24000
    session_id: Optional[str] = None


class AudioResponse(BaseModel):
    """Response model for audio output."""
    audio: str  # Base64 encoded response audio
    user_transcript: str
    agent_transcript: str
    audio_size: int
    session_id: str


async def _drain_until_reply_done(websocket, session_id: str, timeout: float = 30.0):
    """
    Drain events until reply.done or session.ended is received.
    This is critical - we must wait for reply.done to get complete transcripts/audio.
    Also handles tool_call events and executes tools in parallel.
    """
    audio_chunks = []
    user_texts = []
    agent_texts = []
    start_time = asyncio.get_event_loop().time()
    
    # Context for tool execution
    context = {
        "driver_id": session_id,
        "driver_name": "Test Driver",
        "shift_id": session_id,
        "current_delivery": None,
        "session_id": session_id
    }
    
    tool_was_called = False
    message_count = 0
    
    print(f"[AAI DEBUG] Starting drain loop - timeout: {timeout}s", flush=True)
    
    while True:
        message_count += 1
        elapsed = asyncio.get_event_loop().time() - start_time
        
        if elapsed > timeout:
            print(f"[AAI DEBUG] Drain loop timed out after {elapsed:.1f}s, {message_count} messages", flush=True)
            break

        try:
            response = await asyncio.wait_for(websocket.recv(), timeout=5.0)
        except asyncio.TimeoutError:
            print(f"[AAI DEBUG] Drain loop timed out waiting for next message after {elapsed:.1f}s", flush=True)
            break

        print(f"[AAI DEBUG] Message #{message_count}: received after {elapsed:.1f}s", flush=True)

        if isinstance(response, (bytes, bytearray)):
            print(f"[AAI RAW] Unexpected BINARY frame: {len(response)} bytes", flush=True)
            continue

        data = json.loads(response)
        msg_type = data.get("type")
        
        print(f"[AAI DEBUG] Event type: {msg_type}", flush=True)
        if msg_type not in ["reply.audio", "transcript.user", "transcript.agent"]:
            print(f"[AAI DEBUG] Full event data: {json.dumps(data, indent=2)}", flush=True)

        if msg_type == "reply.audio":
            # AssemblyAI uses "data" field, not "audio"
            raw = data.get("data", "")
            if raw:
                decoded = base64.b64decode(raw)
                audio_chunks.append(decoded)
                print(f"[AAI DEBUG] reply.audio chunk: {len(decoded)} bytes (total: {len(b''.join(audio_chunks))} bytes)", flush=True)
            else:
                print(f"[AAI DEBUG] reply.audio with empty 'data' field: {data}", flush=True)

        elif msg_type == "transcript.user":
            text = data.get("text", "")
            user_texts.append(text)
            print(f"[AAI DEBUG] User transcript: {text!r}", flush=True)

        elif msg_type == "transcript.agent":
            text = data.get("text", "")
            agent_texts.append(text)
            print(f"[AAI DEBUG] Agent transcript: {text!r}", flush=True)

        elif msg_type == "tool.call":
            # Handle tool execution
            print(f"[AAI DEBUG] === TOOL CALL DETECTED ===", flush=True)
            print(f"[AAI DEBUG] tool.call received: {json.dumps(data, indent=2)}", flush=True)
            tool_call_id = data.get("call_id")
            tool_name = data.get("name")
            tool_arguments = data.get("arguments", {})
            tool_was_called = True
            
            print(f"[AAI DEBUG] Tool: {tool_name}", flush=True)
            print(f"[AAI DEBUG] Arguments: {json.dumps(tool_arguments, indent=2)}", flush=True)
            
            try:
                result = await execute_tool(tool_name, tool_arguments, context)
                tool_result_message = {
                    "type": "tool.result",
                    "call_id": tool_call_id,
                    "result": json.dumps(result),
                    "is_error": bool(isinstance(result, dict) and result.get("error"))
                }
                await websocket.send(json.dumps(tool_result_message))
                print(f"[AAI DEBUG] Tool {tool_name} SUCCESS: {json.dumps(result, indent=2)}", flush=True)
            except Exception as e:
                print(f"[AAI ERROR] Tool {tool_name} FAILED: {e}", flush=True)
                import traceback
                traceback.print_exc()
                tool_result_message = {
                    "type": "tool.result",
                    "call_id": tool_call_id,
                    "result": json.dumps({"success": False, "error": str(e)}),
                    "is_error": True
                }
                await websocket.send(json.dumps(tool_result_message))
            
            print(f"[AAI DEBUG] === TOOL CALL COMPLETE ===", flush=True)
            
            # Don't break - continue draining to get the agent's spoken response
            # The agent will send a new reply after processing tool results

        elif msg_type == "reply.done":
            print(f"[AAI DEBUG] reply.done received", flush=True)
            # If a tool was called, we need to continue draining to get the agent's response
            # The agent sends reply.done after the initial response, then after tool results,
            # it sends a new reply with the spoken response
            if tool_was_called and not agent_texts:
                print(f"[AAI DEBUG] Tool was called but no agent transcript yet - continuing to drain", flush=True)
                tool_was_called = False  # Reset to avoid infinite loop
                continue
            else:
                print(f"[AAI DEBUG] reply.done received - ending drain (messages: {message_count})", flush=True)
                break

        elif msg_type == "session.ended":
            print(f"[AAI DEBUG] session.ended received - ending drain", flush=True)
            break

        elif msg_type == "session.error":
            print(f"[AAI ERROR] session.error: {json.dumps(data, indent=2)}", flush=True)
            break

        else:
            print(f"[AAI DEBUG] Unhandled event: {msg_type}", flush=True)
            print(f"[AAI DEBUG] Full event data: {json.dumps(data, indent=2)}", flush=True)

    print(f"[AAI DEBUG] Drain complete - messages processed: {message_count}", flush=True)
    print(f"[AAI DEBUG] Audio chunks: {len(audio_chunks)}, User texts: {len(user_texts)}, Agent texts: {len(agent_texts)}", flush=True)
    
    return audio_chunks, user_texts, agent_texts, msg_type == "session.ended"


async def handle_assemblyai_session(audio_data: bytes, session_id: str):
    """
    Handle a single AssemblyAI session following the exact protocol.
    """
    print(f"\n[AAI DEBUG] Starting AssemblyAI session")
    print(f"[AAI DEBUG] Session ID: {session_id}")
    print(f"[AAI DEBUG] Input audio size: {len(audio_data)} bytes")

    headers = {"Authorization": f"Bearer {settings.assemblyai_api_key}"}

    print(f"[AAI DEBUG] Connecting to AssemblyAI WebSocket...")
    print(f"[AAI DEBUG] URL: {settings.assemblyai_voice_agent_url}")

    async with websockets.connect(
        settings.assemblyai_voice_agent_url,
        additional_headers=headers
    ) as websocket:
        print(f"[AAI DEBUG] Connected to AssemblyAI")

        # Step 2: Send session.update immediately after connecting
        print(f"[AAI DEBUG] Sending session.update...")
        session_config = get_session_config(
            driver_id=session_id, 
            shift_id=session_id,
            agent_id=settings.assemblyai_agent_id
        )
        print(f"[AAI DEBUG] Session config: {json.dumps(session_config, indent=2)}", flush=True)
        await websocket.send(json.dumps(session_config))
        print(f"[AAI DEBUG] Session config sent")

        # Step 3: Wait for session.updated or session.ready
        print(f"[AAI DEBUG] Waiting for session.updated or session.ready...")
        try:
            first_response = await asyncio.wait_for(websocket.recv(), timeout=10.0)
            first_data = json.loads(first_response)
            first_type = first_data.get("type")
            print(f"[AAI DEBUG] First response type: {first_type}")
            
            if first_type == "session.error":
                print(f"[AAI ERROR] Session error details: {json.dumps(first_data, indent=2)}", flush=True)
                return None, [], []
            
            if first_type not in ['session.updated', 'session.ready']:
                print(f"[AAI ERROR] Unexpected first response: {first_type}", flush=True)
                return None, [], []
            
            print(f"[AAI DEBUG] Session ready - draining greeting...")
        except asyncio.TimeoutError:
            print(f"[AAI ERROR] Timeout waiting for session ready", flush=True)
            return None, [], []

        # Drain the greeting (greeting audio that server sends automatically)
        greeting_audio, _, greeting_agent_text, greeting_ended = await _drain_until_reply_done(websocket, session_id)
        print(f"[AAI DEBUG] Greeting complete: {len(b''.join(greeting_audio))} bytes, "
              f"agent said: {' '.join(greeting_agent_text)!r}", flush=True)

        if greeting_ended:
            return b"".join(greeting_audio), [], greeting_agent_text

        # Step 4: Stream user audio in chunks (50ms = 2400 bytes at 24kHz)
        print(f"[AAI DEBUG] Streaming user audio in chunks...")
        total_chunks = (len(audio_data) + CHUNK_SIZE - 1) // CHUNK_SIZE
        print(f"[AAI DEBUG] Total chunks to send: {total_chunks}")

        for i in range(total_chunks):
            start = i * CHUNK_SIZE
            end = min(start + CHUNK_SIZE, len(audio_data))
            chunk = audio_data[start:end]
            chunk_b64 = base64.b64encode(chunk).decode('utf-8')
            
            # Send input.audio event
            await websocket.send(json.dumps({"type": "input.audio", "audio": chunk_b64}))
            print(f"[AAI DEBUG] Sent chunk {i+1}/{total_chunks}: {len(chunk)} bytes", flush=True)
            
            # Small delay to simulate real-time streaming
            await asyncio.sleep(0.05)

        print(f"[AAI DEBUG] User audio streaming complete")

        # Step 5: Wait for reply.done to get complete response
        print(f"[AAI DEBUG] Waiting for reply.done...")
        response_audio, user_texts, agent_texts, response_ended = await _drain_until_reply_done(websocket, session_id)

        combined_audio = b"".join(response_audio)
        print(f"[AAI DEBUG] Total response audio: {len(combined_audio)} bytes", flush=True)
        print(f"[AAI DEBUG] User transcript: {' '.join(user_texts)!r}", flush=True)
        print(f"[AAI DEBUG] Agent transcript: {' '.join(agent_texts)!r}", flush=True)

        # Step 6: Send session.end on intentional hangup
        print(f"[AAI DEBUG] Sending session.end...")
        await websocket.send(json.dumps({"type": "session.end"}))
        print(f"[AAI DEBUG] Session ended")

        return combined_audio, user_texts, agent_texts


@router.post("/voice-agent", response_model=AudioResponse)
async def voice_agent_endpoint(request: AudioRequest):
    """
    REST API endpoint for AssemblyAI voice agent interaction.
    Accepts base64-encoded PCM16 audio and returns AssemblyAI's voice response.
    """
    print(f"\n[API DEBUG] Received voice agent request")
    print(f"[API DEBUG] Session ID: {request.session_id}")
    print(f"[API DEBUG] Sample rate: {request.sample_rate}")

    # Generate session ID if not provided
    if not request.session_id:
        request.session_id = f"live_session_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        print(f"[API DEBUG] Generated session ID: {request.session_id}")

    # Decode audio
    try:
        print(f"[API DEBUG] Decoding base64 audio...")
        audio_data = base64.b64decode(request.audio)
        print(f"[API DEBUG] Decoded audio size: {len(audio_data)} bytes")
    except Exception as e:
        print(f"[API ERROR] Invalid base64 audio: {str(e)}")
        raise HTTPException(status_code=400, detail=f"Invalid base64 audio: {str(e)}")

    # Resample to 24 kHz if needed
    if request.sample_rate != TARGET_SAMPLE_RATE:
        print(f"[API DEBUG] Resampling from {request.sample_rate} Hz to {TARGET_SAMPLE_RATE} Hz...")
        audio_data = resample_audio(audio_data, request.sample_rate, TARGET_SAMPLE_RATE)
        print(f"[API DEBUG] Resampled audio size: {len(audio_data)} bytes")

    # Save input audio
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    input_wav = os.path.join(INPUT_AUDIO_DIR, f"input_{request.session_id}_{timestamp}.wav")
    print(f"[API DEBUG] Saving input audio to: {input_wav}")
    save_wav(audio_data, input_wav, TARGET_SAMPLE_RATE)
    print(f"[API DEBUG] Input audio saved")

    # Send to AssemblyAI
    print(f"[API DEBUG] Sending to AssemblyAI...")
    try:
        response_audio, user_transcript, agent_transcript = await handle_assemblyai_session(
            audio_data, request.session_id
        )
        print(f"[API DEBUG] AssemblyAI response received")
        print(f"[API DEBUG] Response audio size: {len(response_audio) if response_audio else 0} bytes")
        print(f"[API DEBUG] User transcript: {' '.join(user_transcript)}")
        print(f"[API DEBUG] Agent transcript: {' '.join(agent_transcript)}")
    except Exception as e:
        print(f"[API ERROR] AssemblyAI error: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"AssemblyAI error: {str(e)}")

    # Save output audio if we got any
    if response_audio and len(response_audio) > 0:
        output_wav = os.path.join(OUTPUT_AUDIO_DIR, f"output_{request.session_id}_{timestamp}.wav")
        print(f"[API DEBUG] Saving output audio to: {output_wav}")
        save_wav(response_audio, output_wav, TARGET_SAMPLE_RATE)
        print(f"[API DEBUG] Output audio saved")
    else:
        print(f"[API WARNING] No audio response received from AssemblyAI")

    # Return response
    return AudioResponse(
        audio=base64.b64encode(response_audio).decode('utf-8') if response_audio else "",
        user_transcript=' '.join(user_transcript),
        agent_transcript=' '.join(agent_transcript),
        audio_size=len(response_audio) if response_audio else 0,
        session_id=request.session_id
    )