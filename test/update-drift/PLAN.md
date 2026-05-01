# Layer 3: Upgrade Drift Test — Plan

## Overview

This directory implements a "pg_dump diff" test that verifies the schema produced by
a fresh `CREATE EXTENSION cat_tools` is byte-for-byte identical (after normalization)
to the schema produced by installing an old version and running `ALTER EXTENSION
cat_tools UPDATE`.

Any difference between the two databases is an "upgrade drift" bug: the upgrade path
produced a different schema than a clean install, meaning users who upgrade will have
a subtly wrong extension state.

## Scope and Version Matrix

The direct predecessor of 0.3.0 is 0.2.2.  The upgrade path under test is:

    fresh:    CREATE EXTENSION cat_tools                          → 0.3.0
    upgraded: CREATE EXTENSION cat_tools VERSION '0.2.2';
              ALTER EXTENSION cat_tools UPDATE;                   → 0.3.0

PG version matrix (minimum where 0.2.2 installs cleanly):

    PG 11  — first version where cat_tools--0.2.2.sql installs (attmissingval barrier)
    PG 12  — oid-visibility boundary; important regression marker
    PG 18  — latest; catches any new catalog drift


## Sequence of Operations

The orchestrator script (`run-drift-test.sh`) executes these steps in order:

1. `make install PGUSER=postgres` — install all SQL files into the PostgreSQL data
   directory so both version strings (0.2.2 and 0.3.0) are available.

2. Create two databases:
   - `drift_fresh`    — `CREATE EXTENSION cat_tools`
   - `drift_upgraded` — `CREATE EXTENSION cat_tools VERSION '0.2.2'`
                        then `ALTER EXTENSION cat_tools UPDATE`

3. For each database: run `unmark-extension.sql` to drop all objects from the
   extension's membership in pg_depend (but keep the objects themselves).  This
   makes pg_dump emit the full DDL for every object instead of just a reference.

4. `pg_dump --schema-only --no-owner --no-privileges --no-comments` on each
   database, capturing stdout.

5. Pass both dump files through `compare-dumps.pl`:
   - Strip pg_dump noise (header, SET statements, section comments, blank lines).
   - Split the remaining output into per-object DDL blocks.
   - Sort the blocks.
   - Diff the two sorted block lists.

6. Exit 0 if the diff is empty; exit 1 and print the diff otherwise.


## Design Decisions

### Why pg_dump instead of querying pg_catalog directly?

pg_dump is the canonical serialization of a PostgreSQL schema.  It already knows
how to reconstruct every object type in the correct CREATE syntax, including all
the edge cases around argument types, defaults, and body quoting.  Writing our own
catalog queries would duplicate a huge amount of pg_dump logic and would likely miss
edge cases.

### Why unmark extension objects?

By default, pg_dump in "extension member" mode emits only:
    -- objects belonging to extension cat_tools are not dumped

We need the actual DDL.  Removing objects from the extension's dependency list
(without dropping the objects themselves) causes pg_dump to treat them as ordinary
user objects and emit their full DDL.

The unmark step uses `pg_identify_object` to get the canonical identity string for
each object, then generates `ALTER EXTENSION cat_tools DROP <type> <identity>`.

After the dump, the databases are dropped; we do not need to restore extension
membership.

### Why `--no-comments` in the pg_dump invocation?

pg_dump emits `COMMENT ON FUNCTION ...` statements for objects that have comments.
If the upgrade script adds or changes comments differently from the install script,
that would show up as drift — which is a real bug.  However, pg_dump also emits
section header comments (pure noise) that must be suppressed.  Using `--no-comments`
removes COMMENT ON statements too, which is slightly too aggressive.

Instead, we do NOT pass `--no-comments` and instead strip the section header lines
(starting with `-- Name:`) and pg_dump boilerplate in the normalization step.  This
means genuine `COMMENT ON` drift will be caught.

### Normalization steps (in compare-dumps.pl)

The following lines/blocks are stripped before splitting into per-object blocks:

1. Everything up to and including the first `SET` statement block at the top
   (pg_dump header: role, encoding, search_path defaults).
2. Lines matching `^--` that are pg_dump section headers:
   `-- Name: ...; Type: ...; Schema: ...; Owner: ...`
   These are comments that pg_dump adds before each object's DDL; they are
   redundant with the DDL itself and vary only in schema/owner (already removed
   by --no-owner).
3. `SET` statements (search_path, client_encoding, etc.) that pg_dump emits
   between objects.
4. `SELECT pg_catalog.set_config(...)` lines.
5. Trailing blank lines.

After stripping, the dump is split into blocks by blank lines.  Each block
corresponds to one DDL statement (CREATE FUNCTION, CREATE VIEW, etc.).
Blocks are sorted lexicographically before diffing.

