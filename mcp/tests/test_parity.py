"""send.sh and fleet_send_request must produce byte-identical requests.

There are deliberately two implementations — the shell one for people without an agent,
the Python one so the MCP works from a config alone. That is the only duplication of the
protocol in the project, and this test is what keeps it from drifting.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

from fleetpost_mcp import fleet
from fleetpost_mcp.config import Config

REPO = Path(__file__).resolve().parents[2]
SEND_SH = REPO / "scripts" / "send.sh"

needs_fleet = pytest.mark.skipif(
    shutil.which("rclone") is None or not SEND_SH.is_file(),
    reason="needs rclone and a Fleetpost checkout (scripts/send.sh)",
)

TOPIC = "Подпиши инсталатора за v0.5"
WANT = "Sign dist/app.exe with the company certificate."
DONE = "signtool verify /pa passes on the uploaded file."
UNTIL = "2026-09-01"


@needs_fleet
def test_shell_and_mcp_write_the_same_request(tmp_path):
    for machine in ("laptop", "desktop", "build"):
        (tmp_path / "remote" / "coord" / machine / "inbox").mkdir(parents=True)

    config_path = tmp_path / "config.env"
    config_path.write_text(
        f'RCLONE_REMOTE="{tmp_path}/remote/"\n'
        f'COORD_DIR="coord"\n'
        f'MACHINE_NAME="laptop"\n'
        f'FLEET="desktop build"\n'
        f'LOCAL_ROOT="{tmp_path}/laptop-root"\n',
        encoding="utf-8",
    )
    cfg = Config(
        path=config_path, remote=f"{tmp_path}/remote/", coord_dir="coord",
        machine="laptop", fleet=("desktop", "build"),
        local_root=tmp_path / "laptop-root", home=REPO,
    )

    fleet.send_request(cfg, "desktop", TOPIC, WANT, DONE, UNTIL)

    result = subprocess.run(
        ["bash", str(SEND_SH), "--to", "build", "--topic", TOPIC,
         "--want", WANT, "--done", DONE, "--until", UNTIL],
        capture_output=True, text=True, timeout=300,
        env={"CONFIG": str(config_path), "PATH": "/usr/bin:/bin:/usr/local/bin",
             "HOME": str(Path.home()), "LANG": "C.UTF-8"},
    )
    assert result.returncode == 0, result.stderr

    def only_file(machine: str) -> Path:
        files = list((tmp_path / "remote" / "coord" / machine / "inbox").iterdir())
        assert len(files) == 1, files
        return files[0]

    from_mcp, from_shell = only_file("desktop"), only_file("build")

    # Same slug from the same topic, including the Cyrillic.
    assert from_mcp.name == from_shell.name
    assert "подпиши-инсталатора-за-v0-5" in from_mcp.name

    assert from_mcp.read_bytes() == from_shell.read_bytes()
