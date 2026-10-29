---
name: discipline-flow
description: Deterministic Spec-Driven Development (SDD) gatekeeper enforced via JSON Schemas, OS-level Git hooks, Bash CLI, and Antigravity run-workflow orchestration.
license: MIT
metadata:
  author: fdomerlo
  version: 2.0.0
---

# Discipline Flow — Operational Specification

## 1. Language & State Invariants (HARD RULES)
- **Human-facing outputs (chat, `plans/PLAN-*.md`, `SESSION.md` body, audit tables, closure reports):** **SPANISH**.
- **Code, comments, commit messages, error strings, and test identifiers:** **ENGLISH**.
- **State immutability:** Never hand-edit the YAML frontmatter (`--- ... ---`) of `SESSION.md`. Mutate state exclusively via `<skill-path>/scripts/sdd.sh`.
- **In-place execution:** Execute scripts, schemas, and workflows directly from `<skill-path>` (recorded in `AGENTS.md`). Never vendor or copy them into the target project.

## 2. Deterministic Contracts (`assets/schemas/`)
All planning, decomposition, state checkpoints, and blind audits must validate against these JSON Schemas:
- `assets/schemas/spec_verification.json`: Pre-execution gate for `plans/PLAN-N.md` (`approved`, `commands`, `boundaries`, `criteria` with `^CRIT-[0-9]{2,}$`, empty `open_questions`).
- `assets/schemas/task_breakdown.json`: Atomic task DAG (`affected_files` capped at `1..5`, `tests_to_create`, `criteria_ids`, `dependencies`, `parallelizable`).
- `assets/schemas/audit_verdict.json`: Blind Doubt-Driven review output (`passed`, `cycle` `1..3`, `coverage`, `violations` classified as `contract_misread | actionable | trade_off | noise`).
- `assets/schemas/session_state.json`: Formal schema for `SESSION.md` (`sdd_state` in `plan | execute | verify`, `active_task`, `plan_hash`, `base_commit`, `human_review`).

## 3. CLI Gatekeeper Commands (`scripts/`)

| Action | Executable Command | Exit Codes / Effect |
| :--- | :--- | :--- |
| **Bootstrap repo** | `bash <skill-path>/scripts/init.sh --test-cmd "<cmd>"` | Installs `AGENTS.md` shim + `.git/hooks/{pre-commit,commit-msg}` |
| **New plan cycle** | `<skill-path>/scripts/sdd.sh plan "<title>"` | Scaffolds `plans/PLAN-N.md` from `assets/PLAN.md.template`, sets `sdd_state: plan` |
| **Start phase** | `<skill-path>/scripts/sdd.sh start F<N> [agent]` | Freezes `plan_hash`, records `Phase-start commit`, sets `sdd_state: execute` |
| **Verify phase (MD)** | `<skill-path>/scripts/sdd.sh verify F<N>` | Runs `verify-crit.sh` + test runner; sets `sdd_state: verify` on `0` |
| **Verify phase (JSON)** | `<skill-path>/scripts/sdd.sh verify --json F<N>` | Emits machine-parseable JSON (`0`=pass, `1`=precondition/test fail, `2`=missing CRIT/bypass/open decision) |
| **Validate schema** | `<skill-path>/scripts/sdd.sh validate <schema> [file\|-]` | Validates JSON against `assets/schemas/<schema>.json` (`0`=valid, `1`=invalid) |
| **Prepare workflow** | `<skill-path>/scripts/sdd.sh orchestrate F<N> [--plan <path>]` | Emits JSON payload (`ScriptPath`, `Cwd`, `Args`) for `run_workflow` |
| **Force state** | `<skill-path>/scripts/sdd.sh advance <plan\|execute\|verify>` | Transitions `sdd_state` in `SESSION.md` |
| **Inspect state** | `<skill-path>/scripts/sdd.sh status` | Prints active state, task, agent, and `plan_hash` integrity |
| **Reset repo** | `bash <skill-path>/scripts/reset.sh [--dry-run\|--force]` | Removes skill hooks, `SESSION.md`, `plans/`, and `AGENTS.md` block |

## 4. Phase Execution (Multi-Harness Protocol)

### Mode A — Antigravity Runtime (`run_workflow` tool available)
Generate the arguments via `<skill-path>/scripts/sdd.sh orchestrate F<N>` and invoke `run_workflow`:

```python
run_workflow(
    ScriptPath="<skill-path>/workflows/sdd_cycle.py",
    Cwd="<workspace-root>",
    Description="Execute Discipline Flow SDD cycle for F1",
    Args={
        "plan_file": "plans/PLAN-1.md",
        "phase_id": "F1",
        "workspace_root": "<workspace-root>",
        "skill_root": "<skill-path>",
        "test_cmd": "<test-command>",
        "lint_cmd": "<lint-command-or-none>",
        "max_doubt_cycles": 3
    }
)
```

### Mode B — Standard Agents without `run_workflow` (Claude Code, Cursor, Codex, OpenCode)
Execute the exact same 4 stages sequentially via CLI and native subagents:
1. **Audit Spec:** Verify `plans/PLAN-N.md` and validate the JSON output with `<skill-path>/scripts/sdd.sh validate spec_verification -` and `task_breakdown -`.
2. **Atomic Implementation:** Run `<skill-path>/scripts/sdd.sh start F<N> <agent>`. Implement tasks (`≤ 5` files per task, TDD RED → GREEN with `CRIT-XX` tags, commits prefixed with `feat(F<N>):`).
3. **Mechanical Gate:** Run `<skill-path>/scripts/sdd.sh verify --json F<N>` (must exit `0` with `"passed": true`).
4. **Doubt-Driven Audit:** Spawn a fresh-context native subagent passing ONLY `ARTIFACT` (`git diff`) + `CONTRACT` (`PLAN-N.md`), validate its JSON response via `<skill-path>/scripts/sdd.sh validate audit_verdict -` (`1..3` cycles), and halt for human diff review.

## 5. Reference Index (`references/`)
Load on demand only when operating conversationally or auditing security-critical paths:
- `references/protocol-invariants.md`: Phase 0 capability map DAG, ambiguity gate (≤ 3 questions), TDD double hierarchy (`Real > Fake > Stub > Mock`), Doubt-Driven finding precedence, and C1/C2 closure reports.
- `references/security-checklist.md`: Threat modeling, AuthN/AuthZ, path/query containment (`realpath`), lockfile hygiene, and AI/LLM boundaries.
