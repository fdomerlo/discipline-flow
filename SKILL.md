---
name: discipline-flow
description: Bootstraps repositories with an AI executor contract (AGENTS.md, conventional commits hook) or scaffolds structured, phased PLAN-N.md cycles with human audit between phases. Trigger when starting a new project, setting up commit conventions, breaking multi-session work into phases, or closing an execution phase.
---

# Discipline Flow

Packages a pattern for working with AI coding agents across multiple
sessions without losing discipline: conventional commits, one phase per
session, human review of every diff before merge, spec-driven development (SDD)
with strict `CRIT-XX` criteria-to-test traceability, and an agent that stops
to ask instead of guessing when a plan is ambiguous.

**Honest scope, read this first.** This is a *prose contract* — conventions
an agent reads and (usually) follows, not code-enforced state. It gives you
maybe 80% of the value of a full transactional workflow engine for a
fraction of the setup. If you need crash-safe state, multi-agent locking,
or a hard approval gate enforced in code rather than in text, that's a
different, heavier tool — see "Upgrade path" below. Say so to the user if
they ask for guarantees this can't give.

## Three entry points

**Before choosing one of these: check for `SESSION.md` at the repo
root.** If it exists, a previous session is resuming — follow its
"Session checkpoint" protocol in `AGENTS.md` first. A resumed session
almost always routes to B (continuing an in-progress phase), never A.

**A — Bootstrap a repo** (new project, or adding discipline to an
existing one). See `references/bootstrap.md`.

**B — Start a plan cycle** (the current task is big enough to need
phases). See `references/plan-cycle.md`.

**C — Close a phase or a cycle** (a phase just finished; or the last
phase did and the cycle needs a closing pass). See
`references/phase-close.md`.

Routing: brand-new repo or "set up commit conventions" → A. A described
piece of multi-step work → B. "Terminé la fase / phase done / what's
left?" with an existing `PLAN-*.md` → C. A and B often chain — bootstrap
first, then start a cycle.

## Before doing any of them, ask once (skip what you can infer)

1. Primary language/stack of the project (for the test-runner line in the
   contract).
2. Chat language: default to mirroring the language the user is writing in
   right now. Code, comments, commit messages, and any file inside the
   project are **always English** regardless of chat language — say this
   explicitly, don't assume the user wants their spoken language in code.
3. For B and C: read every existing `PLAN-*.md` first — the next phase
   number, the out-of-scope list, and the checkbox state are already
   decided there.

Do not turn this into a long interview. Two or three short questions, then
act — same principle the contract itself enforces on the executor.

## Files this skill writes and tools included

- `scripts/verify-crit.sh` — deterministic CLI gate that parses `PLAN-N.md`, enforces 1:1 `CRIT-XX` traceability against test files, executes the test suite, and generates the audit verification table.
- `scripts/init.sh` — automated CLI runner that bootstraps `AGENTS.md`, `CLAUDE.md`, and the git hook in one deterministic step (with safe append for pre-existing contracts).
- `scripts/new-plan.sh` — helper script that scaffolds the next unused `PLAN-N.md` (or `plans/PLAN-N.md`) with title and phase template.
- `AGENTS.md` at repo root (bootstrap) — from `assets/AGENTS.md.template`.
  **Single source of truth**, read natively by OpenCode, Antigravity,
  Codex, Cursor and others. Appended cleanly within managed markers (`<!-- BEGIN DISCIPLINE-FLOW -->`) if an `AGENTS.md` already exists.
- `CLAUDE.md` at repo root — one line: `@AGENTS.md`. Claude Code does not
  read `AGENTS.md` natively; this import is Anthropic's documented pattern
  and, unlike a symlink, works on Windows without special permissions.
  Never fork the contract prose into both files.
- `PLAN-N.md` at repo root (or `plans/`) — from `assets/PLAN.md.template`.
  N = next unused number; follow the repo's existing convention if there
  is one (e.g. `PLAN-2.4` → `PLAN-2.5`), otherwise plain integers from 1.
  Phases define atomic acceptance criteria labeled `CRIT-01`, `CRIT-02`,
  which must be linked 1:1 to automated test names for formal SDD traceability.
- `SESSION.md` at repo root (written at the end of every session, whether
  or not a phase closed) — from `assets/SESSION.md.template`. Read first,
  before anything else, if present at session start. See the "Session
  checkpoint" clause in `AGENTS.md` for the read/write protocol.
- Optional: `scripts/commit-msg-hook.sh` installed as
  `.git/hooks/commit-msg` — the one rule in this skill that can actually
  be enforced in code instead of prose, so it is. Offer it, don't force it.

## Upgrade path

When a project outgrows a prose contract — state must survive a crash
mid-phase, or approval must be enforced in code rather than trusted —
an external transactional workflow engine (such as `context-guard`) can
materialise `PLAN-N.md` as code-enforced changes. The plan format this skill
writes is designed to serve directly as structured input without manual
rewriting.

Full templates and detailed reference manuals are located inside this skill's
directory (under `assets/` and `references/`) — read the relevant reference
file before writing anything, don't improvise the contract from memory.
