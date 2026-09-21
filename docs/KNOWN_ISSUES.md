# Known issues and gotchas

Real things that have already gone wrong once on this project. Check here
before spending time re-debugging something already solved.

## `ASSEMBLYAI_AGENT_ID` breaks voice if set to anything

**Status: this exact incident already happened once and was fixed on 2026-09-16/17** by removing
the variable from the Render deployment. Documented here so it's recognized instantly if it
recurs (e.g. after a redeploy, a new environment, or copying env vars into a new Codespace/host).

**Symptom:** voice worked locally/in dev, then broke immediately after a
fresh deploy (e.g. to Render), with the app reporting "the voice service
rejected the session" and backend logs showing:

```
[VoiceWS] Upstream rejected session: agent_not_found
```

**Cause:** the backend (`voiceops-backend/app/api/websocket/voice.py`,
`_start_upstream()`) always reads `settings.assemblyai_agent_id` (env
`ASSEMBLYAI_AGENT_ID`) and passes it into `get_session_config()`. If that
variable has **any value at all**, the backend switches from its normal
working inline session config (prompt, tools, hardcoded voice) to
AssemblyAI's "stored agent" mode, sending only `{"agent_id": <value>}` and
expecting a pre-created agent to exist under that AssemblyAI account. This
app has no actual stored agent configured, so if the variable is set to
anything, AssemblyAI rejects the session outright.

**Fix:** on the deployment platform (Render, etc.), make sure
`ASSEMBLYAI_AGENT_ID` is **not set at all** — not even to an empty string,
if the platform treats presence differently from value. Keep
`ASSEMBLYAI_API_KEY` set as normal. This most often happens when environment
variables get bulk-copied from a local `.env` file during a new deployment
setup, carrying over a variable that was only ever meant for local
experimentation.

**If this project's voice-tone-selection backend work (see
`docs/backend-handoff/voice-tone-selection.md`) is later implemented,** it
deliberately keeps using inline config with a validated voice ID — it does
not and should not switch this app onto stored-agent mode.

## `staging`/`main`/`dev` drift apart silently

This has happened at least twice. Symptom: a branch you'd expect to be a
strict subset of another (e.g. "surely `main` has everything `staging`
has, plus more") turns out not to be — each has commits the other lacks.

**Root cause pattern:** Maria has, at times, pushed backend-only work
directly to `main` (bypassing the `staging` tier of the branching model),
while frontend feature work lands on `staging` via the normal
`features/* -> staging` PR flow. If nobody merges the two back together
for a while, they genuinely diverge in both directions.

**Before assuming any branch is "the current one":** check both
directions explicitly —

```sh
git fetch origin
git log origin/main..origin/staging   # what staging has that main doesn't
git log origin/staging..origin/main   # what main has that staging doesn't
```

As of 2026-09-21 `origin/main` and `origin/staging` are level (both at `9de5285`) and `origin/dev`
lags behind. Re-check before relying on that.

If both commands print commits, they've diverged and need a real merge
(not a fast-forward) to reconcile — expect conflicts in shared files like
`frontend/lib/core/config/backend_config.dart` if both branches touched
backend/environment config independently.

## Local git clones of this repo can silently orphan from real history

If working from a clone that was set up before this project's real
branching history existed (e.g. a very early clone, or one predating the
VoiceOps → Kora GitHub rename), its local `main`/`dev` branches can end up
as unrelated single-commit orphans or many commits behind, even though
`origin/main`/`origin/dev` are current. Symptoms include things like "my
main branch only has one commit" or a tool refusing to recognize clearly
landed work as landed. Compare `git log <branch>` against
`git log origin/<branch>` directly rather than trusting a local branch name
at face value — if they've diverged and the local branch holds no unique
real work, `git reset --hard origin/<branch>` (after confirming nothing
valuable would be lost) is the fix.

## `flutter analyze`/`flutter test` environment notes

- Expect an unrelated warning wall about `librive_native.so`/
  `librive_native_plugin.so` failing to load during test runs in a
  headless/CI-like environment — this is expected (no native Rive runtime
  available there) and the app falls back to a placeholder mascot. It does
  not indicate a real failure; look at the actual pass/fail summary, not
  this warning block.
- `flutter test`'s default summary output truncates long failure lists to
  "... and N more" — if you need the complete list of failing test names,
  either use `--reporter expanded` or grep the full streaming output rather
  than trusting the final summary section alone.

## GitHub push access is often environment-specific

In at least one prior Codespace, the git credential helper only authorized
pushes to the Codespace's *own* originating repo, not to this project's
repo (`MI-TECHDLIN/kora`) even though reads/clones worked fine. If an
assistant or tool in a new environment reports it can read this repo but
not push to it, that's very likely the same class of limitation — pushes
in that case have to come from a machine/environment with real write
credentials for this specific repo, not worked around. Check this early
rather than assuming a change has been pushed when it's only been
committed locally somewhere without push access.
