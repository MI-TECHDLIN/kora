# Fleetbase for Kora: evidence-based review

**Review date:** 24 September 2026  
**Scope:** Fleetbase's GitHub organisation, current documentation, API surface, releases and issues, compared with Kora on `origin/staging` at `54582665d1d2da10bf268c9ddf55504a384eb558`.  
**Recommendation in one sentence:** Fleetbase is worth a small, isolated integration spike as Kora's operator/dispatcher control plane, but it is not yet safe to adopt as a production dependency without resolving its webhook contract drift, dispatch ownership, status mapping, AGPL boundary, and substantially larger operational footprint.

## Executive view

Fleetbase is a real and actively developed open-source logistics platform, not just a demo repository. Its strongest fit for Kora is the part Kora does not have: an operator console, company/role model, fleet records, order dispatch, customer tracking, route planning, and proof-of-delivery administration. Kora should remain the driver's voice-first client and continue to own the AssemblyAI voice session, preferences, shifts, post-shift intelligence, and in-app navigation experience.

It is also not a drop-in Onfleet replacement. Fleetbase is a pre-1.0, multi-service platform whose main components are AGPL-licensed. Its REST API is usable, but the audited webhook implementation differs materially from the current public webhook page. Its default order workflow does not cleanly represent Kora's `offered`, `unassigned`, `failed`, or `rescheduled` semantics. Its dispatcher and Navigator driver app overlap with systems Kora already owns. Running it means adding MySQL, Redis, SocketCluster, queue and scheduler workers, a PHP API, and an Ember console beside Kora's current Render/FastAPI and Supabase stack.

The sensible path is therefore: test the boundary, do not merge the products. Put Fleetbase behind a small Python adapter/normalisation service, never in Kora's real-time voice WebSocket path, and choose exactly one assignment authority.

## 1. What Fleetbase is, honestly

Fleetbase describes itself as a modular logistics operating system. The current monorepo lists these principal products:

| Component | Practical role | What the evidence says about readiness |
|---|---|---|
| Fleetbase core | API, identity/company context, developer console, extensions and infrastructure | The central platform; actively released, but still version `0.7.x`. |
| FleetOps | Orders, dispatch, drivers, vehicles, places, fleets, routes/manifests, tracking and POD | The most directly relevant module for Kora and the substantive operational product. |
| Navigator | Fleetbase's React Native driver app | Real dispatch, background location and POD client; overlaps with Kora's Flutter driver app. |
| Storefront / Storefront App | Commerce, products, orders and consumer mobile experience | Adjacent to Kora, not needed for the proposed integration. |
| Pallet | Warehouse management | A repository exists, but Fleetbase's own roadmap still calls the WMS “In development” with a Q4 2026 target. It should not be treated as complete. |
| Ledger | Invoicing, wallets and accounting | Optional adjacent module, not required by Kora. |
| Customer Portal | Customer-facing order and tracking portal | Potential value if Kora wants customer self-service. |
| IAM, AI, Developer Console | Access control, AI extension, developer/configuration tooling | Platform extensions with varying maturity; not prerequisites for the first Kora spike. |

