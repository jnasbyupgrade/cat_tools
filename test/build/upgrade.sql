\set ECHO none
\i test/pgxntool/psql.sql
\t

-- Sanity check: install a previous version and upgrade to current.
--
-- cat_tools 0.2.1's install script is incompatible with PG11+:
--   PG11: pg_attribute gained attmissingval (pseudo-type anyarray, not usable in views)
--   PG12: system catalog oid became a visible column, causing duplicate column names
-- Use the current version as the starting point on PG11+.
SELECT current_setting('server_version_num')::int >= 110000 AS pg11plus \gset

\if :pg11plus
BEGIN;
CREATE EXTENSION cat_tools VERSION '0.3.0';
-- Suppress the "version already installed" notice from the no-op UPDATE.
-- (SET LOCAL client_min_messages inside the install script is scoped to that
-- script and reverts when it returns, so we must set it again here.)
SET LOCAL client_min_messages = WARNING;
ALTER EXTENSION cat_tools UPDATE;
ROLLBACK;
\else
-- PG10 and below: 0.2.1 installs cleanly, test the real upgrade.
BEGIN;
CREATE EXTENSION cat_tools VERSION '0.2.1';
-- Suppress expected deprecation warnings from the upgrade.
SET LOCAL client_min_messages = ERROR;
ALTER EXTENSION cat_tools UPDATE;
ROLLBACK;
\endif
