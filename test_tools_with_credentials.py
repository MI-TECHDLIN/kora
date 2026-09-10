"""
Test tools that have credentials in .env
Tests: AssemblyAI, Supabase, Twilio, Google Maps
"""
import asyncio
from app.config import settings
from app.integrations.twilio_client import get_twilio_client, make_call, send_sms
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


async def test_twilio_credentials():
    """Test Twilio credentials and connection."""
    print("\n=== Testing Twilio Credentials ===")
    account_sid = settings.effective_twilio_account_sid
    auth_token = settings.effective_twilio_auth_token
    api_key_sid = settings.effective_twilio_api_key_sid
    api_key_secret = settings.effective_twilio_api_key_secret
    from_number = settings.effective_twilio_from_number

    if account_sid:
        print(f"[OK] Twilio Account SID: {account_sid[:10]}...")
    else:
        print("[FAIL] Twilio Account SID not configured")
        return

    if auth_token:
        print(f"[OK] Twilio Auth Token: {auth_token[:10]}...")
    elif api_key_sid and api_key_secret:
        print(f"[OK] Twilio API Key SID: {api_key_sid[:10]}...")
    else:
        print("[FAIL] Twilio Auth Token or API Key not configured")
        return

    if from_number:
        print(f"[OK] Twilio Phone Number: {from_number}")
    else:
        print("[WARN] Twilio Phone Number not configured (calls and SMS will run in mock mode)")

    client = get_twilio_client()
    if client:
        try:
            account = client.api.accounts(client.account_sid).fetch()
            print(f"[OK] Twilio client connected! Account name: '{account.friendly_name}', status: {account.status}")
        except Exception as e:
            print(f"[FAIL] Twilio authentication check failed: {e}")
    else:
        print("[FAIL] Failed to create Twilio client")


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


async def main():
    """Run all credential tests."""
    print("=" * 60)
    print("VoiceOps - Tool Credentials Test")
    print("=" * 60)
    
    await test_assemblyai_credentials()
    await test_supabase_credentials()
    await test_twilio_credentials()
    await test_google_maps_credentials()
    
    print("\n" + "=" * 60)
    print("Credentials test complete")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())