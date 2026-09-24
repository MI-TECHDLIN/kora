# Post-hackathon roadmap: ideas borrowed from Fleetbase

**Status:** backlog for after the hackathon. The current build (voice co-rider, order queue and target, auto-accept, walking mode, wake word, map, sign-out and the rest) is enough for the hackathon, and none of the ideas below are planned for it. They are recorded here so they are not lost.

Decision: borrow ideas only. Kora does not depend on, embed or run Fleetbase. Its main repositories are AGPL-3.0, so nothing here copies its code, UI or schemas. Each idea below is a general logistics-product pattern that Kora would design and build itself. Evidence for what Fleetbase does is in `docs/research/fleetbase-review.md`; what Kora already has comes from the review verification and the code on `staging`.

Kora's strength stays the same: a voice-first co-rider for the driver. The ideas are chosen either to close a real gap or to make the voice experience more valuable, not to turn Kora into a copy of a dispatch platform.

## The gaps this fills

| Kora today | What is missing |
|---|---|
| One user type: the driver | No dispatcher or operator role, no fleet view, and the fleet routes leak driver phones and locations to any signed-in driver (review finding H3) |
| Kora receives orders and offers them to the nearest driver | Nobody can see or steer the fleet, and nothing can be handed to another system |
| Kora has ETAs, calls and texts to the customer | The customer has no tracking link and no proof of who handed over what |
| Kora has a delivery audit trail | The driver and customer cannot see a readable timeline |

## Ideas, ranked by value to Kora

### 1. Roles and a minimal dispatcher console (biggest gap)
- **What Fleetbase does:** company-scoped accounts with bundled roles such as Dispatch Manager, Fleet Manager, Order Coordinator and Driver Operations.
- **What Kora adds:** an operator role next to the driver role, then a small web console with a live fleet map, an order board, driver online status, and manual assign or reassign. Voice stays the driver's interface; the console is for the person supervising many drivers.
- **Why it matters:** it closes the fleet-route leak, gives a real place to see incidents and shift reports, and makes Kora sellable to fleets, which was the business case in the pitch.
- **Needs first:** Maria's role design (review item B2): how dispatchers are identified and what each role may see.
- **Rough effort:** roles and route protection 1 to 2 weeks; a minimal console 3 to 5 weeks.

### 2. Company scoping from the start
- **What Fleetbase does:** every record belongs to a company, and it relies on each query remembering to filter (its own code notes there is no global safety net, which is a warning as well as a pattern).
- **What Kora adds:** a company id on drivers, shifts, deliveries and preferences, enforced in the database with row-level security as well as in the route code. Kora already has a 6-digit connect code that links a driver to a logistics company, so the seed exists.
- **Why it matters:** the ownership checks added in PR #102 protect one driver from another. Company scoping protects one fleet from another, which any multi-customer product needs before the console exists.
- **Needs first:** Maria's database security review (B3).
- **Rough effort:** 2 to 3 weeks including migration and tests.

### 3. Customer tracking link
- **What Fleetbase does:** a public tracking page with status and ETA for a customer's order.
- **What Kora adds:** when a delivery is en route, Kora (by voice or automatically) texts the customer a short-lived link showing status, ETA, the driver's first name and a map dot. Kora already has ETAs, per-mode ETAs, customer SMS and a browser customer-call demo page, so most parts exist.
- **Why it matters:** fewer "where are you" calls, which are the calls drivers dislike most. It also gives Kora a second audience for demos.
- **Design rules:** unguessable expiring token, no phone numbers or exact history exposed, link dies after delivery.
- **Rough effort:** 1 to 2 weeks.

### 4. Signed outbound webhooks and an event catalog
- **What Fleetbase does:** it emits events (order created, dispatched, completed, failed and so on) in one signed envelope with retries.
- **What Kora adds:** a small set of outbound events (order accepted, en route, arrived, delivered, failed, shift ended) delivered as signed JSON with an id, event name, timestamp and data, plus retry and a delivery log. Kora only receives orders and triggers n8n after a shift today.
- **Why it matters:** anyone can integrate Kora (a fleet's own system, Slack, a customer's ERP) without Kora building each connector. It is also the cleanest way to feed a dispatcher console.
- **Lesson to copy on purpose:** Fleetbase's published webhook page and its code disagree on the header and the signature format. Kora should document its contract once, test against it, and keep TLS verification on by default.
- **Rough effort:** 1 to 2 weeks.

