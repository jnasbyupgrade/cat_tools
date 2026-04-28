#!/bin/bash
#
# run-drift-test.sh -- Layer 3 upgrade drift test
#
# Creates two databases, installs cat_tools fresh (0.3.0 directly) and via
# upgrade (0.2.2 -> 0.3.0), dumps both schemas, normalizes and diffs them.
# Exits 0 if the schemas match; exits 1 with a diff if they differ.
#
# Usage: run-drift-test.sh [PGUSER]
#   PGUSER  PostgreSQL superuser name (default: postgres)
#
# Prerequisite: make install PGUSER=<user> must have been run first so that
# all version scripts are present in the PostgreSQL extension directory.
#
set -euo pipefail

PGUSER="${1:-postgres}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

FRESH_DB="drift_fresh"
UPGRADED_DB="drift_upgraded"
WORK_DIR="$(mktemp -d)"

log() { echo "[drift-test] $*"; }

cleanup() {
    rm -rf "$WORK_DIR"
    psql -U "$PGUSER" postgres -c "DROP DATABASE IF EXISTS $FRESH_DB"    2>/dev/null || true
    psql -U "$PGUSER" postgres -c "DROP DATABASE IF EXISTS $UPGRADED_DB" 2>/dev/null || true
}
trap cleanup EXIT

# Drop any leftover databases from a previous run
psql -U "$PGUSER" postgres -c "DROP DATABASE IF EXISTS $FRESH_DB"
psql -U "$PGUSER" postgres -c "DROP DATABASE IF EXISTS $UPGRADED_DB"

log "Creating fresh database..."
psql -U "$PGUSER" postgres -c "CREATE DATABASE $FRESH_DB"
psql -U "$PGUSER" -d "$FRESH_DB" -c "CREATE EXTENSION cat_tools"

log "Creating upgraded database (0.2.2 -> 0.3.0)..."
psql -U "$PGUSER" postgres -c "CREATE DATABASE $UPGRADED_DB"
psql -U "$PGUSER" -d "$UPGRADED_DB" -c "CREATE EXTENSION cat_tools VERSION '0.2.2'"
psql -U "$PGUSER" -d "$UPGRADED_DB" -c "ALTER EXTENSION cat_tools UPDATE"

log "Unmarking extension objects in $FRESH_DB..."
psql -U "$PGUSER" -d "$FRESH_DB" -tA \
        -f "$SCRIPT_DIR/unmark-extension.sql" \
    | psql -U "$PGUSER" -d "$FRESH_DB" -v ON_ERROR_STOP=1 -f -

log "Unmarking extension objects in $UPGRADED_DB..."
psql -U "$PGUSER" -d "$UPGRADED_DB" -tA \
        -f "$SCRIPT_DIR/unmark-extension.sql" \
    | psql -U "$PGUSER" -d "$UPGRADED_DB" -v ON_ERROR_STOP=1 -f -

log "Dumping schemas..."
pg_dump -U "$PGUSER" --schema-only --no-owner --no-privileges \
    "$FRESH_DB"    > "$WORK_DIR/fresh.sql"
pg_dump -U "$PGUSER" --schema-only --no-owner --no-privileges \
    "$UPGRADED_DB" > "$WORK_DIR/upgraded.sql"

log "Comparing schemas..."
if perl "$SCRIPT_DIR/compare-dumps.pl" \
        "$WORK_DIR/fresh.sql" "$WORK_DIR/upgraded.sql"; then
    log "PASS: fresh and upgraded schemas are identical."
else
    exit 1
fi
