\set ECHO none

\i test/setup.sql

\set s cat_tools
\set f relation__column_names

SELECT plan(8);

SET LOCAL ROLE :no_use_role;

SELECT throws_ok(
  format(
    $$SELECT %I.%I( %L )$$
    , :'s', :'f'
    , 'temp_test_table'
  )
  , '42501'
  , NULL
  , 'Verify public has no perms'
);

SET LOCAL ROLE :use_role;

SELECT lives_ok($$CREATE TEMP TABLE temp_test_table(col1 int, col2 text, col3 boolean, col4 timestamp, col5 numeric)$$, 'Create temp table with multiple columns');

SELECT is(
  cat_tools.relation__column_names('temp_test_table'::regclass)
  , '{col1,col2,col3,col4,col5}'::text[]
  , 'Temp table returns expected column names'
);

SELECT lives_ok($$ALTER TABLE temp_test_table DROP COLUMN col3$$, 'Drop middle column from temp table');

SELECT is(
  cat_tools.relation__column_names('temp_test_table'::regclass)
  , '{col1,col2,col4,col5}'::text[]
  , 'Temp table with dropped column returns expected column names'
);

SELECT lives_ok($$CREATE TEMP TABLE test_table(id int, name text)$$, 'Create test table with columns');

SELECT is(
  cat_tools.relation__column_names('test_table'::regclass)
  , '{id,name}'::text[]
  , 'Test table returns expected column names'
);

SELECT is(
  cat_tools.relation__column_names(NULL)
  , NULL
  , 'NULL input returns NULL (STRICT function)'
);

\i test/pgxntool/finish.sql

-- vi: expandtab ts=2 sw=2