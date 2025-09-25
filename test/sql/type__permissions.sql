\set ECHO none

\i test/setup.sql

-- test_role is set in test/deps.sql

-- Create temp view with all types for testing and grant access to both test roles
-- Note: Must create as superuser before switching roles
CREATE TEMP VIEW type_tests AS
SELECT 'cat_tools.' || typname AS type_name
  FROM pg_type t
  WHERE t.typnamespace = 'cat_tools'::regnamespace
    AND t.typtype IN ('e', 'c') -- enums and composite types
  ORDER BY typname
;

-- Grant access to temp view for both roles
GRANT SELECT ON type_tests TO :use_role, :no_use_role;

SELECT plan(
  (SELECT count(*)::int FROM type_tests) * 2 -- test both failure and success
);

SET LOCAL ROLE :no_use_role;

-- Test type permissions should fail with no_use_role - expect 42501 (insufficient_privilege)
SELECT throws_ok(
  format('SELECT NULL::%s', type_name)
  , '42501' -- insufficient_privilege
  , NULL
  , format('Permission denied trying to use type %s', type_name)
)
FROM type_tests;

SET LOCAL ROLE :use_role;

-- Test type permissions should succeed with use_role
SELECT lives_ok(
  format('SELECT NULL::%s', type_name)
  , format('Permission granted to use type %s', type_name)
)
FROM type_tests;

\i test/pgxntool/finish.sql

-- vi: expandtab ts=2 sw=2