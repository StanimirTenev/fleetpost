# Protocol changes (changelog)

This file is a **signal**, not a manual. Each line records one change to the working
rules or protocol. The full text lives in the canonical file (usually
`00-START-HERE.md` or `docs/PROTOCOL.md`) — here it's only "what changed and where to read".

**How it works:** every machine's sync compares this file's hash to the one it last saw.
On change it raises a "the protocol changed" flag. You read it and, if it affects you,
update your behaviour.

**Who writes here.** Only the single designated node (the one with reliable append-capable
write access) edits this file — one author, so two simultaneous writes can't overwrite an
entry. Other machines request an entry via that node's inbox.

**How to add a change:** (1) edit the canonical file; (2) add a new line at the TOP of the
list below, with date, author machine, and one sentence. Never edit old lines — this log
is append-only.

---

<!-- Replace the line below with your first real entry when you make a change.
     Until then it is just an example. -->

## YYYY-MM-DD · from <machine> · <one-line summary of the change>

<One short paragraph: what changed, and which canonical file has the full text.>
