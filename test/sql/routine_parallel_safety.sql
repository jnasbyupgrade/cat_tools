\set ECHO none

\i test/setup.sql

-- test_role is set in test/deps.sql

SET LOCAL ROLE :use_role;
CREATE TEMP VIEW parallel_safeties AS
  SELECT
      (cat_tools.enum_range('cat_tools.routine_parallel_safety'))[gs] AS parallel_safety
      , (cat_tools.enum_range('cat_tools.routine_proparallel'))[gs] AS proparallel
    FROM generate_series(
      1
      , greatest(
        array_upper(cat_tools.enum_range('cat_tools.routine_parallel_safety'), 1)
        , array_upper(cat_tools.enum_range('cat_tools.routine_proparallel'), 1)
      )
    ) gs
;

SELECT plan(
  1
  + 2 -- Simple is() tests
  + 3 * (SELECT count(*)::int FROM parallel_safeties)
);

SELECT is(
  (SELECT count(*)::int FROM parallel_safeties)
  , 3
  , 'Verify count from parallel_safeties'
);

SELECT is(
  cat_tools.routine__parallel_safety('s')
  , 'safe'
  , 'Simple sanity check of routine__parallel_safety()'
);

SELECT is(
  cat_tools.routine__parallel_safety('s'::cat_tools.routine_proparallel)
  , 'safe'
  , 'Simple sanity check of routine__parallel_safety() with enum'
);


SELECT is(cat_tools.routine__parallel_safety(proparallel::cat_tools.routine_proparallel)::text, parallel_safety, format('SELECT cat_tools.routine__parallel_safety(%L::cat_tools.routine_proparallel)', proparallel))
  FROM parallel_safeties
;

SELECT is(cat_tools.routine__parallel_safety(proparallel::"char")::text, parallel_safety, format('SELECT cat_tools.routine__parallel_safety(%L::"char")', proparallel))
  FROM parallel_safeties
;

SELECT is(cat_tools.routine__parallel_safety(proparallel::"char")::text, parallel_safety, format('SELECT cat_tools.routine__parallel_safety(%L)', proparallel))
  FROM parallel_safeties
;

\i test/pgxntool/finish.sql

-- vi: expandtab ts=2 sw=2