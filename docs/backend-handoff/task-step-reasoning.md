# Handoff: result-backed reasoning on task steps

**For:** Maria, backend owner, and Ez, frontend owner - **From:** task-progress reasoning work - **Date:** 2026-09-21
**Status:** proposal. No backend, frontend, or frozen-contract code was changed.

## Goal

The task progress card will show one short **Why** line below its steps. The line is collapsed by
default and expands on tap. It should explain a completed action with facts the backend actually
received, not with a rationale invented by the model.

The app will treat the field as optional. A backend that does not send it behaves exactly as it
does today: the steps still update and the Why line stays hidden.

## Proposed contract text for Maria and Ez to sign off

The following is the exact proposed addition. It is **not** applied to
`docs/contracts/interface.md` by this handoff:

> Add an optional `reasoning` member to the server-to-client `task_step` event. `reasoning` is a
> string of at most 140 Unicode characters. It uses plain language, contains no implementation
> jargon, and contains no personally identifiable information beyond information already visible
> to the driver. The relay MUST include `reasoning` only when `status` is `done`, the tool result
> has `success: true`, and the text can be deterministically derived from fields returned by that
> tool. The relay MUST omit `reasoning` from `pending` and `active` events, failed tool results,
> and successful results that lack the required fields. The relay MUST NOT ask the model to
> generate, infer, or complete this text. `event`, `step`, and `status` are unchanged. There is no
> confidence field.

With reasoning:

```json
{
  "event": "task_step",
  "step": "Checking delivery route",
  "status": "done",
  "reasoning": "This route saves about 7 min versus the alternative."
}
```

Without reasoning, including every `active` event:

```json
{
  "event": "task_step",
  "step": "Checking delivery route",
  "status": "active"
}
```

```json
{
  "event": "task_step",
  "step": "Updating delivery status",
  "status": "done"
}
```

This is additive, but `task_step` is part of the frozen WebSocket contract. Maria and Ez must both
sign off before `docs/contracts/interface.md` or either implementation changes.

## Backend source and placement

`app/api/websocket/voice.py` already has the right source of truth. `_run_tool` receives
`outcome["parsed_result"]`, mirrors tool-specific UI events, and then emits the `done` step. The
reasoning formatter should run there, immediately before that final event. The same path is used
for spoken tool calls and card-tap `accept_order` / `decline_order` calls.

Use a deterministic formatter keyed by tool name. It should read only the successful parsed result,
prefer structured fields over the free-text `message`, map enum values to plain labels, and return
`None` when a required field is absent or its rendered line would exceed 140 characters. Do not
read the model transcript, tool arguments, session context, another service, or the LLM's eventual
spoken reply to fill a gap. A failed tool still emits `status: "done"` under today's vocabulary, but
it must not carry `reasoning`.

## Result fields and templates, tool by tool

These recommendations follow the handlers in `app/agents/tools/`, the order dispatcher, the relay,
and `docs/VoiceOps_Agent_Tools_Reference.md`. Braces below are formatter substitutions, not text for
the model to complete.

| Tool | Returned fields that may be used | Deterministic template / rule |
|---|---|---|
| `get_next_delivery` | `has_next`, `sequence`, `time_window` | With both values: `Stop {sequence} is next, with a {time_window} delivery window.` With only `sequence`: `Stop {sequence} is next in your run.` With `has_next: false`: `There are no remaining deliveries in this shift.` Do not use the address or customer name just to make the line less sparse. |
| `update_delivery_status` | `status`, `previous_status` | **No reasoning.** This is a driver-requested state change, and the step label plus spoken result already confirms it. The returned fields do not explain a backend choice. |
| `log_exception` | `reason`, `resolution` | If both are present, map their enum tokens to plain labels: `Recorded {reason label}; next step is {resolution label}.` Do not use free-text `notes`. |
| `get_best_route` | `has_faster_route`, `time_saved_mins`, `best_route.duration_mins` | When `has_faster_route` is true and savings are positive: `This route saves about {time_saved_mins} min versus the alternative.` Otherwise, with a duration: `The fastest available route is about {duration_mins} min.` |
| `start_navigation` | `route.distance_km`, `route.duration_mins` | With both fields: `This route is {distance_km} km and about {duration_mins} min.` If `route` is null or either field is absent, send no reasoning. |
| `accept_reroute` | `route.duration_mins`; no comparison fields | **No reasoning today.** A duration alone does not explain why the reroute is better. Emit a Why line only after the result itself carries a real comparison such as time saved or traffic delay. |
| `call_customer` | `call_sid` | When present: `The call request was created for this stop.` Never include `customer_phone`, the customer name, or the provider-specific call id. |
| `notify_customer` | `status` | For an allowlisted successful status: `The customer update is {plain status label}.` Do not copy `customer_name`, `message_sent`, or a custom message into the card. |
| `get_next_order` | `has_next`, `offered_to_you`, `distance_km` | Offered: `This offer is {distance_km} km from your current position.` Unassigned: `The nearest waiting order is {distance_km} km away.` With `has_next: false`: `No new orders are waiting right now.` |
| `accept_order` | `sequence`, `time_window`; no distance field | Today: `The order was added as stop {sequence}.` Append ` Its window is {time_window}.` only if the combined line stays within the limit. Distance-based wording is not valid from the current result; see the data-gap note below. |
| `decline_order` | `passed_to.distance_km`, `passed_to` | With a next driver: `The next driver is {distance_km} km from the drop-off.` With `passed_to: null`: `No other driver is free, so the order returned to the queue.` Do not need another driver's name. |
| `get_shift_summary` | `delivered`, `total`, `remaining`, `failed` | `You have completed {delivered} of {total}; {remaining} remain.` Add ` {failed} failed.` when non-zero and within the limit. |
| `alert_dispatcher` | `priority`, `severity`; persistence errors are swallowed today | **No reasoning.** The current success result does not prove that Supabase or the background notification accepted the alert, so a stronger explanation would overclaim. |
| `show_screen` | `screen` | **No reasoning.** It is a direct, voice-confirmed UI action. The confirmation rule is below. |
| `end_conversation` | generic success only | **No reasoning.** It is intentionally silent and currently emits no task step. |

