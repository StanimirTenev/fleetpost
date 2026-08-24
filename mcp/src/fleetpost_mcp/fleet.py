"""Fleet operations, on top of the same folder layout and scripts the protocol defines.

Reads come straight from what the sync already pulled locally. The two actions that touch
the remote (`handle`, `sync`) shell out to the repo's own scripts, so there is exactly one
implementation of each. `send` writes a request into another machine's inbox -- the only
write this server makes, and the only place the anti-collision rules need enforcing.
"""

from __future__ import annotations

import hashlib
import re
import subprocess
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

from .config import Config

_SAFE_NAME = re.compile(r"^[^/\\\x00]+$")
# Keep letters and digits in any script -- an ASCII-only slug silently erases a topic
# written in Cyrillic, Greek or CJK and leaves a filename nobody can recognise.
_SLUG_STRIP = re.compile(r"[^\w]+", re.UNICODE)


class FleetError(RuntimeError):
    pass


def _checked_name(name: str) -> str:
    """A request filename, never a path."""
    if not name or not _SAFE_NAME.match(name) or name.startswith("."):
        raise FleetError(
            f"invalid request name {name!r}: expected a plain filename from your inbox"
        )
    return name


def _slug(topic: str) -> str:
    slug = _SLUG_STRIP.sub("-", topic.strip().lower()).strip("-")
    if not slug:
        raise FleetError("topic must contain at least one letter or digit")
    return slug[:60]


def _mtime(path: Path) -> str | None:
    if not path.exists():
        return None
    return datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat(timespec="seconds")


def _pending(cfg: Config) -> list[dict[str, Any]]:
    inbox = cfg.local_root / "inbox"
    if not inbox.is_dir():
        return []
    items = []
    for path in sorted(inbox.iterdir()):
        if path.is_file() and not path.name.startswith(".keep"):
            items.append({"name": path.name, "bytes": path.stat().st_size, "modified": _mtime(path)})
    return items


def _protocol_change_pending(cfg: Config) -> bool:
    doc = cfg.local_root / "PROTOCOL-CHANGES.md"
    if not doc.is_file():
        return False
    current = hashlib.sha256(doc.read_bytes()).hexdigest()
    ack_file = cfg.local_root / "state" / "protocol.ack"
    ack = ack_file.read_text(encoding="utf-8").strip() if ack_file.is_file() else ""
    return current != ack


def _heartbeat(cfg: Config, machine: str) -> str | None:
    """When that machine last ran a cycle, as it published it. None = never ran one."""
    path = cfg.local_root / "fleet" / machine / "last-sync.txt"
    return path.read_text(encoding="utf-8").strip() if path.is_file() else None


def _outstanding(cfg: Config) -> list[dict[str, Any]]:
    """Requests this machine sent that are still at the top level of the recipient's inbox.

    Derived by the last sync, not by looking at the remote now, so this stays offline.
    `state` is "pending" (seen unhandled) or "unknown" (that inbox was unreadable then).
    """
    path = cfg.local_root / "state" / "outstanding.tsv"
    if not path.is_file():
        return []
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        to, name, sent_on, state = parts[:4]
        rows.append({
            "to": to,
            "name": name,
            "sent_on": sent_on,
            "state": state,
            "recipient_last_cycle": _heartbeat(cfg, to),
        })
    return rows


def status(cfg: Config) -> dict[str, Any]:
    signal = cfg.local_root / "SIGNAL.md"
    known = []
    for machine in cfg.fleet:
        descriptor = cfg.local_root / "fleet" / machine / "capabilities.md"
        known.append({
            "machine": machine,
            "capabilities_known": descriptor.is_file(),
            "last_updated": _mtime(descriptor),
            "last_cycle": _heartbeat(cfg, machine),
        })

    return {
        "machine": cfg.machine,
        "config": str(cfg.path),
        "signal_raised": signal.is_file(),
        "pending_requests": _pending(cfg),
        "outstanding_sends": _outstanding(cfg),
        "protocol_change_pending": _protocol_change_pending(cfg),
        "fleet": known,
        "last_sync": _mtime(cfg.local_root / "state" / "inbox.state"),
    }


def capabilities(cfg: Config, machine: str | None = None) -> dict[str, Any]:
    def read(path: Path) -> str | None:
        return path.read_text(encoding="utf-8") if path.is_file() else None

    if machine is None:
        out = {m: read(cfg.local_root / "fleet" / m / "capabilities.md") for m in cfg.fleet}
        out[cfg.machine] = read(cfg.local_root / "self" / "capabilities.md")
        return {"capabilities": out}

    if machine == cfg.machine:
        text = read(cfg.local_root / "self" / "capabilities.md")
    elif machine in cfg.fleet:
        text = read(cfg.local_root / "fleet" / machine / "capabilities.md")
    else:
        raise FleetError(f"unknown machine {machine!r}; fleet is: {', '.join(cfg.fleet) or '(empty)'}")

    if text is None:
        raise FleetError(f"no capabilities descriptor pulled for {machine!r} yet — run fleet_sync")
    return {"machine": machine, "capabilities": text}


