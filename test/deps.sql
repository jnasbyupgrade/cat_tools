-- IF NOT EXISTS will emit NOTICEs, which is annoying
SET client_min_messages = WARNING;

-- Add any test dependency statements here
-- Note: pgTap is loaded by setup.sql
--CREATE EXTENSION IF NOT EXISTS ...;

/*
 * Now load our extension. We don't use IF NOT EXISTS here because we want an
 * error if the extension is already loaded (because we want to ensure we're
 * getting the very latest version).
 */
CREATE EXTENSION cat_tools;

-- Used by several unit tests
\set no_use_role cat_tools_testing__no_use_role
\set use_role cat_tools_testing__use_role
CREATE ROLE :no_use_role;
CREATE ROLE :use_role;

GRANT cat_tools__usage TO :use_role;
-- PG15+ removed CREATE on public schema from PUBLIC; grant it explicitly for tests
-- that need to create shadow names in public to test catalog lookup correctness.
GRANT CREATE ON SCHEMA public TO :use_role;

