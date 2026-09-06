import httpx
from typing import Dict, Any, List
from app.config import settings


async def transcribe_and_analyze(text: str, sessions: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Submit transcript to AssemblyAI Speech Understanding API for analysis.
    Enables: sentiment, IAB categories, auto-chapters, entity detection, summarization.
    """
    if not settings.assemblyai_api_key:
        # Return mock data if no API key
        return {
            "sentiment": 0.6,
            "iab_categories": {},
            "chapters": [],
            "entities": [],
            "summary": "Mock intelligence analysis"
        }
    
    url = "https://api.assemblyai.com/v2/transcript"
    
    headers = {
        "authorization": settings.assemblyai_api_key,
        "content-type": "application/json"
    }
    
    data = {
        "audio_url": "",  # Would need audio file URL for real implementation
        "sentiment_analysis": True,
        "iab_categories": True,
        "auto_chapters": True,
        "entity_detection": True,
        "summarization": True,
        "summary_model": "informative",
        "summary_type": "bullets"
    }
    
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(url, headers=headers, json=data, timeout=30.0)
            response.raise_for_status()
            result = response.json()
            
            # Poll until complete
            transcript_id = result.get("id")
            if transcript_id:
                return await _poll_until_complete(transcript_id)
            
            return result
    except Exception as e:
        print(f"AssemblyAI transcription error: {e}")
        return {"error": str(e)}


async def _poll_until_complete(transcript_id: str, max_attempts: int = 60) -> Dict[str, Any]:
    """
    Poll AssemblyAI transcript status until complete.
    """
    url = f"https://api.assemblyai.com/v2/transcript/{transcript_id}"
    headers = {"authorization": settings.assemblyai_api_key}
    
    for attempt in range(max_attempts):
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(url, headers=headers, timeout=10.0)
                response.raise_for_status()
                result = response.json()
                
                status = result.get("status")
                if status == "completed":
                    return result
                elif status == "error":
                    return {"error": result.get("error", "Transcription failed")}
                
                # Wait 3 seconds before next poll
                import asyncio
                await asyncio.sleep(3)
                
        except Exception as e:
            print(f"Poll error (attempt {attempt + 1}): {e}")
            import asyncio
            await asyncio.sleep(3)
    
    return {"error": "Transcription timeout"}


async def run_lemur_analysis(transcript_id: str) -> Dict[str, Any]:
    """
    Run LeMUR analysis with custom prompts for logistics intelligence.
    """
    if not settings.assemblyai_api_key:
        return {
            "failure_patterns": "No failure patterns detected",
            "route_issues": "No route issues detected",
            "recommendations": "Continue current operations"
        }
    
    url = "https://api.assemblyai.com/lemur/v3/generate/task-result"
    
    headers = {
        "authorization": settings.assemblyai_api_key,
        "content-type": "application/json"
    }
    
    prompts = [
        {
            "prompt": "Analyze this delivery transcript for failure patterns. What are the top 3 reasons deliveries fail? Return as JSON with keys: patterns (list of strings), frequency (list of numbers).",
            "context": f"Transcript ID: {transcript_id}"
        },
        {
            "prompt": "Analyze this delivery transcript for route and navigation issues. What locations or routes cause problems? Return as JSON with keys: problem_areas (list of strings), severity (list of strings).",
            "context": f"Transcript ID: {transcript_id}"
        },
        {
            "prompt": "Based on this delivery transcript, provide 3 actionable recommendations to improve operations. Return as JSON with keys: recommendations (list of strings), priority (list of strings).",
            "context": f"Transcript ID: {transcript_id}"
        }
    ]
    
    results = {}
    for i, prompt_data in enumerate(prompts):
        try:
            data = {
                "transcript_ids": [transcript_id],
                "prompt": prompt_data["prompt"],
                "context": prompt_data["context"],
                "model": "anthropic/claude-3-5-sonnet"
            }
            
            async with httpx.AsyncClient() as client:
                response = await client.post(url, headers=headers, json=data, timeout=30.0)
                response.raise_for_status()
                result = response.json()
                
                # Parse result based on prompt index
                if i == 0:
                    results["failure_patterns"] = result.get("response", {})
                elif i == 1:
                    results["route_issues"] = result.get("response", {})
                else:
                    results["recommendations"] = result.get("response", {})
                    
        except Exception as e:
            print(f"LeMUR analysis error (prompt {i + 1}): {e}")
            results[f"error_{i}"] = str(e)
    
    return results
