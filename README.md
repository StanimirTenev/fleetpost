# Fleetpost

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Made with Bash](https://img.shields.io/badge/made%20with-Bash-1f425f.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS-lightgrey.svg)
![Server: none](https://img.shields.io/badge/server-none-brightgreen.svg)
![Transport: rclone](https://img.shields.io/badge/transport-rclone-orange.svg)
![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)

**A mailbox for your machines.** Independent AI coding agents on separate computers
drop tasks in a shared folder and pick them up whenever they wake — no server, no
daemon, and no requirement that both sides be online at once.

> Offline-tolerant coordination for independent AI agents: cross-machine, server-less,
> carried by any folder `rclone` can reach — Google Drive, S3, Dropbox, SFTP, WebDAV.

Fleetpost is a handful of shell scripts and a convention. You run several agents (Claude
Code, Cursor, Codex, Aider, whatever) on several machines. Each keeps its own local
memory. Fleetpost lets them **know what the others can do** and **ask each other for
work** — and it keeps working when a machine is asleep or powered off, because the
messages simply wait in the shared folder until that machine's next sync.

---

## Why this exists

Run an agent on your laptop and another on your desktop and they are blind to each other;
you become the courier, copy-pasting between terminals ([a real, common pain](https://github.com/anthropics/claude-code/issues/28300)).
The usual answers are **live** — both agents must be running and connected at the same
moment. Fleetpost takes the other route: **asynchronous**. Leave the work in the drop and
walk away; the powered-off machine catches up on its own.

## How it works

```
<shared-folder>/                     (any rclone remote: Drive, S3, Dropbox…)
├── 00-START-HERE.md                 onboarding for a new machine
├── PROTOCOL-CHANGES.md              append-only changelog, watched by hash
├── laptop/
│   ├── capabilities.md              what this machine can do (hand-written)
│   ├── inventory.md                 what it knows (index; optional generator)
│   └── inbox/
│       └── handled/                 requests it has completed
├── desktop/
└── server/
```

A small `sync.sh` runs on a timer (systemd / cron / launchd) on each machine and does
four things — and nothing that touches another machine's data:

1. **pulls** this machine's `inbox/`
2. **detects** new requests (and protocol changes) → raises a local `SIGNAL.md` flag
3. **pulls** every other machine's `capabilities.md` so this one knows who to ask
4. **publishes** this machine's own descriptors, only when they actually changed

It never *executes* a request. It fetches and flags; the agent does the work in a session.

## Demo

Your **desktop** needs something only the **laptop** can do, so it drops a request in the
laptop's inbox and forgets about it:

```console
desktop$ echo "Compile the arm64 build and report the sha256." \
           > 2026-08-09-from-desktop-compile.md
desktop$ rclone copy 2026-08-09-from-desktop-compile.md \
           "gdrive:coordination/laptop/inbox/"
```

The laptop is asleep. Hours later it wakes; its timer fires a sync:

```console
laptop$ ./scripts/sync.sh
14:17  1/4 pulling laptop/inbox …
14:17  2/4 detecting new requests and protocol changes …
       -> new requests; raised SIGNAL.md
14:17  3/4 pulling fleet capabilities …
       -> desktop: fetched
14:17  4/4 publishing my descriptors (only if changed) …
14:17  done.
# exit code 10 = "something new for you"

laptop$ cat ~/.agent-coordination/SIGNAL.md
# SIGNAL — something is waiting for you
## New requests in your inbox (~/.agent-coordination/inbox/)
- `2026-08-09-from-desktop-compile.md` (41 bytes)
```

The laptop's agent does the work, drops a reply in `desktop/inbox/`, and moves the
request into `inbox/handled/`. The desktop picks up the answer on *its* next sync — and
at no point did both machines need to be online at the same time.

## What makes it different

The category is not empty — see [Alternatives](#alternatives). Fleetpost's specific bundle is:

- **rclone-first transport** — pull from object storage / Drive / S3 / Dropbox. No sync
  daemon on every host, no git remote. If `rclone` can reach it, Fleetpost can use it.
- **Folder-native protocol** — per-machine `inbox/` + `handled/` subfolders. A machine
  with no automation still sees exactly its unhandled requests at the top level.
- **Offline-published capability descriptor** — each machine leaves a "what I can do" file
  in the folder, discoverable **even while that machine is off** (unlike a live Agent Card
  that needs an HTTP server up).
- **Hash-watched changelog** — rule changes reach already-running agents, which would
  otherwise never re-read the onboarding doc.

## Quickstart

```bash
git clone https://github.com/StanimirTenev/fleetpost
cd fleetpost
cp config.example.env config.env
$EDITOR config.env            # set RCLONE_REMOTE, COORD_DIR, MACHINE_NAME, FLEET

# one-time: seed the shared folder (run once, from any machine)
rclone mkdir "<remote>:<coord-dir>"
rclone copy templates/00-START-HERE.md      "<remote>:<coord-dir>/"
rclone copy templates/PROTOCOL-CHANGES.md   "<remote>:<coord-dir>/"

# publish yourself, then run a cycle
# (~/.agent-coordination is the default LOCAL_ROOT; change both if you edited it.)
# sync.sh creates your <machine>/inbox on the remote automatically on first run.
mkdir -p ~/.agent-coordination/self
cp templates/capabilities.template.md ~/.agent-coordination/self/capabilities.md
$EDITOR ~/.agent-coordination/self/capabilities.md
./scripts/sync.sh

# schedule it (Linux, user timer)
cp examples/systemd/coordination-sync.* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now coordination-sync.timer
loginctl enable-linger "$USER"
```

See [`docs/PROTOCOL.md`](docs/PROTOCOL.md) for the full protocol and [`00-START-HERE.md`](templates/00-START-HERE.md)
for what a new agent reads.

## Requirements

`bash`, [`rclone`](https://rclone.org/) (configured with one remote), `sha256sum`, and a
scheduler (systemd, cron, or launchd). That's it. No server, no database, no language runtime.

## Alternatives

Honest comparison — pick what fits:

| Project | Transport | Cross-machine | Survives machine **off** | Capability discovery |
|---|---|---|---|---|
| **Fleetpost** | rclone (Drive/S3/Dropbox/…) | ✅ | ✅ (waits in folder) | ✅ offline-published |
| [SAMP](https://github.com/slima4/agent-message) | Syncthing/Dropbox/iCloud daemon | ✅ | ✅ | ❌ |
| [GNAP](https://github.com/farol-team/gnap) | git remote (pull/rebase/push) | ✅ | ✅ (on reconnect) | ✅ (`agents.json`) |
| [mcp_agent_mail](https://github.com/Dicklesworthstone/mcp_agent_mail) | HTTP FastMCP server | ✅ | ❌ (server must be up) | partial |
| [A2A](https://a2a-protocol.org/) | JSON-RPC over HTTP | ✅ | ❌ (agent must be online) | ✅ (live Agent Card) |
| LangGraph / CrewAI / AutoGen | in-process runtime | ❌ | ❌ | n/a |

If you already run Syncthing everywhere, [SAMP](https://github.com/slima4/agent-message)
is excellent and closest in spirit. Fleetpost is for when your shared layer is object
storage or a cloud drive (via rclone) and you want folder-native inbox/handled semantics
plus offline capability discovery.

## Design principles

- **Memory stays local.** Only a short descriptor is published. Full memory never travels.
- **Ask for actions, not access.** Secrets never travel; the machine that holds a
  credential does the work and returns only the result.
- **One author per shared document**, so concurrent writers can't clobber a changelog entry.

## License

[MIT](LICENSE).
