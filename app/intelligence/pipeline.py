from typing import Dict, Any
from app.db.queries import (
    get_shift_voice_sessions,
    get_shift_deliveries,
    update_shift_status,
    store_intelligence_report
)
from app.intelligence.assemblyai_batch import transcribe_and_analyze, run_lemur_analysis
from app.intelligence.report_generator import generate_report


async def run_shift_intelligence(shift_id: str, driver_id: str) -> Dict[str, Any]:
    """
    Run the complete post-shift intelligence pipeline.
    Called as FastAPI BackgroundTask on shift end.
    """
    try:
        # Update shift status to processing
        await update_shift_status(shift_id, "processing")
        
        # Fetch shift data
        sessions = await get_shift_voice_sessions(shift_id)
        deliveries = await get_shift_deliveries(shift_id)
        
        if not sessions:
            # No voice sessions, generate basic report
            basic_report = generate_report(shift_id, driver_id, deliveries, sessions, {})
            await store_intelligence_report(shift_id, basic_report)
            await update_shift_status(shift_id, "completed")
            return basic_report
        
        # Combine transcripts from all sessions
        combined_transcript = _combine_transcripts(sessions)
        
        # Submit to AssemblyAI for analysis
        aai_results = await transcribe_and_analyze(combined_transcript, sessions)
        
        # Run LeMUR analysis if transcript ID available
        if "id" in aai_results:
            lemur_results = await run_lemur_analysis(aai_results["id"])
            aai_results["lemur_analysis"] = lemur_results
        
        # Generate final report
        report = generate_report(shift_id, driver_id, deliveries, sessions, aai_results)
        
        # Store report in database
        await store_intelligence_report(shift_id, report)
        
        # Update shift status to completed
        await update_shift_status(shift_id, "completed")
        
        return report
        
    except Exception as e:
        print(f"Intelligence pipeline error: {e}")
        await update_shift_status(shift_id, "error")
        return {"error": str(e)}


def _combine_transcripts(sessions: list) -> str:
    """
    Combine all session transcripts into a single text for analysis.
    """
    transcript_parts = []
    
    for session in sessions:
        driver_text = session.get("driver_transcript", "")
        agent_text = session.get("agent_transcript", "")
        
        if driver_text:
            transcript_parts.append(f"Driver: {driver_text}")
        if agent_text:
            transcript_parts.append(f"Agent: {agent_text}")
    
    return "\n\n".join(transcript_parts)
