"""
Test tools that have credentials in .env
Tests: AssemblyAI, Supabase, LiveKit
"""
import asyncio
from app.config import settings
from app.integrations.livekit_client import get_livekit_client, make_call
from app.integrations.google_maps import get_directions


async def test_assemblyai_credentials():
    """Test AssemblyAI credentials are configured."""
    print("\n=== Testing AssemblyAI Credentials ===")
    if settings.assemblyai_api_key:
        print(f"[OK] AssemblyAI API Key: {settings.assemblyai_api_key[:20]}...")
    else:
        print("[FAIL] AssemblyAI API Key not configured")
    
    if settings.assemblyai_agent_id:
        print(f"[OK] AssemblyAI Agent ID: {settings.assemblyai_agent_id}")
    else:
        print("[FAIL] AssemblyAI Agent ID not configured")


async def test_supabase_credentials():
    """Test Supabase credentials are configured."""
    print("\n=== Testing Supabase Credentials ===")
    if settings.supabase_url:
        print(f"[OK] Supabase URL: {settings.supabase_url}")
    else:
        print("[FAIL] Supabase URL not configured")
    
    if settings.supabase_service_key:
        print(f"[OK] Supabase Service Key: {settings.supabase_service_key[:20]}...")
    else:
        print("[FAIL] Supabase Service Key not configured")


async def test_livekit_credentials():
    """Test LiveKit credentials and connection."""
    print("\n=== Testing LiveKit Credentials ===")
    if settings.livekit_url:
        print(f"[OK] LiveKit URL: {settings.livekit_url}")
    else:
        print("[FAIL] LiveKit URL not configured")
        return
    
    if settings.livekit_api_key:
        print(f"[OK] LiveKit API Key: {settings.livekit_api_key}")
    else:
        print("[FAIL] LiveKit API Key not configured")
        return
    
    if settings.livekit_api_secret:
        print(f"[OK] LiveKit API Secret: {settings.livekit_api_secret[:20]}...")
    else:
        print("[FAIL] LiveKit API Secret not configured")
        return
    
    if settings.livekit_sip_trunk_id:
        print(f"[OK] LiveKit SIP Trunk ID: {settings.livekit_sip_trunk_id}")
    else:
        print("[WARN] LiveKit SIP Trunk ID not configured (will fail call tests)")
    
    # Try to get client
    client = get_livekit_client()
    if client:
        print("[OK] LiveKit client created successfully")
    else:
        print("[FAIL] Failed to create LiveKit client")


async def test_google_maps_credentials():
    """Test Google Maps credentials."""
    print("\n=== Testing Google Maps Credentials ===")
    if settings.google_maps_api_key:
        print(f"[OK] Google Maps API Key: {settings.google_maps_api_key[:20]}...")
        
        # Test a real API call
        print("Testing Google Directions API...")
        routes = await get_directions(6.44, 3.39, 6.4286, 3.4108)
        if routes:
            print(f"[OK] Google Directions API working - got {len(routes)} route(s)")
            for i, route in enumerate(routes):
                print(f"  Route {i+1}: {route['summary']} - {route['duration']/60:.1f} mins")
        else:
            print("[WARN] Google Directions API returned no routes (may be due to invalid API key)")
    else:
        print("[FAIL] Google Maps API Key not configured")
        print("  Using mock data for route queries")


async def test_vonage_credentials():
    """Test Vonage SMS credentials."""
    print("\n=== Testing Vonage SMS Credentials ===")
    if settings.vonage_api_key:
        print(f"[OK] Vonage API Key: {settings.vonage_api_key}")
    else:
        print("[FAIL] Vonage API Key not configured")
        print("  SMS notifications will fail")
    
    if settings.vonage_api_secret:
        print(f"[OK] Vonage API Secret: {settings.vonage_api_secret[:20]}...")
    else:
        print("[FAIL] Vonage API Secret not configured")


async def main():
    """Run all credential tests."""
    print("=" * 60)
    print("VoiceOps - Tool Credentials Test")
    print("=" * 60)
    
    await test_assemblyai_credentials()
    await test_supabase_credentials()
    await test_livekit_credentials()
    await test_google_maps_credentials()
    await test_vonage_credentials()
    
    print("\n" + "=" * 60)
    print("Credentials test complete")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())