### Data gaps that must not be guessed around

- `get_best_route` currently returns OSRM alternatives and `time_saved_mins`; it does not return
  TomTom's `traffic_delay_minutes` or a provider. The traffic integration has those fields in the
  ETA/risk paths, but the reasoning formatter must not reach sideways into those services. If a
  separately reviewed additive tool-result change later returns `provider: "tomtom"` and
  `traffic_delay_minutes`, the template can become `Traffic adds about {delay} min; this route
  saves about {savings} min.` When those fields are missing, omit the traffic clause.
- The proactive order-offer payload and `get_next_order` result contain `distance_km`, but the
  successful `accept_order` result does not. The proactive `order_offer` is not a `task_step`, and
  its distance should not be smuggled into the task-step formatter from session state. If the
  accepted-order Why line must mention distance, add an optional `distance_km` to the
  `accept_order` result from the dispatcher's actual offer data and update the Agent Tools
  Reference in that reviewed change. Until then, use the returned `sequence` or send nothing.
- `get_next_delivery` has no prior-failure flag today. Do not claim a stop was selected because of
  prior attempts until the handler returns such evidence.

## Voice-confirmed screen changes

Today a successful `show_screen` result makes `_emit_tool_events` send `screen_navigate`
immediately, and Flutter's `VoiceSession._dispatch` immediately calls
`navigationProvider.navigateForAgent`. No confirmation exists between those two operations.

The confirmation belongs in Kora's tool-calling behavior, not in a new tap dialog. Add this wording
to the system prompt in `app/agents/agent_config.py`:

> Screen changes require voice confirmation unless the driver's current request explicitly asks to
> open, show, or go to that screen. If you are suggesting a screen change, ask one short question
> naming the destination, for example, "Open your summary?" Wait for the driver to say yes, then
> call `show_screen`. If the driver already asked to open that screen, call `show_screen` immediately
> and do not ask twice.

The `show_screen` tool description is actually defined in `app/agents/tool_registry.py`, not
`agent_config.py`. Give it the matching guard:

> Open a screen in the driver's app. Call immediately when the driver explicitly asked to open,
> show, or go to that screen. When Kora is suggesting the change, ask for voice confirmation and
> call this tool only after the driver agrees. Do not call it merely because the screen might be
> useful.

After an explicit request or spoken yes, the existing `show_screen` result and
`screen_navigate` event remain the complete path. Do not add a WebSocket event and do not add a tap
confirmation dialog.

## Tests Maria should add

1. Event-builder tests: `task_step(..., status="done", reasoning=...)` includes the field; active
   and pending frames omit it. Reject or omit an over-limit value according to the chosen builder
   API, and verify there is no confidence field.
2. Relay tests: a successful tool with all required result fields emits `active` without reasoning
   and `done` with the exact deterministic line. Assert ordering remains mood, active, tool-specific
   events, done.
3. Missing-data tests: successful results lacking a required field emit the unchanged `done` frame,
   and failed/timeout results never emit reasoning.
4. Provenance tests: route savings, delivery sequence/window, order distance, call id presence,
   and shift counts come from the stubbed parsed result. Include strings with PII or excessive
   length and verify the formatter omits them rather than falling back to `message` or model text.
5. Direct-order tests: card-tap accept/decline uses the same reasoning rules as voice-triggered
   accept/decline, while keeping the existing `order_offer_closed` behavior.
6. Compatibility tests: feed the new frame to the current Flutter decoder and confirm it still
   produces the same `TaskStepEvent(step, status)`. Also keep a backend fixture with the old frame
   shape so the updated app proves the Why line is optional.
7. Prompt tests: assert the session prompt contains the confirmation rule and the exposed
   `show_screen` description says to wait for spoken agreement when Kora suggested the change.

## Rollout and compatibility

1. Maria and Ez sign off the exact contract text, then update `docs/contracts/interface.md` in the
   coordinated implementation change.
2. The backend may ship first. The current Flutter decoder in
   `frontend/lib/core/realtime/voice_events.dart` reads only `step` and `status` for a known
   `task_step`; Dart map entries it does not read are ignored. The current provider therefore
   behaves unchanged when `reasoning` arrives.
3. Ez adds optional `reasoning` parsing, state, and the collapsed/expanded Why line. Against an old
   backend, the missing field remains null and the line stays hidden.
4. Enable deterministic templates incrementally. Missing data always degrades to the old event,
   never to guessed copy.

## Open questions for sign-off

- For a turn with several parallel tools that each produce reasoning, which single line should the
  card show: the most recently completed step, a fixed tool priority, or the reasoning for the step
  the driver expands? The wire contract can carry one line per done step, but the card design calls
  for one visible line.
- Is `accept_order.distance_km` approved as a separate additive tool-result change, or should the
  first release use only its existing `sequence` and `time_window` fields?
- Should `get_best_route` gain TomTom comparison fields in a separate tool-contract change, or should
  the first release describe only OSRM duration/savings?
- Are the proposed outcome lines for `log_exception` and `notify_customer` useful enough to count as
  Why, or should the initial allowlist be limited to route, next-stop, order, call, and shift-summary
  tools?
