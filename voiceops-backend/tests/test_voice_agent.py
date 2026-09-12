"""
Simple test for AssemblyAI Voice Agent API.
Tests the voice agent endpoint with a short audio sample.
"""
import requests
import base64
import json

API_URL = "http://localhost:8000/v1/voice-agent"

# Create a simple test audio (silent for now, replace with real audio)
test_audio = b'\x00' * 24000  # 24000 bytes of silence at 24kHz
audio_base64 = base64.b64encode(test_audio).decode('utf-8')

request_data = {
    "audio": audio_base64,
    "sample_rate": 24000,
    "session_id": "test_session"
}

if __name__ == "__main__":
    print("Testing AssemblyAI Voice Agent API...")
    print(f"Sending to: {API_URL}")

    try:
        response = requests.post(API_URL, json=request_data, timeout=60)
        print(f"Status Code: {response.status_code}")
        print(f"Response: {response.text}")
    except Exception as e:
        print(f"Error: {e}")
