# Prompt: Language Choice for Upgrade-Drift Utility Scripts

## Task

This is a **team debate task** — spin up 3 competing agents and synthesize.

- Agent A: Advocate for Perl
- Agent B: Advocate for Python (or push back on Perl assumptions)
- Agent C: Wild card — advocate for "stay in shell/awk" OR make the case for Go

Each agent should argue their position, acknowledge weaknesses, and engage with the
other positions. Then synthesize into a concrete recommendation.

## Background

We need two utility scripts for upgrade-drift testing of the cat_tools PostgreSQL extension:

**Script 1: Static name-presence check** (no PostgreSQL needed)
- Read `sql/cat_tools.sql.in` (new version) and `sql/cat_tools--0.2.2.sql.in` (old version)
- Strip `@generated@` markers (these appear at section boundaries in .sql.in files)
- Extract object names using patterns:
  - `__cat_tools\.create_function\(\s*'([^']+)'` — functions via wrapper (most functions)
  - `CREATE\s+(?:OR\s+REPLACE\s+)?(?:TYPE|VIEW|TABLE|SCHEMA)\s+(\S+)` — plain DDL
  - ENUM value lists from `CREATE TYPE ... AS ENUM (...)` blocks
- Set-diff: what's new in the new version, what was removed
- Check that the upgrade script `sql/cat_tools--0.2.2--0.3.0.sql.in` covers all new
  objects (name appears) and drops all removed objects
- Output report of gaps

**Script 2: pg_dump normalization and diff** (post-pg_dump comparison)
- Input: two `pg_dump --schema-only` output files
- Strip pg_dump noise: timestamps, section headers (`-- Name: ...; Type: ...; Schema: ...`),
  `SET` statements, blank lines at top/bottom
- Split into per-object blocks (pg_dump separates objects with blank lines + `--` headers)
- Sort blocks for stable comparison (order varies between databases)
- Normalize whitespace within blocks
- Diff the two normalized sets; report differences with context

## Project context

- CI uses `pgxn/pgxn-tools` Docker image (Debian-based)
- Build tooling: bash, make, awk (non-trivial awk already in Makefile)
- The `.sql.in` files use dollar-quoting: `$body$...$body$`, `$template$...$template$`,
  `$fmt$...$fmt$`, bare `$$` — extensively and with nesting
- The `@generated@` markers are NOT valid SQL — must be stripped before parsing
- Functions are mostly defined via `__cat_tools.create_function(name, args, opts, body, grants, comment)`
  where body is a dollar-quoted string — the name extraction only needs the first argument,
  which appears before any dollar-quoting begins

## The key tradeoff

- **Perl**: Ships with every Debian system (it's a dependency of dpkg itself); in the
  pgxn/pgxn-tools image with zero extra install steps; paragraph mode (`local $/ = ""`)
  is perfect for block-splitting Script 2; strong regex with `/xsm` modifiers
- **Python**: Not guaranteed in the CI image (needs `apt-get install -y python3`); version
  and venv headaches on dev machines; `re.DOTALL` + `re.VERBOSE` cover the same ground;
  more readable to cold readers
- **Shell/awk**: Already used for similar things in Makefile; zero new dependencies;
  awk `RS=""` paragraph mode exists; limited for set arithmetic and multi-file logic
- **Go**: Requires install + build step; RE2 (no lookahead/lookbehind); overkill for scripts

## Each agent must address

1. Is your language actually available in the CI environment without extra steps?
2. How does it handle multiline regex across dollar-quoted SQL bodies?
3. How does it handle the block-splitting requirement in Script 2?
4. What does the set-arithmetic for Script 1 look like idiomatically?
5. What's the maintenance burden for a future PostgreSQL developer who isn't a language specialist?
6. Specific failure modes for THIS task (not generic language criticism)

## Output format

Each agent: ~1 page, position + honest weaknesses.
Synthesis: concrete recommendation + one-paragraph rationale.
If Perl wins: note any specific Perl idioms to use/avoid for maintainability.

DO NOT make any file changes.
