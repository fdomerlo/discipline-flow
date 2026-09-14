# Flow C — Close a phase, or close a cycle

Two related jobs. Read the whole file: the phase close is the common one,
the cycle close runs once at the end and catches what the phase closes
could not see.

---

## C1 — Closing a phase

Runs when a phase's work is done, **before** anyone starts the next one.

### 1. Deterministic Verification Gate (Mandatory)

Before writing any report or updating state, you MUST run the verification gate:

```bash
./scripts/sdd.sh verify F<N>
# or directly: scripts/verify-crit.sh PLAN-N.md F<N>
```

* If the verification exits with non-zero (missing `CRIT-XX` test or failing suite), **STOP immediately**. Fix the test implementation; do not attempt to bypass or explain away the failure.
* The script output is your ground truth: copy the generated Markdown criteria table directly into your phase report.
* `sdd.sh verify` automatically advances `sdd_state` to `verify` upon success.

### 2. Tick the boxes — strictly backed by script proof

Only after the script exits with `0`:

* Mark `- [ ]` → `- [x]` in `PLAN-N.md` for automated criteria confirmed by `verify-crit.sh`.
* Leave `(manual)` criteria as `- [ ]` for human verification.

### 3. Write the phase report

Immediately below the ticked criteria or in chat:

* **Criteria demonstration table:** Embed the exact table output produced by `verify-crit.sh`.
* **Files changed:** Table format.
* **Tests added & defense:** State the exact attack or regression each test guards against.
* **Deviations from plan:** Any architectural or scope deviations with rationale.
* **Open questions:** Pending decisions for the human.

### 4. Refresh checkpoint & STOP

Rewrite `SESSION.md`:

* `Status: phase-closed, awaiting human audit`
* `Next action`: what starts after human approval.
* `Human review: pending`

**STOP.** Do not start the next phase. The human audits the git diff and reviews the report first.

---

## C2 — Closing a cycle

Runs after the last phase, or whenever the user asks "what's left?".
This is the pass that catches drift between what the plan said and what
the repo actually became.

1. **Unticked boxes.** List every criterion still `- [ ]` across all
   phases, with which phase it belongs to. For each: is it genuinely not
   done, done-but-unverifiable-by-you, or obsolete because the design
   changed mid-cycle? Say which — a stale unticked box is as misleading as
   a wrongly ticked one.
2. **Reality vs. plan.** Read the actual diff of the cycle (`git log`,
   `git diff` against the branch point). Is there anything in the repo
   that no phase asked for? Anything a phase asked for that is not in the
   repo? Both are findings, and the second one is the reason this pass
   exists.
3. **Scope leaks.** Did anything from "Out of scope" get built anyway?
   Name it. That is not necessarily wrong — but it must be a decision, not
   a discovery six weeks later.
4. **Leftovers.** Everything real that remains — unbuilt work, follow-ups
   discovered along the way, deferred decisions — gets written down where
   the user actually keeps things, in this order of preference: an
   existing `BACKLOG.md`, a new section at the end of the plan, or issues
   if the project uses them. Ask which if it is not obvious. **Do not
   silently open a new `PLAN-N+1.md`** — starting the next cycle is the
   user's decision, not the closing report's.
5. **The honest verdict, in two or three lines.** Did this cycle do what
   it set out to do? If not, what part, and was it because the plan was
   wrong or because the work was harder than it looked? Both answers are
   useful; only the vague one ("mostly done, some follow-ups") is not.

A cycle close never modifies code. It reads, ticks nothing new by itself
beyond what C1 already justified, and reports.
