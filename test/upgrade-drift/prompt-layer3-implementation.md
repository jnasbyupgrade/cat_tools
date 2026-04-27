# Prompt: Implement Layer 3 — pg_dump Upgrade Drift Test

## Task

Implement the Layer 3 upgrade-drift test infrastructure. Work in a git worktree on a
new branch off `new_functions`. Write PLAN.md FIRST before any implementation.

## Setup

Main repo: `/root/git/cat_tools` (on master)
Fork remote: `origin` = https://github.com/jnasbyupgrade/cat_tools.git
Upstream remote: `pgext` = https://github.com/Postgres-Extensions/cat_tools.git

```bash
cd /root/git/cat_tools
git fetch origin new_functions
git worktree add ../cat_tools-drift origin/new_functions -b upgrade-drift-test
cd /root/git/cat_tools-drift
```

All work goes in the `../cat_tools-drift` worktree on branch `upgrade-drift-test`.

## What Layer 3 is

A CI job that catches "upgrade drift" — where `ALTER EXTENSION cat_tools UPDATE`
(from 0.2.2 to 0.3.0) produces a different schema than a fresh `CREATE EXTENSION cat_tools`.

Procedure:
1. `make install PGUSER=postgres` (installs all SQL files)
2. Create two databases:
   - **fresh**: `CREATE EXTENSION cat_tools`  (gets 0.3.0 directly)
   - **upgraded**: `CREATE EXTENSION cat_tools VERSION '0.2.2'` then
                   `ALTER EXTENSION cat_tools UPDATE`  (arrives at 0.3.0 via upgrade)
3. For each database: run `unmark-extension.sql` to remove all objects from extension
   membership (so pg_dump includes them as regular objects)
4. `pg_dump --schema-only --no-owner --no-privileges` on each database
5. Normalize both dumps (strip noise, sort object blocks)
6. Diff — any difference is an upgrade drift bug
7. CI job passes if diff is empty; fails with the diff shown

## Unmarking extension objects

```sql
/*
 * Generate ALTER EXTENSION cat_tools DROP ... statements for every
 * object owned by the extension, so pg_dump includes them as regular objects.
 */
SELECT format(
    'ALTER EXTENSION cat_tools DROP %s %s;',
    (pg_identify_object(classid, objid, 0)).type,
    (pg_identify_object(classid, objid, 0)).identity
)
FROM pg_depend
WHERE refobjid = (SELECT oid FROM pg_extension WHERE extname = 'cat_tools')
  AND deptype = 'e'
  AND classid != 'pg_extension'::regclass;
```

Note: `pg_identify_object` returns `(type, schema, name, identity)`. The `identity` field
is suitable for use in `ALTER EXTENSION DROP`. Available PG9.3+.

Some object types may need special handling — test on PG11, PG12, and PG18. The ALTER
EXTENSION DROP syntax must match the object type string exactly as PostgreSQL expects it.

## Normalization approach (Script 2)

The language choice for this script is TBD (see `prompt-language-choice.md`), but
plan for Perl as the likely winner. The script:

1. Strip pg_dump header boilerplate (lines before first `SET` or `--` section)
2. Strip `SET` statements (search_path etc.)
3. Strip `-- Name: ...; Type: ...; Schema: ...` section comment lines
4. Split remaining content into blocks on blank-line boundaries
5. Within each block, normalize whitespace (collapse runs, trim line ends)
6. Sort blocks lexicographically
7. Rejoin and diff the two outputs

Script location: `test/upgrade-drift/normalize-dump.pl` (or .sh if staying in shell)

## File layout

```
test/upgrade-drift/
  PLAN.md                    <- Write this FIRST
  prompt-*.md                <- These prompt files (already exist, don't modify)
  unmark-extension.sql       <- SQL to generate DROP statements
  run-drift-test.sh          <- Orchestrator: creates DBs, runs full test
  normalize-dump.pl          <- Normalization script (or .sh)
```

CI addition: new job `upgrade-drift-test` in `.github/workflows/ci.yml`

## CI job structure

```yaml
upgrade-drift-test:
  strategy:
    matrix:
      pg: [11, 12, 18]
  name: Upgrade drift test on PostgreSQL ${{ matrix.pg }}
  runs-on: ubuntu-latest
  container: pgxn/pgxn-tools
  steps:
    - name: Start PostgreSQL ${{ matrix.pg }}
      run: pg-start ${{ matrix.pg }}
    - name: Check out the repo
      uses: actions/checkout@v4
    - name: Install rsync
      run: apt-get install -y rsync
    - name: Install cat_tools
      run: make install PGUSER=postgres
    - name: Run upgrade drift test
      run: test/upgrade-drift/run-drift-test.sh
```

## PLAN.md must cover

- Overall approach and rationale
- Exact sequence of operations in `run-drift-test.sh`
- Design decisions: why each normalization step, what noise is stripped and why
- Known edge cases:
  - Objects intentionally different between fresh/upgraded (allowlist approach)
  - PG version differences in pg_dump output format
  - The `_cat_tools` private schema (included or excluded?)
  - Table data (schema-only dump ignores it — note this limitation)
- How to run the test locally (without CI)
- What is NOT yet implemented

## Important constraints

- CLAUDE.md: multi-line SQL comments must use `/* ... */` not `--`
- CLAUDE.md: never delete branches without explicit approval
- Commit PLAN.md alone first with message like "test/upgrade-drift: add PLAN.md for Layer 3"
- Then implement and commit the scripts
- Then update ci.yml and commit
- Push branch `upgrade-drift-test` to origin when done

## What success looks like

- `test/upgrade-drift/run-drift-test.sh` runs locally (with PG available) and:
  - PASSes when fresh install and upgrade produce identical schema
  - FAILs with a readable diff when they differ
- CI job defined in ci.yml and syntactically valid
- PLAN.md is complete enough that a new developer understands the full design

## Prior analysis to reference

Two agents previously analyzed this problem. Key findings relevant to implementation:

1. `pg_identify_object(classid, objid, 0).identity` gives the right string for
   `ALTER EXTENSION DROP` without needing to handle each object type separately.
   Test this assumption — it may need adjustment for some types.

2. Paragraph mode (splitting on blank lines) aligns well with pg_dump's output format.
   pg_dump separates object definitions with blank lines and section headers.

3. The `prosrc` field in pg_dump output (function bodies) will be byte-for-byte identical
   if the upgrade script copies them correctly — whitespace differences are signal, not noise.

4. An allowlist of known acceptable diffs (file `test/upgrade-drift/expected-diffs.txt`)
   is the right pattern for intentional differences. Start with an empty allowlist.
