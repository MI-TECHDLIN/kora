# Order accept fails on the second order: multi-worker dispatcher state

## Symptom
The driver accepts the first offered order (voice or tap) fine. The second order cannot be accepted, by voice or by tap. It only happens on the live deployment, not locally or in tests.

## Root cause (what the code proves, and what it doesn't)
Order-dispatch state lives in the memory of one process:

- `OrderDispatcher._orders` (every open order, who it is offered to, the expiry timers) and `_lock`, held by the module singleton `get_order_dispatcher()` in `app/dispatch/order_dispatch.py`.
- The voice-session registry `_sessions` (read through `live_shifts()`) in `app/api/websocket/voice.py`.

Production ran `uvicorn ... --workers 2`, so two separate processes each had their own copy of all of that. Each worker also ran its own startup (`dispatcher.start()`): its own random order feed and its own reload of open orders from the database. Consequences:

- An offer only exists in the worker that made it, and only that worker can accept, decline or expire it. `accept()` in any other worker finds nothing (`_find` returns None) and answers "No order is waiting for you right now."
- A worker only offers to drivers whose socket is open in that same worker. If the app reconnects its socket (a normal mobile event) and lands on the other worker, that worker knows nothing about the offer the first one is still holding. The tap path also guards on the socket's own `offers`, so a stale card gives "That order offer is no longer available."
- Both workers reload the same unassigned orders at boot and both feeds create orders, so the two copies can diverge.

Why the first order works: right after boot the driver's socket, the order and the offer are all in one worker, and nothing has moved. By the second order, sockets have reconnected, timers and feeds in the other worker have produced or parked their own orders, and the offer and the session are more likely to be in different workers.

Confidence: the per-process split is certain (see the test below). That it is what breaks the second accept in production is the best fit for "live only, both voice and tap", but I could not run the live backend, so the exact first-works/second-fails sequence is not proven. The log check below settles it.

## The fix
- `voiceops-backend/Procfile` now runs `--workers 1`. This is the only launch config in the repo (no railway.toml, nixpacks, Dockerfile or render.yaml). The module docstring in `order_dispatch.py` already said "one uvicorn worker"; the Procfile contradicted it.
- Accept and decline failures now log a reason code, order id, shift id and the worker `pid`. No phone numbers, tokens or audio. `decline` takes `shift_id` so its log can name the shift. WebSocket contracts are unchanged.
- Tests: `test_offer_state_is_per_dispatcher_so_a_second_worker_cannot_accept_it` (two dispatchers stand in for two workers: accept on the one that holds the offer succeeds, on the other fails), the Procfile guard, and the log-line tests.

## Owner checks (things not visible from the repo)
- Railway may override the start command, or set `WEB_CONCURRENCY`, in the service settings. Confirm the running command has one worker and that no `WEB_CONCURRENCY`/replica count above 1 is set. More than one replica has the same problem as two workers.
- Redeploy and confirm.

## What to grep in the live logs
- `[Dispatch] accept_failed` and `[Tool:accept_order] accept_failed`: fields `order_id=`, `shift_id=`, `reason=` (`no_matching_order`, `offered_to_other_driver`, `already_assigned`, `database_error`, `missing_active_shift`, `dispatcher_rejected`, `unexpected_exception`) and `pid=`.
- `[Dispatch] decline_failed` (`reason=no_matching_offer`).
- `[Dispatch] started pid=` and `[Dispatch] Reloaded N open orders pid=`: two different pids means two workers are still running.
- Before the fix, a `no_matching_order` for an order that an earlier `[Dispatch] ... offered to driver` line shows with a different `pid` is the proof of the cross-worker split. After it, that should not appear.

## Longer-term fix: shared dispatcher state
One worker is a single point of failure and a scaling cap; a restart drops in-flight offers (open orders are reloaded as unassigned, offers are lost). To run several workers or replicas, the offer state and session routing must be shared:

- **Redis (or Postgres) for offer state plus pub/sub for delivery to sockets.** Offers and locks in Redis (or a `FOR UPDATE` row lock on `deliveries`), and a channel so the worker that owns the driver's socket presents the offer. Cost: a Redis instance (a few dollars a month on Railway), and a rewrite of `_orders`, `_lock`, timers and the hub. Most robust; several days of work.
- **Sticky routing per driver.** Route each driver's requests to one worker. Cheap, but the mock feed, expiry and dispatch are still per worker and a worker restart still loses offers. Not supported on a plain Railway uvicorn setup.
- **Database as the source of truth.** Store the offer (holder, expiry) on the order row and make accept a conditional update. Removes the Redis dependency but still needs cross-worker push to sockets (Postgres LISTEN/NOTIFY or Supabase Realtime).

For the hackathon demo, one worker is enough: async I/O handles many drivers in one process.