Sorting is required because pg_dump output order depends on OID order, which
differs between a fresh install and an upgraded install (objects created in
different sessions get different OIDs, and pg_dump sorts by OID within each
object type).

### Why Perl for compare-dumps.pl?

Perl is universally available in pgxn/pgxn-tools and on any POSIX system.
It handles multi-line block splitting cleanly with slurp mode.  A shell
implementation would require temporary files and be harder to read.
A Python implementation would be fine too but Perl is lighter and has no
import dependencies.

### What --no-owner and --no-privileges do

`--no-owner` suppresses `ALTER TABLE ... OWNER TO` and `ALTER FUNCTION ... OWNER TO`
statements.  Since fresh and upgraded databases will have the same role structure
but potentially different internal OID-derived orderings, omitting ownership is
correct.

`--no-privileges` suppresses `GRANT`/`REVOKE` statements.  cat_tools grants
`EXECUTE` on functions to `cat_tools__usage`; if the upgrade path grants these in a
different order, we'd get false-positive failures.  Since the final grant state is
what matters (not the order), we suppress GRANT/REVOKE entirely.

NOTE: This means privilege drift would NOT be caught.  If a future version adds
new GRANTs in the install script but forgets them in the upgrade script, this test
will not catch it.  A future enhancement could do a separate privilege audit.


## Known Edge Cases

### pg_dump output is PG-version-dependent

Some DDL syntax changes between PG versions (e.g., function argument syntax, type
representation).  We are diffing fresh vs. upgraded on the SAME PG version, so this
is not an issue.  The cross-version comparison happens in the pg-upgrade-test job,
not here.

### OID columns in internal tables

cat_tools uses `_cat_tools.catalog_metadata` and similar internal tables.  pg_dump
will emit CREATE TABLE plus any associated sequences, indexes, and constraints.
These all appear as separate blocks and will be sorted.

### __cat_tools schema objects

The install script creates `__cat_tools` as a temporary workspace schema with helper
functions.  If the upgrade script tears down and recreates these differently, that
will appear as drift.  This is intentional: the test should catch that.

### search_path differences

pg_dump emits `SET search_path = ...` before each function body.  We strip
standalone SET statements between blocks, but the ones embedded inside function
definitions are part of the DDL and are kept.  These should be identical between
fresh and upgraded installs.

### Extension itself

After unmarking, pg_dump will still emit `CREATE EXTENSION cat_tools` (or similar).
We strip these lines as part of normalization because the extension record itself
is not an object we want to compare (it's always the same version after both paths
complete, but may differ in OID).

Actually, after unmarking all members, the extension record has no members.  pg_dump
should still emit a CREATE EXTENSION statement.  We strip any `CREATE EXTENSION`
lines from the dump before comparison.


## What Is NOT Yet Implemented

(For a future developer picking this up:)

- `compare-dumps.pl` does not yet strip `CREATE EXTENSION` lines — add a strip rule.
- Privilege drift detection (GRANT/REVOKE) is not covered.  Consider a follow-up job
  that diffs `\dp` output from psql for each schema.
- The test only covers the 0.2.2 → 0.3.0 path.  When 0.4.0 is released, add
  0.3.0 → 0.4.0 and update the version references in run-drift-test.sh.
- No local Makefile target yet.  Add `make drift-test` to the root Makefile.


## How to Run Locally

Prerequisites: PostgreSQL (PG11+) running, `pg_dump` in PATH, `perl` in PATH.

```bash
# Start PostgreSQL (pgstart alias in the container, or pg_ctlcluster on Ubuntu)
pgstart

# From the repo root:
make install PGUSER=postgres

# Run the drift test:
cd test/update-drift
bash run-drift-test.sh postgres
```

The script accepts one optional argument: the PostgreSQL superuser name (default:
`postgres`).

To clean up the test databases manually:
```bash
psql -U postgres -c "DROP DATABASE IF EXISTS drift_fresh"
psql -U postgres -c "DROP DATABASE IF EXISTS drift_upgraded"
```

Expected output on success:
```
[drift-test] Installing cat_tools (all versions)...
[drift-test] Creating fresh database...
[drift-test] Creating upgraded database (0.2.2 -> 0.3.0)...
[drift-test] Unmarking extension objects in drift_fresh...
[drift-test] Unmarking extension objects in drift_upgraded...
[drift-test] Dumping schemas...
[drift-test] Comparing schemas...
[drift-test] PASS: fresh and upgraded schemas are identical.
```

Expected output on failure:
```
[drift-test] FAIL: schemas differ.  Diff (fresh vs upgraded):
--- fresh
+++ upgraded
@@ ... @@
 ...
```