def read_request(cfg: Config, name: str) -> dict[str, Any]:
    path = cfg.local_root / "inbox" / _checked_name(name)
    if not path.is_file():
        raise FleetError(f"{name!r} is not in your inbox; call fleet_status for what is pending")
    return {"name": name, "body": path.read_text(encoding="utf-8")}


def send_request(
    cfg: Config,
    to: str,
    topic: str,
    what_is_wanted: str,
    done_means: str,
    valid_until: str,
    reply_to: str | None = None,
) -> dict[str, Any]:
    """Drop a well-formed request at the top level of another machine's inbox.

    Rule 1 of the protocol: write only into others' inboxes, only at the top level.
    """
    if to == cfg.machine:
        raise FleetError("that is this machine — send to another node")
    if to not in cfg.fleet:
        raise FleetError(f"unknown machine {to!r}; fleet is: {', '.join(cfg.fleet) or '(empty)'}")
    for field, value in (("what_is_wanted", what_is_wanted), ("done_means", done_means),
                         ("valid_until", valid_until)):
        if not value.strip():
            raise FleetError(f"{field} is required by the protocol and cannot be empty")

    today = date.today().isoformat()
    filename = f"{today}-from-{cfg.machine}-{_slug(topic)}.md"
    answer_to = reply_to or f"{cfg.machine}/inbox/"

    body = (
        f"# {topic.strip()}\n\n"
        f"**From:** {cfg.machine}  \n"
        f"**Date:** {today}  \n"
        f"**Valid until:** {valid_until.strip()}\n\n"
        f"## What I want\n\n{what_is_wanted.strip()}\n\n"
        f"## What \"done\" means\n\n{done_means.strip()}\n\n"
        f"## Where to put the answer\n\n"
        f"A new file in `{answer_to}` reporting what was done **and how it was verified** —\n"
        f"not merely \"done\".\n"
    )

    target = f"{cfg.inbox_of(to)}/{filename}"
    result = subprocess.run(
        ["rclone", "rcat", target],
        input=body.encode("utf-8"),
        capture_output=True,
        timeout=180,
    )
    if result.returncode != 0:
        raise FleetError(f"rclone could not write the request: {result.stderr.decode().strip()}")

    # Same record send.sh keeps: the only ack on a folder bus is the recipient moving the
    # file into its handled/, and that is only meaningful against a list of what was sent.
    log = cfg.local_root / "state" / "sent.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("a", encoding="utf-8") as fh:
        fh.write(f"{today}\t{to}\t{filename}\n")

    return {"sent_to": to, "filename": filename, "remote_path": target, "body": body}


def _run_script(cfg: Config, script: str, args: list[str], timeout: int) -> subprocess.CompletedProcess:
    path = cfg.script_dir / script
    if not path.is_file():
        raise FleetError(
            f"{script} not found at {path}. Set FLEETPOST_HOME to your Fleetpost checkout."
        )
    return subprocess.run(
        ["bash", str(path), *args],
        capture_output=True,
        text=True,
        timeout=timeout,
        env={"CONFIG": str(cfg.path), "PATH": "/usr/bin:/bin:/usr/local/bin", "HOME": str(Path.home())},
    )


def handle_request(cfg: Config, name: str) -> dict[str, Any]:
    """Move a completed request into your own inbox/handled/ (protocol rule 2)."""
    name = _checked_name(name)
    result = _run_script(cfg, "handle.sh", [name], timeout=180)
    if result.returncode != 0:
        raise FleetError(f"handle.sh failed: {(result.stderr or result.stdout).strip()}")

    local_copy = cfg.local_root / "inbox" / name
    if local_copy.is_file():
        local_copy.unlink()  # the next sync would drop it anyway; keep status honest now

    # Clear the flag once nothing is left waiting. Deliberately NOT cleared while a protocol
    # change is pending: sync.sh acknowledges the changelog hash when it finds the flag gone,
    # so clearing early would silently swallow the notice.
    signal = cfg.local_root / "SIGNAL.md"
    cleared = False
    if signal.is_file() and not _pending(cfg) and not _protocol_change_pending(cfg):
        signal.unlink()
        cleared = True

    return {"handled": name, "output": result.stdout.strip(), "signal_cleared": cleared}


def sync(cfg: Config) -> dict[str, Any]:
    """Run one coordination cycle. Exit 10 means something new arrived; it is not an error."""
    result = _run_script(cfg, "sync.sh", [], timeout=600)
    if result.returncode not in (0, 10):
        raise FleetError(f"sync.sh failed: {(result.stderr or result.stdout).strip()}")
    return {
        "something_new": result.returncode == 10,
        "log": result.stdout.strip(),
        "status": status(cfg),
    }
