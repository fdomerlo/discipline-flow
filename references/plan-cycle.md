# Flow B — Start a plan cycle

## When to reach for a plan instead of just doing the work

Not every task needs this. A plan earns its cost when at least one is true:
the work will span more than one session, more than one person will touch
the diff before it merges, or a mistake here is expensive to unwind. A
one-file fix does not need a `PLAN-N.md` — doing it directly, with a good
commit message, is more disciplined than ceremony for its own sake.

## Step 1 — Interrogate the ambiguity BEFORE writing anything

A plan written on top of unresolved ambiguity looks rigorous and is not.
Before filling the template, scan what the user told you for gaps, and ask
about **at most the three highest-impact ones**. Do not interrogate for
sport: most gaps are better resolved during the work, and asking about
them costs the user's patience without buying safety.

A gap is high-impact if getting it wrong would change the shape of the
phases, not just their content. In practice it is almost always one of:

- **A scope boundary.** Is X part of this cycle or a later one? (Wrong
  guess = a phase built for the wrong target.)
- **A structural decision with more than one defensible answer.** One
  change per phase or one for the whole plan? New module or extend the
  existing one? (Wrong guess = rework, not just edits.)
- **A pre-existing constraint you cannot see.** Is there an existing
  convention, a downstream consumer, a deadline that forces sequencing?

Ask each with **your own recommendation and its reasoning attached**, not
as an open question — the user should be able to answer "yes" / "sí" and move on:

- **EN**: `"I recommend one change per phase because it preserves human audit checkpoints between phases. The alternative (a single diff for the whole plan) is lighter but forfeits intermediate control. Shall we go with the first option?"`
- **ES**: `"Recomiendo un change por fase, porque conserva el gate humano entre fases. La alternativa (uno solo para todo el plan) es más liviana pero pierde ese control intermedio. ¿Vamos con lo primero?"`

If a gap is high-impact and you cannot recommend an answer because the
information genuinely lives only with the user, say exactly that, and
**mark it inside the plan as a `## DECISIÓN ABIERTA` block that the
executor must not pass** — a plan may ship with an open decision as long
as it is flagged as a STOP, never as a silent assumption.

## Step 2 — Fill the template

Read the template from the skill's directory (`<skill-dir>/assets/PLAN.md.template`), or run `scripts/sdd.sh plan "<TITLE>"`:

- **Objective**, one sentence. If you can't compress it to one sentence,
  the scope isn't decided yet — go back to the user before writing phases.
- **Diagnosis / evidence**, if the plan is fixing something concrete —
  what's wrong, how you know (a failing command, a bug report, a
  reproduction), not a guess.
- **Phases (F1, F2, ...)**, each with: what changes, the concrete spec,
  what tests prove it (for bug fixes/regressions: demonstrate RED before
  GREEN by showing the adversarial test fail on current code; for new
  features/refactoring: verify baseline suite is green, add specification
  tests, and verify full green), and acceptance criteria **as numbered checkboxes**
  (`- [ ] CRIT-01: ...`).
  - **Granularity & traceability:** Each phase must define between 2 and 7
    atomic criteria, numbered sequentially (`CRIT-01`, `CRIT-02`, etc.).
    The `CRIT-XX` convention is the formal bridge between the specification
    (`PLAN-N.md`) and the project's test suite: any automated test asserting
    that requirement must include the exact identifier in its name (e.g.
    `test('CRIT-01: ...')` or `def test_crit_01_...()`).
  - **Manual criteria:** If a requirement cannot be checked automatically
    (visual layout, live environment verification), label it explicitly with
    an ID: `- [ ] CRIT-03: (manual) ...`. These are left unticked by the agent
    and handed to the human reviewer at phase close.
- **Out of scope**, explicit. Anything tempting-but-tangential goes here,
  not into a phase "while we're at it." This section prevents more scope
  creep than any other single habit in this skill.

## Step 3 — Self-audit the plan before handing it over

Read-only pass over what you just wrote. Do not hand a plan to the user
without running it:

