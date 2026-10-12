# Flow A — Bootstrap a repository

## Steps

### Option 1 — Automated via script (Recommended)

Run `scripts/init.sh` from this skill (resolves templates and paths automatically):

```bash
bash <path-to-skill>/scripts/init.sh --test-cmd "<TEST_COMMAND>" [--project-name "<NAME>"]
```

Options:
- `-t, --test-cmd`: Test suite command (e.g. `pytest`, `npm test`, `cargo test`).
- `-p, --project-name`: Explicit project name (defaults to target directory name).
- `-d, --target-dir`: Target repository root (defaults to `.`).
- `--no-hooks`: Skip git hooks installation (by default, both `pre-commit` and `commit-msg` hooks are installed).
- `-f, --force`: Overwrite existing contract files completely (by default, `init.sh` safely appends/updates the delimited block).

**What gets installed:**
1. `AGENTS.md` with the managed contract block, pointing at the skill
   directory in place (read natively by current Claude Code ≥ v2.1.277,
   Codex, Cursor, OpenCode and other agents — no `CLAUDE.md` shim is created).
   Skill scripts and assets are referenced where they live, never copied.
2. Deterministic Git hooks in `.git/hooks/` (the only real copies: Git
   mandates this location) with the skill path baked in:
   - `pre-commit`: Blocks code commits during `sdd_state: plan`.
   - `commit-msg`: Enforces Conventional Commits and reference to the active phase (e.g. `F1`).

**Handling a pre-existing `AGENTS.md`:**
- If `AGENTS.md` exists, `init.sh` appends the Discipline Flow contract inside managed delimiters (`<!-- BEGIN DISCIPLINE-FLOW -->` ... `<!-- END DISCIPLINE-FLOW -->`), preserving all pre-existing project rules. If re-run, it updates only that section in place.

### Option 2 — Manual step-by-step (Fallback)

1. Confirm repo root (git init if needed — ask first, don't init silently
   over an existing non-git project).
2. Fill `assets/AGENTS.md.template` placeholders:
   - `{{PROJECT_NAME}}` — name of the repository/project.
   - `{{TEST_COMMAND}}` — the project's actual test invocation. Ask if not
     obvious from the stack (don't guess `pytest` for a project that turns
     out to use `unittest` or `go test`).
   - `{{COMMIT_TYPES}}` — default: `feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert, release`.
     Ask only if the project has an existing convention to match.
   - `{{SKILL_PATH}}` — skill directory relative to the repo root
     (e.g. `.agents/skills/discipline-flow`, or `.` when bootstrapping
     the skill repo itself). Computed, never guessed.
3. Write or append to `AGENTS.md` at the repo root:
   - If `AGENTS.md` does not exist: write the filled template directly.
   - If `AGENTS.md` already exists: do NOT overwrite it. Append the filled template enclosed between `<!-- BEGIN DISCIPLINE-FLOW -->` and `<!-- END DISCIPLINE-FLOW -->` at the end of the file.
4. Install git hooks (`pre-commit` and `commit-msg`):
   - Copy `<skill-dir>/scripts/pre-commit-hook.sh` to `.git/hooks/pre-commit`, `chmod +x`,
     replacing `{{SKILL_PATH}}` with the skill directory relative to the repo root.
   - Copy `<skill-dir>/scripts/commit-msg-hook.sh` to `.git/hooks/commit-msg`, `chmod +x`,
     same replacement.
   - Inform the user that in an emergency, hooks can be bypassed with `git commit --no-verify`.
5. Reference, don't copy: `sdd.sh`, `verify-crit.sh`, `new-plan.sh` and
   `lib/sdd-common.sh` stay in `<skill-dir>/scripts/` and run from there.
   Plans (`plans/PLAN-N.md`) and `SESSION.md` live in the project root —
   never inside the skill directory. If the project carries legacy vendored
   copies under its own `scripts/`, they can be deleted once `AGENTS.md`
   points at the skill path.
6. Report what was written and stop. Don't start writing project code in
   the same turn unless the user asked for that too.

## Resetting a project

If the project drifted and must start over, `<skill-dir>/scripts/reset.sh`
removes every trace (plans including archive, `SESSION.md`, contract block,
skill hooks, legacy vendored copies) while preserving foreign hooks, custom
rules and modified scripts with a warning. Interactive by default
(`--dry-run` to preview, `--force` for non-interactive). Re-run `init.sh`
afterwards for a clean bootstrap.

## Why each rule in the contract exists (for when the user asks)

- **Conventional commits** — makes the history itself a queryable log of
  intent; a `git log --oneline` becomes a changelog draft for free.
- **Active phase in commits** — guarantees traceability between git history and the plan.
- **Pre-commit blocking during plan mode** — guarantees that no code is written before specs and criteria are approved.
- **Test before first change, after every logical unit** — the cheapest
  possible check against an agent's unstated assumption that something
  still works.
- **Never leave the suite red at a commit boundary** — a red commit means
  the next session (agent or human) inherits a broken baseline with no
  signal of whose change broke it.
- **Atomic commits, one concern each** — makes `git revert` a real option
  instead of a surgical mess.
- **The plan-mode clause** (see `plan-cycle.md`) — is what upgrades this
  contract from "good habits" to "governs multi-session work," the moment
  the task outgrows a single sitting.
