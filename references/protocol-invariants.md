# Protocol Invariants — Conversational & Audit Rules

Rules in this file govern human interaction, test design, and adversarial review nuances not already enforced mechanically by `scripts/*.sh` or `assets/schemas/*.json`.

## 1. Phase 0 & Plan Cycle (`sdd.sh plan`)
- **Capability Map (Multi-Module Only):** If a request bundles distinct, independently testable capabilities, define a DAG table (`module_id`, responsibility, `depends_on`) with zero cycles and halt for human approval before authoring per-module plans.
- **Ambiguity Gate:** Before drafting `plans/PLAN-N.md`, ask at most **3 high-impact questions** (scope boundary, structural trade-off, external constraint), each with a **recommended option and rationale**. Unresolved blockers must be written as `## DECISIÓN ABIERTA` (mechanically blocked by `verify-crit.sh`).
- **Vertical Slicing:** Order phases (`F1`, `F2`, ...) bottom-up by dependency. Cap each atomic task at `≤ 5` files (`task_breakdown.json`).

## 2. TDD & Test Doubles (`sdd.sh start F<N>`)
- **Loop:** RED (failing test named/tagged with `CRIT-XX`, mandatory reproduction test first for bugs) → GREEN (minimal production code) → REFACTOR (no duplicate runs on unchanged code).
- **Design:** Arrange-Act-Assert (AAA), one concept per test, DAMP over DRY, assert output state/errors rather than internal method calls.
- **Double Hierarchy:** `Real implementation > In-memory Fake > Stub > Mock`. Mock only external I/O, network, DB, or clock boundaries.

## 3. Doubt-Driven Blind Audit (`workflows/sdd_cycle.py`)
- **Context Isolation:** Pass ONLY `ARTIFACT` (git diff) + `CONTRACT` (`PLAN-N.md` phase spec & `CRIT-XX` list) to the reviewer. Never pass author `CLAIM` or reasoning.
- **Precedence (`audit_verdict.json`):** `1. contract_misread` (halt & fix spec) > `2. actionable` (fix code/tests) > `3. trade_off` (document) > `4. noise` (ignore).
- **Stop Conditions:** Max `3` cycles; halt on *Doubt Theater* (≥ 2 cycles with findings and `0` actionable).
- **Cross-Model CLI (Interactive Only):** Offer `codex exec --sandbox read-only` or `gemini --approval-mode plan` piping prompt via stdin (`< /tmp/doubt-prompt.md`, never shell-interpolated) only after explicit per-run human confirmation.

## 4. Multi-Agent & Closure (`sdd.sh verify F<N>`)
- **One Agent = One Phase:** Claim via `sdd.sh start F<N> <agent>` and isolate work on `feat/F<N>-<slug>` branches (or `workspace="branch"` in `parallel()`). Any merge conflict in `SESSION.md` or non-ancestor `Base commit` is a hard STOP.
- **Phase Close (C1):** Run `sdd.sh verify F<N>`, tick `- [x]` only for verified automated `CRIT-XX` (leave `(manual)` as `- [ ]`), output the Spanish closure report (verification table, files changed, tests/defenses, deviations, open questions), and **HALT** for human diff review.
- **Cycle Close (C2):** Read-only pass after the last phase classifying unticked criteria (`unbuilt | manual-pending | obsolete`), checking `git diff` for scope leaks from `Out of scope`, and recording leftovers in `BACKLOG.md` without opening `PLAN-N+1.md`.
