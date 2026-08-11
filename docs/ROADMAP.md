# Fleetpost — product plan & roadmap

A grounded plan, written after market research. It does **not** pretend the category is
empty (it isn't) — it aims Fleetpost at the gap the research actually found.

## Positioning

**One line:** *A mailbox for your machines — offline-tolerant, server-less agent
coordination carried by any rclone remote.*

**The honest wedge.** [SAMP](https://github.com/slima4/agent-message) (sync-daemon
transport) and [GNAP](https://github.com/farol-team/gnap) (git transport) already do
offline, server-less, cross-machine coordination. Fleetpost's defensible bundle is:
rclone/object-storage transport **+** folder-native `inbox/handled` semantics **+**
offline-published capability descriptor **+** hash-watched protocol changelog. Lead with
that bundle and with the **async/offline** contrast to the real-time framing of
[claude-code #28300](https://github.com/anthropics/claude-code/issues/28300).

## Who it's for

- Solo devs / small teams running AI coding agents on **2–5 machines** (laptop + desktop +
  a build box, or a Mac for signing + a Linux CI box) who already use a cloud drive or
  object storage.
- People who want coordination **without standing up a server** and without a sync daemon
  on every host.
- Not for: single-machine multi-agent (use in-process frameworks) or teams needing
  real-time, both-online collaboration (that's A2A / live session messaging).

## Differentiation to defend (and to NOT overclaim)

| Claim | Honest? |
|---|---|
| "Offline-tolerant, server-less, cross-machine" | True but **shared** with SAMP/GNAP — don't imply it's unique. |
| "rclone / object-storage transport" | Genuinely distinct from SAMP (daemons) and GNAP (git). |
| "Folder-native inbox/handled + offline capability discovery + protocol changelog" | The real bundle. Not found combined elsewhere. |

## Roadmap

**v0.1 — Kit (this release).** Parameterized `sync.sh` + `generate-inventory.sh` +
`handle.sh` (mark a request handled), templates, systemd/cron examples, README, protocol
doc, CONTRIBUTING, MIT license. Verified end-to-end against a local rclone remote.
*Goal: someone can wire up 2 machines in 15 minutes.*

**v0.2 — Onboarding & safety.**
- **`scripts/init.sh` — shipped.** Interactive (or flag-driven) setup: writes `config.env`,
  creates the local working directory, stages a capabilities descriptor, claims this
  machine's folder on the remote. Refuses to overwrite an existing config without `--force`,
  and installs no scheduler — it prints the command instead, so nothing lands unasked.
- **`scripts/doctor.sh` — shipped.** Checks config completeness, rclone presence, remote
  reachability, folder layout, a staged descriptor, and a clock behind the remote.
- Still open: launchd example for macOS (native catch-up).

**v0.3 — Ergonomics.**
- **`scripts/send.sh` — shipped.** Composes a well-formed request and drops it in another
  machine's inbox; every protocol-required field is mandatory. Byte-identical to what the
  MCP server writes (`mcp/tests/test_parity.py` asserts it).
- **`scripts/status.sh` — shipped.** Pending requests, protocol changes, fleet capabilities
  and last-seen times, read from the pulled files. No network. Exit `10` = something waits.
- Still open: Windows PowerShell `sync.ps1` parity + Scheduled Task example.

**v0.4 — Agent integration.**
- **MCP server — shipped.** `mcp/` (`fleetpost-mcp` on PyPI): `fleet_status`,
  `fleet_capabilities`, `fleet_read_request`, `fleet_send_request`, `fleet_handle`,
  `fleet_sync`. It reads the same `config.env` and calls the same scripts — no second
  implementation of the protocol, and no server of its own.
  *Note:* this brings v0.3's `send` and `status` in early, as tools rather than as shell
  helpers. The shell equivalents are still worth having for people not driving an agent.
- **Session-start hook — shipped.** `examples/hooks/session-start.sh` surfaces whatever the
  last cycle flagged at the top of an agent session, and is silent when nothing waits —
  closing the "flag → agent" gap. Local-only by default; `FLEETPOST_HOOK_SYNC=1` pulls first,
  for a machine with no scheduler. Cannot break a session: every path exits 0.

**Later, maybe.** Encryption-at-rest note (rclone crypt remote), a tiny web view of the
folder, multi-fleet namespacing.

## Non-goals

- No central server, no database, no daemon of our own — the moment we add one we become
  mcp_agent_mail, not Fleetpost.
- No real-time delivery guarantees. If you need both-online, use A2A or live session
  messaging; Fleetpost is deliberately async.
- No memory sync. Memory stays local, always.

## Go-to-market (lightweight, adoption-first)

1. **SEO/README:** capture Tier-A traffic ("Claude Code multiple machines", "coordinate
   multiple agents") in the README intro; own a Tier-C phrase ("offline-tolerant agent
   message bus over a shared folder"). GitHub topics: `ai-agents`, `multi-agent`,
   `agent-coordination`, `claude-code`, `rclone`, `offline-first`, `message-bus`.
2. **Honest launch note** on the claude-code #28300 thread and relevant discussions:
   "async/offline take, complements the real-time asks." Link, don't spam.
3. **A 60-second asciinema** of two machines exchanging a task with one powered off.
4. **Cross-link SAMP** in the README (done) — being a good citizen in a small niche earns
   more than pretending to be first.

## Success signals

Stars are vanity; the real signals are: someone files an issue describing a 3-machine
setup we didn't anticipate; a PR adding a launchd/PowerShell variant; the term "rclone
agent coordination" starts returning this repo.
