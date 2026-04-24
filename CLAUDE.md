# Claude Code Instructions for cat_tools

## Git

**Never delete a branch without explicit user approval.** This includes `git push origin --delete`, `git branch -d`, and `git branch -D`. Always ask first.

**Always open PRs against the main repo** (`Postgres-Extensions/cat_tools`), not a fork.

## SQL file conventions

For versions 0.2.0+, `.sql.in` files are the source templates (checked in); the generated
`.sql` files are built by `make` via awk/sed processing and are gitignored by `sql/.gitignore`.

- **Check in**: all `.sql.in` files (e.g. `sql/cat_tools--0.2.2.sql.in`, upgrade scripts
  like `sql/cat_tools--0.2.1--0.2.2.sql.in`)
- **Do not commit**: the generated `.sql` outputs (e.g. `sql/cat_tools--0.2.2.sql`,
  `sql/cat_tools--0.2.0--0.2.1.sql`) — covered by `sql/.gitignore`
- **Exception**: pre-0.2.0 files (`sql/cat_tools--0.1.*.sql` and their upgrade scripts) have
  no `.sql.in` source and must be tracked directly

## CI: extension-update-test matrix

The `extension-update-test` job in `.github/workflows/ci.yml` is currently restricted to
`pg: [11, 10]` because those are the only PostgreSQL versions where a pre-0.2.2 install
script (`cat_tools--0.2.0.sql`) installs cleanly. PG 12+ exposed the `oid` system column
in `SELECT *`, breaking `0.2.0` and `0.2.1` with "column oid specified more than once".

**When working on a new version:** review and expand this matrix. The new version's install
script may support more PG versions, enabling testing of the upgrade path from older
cat_tools versions on newer PostgreSQL.

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
