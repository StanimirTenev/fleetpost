from __future__ import annotations

import pytest

from fleetpost_mcp import config as cfgmod


def _write(tmp_path, text):
    path = tmp_path / "config.env"
    path.write_text(text, encoding="utf-8")
    return path


BASE = '''
# a comment
RCLONE_REMOTE="myremote:"
COORD_DIR="agent-coordination"
MACHINE_NAME="laptop"
FLEET="desktop server"
LOCAL_ROOT="$HOME/.agent-coordination"
MEMORY_DIR=""
'''


def test_parses_the_documented_format(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("FLEETPOST_CONFIG", str(_write(tmp_path, BASE)))

    cfg = cfgmod.load()
    assert cfg.remote == "myremote:"
    assert cfg.machine == "laptop"
    assert cfg.fleet == ("desktop", "server")
    assert cfg.remote_root == "myremote:agent-coordination"
    assert cfg.inbox_of("desktop") == "myremote:agent-coordination/desktop/inbox"


def test_expands_home_in_local_root(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", "/home/someone")
    monkeypatch.setenv("FLEETPOST_CONFIG", str(_write(tmp_path, BASE)))
    assert str(cfgmod.load().local_root) == "/home/someone/.agent-coordination"


def test_single_quotes_are_literal(tmp_path, monkeypatch):
    monkeypatch.setenv("FLEETPOST_CONFIG", str(_write(tmp_path, BASE + "\nMACHINE_NAME='$HOME'\n")))
    assert cfgmod.load().machine == "$HOME"


def test_trailing_comment_is_dropped(tmp_path, monkeypatch):
    monkeypatch.setenv("FLEETPOST_CONFIG", str(_write(tmp_path, BASE + "\nMACHINE_NAME=box # the name\n")))
    assert cfgmod.load().machine == "box"


def test_missing_required_field_names_it(tmp_path, monkeypatch):
    text = BASE.replace('MACHINE_NAME="laptop"', "")
    monkeypatch.setenv("FLEETPOST_CONFIG", str(_write(tmp_path, text)))
    with pytest.raises(cfgmod.ConfigError, match="MACHINE_NAME"):
        cfgmod.load()


def test_missing_file_is_reported_clearly(tmp_path, monkeypatch):
    monkeypatch.setenv("FLEETPOST_CONFIG", str(tmp_path / "nope.env"))
    with pytest.raises(cfgmod.ConfigError, match="missing file"):
        cfgmod.load()


def test_home_defaults_to_the_config_directory(tmp_path, monkeypatch):
    monkeypatch.delenv("FLEETPOST_HOME", raising=False)
    monkeypatch.setenv("FLEETPOST_CONFIG", str(_write(tmp_path, BASE)))
    cfg = cfgmod.load()
    assert cfg.home == tmp_path
    assert cfg.script_dir == tmp_path / "scripts"
