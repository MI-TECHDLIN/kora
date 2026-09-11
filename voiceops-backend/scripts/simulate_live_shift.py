"""
Real-Life Live End-to-End Shift Simulation
Simulates the exact real-world sequence of a driver using VoiceOps:
1. Driver registers / connects shift
2. Starts shift in Supabase (creates real UUID shift)
3. Receives real delivery stops (manifest)
4. Interacts with the Voice Assistant (logs realistic multi-turn voice sessions, transcripts & tools)
5. Driver ends shift -> Triggers AssemblyAI LeMUR intelligence pipeline
6. LeMUR analyzes all voice transcripts, identifies incidents & sentiment, saves report in Supabase
7. Triggers n8n post-shift intelligence webhook to notify fleet operations
8. Queries Supabase intelligence_reports table to verify output
"""
import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import asyncio
import json

from datetime import datetime, timezone, timedelta
from app.db.client import get_supabase_client
from app.intelligence.lemur_pipeline import run_shift_intelligence
from app.integrations.n8n_client import send_post_shift_report



async def main():
    sb = get_supabase_client()
    print("=" * 70)
    print("🚀 STARTING REAL-LIFE LIVETEST: VOICEOPS + ASSEMBLYAI LEMUR + N8N")
    print("=" * 70)

    # 1. Driver verification
    print("\n📍 [Step 1/7] Fetching Driver in Supabase...")
    driver_res = sb.table("drivers").select("*").limit(1).execute()
    if driver_res.data:
        driver = driver_res.data[0]
    else:
        driver_ins = sb.table("drivers").insert({
            "name": "Emeka Okafor",
            "phone": "+2348012345678",
            "vehicle_type": "Logistics Van"
        }).execute()
        driver = driver_ins.data[0]
    
    driver_id = driver["id"]
    driver_name = driver.get("name") or "Emeka Okafor"
    print(f"   Driver: {driver_name} | ID: {driver_id}")

    # 2. Start Shift
    print("\n⏱️  [Step 2/7] Starting Driver Shift in Supabase...")
    started_time = (datetime.now(timezone.utc) - timedelta(hours=4)).isoformat()
    shift_res = sb.table("shifts").insert({
        "driver_id": driver_id,
        "status": "active",
        "started_at": started_time
    }).execute()
    shift = shift_res.data[0]
    shift_id = shift["id"]
    print(f"   ✅ Active Shift Created in Supabase! UUID: {shift_id}")

    # 3. Assign Deliveries
    print("\n📦 [Step 3/7] Dispatching 5 Deliveries to Driver Manifest...")
    deliveries_data = [
        {
            "shift_id": shift_id,
            "recipient_name": "Amara Johnson",
            "address": "14 Broad Street, Lagos Island",
            "status": "delivered",
            "sequence_order": 1,
            "notes": "Leave with receptionist on ground floor"
        },
        {
            "shift_id": shift_id,
            "recipient_name": "Tunde Bakare",
            "address": "25 Marina Road, Lagos",
            "status": "delivered",
            "sequence_order": 2,
            "notes": "Call upon arrival"
        },
        {
            "shift_id": shift_id,
            "recipient_name": "Fatima Bello",
            "address": "8 Adeola Odeku, Victoria Island",
            "status": "failed",
            "failure_reason": "Gate locked. Security denied entry without resident badge.",
            "sequence_order": 3,
            "notes": "High-security estate"
        },
        {
            "shift_id": shift_id,
            "recipient_name": "Chidi Obi",
            "address": "12 Awolowo Road, Ikoyi",
            "status": "delivered",
            "sequence_order": 4,
            "notes": "Doorbell ring twice"
        },
        {
            "shift_id": shift_id,
            "recipient_name": "Kolawole Adams",
            "address": "45 Allen Avenue, Ikeja",
            "status": "delivered",
            "sequence_order": 5,
            "notes": "Commercial drop-off"
        }
    ]
    sb.table("deliveries").insert(deliveries_data).execute()
    print("   ✅ 5 deliveries saved in Supabase (4 completed, 1 failed due to locked gate).")

    # 4. Driver voice sessions
    print("\n🎙️  [Step 4/7] Driver is on the road — logging 5 real-time voice sessions...")
    sessions_data = [
        {
            "shift_id": shift_id,
            "driver_id": driver_id,
            "driver_transcript": "What is my first stop for today?",
            "agent_transcript": "Your first stop is 14 Broad Street, Lagos Island for Amara Johnson. Leave with ground floor reception.",
            "tool_calls": [{"name": "get_next_delivery", "arguments": {}}],
            "started_at": (datetime.now(timezone.utc) - timedelta(hours=3, minutes=45)).isoformat()
        },
        {
            "shift_id": shift_id,
            "driver_id": driver_id,
            "driver_transcript": "Road is completely blocked by road construction near Marina Road, alert the dispatcher right now.",
            "agent_transcript": "Alerting dispatcher with high priority. Alternate route suggested via Marina bypass.",
            "tool_calls": [{"name": "alert_dispatcher", "arguments": {"message": "Construction road blockage", "severity": "high"}}],
            "started_at": (datetime.now(timezone.utc) - timedelta(hours=2, minutes=30)).isoformat()
        },
        {
            "shift_id": shift_id,
            "driver_id": driver_id,
            "driver_transcript": "Gate is locked at Adeola Odeku and security will not let me through without clearance. Call customer Fatima.",
            "agent_transcript": "Connecting you to customer Fatima Bello via secure masked phone bridge.",
            "tool_calls": [{"name": "call_customer", "arguments": {"recipient": "Fatima Bello"}}],
            "started_at": (datetime.now(timezone.utc) - timedelta(hours=1, minutes=40)).isoformat()
        },
        {
            "shift_id": shift_id,
            "driver_id": driver_id,
            "driver_transcript": "Nobody answered the call. Mark stop as failed delivery.",
            "agent_transcript": "Marked delivery as failed: Gate locked, recipient unavailable.",
            "tool_calls": [{"name": "update_delivery_status", "arguments": {"status": "failed", "reason": "Gate locked"}}],
            "started_at": (datetime.now(timezone.utc) - timedelta(hours=1, minutes=30)).isoformat()
        },
        {
            "shift_id": shift_id,
            "driver_id": driver_id,
            "driver_transcript": "Completed all other deliveries. How am I doing for today?",
            "agent_transcript": "You completed 4 out of 5 stops with an 80% success rate. Great work.",
            "tool_calls": [{"name": "get_shift_summary", "arguments": {}}],
            "started_at": (datetime.now(timezone.utc) - timedelta(minutes=15)).isoformat()
        }
    ]
    sb.table("voice_sessions").insert(sessions_data).execute()
    print("   ✅ 5 voice sessions with transcripts and tool invocations recorded in Supabase.")

    # 5. End Shift & Run LeMUR Intelligence
    print("\n🏁 [Step 5/7] Driver taps 'End Shift' in App -> Executing LeMUR Intelligence Pipeline...")
    sb.table("shifts").update({
        "status": "completed",
        "ended_at": datetime.now(timezone.utc).isoformat()
    }).eq("id", shift_id).execute()
    print("   ✅ Shift status updated to 'completed' in Supabase.")

    print("\n🧠 [Step 6/7] Running AssemblyAI LeMUR on Voice Transcripts...")
    lemur_result = await run_shift_intelligence(shift_id, driver_id=driver_id)
    analysis = lemur_result["analysis"]

    print("\n   --- 📋 ASSEMBLYAI LEMUR INTELLIGENCE RESULTS ---")
    print(f"   • Source:                  {analysis.get('lemur_source')}")
    print(f"   • Executive Summary:       {analysis.get('executive_summary')}")
    print(f"   • Driver Sentiment Score:  {analysis.get('sentiment_score')} / 1.0")
    print(f"   • Detected Incidents:      {analysis.get('incidents')}")
    print(f"   • Route Bottlenecks:       {analysis.get('route_issues')}")
    print(f"   • Coaching Advice:         {analysis.get('recommendations')}")
    print(f"   • Stored in Supabase:      {lemur_result.get('stored')}")

    # 6. Fire n8n Post-Shift Notification
    print("\n🌐 [Step 7/7] Firing n8n Post-Shift Intelligence Webhook...")
    n8n_res = await send_post_shift_report(
        shift_id=shift_id,
        driver_id=driver_id,
        driver_name=driver_name,
        total_deliveries=5,
        delivered_count=4,
        failed_count=1,
        shift_duration_min=240,
        dispatcher_alerts=1,
        voice_sessions=5,
        operator_email="tomarianoor@gmail.com",
        webhook_url="http://localhost:5678/webhook/post-shift-intelligence"
    )
    print(f"   ✅ n8n Webhook Status: {n8n_res.get('status_code', 'Triggered')} | Success: {n8n_res.get('success')}")

    # 7. Verify Supabase record
    print("\n📊 Verifying Final Record in Supabase 'intelligence_reports' Table...")
    report_check = sb.table("intelligence_reports").select("*").eq("shift_id", shift_id).execute()
    if report_check.data:
        r = report_check.data[0]
        print(f"   • Report UUID:     {r['id']}")
        print(f"   • Shift UUID:      {r['shift_id']}")
        print(f"   • Deliveries:      {r['delivered_count']}/{r['total_deliveries']} ({r['success_rate']}%)")
        print(f"   • Sentiment Score: {r['sentiment_score']}")
        print(f"   • Generated At:    {r['generated_at']}")
        print(f"   • Failure Details: {json.dumps(r['failure_patterns'], indent=6)[:250]}...")
    
    print("\n" + "=" * 70)
    print("🎉 REAL-LIFE LIVE END-TO-END SHIFT LIFECYCLE COMPLETED SUCCESSFULLY!")
    print("=" * 70)


if __name__ == "__main__":
    asyncio.run(main())
