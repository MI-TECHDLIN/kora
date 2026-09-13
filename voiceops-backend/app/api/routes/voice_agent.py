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
import requests
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from app.config import settings
from app.agents.agent_config import get_session_config
from app.agents.tool_registry import execute_tool
from app.agents.orchestrator import ToolOrchestrator
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
    authorization: Optional[str] = None  # Bearer <supabase_jwt>


class AudioResponse(BaseModel):
    """Response model for audio output."""
    audio: str  # Base64 encoded response audio
    user_transcript: str
    agent_transcript: str
    audio_size: int
    session_id: str


async def _drain_until_reply_done(
    websocket,
    session_id: str,
    context: Optional[dict] = None,
    timeout: float = 30.0
):
    """
    Drain events until reply.done or session.ended is received.
    This is critical - we must wait for reply.done to get complete transcripts/audio.
    Also handles tool_call events and executes tools in parallel.
    """
    audio_chunks = []
    user_texts = []
    agent_texts = []
    start_time = asyncio.get_event_loop().time()
    
    # Resolved live context for tool execution
    if context is None:
        context = {
            "driver_id": session_id,
            "driver_name": "Driver",
            "shift_id": session_id,
            "session_id": session_id,
        }
    
    tool_was_called = False
    pending_tool_tasks = []
    message_count = 0
    
    last_msg_type = ""
    print(f"[VoiceOps] Session started — draining audio (timeout: {timeout}s)")
    
    while True:
        message_count += 1
        elapsed = asyncio.get_event_loop().time() - start_time
        
        if elapsed > timeout:
            print(f"[VoiceOps] WARNING: Drain timed out after {elapsed:.1f}s")
            break

        try:
            response = await asyncio.wait_for(websocket.recv(), timeout=5.0)
        except asyncio.TimeoutError:
            print(f"[VoiceOps] WARNING: No message received for 5s, ending drain")
            break


        if isinstance(response, (bytes, bytearray)):
            print(f"[AAI RAW] Unexpected BINARY frame: {len(response)} bytes", flush=True)
            continue

        data = json.loads(response)
        msg_type = data.get("type")
        last_msg_type = msg_type

        if msg_type == "reply.audio":
            raw = data.get("data", "")
            if raw:
                decoded = base64.b64decode(raw)
                audio_chunks.append(decoded)
                # Log only every 100 chunks to confirm audio is flowing
                if len(audio_chunks) % 100 == 0:
                    total = sum(len(c) for c in audio_chunks)
                    print(f"[VoiceOps] Audio streaming... {len(audio_chunks)} chunks, {total // 1024}KB received")

        elif msg_type == "transcript.user":
            text = data.get("text", "")
            user_texts.append(text)
            print(f"[VoiceOps] User said: {text!r}")

        elif msg_type == "transcript.agent":
            text = data.get("text", "")
            agent_texts.append(text)
            print(f"[VoiceOps] Agent replied: {text!r}")

        elif msg_type == "tool.call":
            tool_name = data.get("name")
            tool_call_id = data.get("call_id")
            tool_arguments = data.get("arguments", {})
            tool_was_called = True
            print(f"[VoiceOps] TOOL CALL: {tool_name} | args: {tool_arguments}")

            async def _execute_and_reply(t_name, t_args, t_id):
                tool_res = await ToolOrchestrator.execute_single_tool(
                    tool_name=t_name,
                    parameters=t_args,
                    context=context,
                    call_id=t_id
                )
                tool_result_message = {
                    "type": "tool.result",
                    "call_id": tool_res["call_id"],
                    "result": tool_res["result"],
                    "is_error": tool_res["is_error"]
                }
                await websocket.send(json.dumps(tool_result_message))
                print(f"[VoiceOps] ✅ Tool {t_name} completed in {tool_res['duration_ms']}ms: {tool_res['parsed_result']}")

            # Schedule task so multiple tool calls run concurrently via asyncio
            task = asyncio.create_task(_execute_and_reply(tool_name, tool_arguments, tool_call_id))
            pending_tool_tasks.append(task)

        elif msg_type == "reply.done":
            if pending_tool_tasks:
                await asyncio.gather(*pending_tool_tasks, return_exceptions=True)
                pending_tool_tasks = []
            total_audio = sum(len(c) for c in audio_chunks)
            print(f"[VoiceOps] Reply complete — {len(audio_chunks)} chunks, {total_audio // 1024}KB audio")
            if tool_was_called and not agent_texts:
                tool_was_called = False
                continue
            else:
                break

        elif msg_type == "session.ended":
            print(f"[VoiceOps] Session ended")
            break

        elif msg_type == "session.error":
            print(f"[VoiceOps] ERROR: Session error: {json.dumps(data, indent=2)}")
            break

        else:
            print(f"[VoiceOps] Received message type: {msg_type}")
            if msg_type not in ["session.ready", "session.updated", "input.speech.started", "input.speech.stopped", "transcript.user", "transcript.user.delta", "reply.started", "reply.audio", "transcript.agent", "tool.call", "tool.result", "reply.done", "session.ended", "session.error"]:
                print(f"[VoiceOps] UNKNOWN MESSAGE TYPE: {msg_type} | data: {json.dumps(data, indent=2)[:200]}")
            pass  # silently ignore unknown event types

    return audio_chunks, user_texts, agent_texts, last_msg_type == "session.ended"


