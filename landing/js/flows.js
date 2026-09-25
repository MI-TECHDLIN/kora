/*
 * Scripted flows for the phone preview, and the tiny intent matcher that maps
 * free text to the nearest one. No model, no network: a keyword score picks a
 * flow, the flow drives the phone. Task-step labels and reasoning lines are the
 * relay's own (voiceops-backend/app/api/websocket/events.py, reasoning.py).
 */

/** Tappable prompts. The first four are the ones shown to judges first. */
export const PROMPTS = [
  { id: "next", text: "What's my next delivery?", icon: "map-pin", accent: "blue" },
  { id: "auto", text: "Accept nearby orders automatically.", icon: "sparkles", accent: "violet" },
  { id: "progress", text: "How am I doing today?", icon: "chart-bar", accent: "pink" },
  { id: "call", text: "Call the customer and tell them I'm arriving soon.", icon: "phone-call", accent: "green" },
  { id: "offer", text: "Any new orders?", icon: "package", accent: "violet", secondary: true },
  { id: "queue", text: "What's left on my list?", icon: "list-check", accent: "amber", secondary: true },
];

const km = (n) => `${n} kilometers`;

const FLOWS = {
  /** get_next_delivery, then get_best_route and start_navigation in parallel. */
  async next(p) {
    const a = p.active;
    if (!a) return FLOWS.nothingLeft(p);
    p.setMood("mapping");
    p.step("Finding your next stop", "active");
    p.step("Checking delivery route", "pending");
    p.step("Starting navigation", "pending");
    await p.wait(1000);
    p.step("Finding your next stop", "done", `Stop ${a.seq} is next, with a ${a.window} delivery window.`);
    await p.wait(350);
    p.step("Checking delivery route", "active");
    p.step("Starting navigation", "active");
    await p.wait(1100);
    p.step("Checking delivery route", "done", `The fastest available route is about ${a.eta} min.`);
    await p.wait(450);
    p.step("Starting navigation", "done", `This route is 2.4 km and about ${a.eta} min.`);
    p.setTab("map", true);
    p.showRoute();
    await p.wait(1400);
    await p.speak(
      `Your next stop is number ${a.seq}, ${a.name} at ${a.address}. It's ${km(2.4)}, about ${a.eta} minutes. The route is on your map.`,
    );
  },

  /** set_preference, then a new order arrives and is taken out loud. */
  async auto(p) {
    const already = p.s.autoAccept;
    p.setMood("task");
    if (!already) {
      p.step("Saving your preference", "active");
      p.step("Opening the screen", "active");
      await p.wait(1000);
      p.step("Saving your preference", "done");
      p.setTab("settings", true);
      p.setAutoAccept(true);
      p.step("Opening the screen", "done");
      await p.wait(1700);
    }
    if (p.s.nextSeq > 16) {
      await p.speak("Auto-accept is on. There are no new orders nearby right now, and I'll take matching ones out loud as they arrive.");
      return;
    }
    p.openOffer(true);
    p.setMood("task");
    p.step("Checking the order queue", "active");
    await p.wait(1000);
    p.step("Checking the order queue", "done", "This offer is 1.2 km from your current position.");
    await p.wait(300);
    p.step("Accepting the order", "active");
    await p.wait(1000);
    const seq = p.addAcceptedOrder();
    p.step("Accepting the order", "done", `The order was added as stop ${seq}. Its window is ${p.s.offer.window}.`);
    p.s.offer.status = "accepted";
    p.renderTop();
    p.emit({ event: "order_offer_closed", order_id: p.s.offer.id, outcome: "accepted" });
    await p.wait(600);
    p.setMood("celebrating");
    await p.wait(500);
    await p.speak(
      `${already ? "" : "Auto-accept is on. "}A new order just came in, ${km(1.2)} away on Riverside Drive, so I took it. It's stop ${seq}, with a window of 16:00 to 17:00.`,
    );
    p.dismissOffer();
  },

  /** get_shift_summary, then the Summary tab. */
  async progress(p) {
    p.setMood("summarizing");
    p.step("Summarising your shift", "active");
    await p.wait(1200);
    const c = p.counts;
    p.step("Summarising your shift", "done", `You have completed ${c.completed} of ${c.total}; ${c.total - c.completed} remain.`);
    p.setTab("summary", true);
    p.el.summaryScroll.scrollTo({ top: 0 });
    await p.wait(1500);
    const t = p.s.target;
    const left = Math.max(0, t - c.completed);
    await p.speak(
      `You've completed ${c.completed} of your ${t}-delivery target, so ${left} to go. ${c.active + c.pending} stops are still open and none have failed.`,
    );
  },

  /** call_customer and notify_customer run at the same time. */
  async call(p) {
    const a = p.active;
    if (!a) return FLOWS.nothingLeft(p);
    p.setMood("calling");
    p.step("Calling the customer", "active");
    p.step("Messaging the customer", "active");
    await p.wait(1000);
    p.s.call = { name: a.name };
    p.renderTop();
    p.emit({ event: "call_started", call_id: "sim-call", customer_name: a.name, sequence: a.seq });
    p.step("Calling the customer", "done", "The call request was created for this stop.");
    await p.wait(600);
    p.s.sms = { name: a.name, text: "Hi, your courier is arriving in a few minutes." };
    p.renderTop();
    p.step("Messaging the customer", "done", "The customer update is sent.");
    await p.wait(1200);
    await p.speak(`I'm calling ${a.name} now, and I've sent a text saying you're arriving in a few minutes.`);
    await p.wait(900);
    p.endCall();
    await p.wait(2400);
    p.s.sms = null;
    p.renderTop();
  },

  /** get_next_order offers the nearest order; the driver decides. */
  async offer(p) {
    p.setMood("task");
    p.step("Checking the order queue", "active");
    await p.wait(1000);
    p.step("Checking the order queue", "done", "This offer is 1.2 km from your current position.");
    p.setTab("voice", true);
    if (!p.hasOpenOffer()) p.openOffer(false);
    await p.wait(700);
    await p.speak(`There's a new order ${km(1.2)} away on Riverside Drive. Window 16:00 to 17:00, two packages. Say accept, or tap Accept.`);
  },

  /** accept_order / decline_order. */
  async respond(p, accept) {
    p.setMood("task");
    if (accept) {
      p.step("Accepting the order", "active");
      await p.wait(1000);
      const seq = p.addAcceptedOrder();
      p.step("Accepting the order", "done", `The order was added as stop ${seq}. Its window is ${p.s.offer ? p.s.offer.window : "16:00–17:00"}.`);
      if (p.s.offer) p.s.offer.status = "accepted";
      p.renderTop();
      p.emit({ event: "order_offer_closed", order_id: "ord-2041", outcome: "accepted" });
      await p.wait(600);
      p.setMood("celebrating");
      await p.speak(`Done. It's stop ${seq} on your list.`);
      p.dismissOffer();
    } else {
      p.step("Passing the order on", "active");
      await p.wait(1000);
      p.step("Passing the order on", "done", "The next driver is 2.1 km from the drop-off.");
      p.closeOffer("declined", "Passed to the next nearest driver.");
      await p.speak("No problem. I passed it to the next nearest driver.");
    }
  },

  /** Read the queue aloud, and show it. */
  async queue(p) {
    const open = p.s.queue.filter((o) => !o.done);
    p.setMood("task");
    p.step("Checking the order queue", "active");
    await p.wait(1100);
    p.step("Checking the order queue", "done");
    p.setTab("summary", true);
    await p.wait(200);
    p.el.summaryScroll.scrollTo({ top: p.el.summaryScroll.scrollHeight, behavior: "smooth" });
    await p.wait(1200);
    if (!open.length) return FLOWS.nothingLeft(p);
    const next = open.slice(0, 3).map((o) => `${o.name} at ${o.address.replace(/,.*$/, "")}`);
    await p.speak(`${open.length} stops left. Next is ${next[0]}${next[1] ? ", then " + next[1] : ""}${next[2] ? ", and " + next[2] : ""}.`);
  },

  /** set_preference for the daily target. */
  async target(p, n) {
    p.setMood("task");
    p.step("Saving your preference", "active");
    await p.wait(1000);
    p.s.target = n;
    p.step("Saving your preference", "done");
    p.setTab("summary", true);
    p.el.summaryScroll.scrollTo({ top: 0 });
    p.renderQueueViews();
    await p.wait(1000);
    const done = p.counts.completed;
    await p.speak(
      n <= done
        ? `Your target is now ${n} deliveries, and you've already reached it. Nice work today.`
        : `Done. Your target is ${n} deliveries today. You've completed ${done}, so ${n - done} to go.`,
    );
  },

  async nothingLeft(p) {
    await p.speak("There are no stops left in this shift. Nice work today.");
  },

  async hello(p) {
    await p.speak("Hi, I'm Kora, your co-rider. Ask for your next delivery, a customer call, your progress, or a new order.");
  },

  async unknown(p) {
    p.emit({ event: "preview_hint" });
    await p.speak("In the app I'd handle that. In this preview, try your next delivery, auto-accept, today's progress, a customer call, your queue or a new order.");
  },
};

