# Claude Code Instructions for cat_tools

## Git

**Never delete a branch without explicit user approval.** This includes `git push origin --delete`, `git branch -d`, and `git branch -D`. Always ask first.

**Always open PRs against the main repo** (`Postgres-Extensions/cat_tools`), not a fork.

## SQL file conventions

Rules for what to track in git:

0. If a `.sql.in` file exists, track the `.sql.in` and **not** the corresponding `.sql`.
1. If no `.sql.in` exists, track the `.sql` directly (e.g. historical pre-0.2.0 files).
2. Version-specific install scripts (e.g. `sql/cat_tools--0.2.2.sql.in`) MUST be tracked.
3. Upgrade scripts (e.g. `sql/cat_tools--0.2.1--0.2.2.sql.in`) MUST be tracked.
4. The current version'''s install script (e.g. `sql/cat_tools--0.2.2.sql.in`) is generated
   by `make` from `sql/cat_tools.sql.in`, but MUST still be tracked (rule 2 applies).
5. Version-specific files MUST NEVER be edited manually — always edit `sql/cat_tools.sql.in`
   and regenerate.

## CI: PostgreSQL version support

PG10 is formally dropped as of the 0.3.0 release. The `ALTER TYPE ... ADD VALUE` statements
in the 0.2.2→0.3.0 upgrade script cannot run inside an extension update script on PG10 (a
PG10 restriction lifted in PG12).

The `extension-update-test` job tests `pg: [11, 12]` — these are the oldest versions where
the 0.2.2 install script works. The 0.2.0/0.2.1 upgrade paths required PG10 and can no
longer be tested.

## Code Style

### Comments
Always use block comment format for multi-line comments in SQL files:

```sql
/*
 * First line of comment.
 * Second line of comment.
 */
```

Never use `--` line comments for multi-line explanations.