async def handle_assemblyai_session(audio_data: bytes, session_id: str, context: Optional[dict] = None):
    """
    Handle a single AssemblyAI session following the exact protocol.
    """
    effective_context = context or {
        "driver_id": session_id,
        "shift_id": session_id,
        "session_id": session_id,
    }
    driver_id = effective_context.get("driver_id", session_id)
    shift_id = effective_context.get("shift_id", session_id)

    print(f"[VoiceOps] New session: {session_id} (driver: {driver_id}) | audio: {len(audio_data)} bytes")

    # Use token-based authentication for compatibility with current websockets library
    # This is the recommended approach for environments that can't set custom headers
    try:
        # Generate temporary token for authentication
        token_url = f"https://agents.assemblyai.com/v1/token?expires_in_seconds=300"
        token_response = await asyncio.to_thread(
            lambda: requests.get(token_url, headers={"Authorization": f"Bearer {settings.assemblyai_api_key}"})
        )
        
        if token_response.status_code == 200:
            token_data = token_response.json()
            temp_token = token_data.get("token")
            
            if temp_token:
                ws_url_with_token = f"{settings.assemblyai_voice_agent_url}?token={temp_token}"
                print(f"[VoiceOps] Using temporary token authentication")
                
                async with websockets.connect(ws_url_with_token) as websocket:
                    # Step 2: Send session.update immediately after connecting
                    session_config = get_session_config(
                        driver_id=str(driver_id), 
                        shift_id=str(shift_id),
                        agent_id=None  # Use inline config for now to get audio
                    )
                    await websocket.send(json.dumps(session_config))

                    # Step 3: Wait for session.updated then session.ready
                    try:
                        first_response = await asyncio.wait_for(websocket.recv(), timeout=10.0)
                        first_data = json.loads(first_response)
                        first_type = first_data.get("type")
                        
                        if first_type == "session.error":
                            print(f"[VoiceOps] ERROR: Session error: {json.dumps(first_data, indent=2)}")
                            return None, [], []
                        
                        # Handle the expected sequence: session.updated -> session.ready
                        if first_type == "session.updated":
                            print("[VoiceOps] Session configuration updated")
                            # Wait for session.ready
                            second_response = await asyncio.wait_for(websocket.recv(), timeout=10.0)
                            second_data = json.loads(second_response)
                            second_type = second_data.get("type")
                            
                            if second_type == "session.ready":
                                print(f"[VoiceOps] Session ready: {second_data.get('session_id')}")
                            else:
                                print(f"[VoiceOps] ERROR: Expected session.ready, got {second_type}")
                                return None, [], []
                        
                        elif first_type == "session.ready":
                            print(f"[VoiceOps] Session ready: {first_data.get('session_id')}")
                        
                        else:
                            print(f"[VoiceOps] ERROR: Unexpected first response: {first_type}")
                            return None, [], []
                        
                    except asyncio.TimeoutError:
                        print(f"[VoiceOps] ERROR: Timeout waiting for session ready")
                        return None, [], []

                    # Step 4: Drain the greeting first
                    print("[VoiceOps] Draining greeting audio...")
                    greeting_audio, _, greeting_agent_text, greeting_ended = await _drain_until_reply_done(
                        websocket, session_id, context=effective_context
                    )
                    print(f"[VoiceOps] Greeting drained: {len(greeting_audio)} bytes, text: {greeting_agent_text}")
                    
                    # Step 5: Stream user audio in chunks (50ms = 2400 bytes at 24kHz)
                    total_chunks = (len(audio_data) + CHUNK_SIZE - 1) // CHUNK_SIZE
                    print(f"[VoiceOps] Streaming {total_chunks} audio chunks to AssemblyAI...")

                    for i in range(total_chunks):
                        start = i * CHUNK_SIZE
                        end = min(start + CHUNK_SIZE, len(audio_data))
                        chunk = audio_data[start:end]
                        chunk_b64 = base64.b64encode(chunk).decode('utf-8')
                        await websocket.send(json.dumps({"type": "input.audio", "audio": chunk_b64}))
                        await asyncio.sleep(0.05)

                    print(f"[VoiceOps] Audio streaming complete — {total_chunks} chunks, {len(audio_data)//1024}KB sent")

                    # Step 6: Wait for reply.done to get complete response
                    print("[VoiceOps] Waiting for agent response...")
                    response_audio, user_texts, agent_texts, response_ended = await _drain_until_reply_done(
                        websocket, session_id, context=effective_context
                    )

                    combined_audio = b"".join(response_audio)
                    print(f"[VoiceOps] Response received: {len(combined_audio)} bytes audio, user texts: {user_texts}, agent texts: {agent_texts}")

                    # Step 7: Send session.end
                    await websocket.send(json.dumps({"type": "session.end"}))

                    return combined_audio, user_texts, agent_texts
            else:
                print("[VoiceOps] ERROR: Failed to generate temporary token")
                return None, [], []
        else:
            print(f"[VoiceOps] ERROR: Token request failed: {token_response.status_code}")
            return None, [], []
            
    except Exception as e:
        print(f"[VoiceOps] Token-based authentication failed: {e}")
        return None, [], []


