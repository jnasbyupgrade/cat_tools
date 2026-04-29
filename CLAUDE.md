# Claude Code Instructions for cat_tools

## Git

**Never delete a branch without explicit user approval.** This includes `git push origin --delete`, `git branch -d`, and `git branch -D`. Always ask first.

**Always open PRs against the main repo** (`Postgres-Extensions/cat_tools`), not a fork.

## Terminology

- **Extension update**: moving from one cat_tools version to another (e.g. `ALTER EXTENSION cat_tools UPDATE`). Always say "update" for this.
- **PostgreSQL upgrade**: upgrading a PostgreSQL cluster to a newer major version (e.g. `pg_upgrade`, `pg_upgradecluster`). Always say "upgrade" for this.

Never use "upgrade" to describe an extension version change, and never use "update" to describe a PostgreSQL cluster version change.

## SQL file conventions

Rules for what to track in git:

0. If a `.sql.in` file exists, track the `.sql.in` and **not** the corresponding `.sql`.
1. If no `.sql.in` exists, track the `.sql` directly (e.g. historical pre-0.2.0 files).
2. Version-specific install scripts (e.g. `sql/cat_tools--0.2.2.sql.in`) MUST be tracked.
3. Update scripts (e.g. `sql/cat_tools--0.2.1--0.2.2.sql.in`) MUST be tracked.
4. The current version'''s install script (e.g. `sql/cat_tools--0.2.2.sql.in`) is generated
   by `make` from `sql/cat_tools.sql.in`, but MUST still be tracked (rule 2 applies).
5. Version-specific files MUST NEVER be edited manually — always edit `sql/cat_tools.sql.in`
   and regenerate.

## CI: PostgreSQL version support

PG10 and PG11 are not supported for the 0.2.2→0.3.0 update. The `ALTER TYPE ... ADD VALUE`
statements in the update script cannot run inside an extension update script on PG10 or PG11
(PROCESS_UTILITY_QUERY context); this restriction was lifted in PG12.

The `extension-update-test` job tests `pg: [12]` — PG12 is the oldest version where the
0.2.2→0.3.0 update works. PG11 (and PG10) cannot run `ALTER TYPE ... ADD VALUE` in
extension update scripts; this restriction was lifted in PG12. The 0.2.0/0.2.1 update
paths required PG10 and can no longer be tested.

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
