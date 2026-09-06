from typing import Dict, Any, List
import json
import re


def generate_report(
    shift_id: str,
    driver_id: str,
    deliveries: List[Dict[str, Any]],
    sessions: List[Dict[str, Any]],
    aai_results: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Generate intelligence report from shift data and AssemblyAI analysis.
    """
    # Compute basic stats
    total = len(deliveries)
    delivered = sum(1 for d in deliveries if d.get("status") == "delivered")
    failed = sum(1 for d in deliveries if d.get("status") == "failed")
    success_rate = (delivered / total * 100) if total > 0 else 0
    
    # Extract sentiment from sessions
    sentiment_scores = []
    for session in sessions:
        if "sentiment" in session:
            sentiment_scores.append(session["sentiment"])
    
    avg_sentiment = sum(sentiment_scores) / len(sentiment_scores) if sentiment_scores else 0.5
    
    # Parse LeMUR results safely
    lemur_results = aai_results.get("lemur_analysis", {})
    failure_patterns = _safe_parse_json(lemur_results.get("failure_patterns", "{}"))
    route_issues = _safe_parse_json(lemur_results.get("route_issues", "{}"))
    recommendations = _safe_parse_json(lemur_results.get("recommendations", "{}"))
    
    # Build report
    report = {
        "total_deliveries": total,
        "delivered_count": delivered,
        "failed_count": failed,
        "success_rate": round(success_rate, 2),
        "sentiment_score": round(avg_sentiment, 2),
        "failure_patterns": failure_patterns,
        "route_issues": route_issues,
        "recommendations": recommendations,
        "top_failure_reason": _get_top_failure(deliveries),
        "sessions_analyzed": len(sessions),
        "driver_flagged": avg_sentiment < 0.25  # Flag frustrated drivers
    }
    
    return report


def _safe_parse_json(json_str: str) -> Dict[str, Any]:
    """
    Safely parse JSON string, handling markdown code blocks and malformed JSON.
    """
    if not json_str:
        return {}
    
    # Remove markdown code blocks if present
    json_str = re.sub(r'```json\s*', '', json_str)
    json_str = re.sub(r'```\s*', '', json_str)
    json_str = json_str.strip()
    
    try:
        return json.loads(json_str)
    except json.JSONDecodeError:
        # Try to extract JSON from string
        try:
            # Find first { and last }
            start = json_str.find('{')
            end = json_str.rfind('}') + 1
            if start >= 0 and end > start:
                return json.loads(json_str[start:end])
        except:
            pass
        
        return {"error": "Could not parse JSON", "raw": json_str}


def _get_top_failure(deliveries: List[Dict[str, Any]]) -> str:
    """
    Determine the most common failure reason from deliveries.
    """
    failure_reasons = {}
    
    for delivery in deliveries:
        if delivery.get("status") == "failed":
            reason = delivery.get("failure_reason", "unknown")
            failure_reasons[reason] = failure_reasons.get(reason, 0) + 1
    
    if not failure_reasons:
        return "No failures"
    
    # Get most common reason
    top_reason = max(failure_reasons.items(), key=lambda x: x[1])
    return f"{top_reason[0]} ({top_reason[1]} occurrences)"