The module list is in the [Fleetbase README](https://github.com/fleetbase/fleetbase/blob/4ff6980c6db6f3e8103b3ec425a089aa6d251af4/README.md#L72-L89), while the same README's [roadmap](https://github.com/fleetbase/fleetbase/blob/4ff6980c6db6f3e8103b3ec425a089aa6d251af4/README.md#L179-L184) is the evidence that Pallet is not finished despite having its own repository. That discrepancy is a useful warning: repository existence is not equivalent to product maturity.

### Open source versus paid

The platform and the named public modules/mobile apps are available as source. Fleetbase uses a dual-license model: AGPL-3.0 for the open-source edition and a paid Fleetbase Commercial License for proprietary modifications, SaaS/white-label distribution, support, and indemnification ([main licensing statement](https://github.com/fleetbase/fleetbase/blob/4ff6980c6db6f3e8103b3ec425a089aa6d251af4/README.md#L246-L254)). Fleetbase Cloud, implementation help, support plans, and the commercial licence are paid offerings.

Current public prices observed on 24 September 2026 were:

- Fleetbase Cloud: **$29/month**, plus **$5 per additional driver, vehicle, or storefront**; the first 100,000 API calls and webhook sends are included, then $0.25 per additional 100,000 ([pricing page](https://fleetbase.io/pricing)).
- Optional self-hosted implementation assistance: **$2,500**; published support tiers were **$1,000, $3,500, and $5,000/month** ([pricing page](https://fleetbase.io/pricing)).
- Commercial licensing: **$25,000/year**, **$2,500/month**, **$25,000 for a major-version perpetual licence**, or **$15,000 for a minor-version perpetual licence** ([commercial licence page](https://fleetbase.io/licensing/commercial)).

These are public list prices, not a quote; terms, tax, region, SLA, and data residency still need confirmation from Fleetbase.

### Technology and deployment shape

The core API is PHP 8 / Laravel 10 ([composer manifest](https://github.com/fleetbase/fleetbase/blob/4ff6980c6db6f3e8103b3ec425a089aa6d251af4/api/composer.json#L19-L34)); the operator console is Ember 5.4 on Node 22+ ([console manifest](https://github.com/fleetbase/fleetbase/blob/4ff6980c6db6f3e8103b3ec425a089aa6d251af4/console/package.json#L121-L155)); Navigator is React Native with Tamagui ([Navigator manifest](https://github.com/fleetbase/navigator-app/blob/37af1ee7dfdcc53052058edd853c66400d3e7e32/package.json#L1-L28)). The standard Compose file adds MySQL 8, Redis, SocketCluster, a queue worker, scheduler, API and web server ([Compose file](https://github.com/fleetbase/fleetbase/blob/4ff6980c6db6f3e8103b3ec425a089aa6d251af4/docker-compose.yml#L1-L127)). Production documentation describes Laravel Octane/Caddy rather than a single conventional PHP process ([architecture docs](https://fleetbase.io/docs/platform/architecture)).

This is separate infrastructure, not an extension that can be installed into Kora's FastAPI process or Supabase PostgreSQL database.

### Maturity and maintenance

Snapshot taken with GitHub's API through `gh-axi` on 24 September 2026:

| Repository | Stars / forks | Open issues* | Contributors* | Latest release | Commits in last 30 / 90 / 365 days* |
|---|---:|---:|---:|---|---:|
| `fleetbase/fleetbase` | 3,890 / 1,036 | 14 | 21 | `v0.7.64`, 23 Sep 2026 | 109 / 303 / 555 |
| `fleetbase/fleetops` | 34 / 66 | 9 | 15 | `v0.6.69`, 22 Sep 2026 | 232 / 1,085 / 1,821 |
| `fleetbase/core-api` | 18 / 39 | 4 | 8 | `v1.6.63`, 22 Sep 2026 | 68 / 513 / 837 |
| `fleetbase/navigator-app` | 107 / 147 | 2 | 4 | `v2.0.11`, 31 Aug 2026 | 10 / 24 / 24 |
| `fleetbase/fleetbase-js` | 12 / 8 | 7 | 4 | `v2.0.0`, 10 Sep 2026 | 30 / 30 / 30 |

\*Issue count excludes pull requests. Contributor count is the GitHub contributor endpoint's returned set, so it is a useful snapshot rather than an employment/team count. Commit counts were calculated from each cloned default branch by commit date.

The main platform, FleetOps, and core API each have more than 100 tagged releases. Eight main-platform releases landed between 6 and 23 September 2026, and eight FleetOps releases between 6 and 22 September. This is active maintenance, but also a high rate of change. Navigator had only 24 commits in the past year, with its recent releases following a long quieter period. Development is concentrated in a relatively small contributor group.

The honest maturity assessment is **active, useful, but still pre-1.0 and uneven across modules**. Current issues show practical rough edges: [PostgreSQL/PostGIS support is requested because the platform is coupled to MySQL](https://github.com/fleetbase/fleetbase/issues/548); FleetOps has reports of [a 500 error when Google Maps is not configured](https://github.com/fleetbase/fleetops/issues/337) and [spatial writes failing](https://github.com/fleetbase/fleetops/issues/334); Navigator has a reported [blank Android map](https://github.com/fleetbase/navigator-app/issues/106). These do not make the platform unusable, but they argue for a pilot and pinned versions rather than immediate production adoption.

### Licences and what they mean for Kora

Repositories relied on in this review:

| Repository(s) | Licence found in repository | Consequence for Kora |
|---|---|---|
| [`fleetbase`](https://github.com/fleetbase/fleetbase/blob/4ff6980c6db6f3e8103b3ec425a089aa6d251af4/LICENSE.md), [`core-api`](https://github.com/fleetbase/core-api/blob/3e1e14a5a1fb84629caf2bbdf0fdb44f7dcb2e9d/LICENSE.md), [`fleetops`](https://github.com/fleetbase/fleetops/blob/a80f78d791d79df7af0825959610f9ff75e00875/LICENSE.md), [`navigator-app`](https://github.com/fleetbase/navigator-app/blob/37af1ee7dfdcc53052058edd853c66400d3e7e32/LICENSE.md), [`fleetbase-js`](https://github.com/fleetbase/fleetbase-js/blob/b76e577cae6b735e600285dc1e46edc925244ff8/LICENSE.md) | GNU AGPL v3; several manifests say `AGPL-3.0-or-later` | Kora may inspect, run and self-host them. If Kora modifies an AGPL component and lets users interact with that modified version over a network, AGPL section 13 requires offering the corresponding source under AGPL. Combining AGPL code into Kora could also put the combined work under copyleft obligations. |
| [`pallet`](https://github.com/fleetbase/pallet/blob/adea3d9886ce3736ab1ddcf0f08de6381a1c1679/LICENSE.md), [`customer-portal`](https://github.com/fleetbase/customer-portal/blob/dca220ff893f2152effbd56253429cca97614adf/LICENSE.md), [`vroom`](https://github.com/fleetbase/vroom/blob/ab8029000c9489581c1b6b2d75019b64fe80174e/LICENSE.md), [`valhalla`](https://github.com/fleetbase/valhalla/blob/13aa5eed207ed6ead952aaacdcafd31e6ef03d8f/LICENSE.md), [`ledger`](https://github.com/fleetbase/ledger/blob/d2e5de66bb327d64f561204c1c2bca2adc4a6eda/LICENSE.md) | GNU AGPL v3 | Same AGPL implications. Some README licence labels disagree with these actual licence files, so the file was treated as authoritative. |
| [`docs`](https://github.com/fleetbase/docs/blob/08e9a465ddd5070cd19ff783e187cf0eba025c2b/LICENSE) | MIT | Its code/text may be reused subject to retaining the MIT copyright and permission notice. Normal citation/linking requires no incorporation. |
| [`postman`](https://github.com/fleetbase/postman/tree/822b867218f174bad18a789d4fd6791ccfd2af34) | No `LICENSE` file found | Default copyright applies; use it as documentation/evidence, but do not copy or redistribute its collection without permission. |

The applicable source is the licence file, not a README badge or paragraph. In particular, the Pallet and VROOM READMEs say MIT, but their checked-in licence files contain AGPL-3.0; compare [Pallet README](https://github.com/fleetbase/pallet/blob/adea3d9886ce3736ab1ddcf0f08de6381a1c1679/README.md#L119-L125) with [Pallet licence](https://github.com/fleetbase/pallet/blob/adea3d9886ce3736ab1ddcf0f08de6381a1c1679/LICENSE.md#L530-L539), and [VROOM README](https://github.com/fleetbase/vroom/blob/ab8029000c9489581c1b6b2d75019b64fe80174e/README.md#L118-L124) with [VROOM licence](https://github.com/fleetbase/vroom/blob/ab8029000c9489581c1b6b2d75019b64fe80174e/LICENSE.md#L530-L539).

The main AGPL's [network-use clause](https://github.com/fleetbase/fleetbase/blob/4ff6980c6db6f3e8103b3ec425a089aa6d251af4/LICENSE.md#L530-L539) is the important difference from permissive licences. The lowest-risk architecture is to keep Fleetbase unmodified as a separate service and have Kora call its HTTP API with its own small Python client. Merely linking to Fleetbase's website or interoperating over REST does not copy its code. Kora should **not** embed the AGPL JavaScript/PHP SDK or Fleetbase UI code into a proprietary client without a legal review. White-labelling, distributing a modified build, or keeping Fleetbase modifications private should trigger review of the commercial licence. This is an engineering interpretation, not legal advice.

## 2. Integration surface

### REST API

FleetOps exposes the primitives Kora needs. The current server route table—not just the prose API page—defines:

- drivers: list/create/read/update/delete, track location, toggle online status, and retrieve manifests ([routes](https://github.com/fleetbase/fleetops/blob/a80f78d791d79df7af0825959610f9ff75e00875/server/src/routes.php#L36-L64));
- orders: CRUD, scheduling, dispatch, start, cancel, activity/status update, completion, public tracker, ETA, signature/QR/photo POD and proof records ([routes](https://github.com/fleetbase/fleetops/blob/a80f78d791d79df7af0825959610f9ff75e00875/server/src/routes.php#L186-L220));
- places ([routes](https://github.com/fleetbase/fleetops/blob/a80f78d791d79df7af0825959610f9ff75e00875/server/src/routes.php#L259-L267)); and
- vehicles, including tracking ([routes](https://github.com/fleetbase/fleetops/blob/a80f78d791d79df7af0825959610f9ff75e00875/server/src/routes.php#L320-L330)).

The official reference has resource examples for [orders](https://fleetbase.io/docs/api/fleetbase/orders), [drivers](https://fleetbase.io/docs/api/fleetbase/drivers), [vehicles](https://fleetbase.io/docs/api/fleetbase/vehicles), and [places](https://fleetbase.io/docs/api/fleetbase/places). An order can include pickup, drop-off, waypoints, scheduled time, customer, driver, dispatch flag and notes; the [official Postman example](https://github.com/fleetbase/postman/blob/822b867218f174bad18a789d4fd6791ccfd2af34/FleetOps/Orders/Create%20Order.bru#L1-L31) shows the current request shape.

### Authentication, limits and SDKs

External API calls use `Authorization: Bearer <public-key>`. Developer Console creates test/live keys with expiration and rotation ([API-key documentation](https://fleetbase.io/docs/platform/developer-console/api-keys)). The code confirms Bearer authentication; notably, an API secret is accepted as a credential only for the Fleetbase Node SDK's exact user-agent ([authentication middleware](https://github.com/fleetbase/core-api/blob/3e1e14a5a1fb84629caf2bbdf0fdb44f7dcb2e9d/src/Http/Middleware/AuthenticateOnceWithBasicAuth.php#L43-L70)). Kora should hold a live public API key on its backend only—never in the Flutter app—and should not send the secret.

The default server throttle is **120 requests per minute**, configurable through `THROTTLE_REQUESTS_PER_MINUTE` ([configuration](https://github.com/fleetbase/core-api/blob/3e1e14a5a1fb84629caf2bbdf0fdb44f7dcb2e9d/config/api.php#L4-L25)). Capacity must be tested with location updates and webhook reconciliation; it should not be assumed that the public cloud uses unchanged defaults.

Official SDKs are [JavaScript/TypeScript and PHP](https://fleetbase.io/developers/sdks). The current JS SDK is v2.0.0, needs Node 20.19.4+, and is itself AGPL. There is no official Python SDK. For Kora, a narrow `httpx`/async Python client is both technically simpler and a cleaner licence boundary.

### Webhooks: useful, but the public description and code disagree

FleetOps declares events for orders (`created`, `ready`, `updated`, `deleted`, `dispatched`, `dispatch_failed`, `failed`, `driver_assigned`, `completed`, `canceled`), plus driver creation/update/deletion/assignment/location changes and vehicle, place, tracking, fleet, vendor and service-area events ([event configuration](https://github.com/fleetbase/fleetops/blob/a80f78d791d79df7af0825959610f9ff75e00875/server/config/api.php#L10-L109)). The emitted envelope is `{id, api_version, event, created_at, data}` ([event resource](https://github.com/fleetbase/core-api/blob/3e1e14a5a1fb84629caf2bbdf0fdb44f7dcb2e9d/src/Events/ResourceLifecycleEvent.php#L334-L368)); an order's webhook data includes its public ID, customer, payload, driver, status and timestamps ([order resource](https://github.com/fleetbase/fleetops/blob/a80f78d791d79df7af0825959610f9ff75e00875/server/src/Http/Resources/v1/Order.php#L194-L215)).

However, this is the largest integration warning found in the review:

| Subject | Current public webhook page | Audited code at pinned commits |
|---|---|---|
| Signature header | `X-Fleetbase-Signature` | Default is `Signature` ([config](https://github.com/fleetbase/core-api/blob/3e1e14a5a1fb84629caf2bbdf0fdb44f7dcb2e9d/config/webhook-server.php#L19-L25)). |
| Signature format | `sha256=<digest>` using a per-webhook secret | Signer returns raw hexadecimal HMAC-SHA256 of JSON; no `sha256=` prefix ([signer](https://github.com/fleetbase/core-api/blob/3e1e14a5a1fb84629caf2bbdf0fdb44f7dcb2e9d/src/Support/Signature.php#L7-L16)). The listener appears to use the event API credential's secret. |
| Retries | Four retries | Default `max_tries` is three ([config](https://github.com/fleetbase/core-api/blob/3e1e14a5a1fb84629caf2bbdf0fdb44f7dcb2e9d/config/webhook-server.php#L27-L42)). |
| TLS verification | Not stated as disabled | The checked-in default is `verify_ssl => false` ([config](https://github.com/fleetbase/core-api/blob/3e1e14a5a1fb84629caf2bbdf0fdb44f7dcb2e9d/config/webhook-server.php#L51-L59)). |

The conflicting published contract is [Fleetbase's webhook page](https://fleetbase.io/developers/webhooks). A live, release-pinned contract test is mandatory. Production self-hosting should enable TLS verification.

Fleetbase cannot therefore post directly to Kora's current intake endpoint. Kora requires `X-VoiceOps-Signature: sha256=<hex HMAC-SHA256 of the raw body>` and an `IncomingOrder` body, with idempotency on `(source, external_id)` (`docs/contracts/interface.md:313-343`; `voiceops-backend/app/api/routes/logistics.py:31-63`). A dedicated receiver must verify the Fleetbase signature actually emitted by the selected release, validate and normalise the body, then invoke Kora's ingestion service or re-sign a new request according to Kora's frozen contract.

### Real-time channels

Fleetbase uses SocketCluster for operator/mobile real-time updates. The official [socket-event documentation](https://fleetbase.io/docs/platform/developer-console/socket-events) warns that without origin restrictions, anyone who knows the socket address can connect and receive events. The route code creates company/model/API/relationship channels as public Laravel channels, not authenticated private channels ([channel routes](https://github.com/fleetbase/core-api/blob/3e1e14a5a1fb84629caf2bbdf0fdb44f7dcb2e9d/routes/channels.php)). Kora should use authenticated server-side webhooks plus reconciliation for its system boundary, not connect the public Flutter app directly to these channels.

This channel is unrelated to Kora's AssemblyAI voice-agent WebSocket. Fleetbase must stay out of the real-time voice path; tools can call the adapter in the FastAPI orchestration layer as they do today.

### Lifecycle mapping

Fleetbase's default order flow is `created → dispatched → started → enroute → completed`, and administrators can configure workflow activities ([default workflow](https://github.com/fleetbase/fleetops/blob/a80f78d791d79df7af0825959610f9ff75e00875/server/src/FleetOps.php#L35-L140)). Kora's frozen external delivery status is `pending | delivered | failed | rescheduled`; new-order dispatch separately uses `offered | unassigned` (`docs/contracts/interface.md:404-436`). The mapping is necessarily lossy:

| Kora state | Closest Fleetbase representation | Gap / rule needed |
|---|---|---|
| `unassigned` | `created`, no driver, not dispatched | Fleetbase has no equivalent standard lifecycle status; query fields express assignment/dispatch separately. |
| `offered` | Ad-hoc order with `adhoc=true`, `dispatched=true`, no driver | Not equivalent. Navigator discovers nearby ad-hoc orders; it does not model Kora's one-driver-at-a-time timed offer. |
| `pending` | Assigned/dispatched/started/enroute | Kora collapses several meaningful Fleetbase stages into one external value. Store the Fleetbase activity separately. |
| `delivered` | `completed` | Clean mapping if completion/POD succeeds in Fleetbase first. |
| `failed` | A configured `failed` activity/event | `failed` is declared as an event but is not part of the default workflow. Configure it explicitly; do not map `canceled` to failed. |
| `rescheduled` | Updated `scheduled_at` through the schedule route | Scheduling is an operation/field, not a default terminal status. Kora must keep its mirror status or Fleetbase must add a custom activity. |

Navigator confirms the different offer model: it queries orders as `nearby + adhoc + unassigned + dispatched` ([order manager](https://github.com/fleetbase/navigator-app/blob/37af1ee7dfdcc53052058edd853c66400d3e7e32/src/services/OrderManager.tsx#L147-L168)); accepting starts/assigns the order, while dismissing is local state only ([ad-hoc card](https://github.com/fleetbase/navigator-app/blob/37af1ee7dfdcc53052058edd853c66400d3e7e32/src/components/orders/AdhocOrderCard.tsx#L46-L87)). Kora instead selects nearest online drivers and offers sequentially (`voiceops-backend/app/dispatch/order_dispatch.py:291-317,382-403,605-720`).

Kora also has an internal state machine with `en_route` and `arrived` (`voiceops-backend/app/services/delivery_state_machine.py:10-17`) even though the external frozen enum has four states. The spike must decide whether these remain internal progress states or are mirrored to Fleetbase activities; it must not silently expand the frozen API enum.

## 3. Fit against Kora's `LogisticsAdapter`

Kora was designed for this kind of integration, but the current abstraction covers dispatch feed/assignment—not the whole delivery lifecycle. `LogisticsAdapter` currently requires only:

- `start_order_feed(callback)`;
- `stop_order_feed()`;
- `order_assigned(external_id, driver_id)`; and
- `order_unassigned(external_id, reason)`.

Its `IncomingOrder` contains external/source IDs, pickup/drop-off, package/customer data, schedule/priority, metadata and requested vehicle (`voiceops-backend/app/integrations/logistics/base.py:43-140`). Only `MockAdapter` exists; no Onfleet adapter was found in `voiceops-backend/app/integrations/logistics/`.

A production `FleetbaseAdapter` would need:

1. An asynchronous, server-side REST client with strict timeouts, bounded retries, idempotency keys where supported, secret-safe logging, and Fleetbase-to-Kora ID mappings.
2. A signed webhook receiver and normaliser for order created/updated/assigned/canceled/completed events. It should call the same ingestion path as `POST /v1/logistics/orders`, not duplicate dispatch logic.
3. Feed handling: webhook-first, with polling/reconciliation after gaps or restarts. Webhook retries can be exhausted, duplicated, or arrive out of order.
4. `order_assigned`: translate the chosen authority's action to Fleetbase driver assignment/dispatch/start operations and retain the response/version.
5. `order_unassigned`: clear or decline assignment according to an explicit policy and store the Kora reason without turning it into `failed`.
6. Driver, vehicle and place synchronisation plus durable cross-system IDs.
7. Lifecycle/POD write-back. The existing base interface has no completion, failure, reschedule, cancellation, location or POD methods. A full integration either extends the adapter and updates `MockAdapter` in the same change, as Kora's rules require, or introduces a separate lifecycle synchronisation service with clearly documented ownership.
8. A dead-letter/reconciliation job and operator-visible sync errors; webhook delivery alone is not a transaction across two databases.

### Recommended ownership and source of truth

| Entity/capability | Recommended owner | What is synchronised |
|---|---|---|
| Order, customer, pickup/drop-off/place | **Fleetbase** | Mirror only the fields needed for Kora voice/shift operation into Supabase, keyed by `source=fleetbase` and Fleetbase's public order ID as `external_id`. Carry a Kora correlation ID in Fleetbase metadata/internal ID. |
| Assignment and dispatch | **Fleetbase, if adopting the strategic option** | Kora receives the assigned order and presents/acts on it. Disable Kora's nearest-driver offer algorithm for this source. If Kora remains assignment owner, Fleetbase is only an order source—not the dispatcher. Never run both algorithms on the same order. |
| Operational driver, vehicle, fleet | **Fleetbase** | Map Fleetbase IDs to Kora's Supabase driver identity. Keep Kora authentication/profile linkage; do not duplicate mutable vehicle/fleet truth in both systems. |
| Voice session, co-rider, preferences, auto-accept, daily target, driver queue presentation | **Kora** | No Fleetbase ownership. Kora's preferences include auto-accept/decline, distance, navigation, calls/SMS and target (`voiceops-backend/app/services/preference_service.py:23-43`). |
| Shift and post-shift intelligence | **Kora** | Kora keeps shift state, turns, report, n8n post-shift trigger and AssemblyAI analysis. A Fleetbase manifest may be linked, but is not the voice shift. |
| Delivery lifecycle and POD | **Fleetbase operational truth; Kora mirror** | Kora captures the driver's action/photo/signature/GPS and writes it to Fleetbase, then records Fleetbase references and the frozen Kora status. Kora already captures POD and marks delivery (`voiceops-backend/app/services/pod.py:26-127`), so avoid two independent proof records. |
| Driver location | **Kora app captures; Fleetbase stores/operator-displays** | Kora backend forwards throttled pings while the driver is online/on shift. Kora retains only what it needs for offer/voice operation. Do not run Navigator and Kora background tracking simultaneously. |
| Route plan | **Fleetbase operator plan; Kora active navigation** | Kora renders the route in-app with its OSRM/TomTom stack and handles accepted traffic reroutes. Write significant route/order changes back where supported. |
| Customer tracking/portal | **Fleetbase** | Kora can speak/share the canonical Fleetbase tracking state rather than create a second customer portal. |

The key overlap is dispatch. Fleetbase can assign and dispatch orders; Kora's `order_dispatch.py` offers each new order to the nearest driver with an open voice session and advances on decline/timeout. Choosing Fleetbase as control plane means Fleetbase assigns first and Kora stops offering that order. Choosing Kora's safer initial “order source” mode means Kora continues its own offering and only reports the result back. Mixing them creates double assignment and race conditions.

The second overlap is the driver app. Navigator provides dispatch, navigation, status changes, background location and POD, but replacing Kora with it would discard Kora's central voice-first differentiation. Kora should not embed Navigator. The operator console and API are the useful parts.

## 4. Ways Kora could use Fleetbase, ranked

Effort ranges below are rough engineering estimates for this codebase, not vendor estimates. They exclude procurement/legal lead time and assume one experienced engineer, an available Fleetbase environment, and no redesign of Kora's frozen client contract.

| Rank | Option | What Kora gains | Cost / rough effort | Main risks |
|---:|---|---|---|---|
| 1 | **Fleetbase as operator/dispatcher control plane; Kora as voice driver client** | Fills Kora's missing operator UI and role design; adds fleet/vehicle/place/order administration, dispatch, route planning, tracking, customer portal and POD administration while preserving Kora's differentiator. | 3–5 day proof-of-concept; approximately 4–8 engineering weeks to make sync, reconciliation, POD, status, observability and deployment production-grade. Ongoing Fleetbase operations or Cloud fees. | AGPL/commercial choice, webhook drift, assignment race, status mismatch, MySQL/Redis/socket operations, upgrade churn and driver-location governance. |
| 2 | **Fleetbase only as an order source feeding Kora intake** | Fastest low-risk connection. Fleetbase operators create orders, then a normaliser posts them through Kora's existing idempotent intake; Kora retains nearest-driver voice offers and all execution logic. | About 1–2 weeks for production-quality receiver, ID mapping, retries, status callbacks and tests after the spike. | Fleetbase's console will not show authoritative assignment/status unless write-back is added; duplicated records; gives up much of Fleetbase's dispatch value. |
| 3 | **Borrow concepts/data-model ideas only** | Useful vocabulary for companies, drivers, vehicles, places, service areas, manifests, POD and roles without a runtime dependency. | 2–5 days of design work, then Kora would still need to build an operator console/API. | Easy to underestimate the product work; do not copy AGPL source/UI. Ideas and independently designed schemas are safer than copying implementation. |
| 4 | **Do not use Fleetbase; continue toward Onfleet or build only Kora gaps** | Avoids new infrastructure, AGPL questions and sync complexity. | No Fleetbase work, but dispatcher/operator, tracking and POD administration remain to be bought or built. | Kora's current missing operator role/console persists; Onfleet creates a proprietary dependency and recurring cost. |

Rank 1 is the best strategic fit if the pilot passes. Rank 2 is the safest first integration mode and should be the shape of the spike before transferring dispatch authority.

## 5. Self-hosting and operations

### What must run

The supported local Compose stack contains MySQL 8, Redis, SocketCluster (configured with multiple workers/brokers), API, scheduler, queue worker, console/web assets and HTTP server ([Compose](https://github.com/fleetbase/fleetbase/blob/4ff6980c6db6f3e8103b3ec425a089aa6d251af4/docker-compose.yml#L1-L127)). Fleetbase's quickstart asks for at least **4 GB RAM and 10 GB disk**, and documents local or S3-compatible storage ([local installation](https://fleetbase.io/docs/platform/quickstart/running-locally)). A real deployment also needs TLS, DNS, backups, email, object storage for POD, monitoring, secrets, and enough workers for queues/webhooks.

This is materially heavier than Kora's current architecture: Flutter clients, a FastAPI service on Render, Supabase PostgreSQL/auth/storage, and n8n for post-shift work. Fleetbase cannot simply share Supabase PostgreSQL; the project is coupled to MySQL, as its [PostgreSQL support request](https://github.com/fleetbase/fleetbase/issues/548) confirms.

The checked-in Compose defaults are development-oriented: MySQL can allow an empty password, port 3306 is published, binary logging is disabled, and images use moving `latest` tags. They must not be copied to production unchanged. A Helm chart exists, but its chart/app metadata is old, images default to `latest`, and it has no useful default resource requests; treat it as a starting point, not proof of a maintained production Kubernetes path ([chart metadata](https://github.com/fleetbase/fleetbase/blob/4ff6980c6db6f3e8103b3ec425a089aa6d251af4/infra/helm/Chart.yaml), [values](https://github.com/fleetbase/fleetbase/blob/4ff6980c6db6f3e8103b3ec425a089aa6d251af4/infra/helm/values.yaml)).

A small non-high-availability self-hosted installation is likely in the broad **$30–$150/month infrastructure range**, before backups, object storage, mail/SMS/maps, support and engineering time. This is an order-of-magnitude planning estimate, not a tested benchmark or Fleetbase quote. Fleetbase Cloud's $29 base price may be cheaper for a pilot if its region, privacy, export, SLA and licence terms are acceptable.

### Upgrades

Fleetbase publishes frequent releases and database migrations. Pin every component to tested tags; never deploy `latest`. Before upgrading: snapshot MySQL and object storage, replay the integration contract tests in staging, review migration notes, then roll API/workers/console together. The main repository's eight releases in 18 days show why unattended upgrades are risky even though active maintenance is positive.

### Maps, routing and optimisation

FleetOps supports Leaflet and Google as map-provider choices. The default Leaflet configuration uses OpenStreetMap raster tiles and accepts a custom XYZ tile URL ([Leaflet tile configuration](https://github.com/fleetbase/fleetops/blob/a80f78d791d79df7af0825959610f9ff75e00875/console/app/utils/leaflet-tile-url.js#L1-L29)); Google is optional, so Kora does not need to reintroduce Google Maps. Production use still needs a tile service whose terms and capacity permit the traffic—public OSM tiles are not a free production CDN.

Fleetbase has OSRM support and its default environment points to an OSRM server ([FleetOps routing config](https://github.com/fleetbase/fleetops/blob/a80f78d791d79df7af0825959610f9ff75e00875/server/config/fleetops.php#L34-L41)), so it can align with Kora's OSRM choice. OSRM provides routing, not live traffic. Fleetbase can use its VROOM extension for route optimisation, with self-hosted or hosted VROOM endpoints ([VROOM configuration](https://github.com/fleetbase/vroom/blob/ab8029000c9489581c1b6b2d75019b64fe80174e/server/config/vroom.php#L12-L36)), and also has a simpler built-in optimiser.

Kora's OpenFreeMap/MapLibre vector setup is not automatically a drop-in for FleetOps's Leaflet raster-XYZ UI. The two apps can use different renderers, or FleetOps can be configured with a compatible raster tile source. Kora should retain its in-app map and TomTom traffic reroutes; Fleetbase should own operator planning, not turn-by-turn voice navigation.

## 6. Security, tenancy, roles and driver privacy

### Multi-tenancy and access

Fleetbase is company-scoped and has a detailed policy/role model. FleetOps defines policies such as Dispatch Manager, Fleet Manager, Order Coordinator and Driver Operations, then bundles permissions into roles including Operations Manager, Fleet Supervisor, Service Coordinator, Operations Administrator, Driver Coordinator, Navigator Manager and Driver ([role schema](https://github.com/fleetbase/fleetops/blob/a80f78d791d79df7af0825959610f9ff75e00875/server/src/Schema/FleetOpsSchema.php#L182-L462)). Although the literal role name “Dispatcher” is absent, Dispatch Manager/Operations roles cover that product gap far better than Kora's present driver-only experience.

External API routes sit behind authentication and authorisation middleware. Data is generally keyed by `company_uuid`. However, the core model helper explicitly says there is **no global tenant scope**, so each query path must apply company filtering itself ([model behaviour](https://github.com/fleetbase/core-api/blob/3e1e14a5a1fb84629caf2bbdf0fdb44f7dcb2e9d/src/Models/Concerns/HasApiModelBehavior.php#L21-L34)). That makes tenant isolation dependent on implementation discipline. The very recent v0.7.64 release included cross-organisation fixes, which reinforces the need to keep patched and test tenant boundaries ([release](https://github.com/fleetbase/fleetbase/releases/tag/v0.7.64)).

Security conditions for a pilot should include: restricted API credentials, explicit company IDs in reconciliation tests, TLS verification enabled for webhooks, no public mobile API key, origin restrictions or no direct SocketCluster exposure, rate limits, encrypted backups, and a test proving one organisation cannot fetch or mutate another's order/driver/vehicle/POD.

### Driver location privacy

Navigator demonstrates the expected tracking model: it transmits precise coordinates plus heading, speed, altitude, activity and battery when the driver is logged in, linked to a driver, online and has fine-location permission ([location context](https://github.com/fleetbase/navigator-app/blob/37af1ee7dfdcc53052058edd853c66400d3e7e32/src/contexts/LocationContext.tsx#L21-L110)). Its background rationale says tracking continues when the app is closed or not in use while the driver is online, uses a 10-metre filter, does not stop on process termination, and starts on boot ([same source](https://github.com/fleetbase/navigator-app/blob/37af1ee7dfdcc53052058edd853c66400d3e7e32/src/contexts/LocationContext.tsx#L165-L180)).

That behaviour can be operationally useful and privacy-sensitive. This review did not find a verified retention/deletion schedule in the audited repositories. Before production, Kora needs explicit consent language, a visible online/on-shift indicator, an off-shift hard stop, a retention/deletion period, operator-role access rules, audit logging, and a country-by-country legal review. Kora should send one location stream; installing/running both Navigator and Kora would duplicate collection and could produce conflicting online state.

## 7. Alternatives, briefly

**Onfleet**, Kora's original plan, is a managed proprietary last-mile product with mature dispatcher, driver, routing, tracking and webhook features; it is likely the faster operational integration and avoids self-hosting, but brings recurring SaaS cost, less control and the same driver-app overlap. Its public API documents a [20 requests/second limit](https://docs.onfleet.com/reference/throttling). **Traccar** is a mature [Apache-2.0 open-source GPS tracking server](https://github.com/traccar/traccar/blob/master/LICENSE.txt) with live location and geofences, but it does not replace a last-mile order/dispatch/POD console. **ERPNext** is GPLv3 and has [Delivery Trips with drivers, vehicles and route optimisation](https://docs.frappe.io/erpnext/delivery-trip), but it is an ERP-first workflow rather than a focused real-time last-mile dispatcher. Fleetbase is the most complete open-source match for Kora's operator-side gap; Onfleet remains the lower-operations commercial comparison.

## 8. Recommendation and smallest safe next step

### Recommendation

Proceed with a **time-boxed 3–5 working-day spike**, then make a go/no-go decision. The strategic target should be Fleetbase as the dispatcher/operator control plane and Kora as the only driver app, but the spike should begin in order-source mode. Do not yet commit to production, modify Fleetbase, embed its SDKs/UI, or route live drivers through it.

The reasons are straightforward:

- Fleetbase fills a genuine Kora gap—operator roles and console—without replacing Kora's voice value.
- Its FleetOps domain is broad enough that Kora avoids building fleet/vehicle/place/order/POD/customer-tracking administration from scratch.
- Its REST API and OSRM-compatible routing are workable.
- The risks are concrete and testable: signature drift, dispatch ownership, lifecycle translation, tenant isolation, location privacy, operational size and AGPL boundaries.

### Spike definition

In a disposable local environment pinned to exact release tags:

1. Stand up Fleetbase with Docker and record actual RAM/disk/startup time.
2. Create two organisations, operator/driver roles, a driver, vehicle, place and order. Prove cross-organisation reads and mutations fail.
3. Create a live/test API key and exercise order, driver, vehicle, place and tracking calls from a tiny throwaway asynchronous Python client—without importing Fleetbase's AGPL SDK.
4. Register a webhook receiver, capture the exact bytes/headers, and verify its signature, retry count, TLS configuration and event envelope against the deployed release. Raise an upstream issue if the docs still disagree.
5. Normalise one Fleetbase order into Kora's `IncomingOrder`; exercise Kora's idempotent intake twice and confirm only one order exists.
6. Run the order end-to-end: offer/accept, assignment/dispatch/start, one location update, route retrieval, POD and completion. Repeat branches for decline/unassigned, failure and reschedule.
7. Kill/restart the receiver to test replay, reconciliation, duplicate and out-of-order events. Confirm failed syncs are observable and recoverable.
8. Measure REST/webhook latency but keep every call outside the AssemblyAI voice WebSocket relay. Confirm Kora's tool orchestrator remains parallel.

### Decisions required before implementation

- Is Fleetbase or Kora the sole assignment/dispatch authority?
- Is Kora comfortable operating under AGPL with an unmodified separate service, or does the intended use require Fleetbase's commercial licence? Obtain legal review.
- Fleetbase Cloud or self-hosted? Decide data region, SLA, backups, export/exit plan and support level.
- Which system is canonical for driver/vehicle identity, route plans, status and POD? The source-of-truth table above is the recommended answer.
- What location consent, collection window, operator visibility, retention and deletion rules apply?
- How are Kora `failed` and `rescheduled` represented in Fleetbase, and are Fleetbase `started/enroute/canceled` stored without changing Kora's frozen external enum?

### Go/no-go criteria

Proceed beyond the spike only if:

- the deployed webhook can be authenticated safely, TLS verification is enabled, and reconciliation closes missed-event gaps;
- the status/POD mapping is deterministic and tested;
- exactly one system assigns each order;
- operator workflows are good enough for the team without embedding or heavily modifying Fleetbase UI;
- measured resource/upgrade burden is acceptable, or Fleetbase Cloud terms are acceptable;
- tenant and location-privacy tests pass; and
- legal review approves the AGPL boundary or a commercial licence is budgeted.

### What this review could not verify

No authenticated Fleetbase Cloud tenant was available, and this scout did not operate a full Fleetbase stack end-to-end with real drivers. Therefore it could not verify production performance, cloud SLA/backups/data residency/DPA, hosted rate-limit overrides, actual support quality, private/paid extension behaviour, marketplace terms, or production upgrade reliability. The live webhook behaviour was derived from current source and documentation, whose conflict must be resolved by the spike. The review also does not provide a legal conclusion on AGPL, nor a jurisdiction-specific conclusion on driver tracking. Public prices may change.

## Evidence and reproducibility notes

Repositories were cloned with `gh-axi repo clone fleetbase/<repo>` and inspected at these commits:

```text
fleetbase       4ff6980c6db6f3e8103b3ec425a089aa6d251af4
fleetops        a80f78d791d79df7af0825959610f9ff75e00875
navigator-app   37af1ee7dfdcc53052058edd853c66400d3e7e32
fleetbase-js    b76e577cae6b735e600285dc1e46edc925244ff8
core-api        3e1e14a5a1fb84629caf2bbdf0fdb44f7dcb2e9d
docs            08e9a465ddd5070cd19ff783e187cf0eba025c2b
postman         822b867218f174bad18a789d4fd6791ccfd2af34
pallet          adea3d9886ce3736ab1ddcf0f08de6381a1c1679
customer-portal dca220ff893f2152effbd56253429cca97614adf
vroom           ab8029000c9489581c1b6b2d75019b64fe80174e
valhalla        13aa5eed207ed6ead952aaacdcafd31e6ef03d8f
ledger          d2e5de66bb327d64f561204c1c2bca2adc4a6eda
```

Commands used for the activity/maturity snapshot included:

```bash
gh-axi api repos/fleetbase/REPO
gh-axi api 'repos/fleetbase/REPO/issues?state=open&per_page=100'
gh-axi api 'repos/fleetbase/REPO/contributors?per_page=100&anon=1'
gh-axi api 'repos/fleetbase/REPO/releases?per_page=100'
git -C REPO rev-list --count --since='30 days ago' HEAD
git -C REPO rev-list --count --since='90 days ago' HEAD
git -C REPO rev-list --count --since='365 days ago' HEAD
```

Kora evidence was read directly from `origin/staging`, including `AGENTS.md`, `docs/contracts/interface.md`, `voiceops-backend/app/integrations/logistics/`, `voiceops-backend/app/api/routes/logistics.py`, `voiceops-backend/app/dispatch/order_dispatch.py`, the delivery state machine, order queue, driver, shift, preference and POD services. No Kora source files were changed.
