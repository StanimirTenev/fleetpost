"""MCP server: the fleet's mailbox, as agent tools."""

from __future__ import annotations

from typing import Any

from mcp.server.mcpserver import MCPServer

from . import __version__, fleet
from .config import load

mcp = MCPServer("fleetpost", version=__version__)


@mcp.tool()
def fleet_status() -> dict[str, Any]:
    """What is waiting for this machine: unhandled requests in its inbox, whether the
    shared protocol changed, which other machines' capabilities are known, and when the
    last coordination cycle ran. Reads local files only."""
    return fleet.status(load())


@mcp.tool()
def fleet_capabilities(machine: str | None = None) -> dict[str, Any]:
    """What the machines in this fleet can do. Omit `machine` for all of them. Use this
    before asking another machine for something, to check it can actually do it."""
    return fleet.capabilities(load(), machine)


@mcp.tool()
def fleet_read_request(name: str) -> dict[str, Any]:
    """Read one unhandled request from this machine's own inbox, by filename as reported
    by fleet_status."""
    return fleet.read_request(load(), name)


@mcp.tool()
def fleet_send_request(
    to: str,
    topic: str,
    what_is_wanted: str,
    done_means: str,
    valid_until: str,
    reply_to: str | None = None,
) -> dict[str, Any]:
    """Ask another machine in the fleet to do something, by dropping a request in its inbox.

    The machine may be offline; it will pick the request up on its next cycle. Every field
    below is required by the protocol, because a request missing them cannot be acted on.

    Ask for an *action*, not for access: if the task needs a credential this machine lacks,
    the machine that holds it does the work and returns the result. Secrets never travel.

    Args:
        to: Target machine name, as listed by fleet_status.
        topic: Short subject; also becomes part of the filename.
        what_is_wanted: Exactly what should be done.
        done_means: How the other side will know it finished — the acceptance test.
        valid_until: When this stops being worth doing (e.g. "2026-08-20").
        reply_to: Where to put the answer. Defaults to this machine's inbox.
    """
    return fleet.send_request(load(), to, topic, what_is_wanted, done_means, valid_until, reply_to)


@mcp.tool()
def fleet_handle(name: str) -> dict[str, Any]:
    """Mark a request in this machine's own inbox as done, moving it to inbox/handled/.

    Do this only after the work is done and the answer has been sent. A request left at the
    top level counts as still pending and will keep being flagged."""
    return fleet.handle_request(load(), name)


@mcp.tool()
def fleet_sync() -> dict[str, Any]:
    """Run one coordination cycle now: pull this machine's inbox and the fleet's
    capabilities, then publish this machine's own descriptors if they changed.

    Never executes a request and never changes another machine's data."""
    return fleet.sync(load())


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
