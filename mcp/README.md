# fleetpost-mcp

<!-- mcp-name: io.github.StanimirTenev/fleetpost-mcp -->

**Give your agent the fleet's mailbox.** An MCP server for
[Fleetpost](https://github.com/StanimirTenev/fleetpost) — offline-tolerant, server-less
coordination between machines over any rclone remote.

Your agent can ask what the other machines can do, hand one of them a task, and work through
its own inbox — without a server, a daemon, or every machine being online at once. A machine
that is off picks up its mail on its next cycle.

## Tools

| Tool | What it does |
| --- | --- |
| `fleet_status` | What is waiting: unhandled requests, protocol changes, who is known, last cycle |
| `fleet_capabilities` | What each machine in the fleet can do |
| `fleet_read_request` | Read one request from this machine's inbox |
| `fleet_send_request` | Ask another machine to do something — drops a request in its inbox |
| `fleet_handle` | Mark a request done; moves it to `inbox/handled/` |
| `fleet_sync` | Run one coordination cycle now |

Only `fleet_send_request` and `fleet_sync` touch the remote. Everything else reads files the
sync already pulled, so status is instant and works with no network at all.

## Setup

You need a working Fleetpost checkout with a filled-in `config.env` — see the
[main README](https://github.com/StanimirTenev/fleetpost). The MCP server reads that same
file; it introduces no configuration of its own.

```json
{
  "mcpServers": {
    "fleetpost": {
      "command": "uvx",
      "args": ["fleetpost-mcp"],
      "env": {
        "FLEETPOST_CONFIG": "/path/to/fleetpost/config.env"
      }
    }
  }
}
```

`FLEETPOST_CONFIG` can be omitted if the server starts in the directory holding `config.env`.
If you copied the config away from the checkout, also set `FLEETPOST_HOME` to the checkout —
`fleet_sync` and `fleet_handle` run the repo's own scripts.

Then ask your agent:

> Anything waiting for me? — and if the build box can sign, ask it to sign the release.

## What it will not do

The protocol's rules are enforced here, not just documented:

- **Writes only into another machine's inbox, at the top level.** Never into `handled/`,
  never into anyone's descriptors. That is what keeps concurrent writes safe.
- **`fleet_handle` only tidies your own inbox** — the owner is the only one allowed to.
- **A request must be complete to be sent.** What is wanted, what "done" means, and an
  expiry are required arguments; a malformed request cannot be created.
- **Ask for actions, not access.** If a job needs a credential you lack, the machine that
  has it does the work and returns the result. Secrets never travel.

There is no server, no database, and no daemon of our own — the transport stays a folder on
an rclone remote, and this server only reads and writes files in it.

## License

MIT.