@router.post("/voice-agent", response_model=AudioResponse)
async def voice_agent_endpoint(request: AudioRequest):
    """
    REST API endpoint for AssemblyAI voice agent interaction.
    Accepts base64-encoded PCM16 audio and returns AssemblyAI's voice response.
    """
    from app.agents.context_builder import build_driver_context

    # Generate session ID if not provided
    if not request.session_id:
        request.session_id = f"live_session_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

    # Resolve live driver context
    context = await build_driver_context(request.authorization, request.session_id)

    # Decode audio
    try:
        audio_data = base64.b64decode(request.audio)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid base64 audio: {str(e)}")

    # Resample to 24 kHz if needed
    if request.sample_rate != TARGET_SAMPLE_RATE:
        audio_data = resample_audio(audio_data, request.sample_rate, TARGET_SAMPLE_RATE)

    # Save input audio
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    input_wav = os.path.join(INPUT_AUDIO_DIR, f"input_{request.session_id}_{timestamp}.wav")
    save_wav(audio_data, input_wav, TARGET_SAMPLE_RATE)

    # Send to AssemblyAI
    try:
        response_audio, user_transcript, agent_transcript = await handle_assemblyai_session(
            audio_data, request.session_id, context=context
        )
    except Exception as e:
        print(f"[VoiceOps] ERROR: AssemblyAI error: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"AssemblyAI error: {str(e)}")

    # Save output audio
    if response_audio and len(response_audio) > 0:
        output_wav = os.path.join(OUTPUT_AUDIO_DIR, f"output_{request.session_id}_{timestamp}.wav")
        save_wav(response_audio, output_wav, TARGET_SAMPLE_RATE)

    return AudioResponse(
        audio=base64.b64encode(response_audio).decode('utf-8') if response_audio else "",
        user_transcript=' '.join(user_transcript),
        agent_transcript=' '.join(agent_transcript),
        audio_size=len(response_audio) if response_audio else 0,
        session_id=request.session_id
    )