### 5. Proof of delivery with a handoff code
- **What Fleetbase does:** photo, signature and QR-based proof.
- **What Kora adds:** Kora already takes photo and signature. Add a short handoff code the customer receives with the tracking link and reads out or shows; the driver says it to Kora ("code four eight two one") and Kora confirms. It fits the voice-first idea and reduces "I never got it" disputes.
- **Rough effort:** about 1 week on top of idea 3.

### 6. Places and service areas
- **What Fleetbase does:** saved places and service areas that shape dispatch.
- **What Kora adds:** named places (depots, recurring customers, tricky entrances, parking spots) and dispatcher-drawn service areas. Maria's driver preferences already support preferred and avoided zones per driver, and `docs/backend-handoff/traffic-parking-intelligence.md` proposes parking help; shared named places would give both a common base and let Kora say "the loading dock is round the back".
- **Rough effort:** 2 to 3 weeks.

### 7. A real vehicle record
- **What Fleetbase does:** vehicles as their own records, assigned to drivers, with tracking.
- **What Kora adds:** replace the free-text `vehicle_type` with a vehicle entity (type, plate, capacity, currently assigned driver). Orders already carry a requested vehicle, so capacity-aware offers become possible, and the per-mode ETAs from the walking-mode work attach naturally.
- **Rough effort:** 1 to 2 weeks.

### 8. Multi-stop sequencing
- **What Fleetbase does:** route optimisation across stops.
- **What Kora adds:** sensible ordering of a driver's stops. The routing engine Kora already uses appears to offer a trip-planning service for this, which should be verified before relying on it. Voice angle: "Kora, reorder my stops to save time," with Kora explaining the saving.
- **Rough effort:** 1 to 2 weeks after verifying the engine option.

### 9. Driver availability and breaks
- **What Fleetbase does:** an online or offline toggle that dispatchers see.
- **What Kora adds:** "going on break" and "I'm back" by voice, visible on the console, with the break time excluded from delivery-time calculations. Maria's preferences already include break times.
- **Rough effort:** under 1 week.

### 10. A readable order timeline
- **What Fleetbase does:** configurable workflow activities on each order.
- **What Kora adds:** Kora already writes an audit event for every status change and has internal en-route and arrived states. Show them as a plain timeline for the driver, the dispatcher and the tracking page, without changing the frozen external status list.
- **Rough effort:** about 1 week.

### 11. Scoped API keys for integrators
- **What Fleetbase does:** test and live keys with expiry and rotation.
- **What Kora adds:** the same, once idea 4 exists, so third parties can send orders and receive events safely.
- **Rough effort:** 1 week.

## Reliability habits worth copying

- **Webhook first, reconcile after.** Events can be lost or duplicated. Any sync should have a periodic check that closes gaps, and failures should be visible to an operator.
- **Pin versions and test contracts.** Fleetbase releases every few days, and its own webhook docs drifted from its code. Kora should keep its contract tests and avoid unpinned dependencies.
- **Location privacy up front.** Consent wording, a visible on-shift indicator, an off-shift hard stop and a retention period, before any dispatcher can see live positions.

## What not to copy

- The heavy stack (a second database, queues and a real-time server); Kora's FastAPI and Supabase setup stays.
- Public real-time channels that anyone who knows the address can listen to.
- Its driver app. Kora's voice co-rider is the differentiator.
- Any Fleetbase code, UI or schema (AGPL).

## Suggested order

1. **Foundations (needs Maria):** role design and company scoping (ideas 1 backend and 2). Without these, the console and any integrations are unsafe.
2. **Quick wins that stand alone:** customer tracking link (3), handoff code (5), order timeline (10), breaks by voice (9). These improve the driver and customer experience without needing the console.
3. **Integration layer:** signed outbound webhooks (4), then scoped keys (11).
4. **Console and richer data:** the dispatcher console (1 frontend), places (6), vehicle records (7), stop sequencing (8).

A good first batch of two when work resumes: the tracking link with handoff code, and the outbound webhooks with the order timeline. Both are self-contained, use parts Kora already has, and do not wait on the backend role design (`docs/backend-handoff/review-fixes-for-maria.md`, item 2).
