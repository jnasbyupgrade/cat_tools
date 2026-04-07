\set ECHO none
\i test/pgxntool/psql.sql
\t

-- Sanity check: install the oldest available version and upgrade to current.
BEGIN;
CREATE EXTENSION cat_tools VERSION '0.2.1';
-- Suppress expected deprecation warnings emitted during the upgrade.
-- (The 0.2.1 install script does SET LOCAL client_min_messages = WARNING, so
-- we must use SET LOCAL here too to override it within this transaction.)
SET LOCAL client_min_messages = ERROR;
ALTER EXTENSION cat_tools UPDATE;
ROLLBACK;