const RULES = [
  ["offer", [[/new order|any orders?|orders? (nearby|available|waiting|coming)|offer|dispatch/, 3]]],
  ["auto", [[/auto/, 3], [/nearby|matching|automatic/, 1], [/accept/, 1]]],
  ["call", [[/call|phone|ring|text|message|sms|notify|arriving|tell (them|the|my)/, 2], [/customer|recipient/, 1]]],
  ["next", [[/next (delivery|stop|order|drop|one)|where (do|am|to|should)|navigate|directions|route|take me|go next/, 2], [/deliver|stop/, 1]]],
  ["progress", [[/how am i|how('s| is| did)|doing|progress|summary|so far|stats|performance/, 2], [/today|shift|target|goal/, 1]]],
  ["queue", [[/left|queue|list|remaining|upcoming|still to|to go/, 2], [/orders?|stops?|deliveries/, 1]]],
];

/** @returns {{id: string, arg?: number}} the nearest flow for what was said */
export function match(raw, phone) {
  const t = raw.toLowerCase().trim();
  if (phone.hasOpenOffer() && !/auto/.test(t)) {
    if (/\b(accept|yes|yeah|yep|take it|sure|ok|okay)\b/.test(t)) return { id: "accept" };
    if (/\b(decline|no|nope|pass|skip|reject)\b/.test(t)) return { id: "decline" };
  }
  if (/^(hi|hello|hey|good (morning|afternoon|evening))\b/.test(t)) return { id: "hello" };
  const num = t.match(/\b(\d{1,3})\b/);
  if (/(target|goal)/.test(t) && num && /\b(set|make|change|update|to)\b/.test(t)) {
    return { id: "target", arg: Math.min(500, Math.max(1, parseInt(num[1], 10))) };
  }
  let best = { id: "unknown", score: 1 };
  for (const [id, rules] of RULES) {
    const score = rules.reduce((sum, [re, w]) => sum + (re.test(t) ? w : 0), 0);
    if (score > best.score) best = { id, score };
  }
  return { id: best.id };
}

/** Says `text` to the phone: picks the flow and plays it. */
export function ask(phone, text) {
  const { id, arg } = match(text, phone);
  const scripts = {
    accept: () => FLOWS.respond(phone, true),
    decline: () => FLOWS.respond(phone, false),
    target: () => FLOWS.target(phone, arg),
  };
  const script = scripts[id] || (() => FLOWS[id](phone));
  return { id, done: phone.run(script, text) };
}

/** Wires flow-owned handlers into a phone (manual Accept/Decline, PTT tap). */
export function attach(phone, { nextPrompt }) {
  phone.handlers = { respond: (accept) => phone.run(() => FLOWS.respond(phone, accept), accept ? "Accept it" : "Decline it") };
  phone.onPttTap = () => {
    if (phone.busy && phone.s.ptt === "speaking") {
      // Tapping while Kora speaks interrupts her, like the app.
      phone.runToken++;
      phone.busy = false;
      phone.s.caption = null;
      phone.renderCaption();
      phone.setMood("idle");
      phone.setPtt("idle");
      phone.root.classList.remove("is-running");
      return;
    }
    if (phone.busy) return;
    const text = nextPrompt();
    if (text) ask(phone, text);
  };
}