1. **Coverage & Traceability.** Does every automated acceptance criterion
   have a clear test target matching its `CRIT-XX` identifier? Does every
   manual criterion carry an explicit `(manual)` tag? A criterion nothing
   proves is decoration.
2. **Checkability.** Any criterion that reads like a vibe ("should work
   well", "is cleaner") is a defect — rewrite it as something a command
   can answer, or drop it.
3. **Scope leak.** Is anything from "Out of scope" quietly present in a
   phase body? If yes, either it is in scope (move it) or it is not
   (remove it) — never both.
4. **Phase size.** Can each phase be reviewed as a single diff? If a phase
   only makes sense once a later one lands, they are one phase, not two —
   or the split is in the wrong place.
5. **Dependency order.** Does any phase need something a later phase
   builds?

Report the findings to the user in two or three lines *with* the plan
("revisé el plan: F2 tenía un criterio no verificable, lo reescribí"), not
as a separate ceremony. If a finding needs a decision you can't make,
that's a `## DECISIÓN ABIERTA` block, same as Step 1.

## Step 4 — Hand over, do not execute

Write `PLAN-N.md` to the repo root (or inside a dedicated `plans/` directory
if the project maintains multiple cycles). **Do not start executing a phase in
the same turn the plan is created** — the human reviews the plan itself
first. Never overwrite an existing `PLAN-N.md`: each cycle gets its own
file; completed ones stay in the repo as history (or can be moved to
`plans/archive/` at cycle close).

Ensure the repository is in plan state:
```bash
./scripts/sdd.sh advance plan
```
This activates the `pre-commit` lock protecting against accidental code edits while the plan is under review.

Give the user the session-start prompt to reuse for each phase:

- **EN**: `"Execute Phase F{N} according to PLAN-{N}.md. First run ./scripts/sdd.sh start F{N} to unlock code commits. If ambiguous: STOP and ask. Upon completion, run ./scripts/sdd.sh verify F{N}. Report modified files, the verification table, and deviations — then halt for human diff audit."`
- **ES**: `"Ejecutá la Fase F{N} según PLAN-{N}.md. Primero ejecutá ./scripts/sdd.sh start F{N} para desbloquear commits de código. Si hay ambigüedad: PARÁ y preguntá. Al completar el código, ejecutá ./scripts/sdd.sh verify F{N}. Reportá archivos cambiados, la tabla de verificación y desviaciones — luego detenete, yo audito el diff."`

## The non-negotiable rules (put these in the plan or the AGENTS.md contract,
## not just in this reference — the executor needs to see them, not you)

- One phase = one session = one reviewable diff. Never chain phases in a
  single turn without the human looking at what happened in between.
- Phase activation before code: run `./scripts/sdd.sh start F<N>` before writing code.
- Phase-tagged commits: include the phase identifier (e.g. `feat(F1): ...`) in every commit.
- The plan is the spec. If code and plan disagree, that's a bug in one of
  them — stop and say which, don't silently pick one.
- No new dependencies without explicit approval, ever, mid-phase.
- Ambiguity is a STOP condition, not a coin flip. An agent that guesses
  well on 9 out of 10 ambiguous calls will eventually guess wrong on
  something expensive — the rule exists for the tenth time, not the first
  nine.
- A plan cycle produces a *report* at the end of each phase (files changed,
  tests added with what each one guards against, deviations with
  justification, open questions) — never just a diff with no narration.
  The narration is what makes human audit fast instead of a full re-read.

## What this does not give you

No file here is transactional. `SESSION.md` (see the "Session checkpoint"
clause in `AGENTS.md`) narrows the gap: the next session reads where the
last one stopped, with its base commit checked against the current `HEAD`,
instead of reconstructing everything from `git log` and `git status`
alone. It is still a prose note written by the same agent that did the
work, not a `manifest.json` a program enforces — no locks, no rollback,
no protection against two agents writing it at once. Ticked checkboxes
have the same limit: a convenience, not a guarantee. If a project ever
needs code-enforced, crash-resilient state instead — see "Upgrade path"
in SKILL.md.
