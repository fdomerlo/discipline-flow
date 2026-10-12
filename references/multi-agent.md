# Multi-agent protocol

Two agents must never write the same phase. Files cannot lock (see
"Upgrade Path" in `SKILL.md`), so parallelism here is coordination plus
audit, not mutual exclusion. The moment two agents touch `SESSION.md` at
once, the checkpoint is suspect — stop and let the human arbitrate.

## Rules

1. **One agent = one phase.** `F1` belongs to exactly one agent at a time.
   The other agent takes a different phase (`F2`) or waits for the human
   audit at phase close.
2. **Claim before code.** Start with your name so the claim is on record:
   ```bash
   ./scripts/sdd.sh start F1 alice
   ```
   Starting without a name releases the claim (`active_agent: none`).
   Re-claiming a phase owned by someone else prints a warning and proceeds —
   the warning is the audit trail, not a lock. If you did not mean to take
   it over, stop and ask the human.
3. **Branch per phase.** Each agent works on its own branch:
   ```bash
   git checkout -b feat/F1-descripcion-corta
   ```
   Merge only after the human audits each phase diff separately. Never push
   two phases in one branch, and never rebase someone else's phase branch.
4. **One SESSION.md writer per phase.** The agent owning the active phase is
   the only one who runs `sdd.sh start/verify`. The other agent may read
   `SESSION.md` and the plan, but must not mutate state.
5. **Conflict markers = full stop.** If `git` reports a conflict in
   `SESSION.md` (or its `Base commit` is not an ancestor of your `HEAD`),
   do not resolve it by guessing. Report both versions to the human and
   wait — a wrongly merged checkpoint silently invalidates every later
   gate (`plan_hash`, bypass audit, phase scope).

## Why no hard lock

An atomic claim would need a daemon, a distributed lock, or a database —
all explicitly out of scope for this zero-dependency harness. The claim
record (`active_agent`), the conflict warning, and the per-phase branches
make collisions visible and recoverable, which is the most a Bash + Git
harness can honestly promise.
