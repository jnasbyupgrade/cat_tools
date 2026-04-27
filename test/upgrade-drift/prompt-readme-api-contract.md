# Prompt: README ↔ API Contract Cross-Reference

## Task

This is a **team brainstorming task** — spin up 2-3 agents with competing perspectives and
synthesize their findings. Do NOT just produce one answer.

Suggested agent angles:
- Agent A: "Generate pgTAP tests FROM the README" — README as source of truth
- Agent B: "Validate README AGAINST the code" — code as source of truth, README as docs
- Agent C: "Enforce consistency in CI" — focus on the checking mechanism, not the content

## Background

The cat_tools PostgreSQL extension is adding a Layer 2 of upgrade-drift testing: pgTAP
structural assertions (`has_function`, `function_returns`, `volatility_is`, `is_strict`,
`has_type`, `has_view`, etc.) run under both fresh install and upgrade paths to catch
schema drift.

The observation: the README.asc documents the public API. That README is effectively a spec.
The pgTAP structural tests should be cross-referenced with what README says is public.

## Relevant files (read these)

- `README.asc` — documents public API (functions, types, views)
- `sql/cat_tools.sql.in` — canonical install script; source of truth for what exists
- `test/sql/function.sql`, `test/sql/relation_type.sql`, etc. — existing behavioral tests
- `pgxntool/CLAUDE.md` — project conventions

## Key questions each agent should address

1. What is the right source of truth — README or code? What are the failure modes of each?

2. How should the README and pgTAP tests be kept in sync? Options:
   - Generate pgTAP stubs from README entries (README drives tests)
   - Generate README entries from pgTAP assertions (tests drive docs)
   - Independent check: parse both and diff the object name sets
   - Manual convention with a CI lint check

3. What's the simplest CI check that catches:
   - "README documents function X but no pgTAP assertion exists for it"
   - "pgTAP asserts function X exists but README doesn't mention it" (undocumented public API)
   - "Function X is in code but neither README nor pgTAP covers it"

4. Produce a concrete pgTAP sketch for 5-10 representative assertions (mix of function,
   type, view, volatility, strictness, return type).

5. How does this interact with the _cat_tools private schema? Should private objects have
   pgTAP assertions? Should they be in the README?

6. What's the maintenance burden over time as new functions are added?

## Constraints

- The extension uses `__cat_tools.create_function()` wrapper — functions aren't defined
  with literal `CREATE FUNCTION` in the source. Static parsing must handle this.
- README uses AsciiDoc format.
- pgTAP tests use pg_regress (`.sql` files with `.out` expected output).
- Test convention: look at existing test/sql/*.sql files for style.

## Output format

Each agent produces a 1-2 page analysis. Then synthesize into:
1. Recommended approach (with rationale)
2. Concrete pgTAP sketch (10 example assertions)
3. Proposed CI check (what command, what it checks, how it fails)
4. Open questions for the human to decide

DO NOT make any file changes.
