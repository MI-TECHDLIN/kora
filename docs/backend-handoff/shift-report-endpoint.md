# Handoff: shift report read endpoint

**For:** Maria, backend owner - **From:** frontend (Summary screen redesign) - **Date:** 2026-09-16
**Status:** proposal. No backend code was changed.

## What the app needs

The Summary screen now draws the structured post-shift report: a success ring, delivered,
failed, and remaining tiles, a sentiment bar, incidents, route notes, and a coach's note.
Everything it needs comes from `run_shift_intelligence()`
(`app/intelligence/lemur_pipeline.py`), which already stores all of it in `intelligence_reports`.

## The endpoint mostly exists already

`GET /v1/shift/{shift_id}/report` (`app/api/routes/shift.py`) is mounted and listed in
`docs/contracts/interface.md` section 2. It returns the stored row, or
`200 {"status": "processing", "message": "Report is being generated"}` when no row exists.
**The app is built against that response as it is today**, in
`frontend/lib/core/api/voiceops_api.dart` (`fetchShiftReport`) and
`frontend/lib/features/summary/data/shift_report.dart`. Nothing below blocks the app. Each item
fixes a gap and is additive.

### Response the app reads (a ready report)

```json
{
  "id": "...", "shift_id": "...",
  "total_deliveries": 20, "delivered_count": 17, "failed_count": 2,
  "success_rate": 85.0,
  "sentiment_score": 0.82,
  "recommendations": "Pre-verify gate codes by SMS in congested zones.",
  "route_issues": ["Congestion noted around Marina"],
  "failure_patterns": {
    "executive_summary": "...",
    "incidents": ["Customer security gate access delay"],
    "voice_sessions_analyzed": 14
  },
  "generated_at": "2026-09-16T18:04:00Z"
}
```

`success_rate` is a 0-100 percentage and `sentiment_score` runs from 0.0 to 1.0. The app also
accepts `incidents` at the top level, in case you flatten it later.

## Proposed changes, in priority order

1. **Check ownership (security).** Today any signed-in driver can read any shift's report. Load
   the shift with `get_shift_by_id` and return `404 {"detail": "Shift not found"}` unless
   `shift.driver_id == current_user["id"]`. This matches the auth on the other
   `get_current_driver` routes: a Bearer JWT, and 401 when it's missing or invalid.
2. **Return the newest report.** `/analyze-lemur` and every `/end` call insert a new row, but
   `get_intelligence_report_by_shift` returns `data[0]` with no ordering. Add
   `.order("generated_at", desc=True).limit(1)`.
3. **Tell "not ready" apart from "not found".**
   - Unknown shift, another driver's shift, or a non-UUID id: `404`.
   - Shift exists but no report row yet: keep `200 {"status": "processing", "message": "..."}`.
   - A ready report: add `"status": "ready"` to the row (optional; the app treats a missing
     `status` as ready).

   **Why "processing" stays a 200 and isn't a 404:** the report is written seconds after
   `POST /end` returns, so "not yet" is an expected state, not an error. The app shows "still
   being put together" with a "Check again" button, and only a real 404 or 5xx shows the error
   state. `interface.md` already documents the processing body, so keeping it makes this
   change additive.
4. **Stop hiding database errors as "processing".** `get_intelligence_report_by_shift` catches
   every exception and returns `None`, so a Supabase outage looks like a report that never
   finishes. Let the error propagate as a 500, the way `get_shift_by_id` does.
5. **Add shift timing (optional, additive).** Include `shift_started_at` and `shift_ended_at`
   from the `shifts` row, which you'll already have loaded for item 1. When both are present
   the app shows an "On shift 6h 40m" tile. Without them it shows a "Voice check-ins" tile
   instead. `/end` also sends `shift_duration_min=0` to n8n today, and the same timestamps
   would fix that.

## Contract note

Items 1-4 tighten behaviour that `interface.md` section 2 already describes. Item 3's `"status":
"ready"` and item 5's timestamps are new optional fields. Please update the section 2 row for
`/report` in the same change.
