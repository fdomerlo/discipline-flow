---
name: discipline-flow
description: Enforces a deterministic Spec-Driven Development (SDD) workflow via programmatic Python workflows (`run_workflow`), JSON Schema contracts, and OS-level Git hooks. Use when implementing features, fixing bugs, or modifying software in a repository governed by Discipline Flow.
license: MIT
metadata:
  author: fdomerlo
  version: 2.0.0
---

# Operational Contract: Programmatic SDD Gatekeeper (Discipline-Flow)

## Unbreakable Language & Code Rule
- **Human-facing outputs (`PLAN-*.md`, `SESSION.md` body, chat, audit tables, closure reports):** **SPANISH**.
- **Code, comments, error messages, commit messages, and test identifiers:** **ENGLISH**.

## Deterministic Architecture (Zero-Prose Overhead)
Instead of loading ~100 KB of prose manuals into the context window, Discipline-Flow enforces Spec-Driven Development, Doubt-Driven Development, TDD (Red-Green-Refactor), Multi-Agent isolation, Security checks, and Phase/Cycle closure **programmatically** through two layers:
1. **OS/Git Layer (`<skill-path>/scripts/`):** `sdd.sh`, `verify-crit.sh`, `pre-commit-hook.sh`, and `commit-msg-hook.sh` guard `SESSION.md` YAML state and block unauthorized commits. **Never hand-edit `SESSION.md` YAML frontmatter.**
2. **Orchestration Layer (`<skill-path>/workflows/` via `run_workflow`):** Self-contained Python workflows enforce JSON Schemas, context isolation, `CRIT-XX` traceability, and automated checkbox ticking.

## Lifecycle & Execution

### 0. Bootstrap / Reset (CLI only)
- Initialize repo: `bash <skill-path>/scripts/init.sh --test-cmd "<cmd>"`
- Reset repo: `bash <skill-path>/scripts/reset.sh`

### 1. Ideation & Doubt (`workflows/sdd_doubt.py`)
- Ask up to 3 high-impact clarifying questions (with your recommendation attached) before planning.
- To stress-test a non-trivial architectural claim or artifact with fresh-context adversarial review:
  `run_workflow(ScriptPath="<skill-path>/workflows/sdd_doubt.py", Description="Adversarial doubt cycle", Args={"claim": "...", "artifact": "...", "contract": "..."})`

### 2. Planning (`workflows/sdd_plan.py`)
- Generate, self-audit across 4 parallel axes, render `plans/PLAN-N.md`, and lock `sdd_state: plan`:
  `run_workflow(ScriptPath="<skill-path>/workflows/sdd_plan.py", Description="Draft and audit SDD plan", Args={"title": "...", "spec": "...", "decompose": False})`
- Present the resulting plan and ask: *"¿Apruebas este plan para comenzar la ejecución?"*. Do **not** execute a phase in the same turn.

### 3. Phase Execution & Verification (`workflows/sdd_execute.py`)
- When the user approves starting a phase (e.g. `"Inicia F1"`), run:
  `run_workflow(ScriptPath="<skill-path>/workflows/sdd_execute.py", Description="Execute and verify phase F1", Args={"phase": "F1"})`
  *(For independent parallel phases on isolated shared workspaces: `Args={"phases": ["F1", "F2"]}`)*
- The workflow automatically validates `SESSION.md` ancestry, runs `sdd.sh start F<N>`, isolates **TDD RED** (tests with `CRIT-XX` IDs) from **TDD GREEN** (implementation + `feat(F<N>): ...` commits), triggers conditional Security/DoD audit if sensitive surfaces are touched, runs `sdd.sh verify F<N>`, ticks `- [x]` in `PLAN-N.md`, and halts for human diff audit.
- **Fallback (if `run_workflow` tool is unavailable):** Execute `<skill-path>/scripts/sdd.sh start F<N>`, write `CRIT-XX` failing tests first (RED) then implementation (GREEN), and run `<skill-path>/scripts/sdd.sh verify F<N>`: on success it ticks the verified `CRIT-XX` boxes (and derivable cycle criteria) in `PLAN-N.md` by itself via `scripts/tick-plan.sh`. Never tick by hand; `(manual)` criteria are ticked by the human.

### 4. Cycle Close (`workflows/sdd_close.py`)
- After the final phase is audited, run the C2 cycle closure audit (unticked boxes, reality vs. plan, scope leaks; ticks "Out of scope" criterion only if no leaks):
  `run_workflow(ScriptPath="<skill-path>/workflows/sdd_close.py", Description="Close SDD cycle")`
