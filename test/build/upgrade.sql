\set ECHO none
\i test/pgxntool/psql.sql
\t

-- Sanity check: install the previous version and upgrade to current.
--
-- cat_tools 0.2.1's install script uses SELECT c.oid AS reloid, c.* which
-- produces a duplicate "oid" column on PG12+ (where oid became a visible
-- column). The upgrade script fixes this, but we can't get there from the
-- broken install. Skip on PG12+.
SELECT current_setting('server_version_num')::int < 120000 AS pre_pg12 \gset

\if :pre_pg12
BEGIN;
CREATE EXTENSION cat_tools VERSION '0.2.1';
ALTER EXTENSION cat_tools UPDATE;
ROLLBACK;
\else
\echo 'Skipping upgrade-from-0.2.1: install script incompatible with PG12+ (duplicate oid in catalog views)'
\endif
