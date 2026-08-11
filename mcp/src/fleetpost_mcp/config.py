"""Read the same `config.env` the shell scripts read.

Parsed, not sourced: the file is documented as plain `VAR="value"` assignments, and an
MCP server should not execute its configuration.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from pathlib import Path

_ASSIGN = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$")


class ConfigError(RuntimeError):
    pass


def _strip_value(raw: str) -> str:
    value = raw.strip()
    # Drop a trailing unquoted comment before unquoting.
    if not value.startswith(("'", '"')):
        value = value.split(" #", 1)[0].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        quote, value = value[0], value[1:-1]
        if quote == "'":
            return value  # single quotes are literal in shell
    return os.path.expandvars(value)


def _parse(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = _ASSIGN.match(line)
        if match:
            values[match.group(1)] = _strip_value(match.group(2))
    return values


def _find_config() -> Path:
    explicit = os.environ.get("FLEETPOST_CONFIG")
    if explicit:
        path = Path(explicit).expanduser()
        if not path.is_file():
            raise ConfigError(f"FLEETPOST_CONFIG points at a missing file: {path}")
        return path

    for candidate in (Path.cwd() / "config.env", Path.home() / ".fleetpost" / "config.env"):
        if candidate.is_file():
            return candidate

    raise ConfigError(
        "no config.env found. Set FLEETPOST_CONFIG to your Fleetpost config.env, "
        "or run the server from the checkout that contains it."
    )


@dataclass(frozen=True)
class Config:
    path: Path
    remote: str
    coord_dir: str
    machine: str
    fleet: tuple[str, ...]
    local_root: Path
    home: Path

    @property
    def remote_root(self) -> str:
        return f"{self.remote}{self.coord_dir}"

    def inbox_of(self, machine: str) -> str:
        return f"{self.remote_root}/{machine}/inbox"

    @property
    def script_dir(self) -> Path:
        return self.home / "scripts"


def load() -> Config:
    path = _find_config()
    values = _parse(path)

    missing = [k for k in ("RCLONE_REMOTE", "COORD_DIR", "MACHINE_NAME", "LOCAL_ROOT")
               if not values.get(k)]
    if missing:
        raise ConfigError(f"{path} is missing: {', '.join(missing)}")

    # The scripts live next to config.env in a checkout; allow an override for the case
    # where the config was copied elsewhere.
    home = Path(os.environ.get("FLEETPOST_HOME", path.parent)).expanduser()

    return Config(
        path=path,
        remote=values["RCLONE_REMOTE"],
        coord_dir=values["COORD_DIR"],
        machine=values["MACHINE_NAME"],
        fleet=tuple(values.get("FLEET", "").split()),
        local_root=Path(values["LOCAL_ROOT"]).expanduser(),
        home=home,
    )
