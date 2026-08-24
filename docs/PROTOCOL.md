# The coordination protocol

A precise description of how machines talk through the shared folder. The scripts
implement this; agents follow it by reading `00-START-HERE.md`.

## Model

- A **fleet** is a set of machines, each running its own agent with its own local memory.
- Machines never share memory. They share a single **coordination folder** on any
  rclone-reachable remote (Drive, S3, Dropbox, SFTP, …).
- The unit of identity is the **machine node** — one folder per machine, named uniquely.
- Everything is **pull-based and asynchronous**. A machine that is off simply picks up
  its mail the next time its sync runs. Nothing is lost, nothing blocks.

## Per-machine folder

```
<machine>/
├── capabilities.md   what this machine can do (hand-written)
├── inventory.md      what this machine knows (index; may be generated)
├── last-sync.txt     UTC stamp of its last cycle — its heartbeat
└── inbox/
    └── handled/      requests this machine has completed
```

## The four rules

1. **Read only your own inbox. Write only into others' inboxes** — and only to drop a
   new request at the top level. This is what makes concurrent writes safe.
2. **The owner tidies its own inbox.** A completed request is *moved* to `inbox/handled/`,
   never deleted, never left at the top level. Top level == "not yet done". This is the
   one place a machine writes inside its own inbox, and it's allowed precisely because
   it's the owner.
3. **Ask for actions, not access.** If a task needs a credential you lack, the machine
   that has it performs the action and returns only the result. Secrets never travel.
4. **One author for shared documents.** `PROTOCOL-CHANGES.md` (and any shared canonical
   doc) is edited by a single designated node. Others request an edit via that node's
   inbox. Reason: some transports (e.g. a connector that re-creates the whole file on
   write) can't append safely, so two simultaneous writers would clobber each other.

## Request format

Filename: `YYYY-MM-DD-from-<sender>-short-topic.md`. Body must contain: sender + date;
an expiry ("valid until …"); exactly what is wanted; what "done" means; where to put the
answer. The reply is a new file in the sender's inbox, and it reports what was done and
how it was verified — not merely "done".

## Freshness detection

The sync records the set of top-level inbox files as `name:size` pairs (`inbox.state`).
A file that is new — or a reworked file of the same name but different size — appears in
the diff and raises the flag. Handled files leave the top level (rule 2), so they drop
out of the set and never re-flag. A machine without automation gets the same result for
free: the top level of its inbox is exactly its unhandled requests.

## Delivery: what the sender can and cannot know

There is no delivery receipt on a folder bus. The **only** ack is rule 2: the recipient
moves the request out of the top level of its inbox. That makes the ack observable, but
only to whoever goes and looks — so the sender does two things:

- `send.sh` (and the MCP server's `fleet_send_request`) appends what it sent to
  `state/sent.log`: date · recipient · filename.
- each sync lists the top level of every fleet machine's inbox — a **read**, which rule 1
  permits; it forbids writing there — and rewrites `state/outstanding.tsv` with the sent
  requests still sitting there. `status.sh` and `fleet_status` read that file offline.

A row is marked `pending` when the inbox was read and the request was still in it, and
`unknown` when that inbox could not be listed at all. The distinction matters: a failed
listing that silently read as "picked up" would be exactly the kind of quiet loss this
protocol is trying to avoid.

**Every machine publishes `last-sync.txt` on every cycle**, changed or not — its whole
value is its age. That is what separates *"hasn't got to it yet"* from *"has not run in
nine days"* from *"has never run a cycle at all"* (no `last-sync.txt` on the remote). The
last case is the one a shared folder otherwise hides completely: a recipient that was
never really part of the fleet looks identical to one that is simply busy.

**What this still does not give you.** Not push, not real-time, and no guarantee: the
sender learns a request was never picked up only on its *own* next cycle, and only if it
can reach the remote. If you need delivery guarantees rather than observable state, you
want a broker, not a folder.

## Protocol-change propagation

An established agent won't re-read `00-START-HERE.md`, so rule changes wouldn't reach it.
`PROTOCOL-CHANGES.md` is an append-only changelog at the folder root. Each sync fetches
it and compares its hash to the last seen (`protocol.hash`); on change it raises the same
flag. Each entry is one line: date · author · what changed · which canonical file holds
the full text.

## Exit codes

`sync.sh` returns `0` (quiet), `10` (something new for you), or `1` (error). Schedule it
so that `10` is treated as success (e.g. systemd `SuccessExitStatus=10`), and so a run
missed while the machine was off is caught up (systemd `Persistent=true`, launchd
`StartCalendarInterval`).

## What the sync deliberately does NOT do

It never executes a request and never changes another machine's data. It fetches, flags,
and publishes this machine's own descriptors. The actual work is done by an agent in a
session, after it reads the flag.
