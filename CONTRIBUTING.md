# Contributing to Fleetpost

Thanks for looking. Fleetpost is intentionally small — shell + rclone + a scheduler —
and the goal is to keep it that way.

## Principles (please don't break these)

- **No server, no daemon, no database, no language runtime.** The moment we add one,
  Fleetpost stops being what it is. Bash + rclone only.
- **The scripts change nothing on another machine's data.** They fetch, flag, and publish
  this machine's own descriptors. Executing requests is the agent's job, not the sync's.
- **Secrets never travel.** Descriptors and requests carry tasks and results, never
  credentials. See `docs/PROTOCOL.md`.

## Before you open a PR

- Keep it dependency-free and POSIX-friendly where practical (Bash 4+ is assumed for
  associative arrays; note it if you rely on more).
- Run `bash -n scripts/*.sh` and, if you have it, `shellcheck scripts/*.sh`.
- If you change the protocol or a shared convention, update `docs/PROTOCOL.md` **and**
  the `00-START-HERE.md` template, and add a line to `PROTOCOL-CHANGES.md`.

## Good first contributions

See `docs/ROADMAP.md`. High-value, well-scoped items: a `launchd` example for macOS, a
PowerShell `sync.ps1` for Windows, and the `init` / `doctor` setup helpers.

## Reporting

Issues describing a real multi-machine setup — especially one the design didn't
anticipate — are the most useful thing you can file.
