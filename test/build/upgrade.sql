\set ECHO none
\i test/pgxntool/psql.sql
\t

-- Sanity check: install a previous version and upgrade to current.
--
-- cat_tools 0.2.1's install script uses SELECT c.oid AS reloid, c.* which
-- produces duplicate column names on PG12+ (oid became a visible regular
-- column in PG12). Use the current version as the starting point on PG12+.
SELECT current_setting('server_version_num')::int >= 120000 AS pg12plus \gset

\if :pg12plus
BEGIN;
CREATE EXTENSION cat_tools VERSION '0.3.0';
-- Suppress the "version already installed" notice from the no-op UPDATE.
-- (SET LOCAL client_min_messages inside the install script is scoped to that
-- script and reverts when it returns, so we must set it again here.)
SET LOCAL client_min_messages = WARNING;
ALTER EXTENSION cat_tools UPDATE;
ROLLBACK;
\else
BEGIN;
CREATE EXTENSION cat_tools VERSION '0.2.1';
-- Suppress expected deprecation warnings from the upgrade.
SET LOCAL client_min_messages = ERROR;
ALTER EXTENSION cat_tools UPDATE;
ROLLBACK;
\endif
