"""Fleet behaviour, including a real two-machine cycle over a local rclone remote."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

from fleetpost_mcp import fleet
from fleetpost_mcp.config import Config

REPO = Path(__file__).resolve().parents[2]

# The end-to-end tests drive the repo's own sync.sh, so they need a checkout (an sdist
# unpacked on its own has no scripts/) and rclone.
needs_fleet = pytest.mark.skipif(
    shutil.which("rclone") is None or not (REPO / "scripts" / "sync.sh").is_file(),
    reason="needs rclone and a Fleetpost checkout (scripts/sync.sh)",
)


def _cfg(tmp_path: Path, machine: str = "laptop", others=("desktop",)) -> Config:
    return Config(
        path=tmp_path / "config.env",
        remote=f"{tmp_path}/remote/",
        coord_dir="coord",
        machine=machine,
        fleet=tuple(others),
        local_root=tmp_path / f"{machine}-root",
        home=REPO,
    )


# ── guards ───────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("name", ["../secrets.env", "a/b.md", "..", ".hidden", "", "x\x00y"])
def test_request_names_that_are_not_plain_filenames_are_refused(tmp_path, name):
    with pytest.raises(fleet.FleetError):
        fleet.read_request(_cfg(tmp_path), name)


def test_cannot_send_to_this_machine(tmp_path):
    with pytest.raises(fleet.FleetError, match="this machine"):
        fleet.send_request(_cfg(tmp_path), "laptop", "t", "w", "d", "2026-09-01")


def test_cannot_send_to_a_machine_outside_the_fleet(tmp_path):
    with pytest.raises(fleet.FleetError, match="unknown machine"):
        fleet.send_request(_cfg(tmp_path), "mars", "t", "w", "d", "2026-09-01")


@pytest.mark.parametrize("field", ["what_is_wanted", "done_means", "valid_until"])
def test_the_protocol_required_fields_cannot_be_blank(tmp_path, field):
    args = {"what_is_wanted": "w", "done_means": "d", "valid_until": "2026-09-01"}
    args[field] = "   "
    with pytest.raises(fleet.FleetError, match=field):
        fleet.send_request(_cfg(tmp_path), "desktop", "topic", **args)


def test_a_topic_in_cyrillic_survives_into_the_filename():
    assert fleet._slug("Подпиши инсталатора") == "подпиши-инсталатора"


def test_a_topic_with_no_letters_or_digits_is_refused():
    with pytest.raises(fleet.FleetError):
        fleet._slug("!!! ---")


# ── the real cycle ───────────────────────────────────────────────────────────

def _write_config(tmp_path: Path, machine: str, other: str) -> Path:
    path = tmp_path / f"config-{machine}.env"
    path.write_text(
        f'RCLONE_REMOTE="{tmp_path}/remote/"\n'
        f'COORD_DIR="coord"\n'
        f'MACHINE_NAME="{machine}"\n'
        f'FLEET="{other}"\n'
        f'LOCAL_ROOT="{tmp_path}/{machine}-root"\n',
        encoding="utf-8",
    )
    return path


def _sync(config_path: Path) -> int:
    result = subprocess.run(
        ["bash", str(REPO / "scripts" / "sync.sh")],
        capture_output=True, text=True, timeout=300,
        env={"CONFIG": str(config_path), "PATH": "/usr/bin:/bin:/usr/local/bin",
             "HOME": str(Path.home())},
    )
    assert result.returncode in (0, 10), result.stderr
    return result.returncode


@needs_fleet
def test_a_request_travels_is_flagged_handled_and_never_reflagged(tmp_path):
    for machine in ("laptop", "desktop"):
        (tmp_path / "remote" / "coord" / machine / "inbox").mkdir(parents=True)
        (tmp_path / f"{machine}-root" / "self").mkdir(parents=True)
        (tmp_path / f"{machine}-root" / "self" / "capabilities.md").write_text(
            f"{machine} can do {machine} things\n", encoding="utf-8")

    laptop_cfg_path = _write_config(tmp_path, "laptop", "desktop")
    desktop_cfg_path = _write_config(tmp_path, "desktop", "laptop")
    _sync(laptop_cfg_path)
    _sync(desktop_cfg_path)

    laptop = _cfg(tmp_path, "laptop", ("desktop",))
    desktop = _cfg(tmp_path, "desktop", ("laptop",))
    object.__setattr__(laptop, "path", laptop_cfg_path)
    object.__setattr__(desktop, "path", desktop_cfg_path)

    # laptop asks desktop for something
    sent = fleet.send_request(
        laptop, "desktop", "sign the installer",
        what_is_wanted="sign dist/app.exe", done_means="signtool verify passes",
        valid_until="2026-09-01",
    )
    assert sent["filename"].startswith("20") and "from-laptop" in sent["filename"]

    # desktop notices it
    assert _sync(desktop_cfg_path) == 10
    status = fleet.status(desktop)
    assert status["signal_raised"] is True
    assert [r["name"] for r in status["pending_requests"]] == [sent["filename"]]

    body = fleet.read_request(desktop, sent["filename"])["body"]
    assert "signtool verify passes" in body and "Valid until" in body

    # desktop finishes it
    handled = fleet.handle_request(desktop, sent["filename"])
    assert handled["signal_cleared"] is True
    assert fleet.status(desktop)["pending_requests"] == []

    # and it never comes back
    assert _sync(desktop_cfg_path) == 0
    assert fleet.status(desktop)["signal_raised"] is False
    assert (tmp_path / "remote" / "coord" / "desktop" / "inbox" / "handled" / sent["filename"]).is_file()


@needs_fleet
def test_capabilities_are_readable_after_a_cycle(tmp_path):
    for machine in ("laptop", "desktop"):
        (tmp_path / "remote" / "coord" / machine / "inbox").mkdir(parents=True)
        (tmp_path / f"{machine}-root" / "self").mkdir(parents=True)
        (tmp_path / f"{machine}-root" / "self" / "capabilities.md").write_text(
            f"{machine}: has a signing key\n", encoding="utf-8")

    _sync(_write_config(tmp_path, "desktop", "laptop"))
    _sync(_write_config(tmp_path, "laptop", "desktop"))

    laptop = _cfg(tmp_path, "laptop", ("desktop",))
    assert "signing key" in fleet.capabilities(laptop, "desktop")["capabilities"]

    with pytest.raises(fleet.FleetError, match="unknown machine"):
        fleet.capabilities(laptop, "mars")


@needs_fleet
def test_the_sender_sees_a_request_that_was_never_picked_up(tmp_path):
    """The gap this closes: on a folder bus nothing reports back, so an unhandled request
    and a handled one look identical to the sender unless the sync goes and looks."""
    for machine in ("laptop", "desktop"):
        (tmp_path / "remote" / "coord" / machine / "inbox").mkdir(parents=True)
        (tmp_path / f"{machine}-root" / "self").mkdir(parents=True)
        (tmp_path / f"{machine}-root" / "self" / "capabilities.md").write_text(
            f"{machine} can do {machine} things\n", encoding="utf-8")

    laptop_cfg_path = _write_config(tmp_path, "laptop", "desktop")
    desktop_cfg_path = _write_config(tmp_path, "desktop", "laptop")
    laptop = _cfg(tmp_path, "laptop", ("desktop",))
    desktop = _cfg(tmp_path, "desktop", ("laptop",))
    object.__setattr__(laptop, "path", laptop_cfg_path)
    object.__setattr__(desktop, "path", desktop_cfg_path)

    _sync(laptop_cfg_path)
    # desktop has not run a cycle yet: no heartbeat, and the laptop can say so.
    assert fleet.status(laptop)["fleet"][0]["last_cycle"] is None

    sent = fleet.send_request(
        laptop, "desktop", "sign the installer",
        what_is_wanted="sign dist/app.exe", done_means="signtool verify passes",
        valid_until="2026-09-01",
    )

    _sync(laptop_cfg_path)
    outstanding = fleet.status(laptop)["outstanding_sends"]
    assert [(r["name"], r["to"], r["state"]) for r in outstanding] == [
        (sent["filename"], "desktop", "pending")]
    # and it is distinguishable from "hasn't got to it yet": desktop has never synced.
    assert outstanding[0]["recipient_last_cycle"] is None

    # desktop wakes up, runs a cycle, and picks the request up
    _sync(desktop_cfg_path)
    fleet.handle_request(desktop, sent["filename"])

    _sync(laptop_cfg_path)
    laptop_status = fleet.status(laptop)
    assert laptop_status["outstanding_sends"] == []
    assert laptop_status["fleet"][0]["last_cycle"] is not None


@needs_fleet
def test_an_unreadable_inbox_is_reported_as_unknown_not_as_picked_up(tmp_path):
    """A failed listing must never read as an ack — that is the silent-loss class of bug."""
    for machine in ("laptop", "desktop"):
        (tmp_path / "remote" / "coord" / machine / "inbox").mkdir(parents=True)
        (tmp_path / f"{machine}-root" / "self").mkdir(parents=True)
        (tmp_path / f"{machine}-root" / "self" / "capabilities.md").write_text(
            f"{machine}\n", encoding="utf-8")

    laptop_cfg_path = _write_config(tmp_path, "laptop", "desktop")
    laptop = _cfg(tmp_path, "laptop", ("desktop",))
    object.__setattr__(laptop, "path", laptop_cfg_path)

    sent = fleet.send_request(
        laptop, "desktop", "sign it", what_is_wanted="w", done_means="d",
        valid_until="2026-09-01",
    )
    _sync(laptop_cfg_path)
    assert fleet.status(laptop)["outstanding_sends"][0]["state"] == "pending"

    # the recipient's inbox becomes unreachable (folder gone, remote down — same effect)
    shutil.rmtree(tmp_path / "remote" / "coord" / "desktop")
    _sync(laptop_cfg_path)
    still = fleet.status(laptop)["outstanding_sends"]
    assert [(r["name"], r["state"]) for r in still] == [(sent["filename"], "unknown")]
