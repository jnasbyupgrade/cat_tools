\set ECHO none

\i test/setup.sql

\set s cat_tools
\set f relation__is_temp

SELECT plan(5);

SET LOCAL ROLE :no_use_role;

SELECT throws_ok(
  format(
    $$SELECT %I.%I( %L )$$
    , :'s', :'f'
    , 'pg_catalog.pg_class'
  )
  , '42501'
  , NULL
  , 'Verify public has no perms'
);

SET LOCAL ROLE :use_role;

SELECT is(
  cat_tools.relation__is_temp('pg_catalog.pg_class'::regclass)
  , false
  , 'pg_catalog.pg_class is not a temp relation'
);

SELECT lives_ok($$CREATE TEMP TABLE test_temp_table()$$, 'Create temp table for testing');

SELECT is(
  cat_tools.relation__is_temp('test_temp_table'::regclass)
  , true
  , 'temp relation is correctly identified as temp'
);

SELECT is(
  cat_tools.relation__is_temp(NULL)
  , NULL
  , 'NULL input returns NULL (STRICT function)'
);

\i test/pgxntool/finish.sql

-- vi: expandtab ts=2 sw=2