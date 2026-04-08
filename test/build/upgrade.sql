\set ECHO none
\i test/pgxntool/psql.sql
\t

-- Sanity check: install a previous version and upgrade to current.
--
-- cat_tools 0.2.1's install script is incompatible with PG11+:
--   PG11: pg_attribute gained attmissingval (pseudo-type anyarray, not usable in views)
--   PG12: system catalog oid became a visible column, causing duplicate column names
-- Use 0.2.2 (the first version compatible with PG11+) on PG11+ for a real upgrade test.
-- Use 0.2.1 on PG10 and below (the last version that predates these fixes).
SELECT current_setting('server_version_num')::int >= 110000 AS pg11plus \gset

\if :pg11plus
-- PG11+: 0.2.2 installs cleanly, test the real upgrade to current.
BEGIN;
CREATE EXTENSION cat_tools VERSION '0.2.2';
-- Suppress expected notices from the upgrade.
SET LOCAL client_min_messages = WARNING;
ALTER EXTENSION cat_tools UPDATE;
ROLLBACK;
\else
-- PG10 and below: 0.2.1 installs cleanly, test the real upgrade chain.
BEGIN;
CREATE EXTENSION cat_tools VERSION '0.2.1';
-- Suppress expected deprecation warnings from the upgrade.
SET LOCAL client_min_messages = ERROR;
ALTER EXTENSION cat_tools UPDATE;
ROLLBACK;
\endif
