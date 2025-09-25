\set ECHO none

\i test/setup.sql

-- test_role is set in test/deps.sql

SET LOCAL ROLE :use_role;
CREATE TEMP VIEW routine_kinds AS
  SELECT
      (cat_tools.enum_range('cat_tools.routine_type'))[gs] AS routine_type
      , (cat_tools.enum_range('cat_tools.routine_prokind'))[gs] AS prokind
    FROM generate_series(
      1
      , greatest(
        array_upper(cat_tools.enum_range('cat_tools.routine_type'), 1)
        , array_upper(cat_tools.enum_range('cat_tools.routine_prokind'), 1)
      )
    ) gs
;

SELECT plan(
  1
  + 2 -- Simple is() tests
  + 3 * (SELECT count(*)::int FROM routine_kinds)
);

SELECT is(
  (SELECT count(*)::int FROM routine_kinds)
  , 4
  , 'Verify count from routine_kinds'
);

SELECT is(
  cat_tools.routine__type('f')
  , 'function'
  , 'Simple sanity check of routine__type()'
);

SELECT is(
  cat_tools.routine__type('f'::cat_tools.routine_prokind)
  , 'function'
  , 'Simple sanity check of routine__type() with enum'
);


SELECT is(cat_tools.routine__type(prokind::cat_tools.routine_prokind)::text, routine_type, format('SELECT cat_tools.routine__type(%L::cat_tools.routine_prokind)', prokind))
  FROM routine_kinds
;

SELECT is(cat_tools.routine__type(prokind::"char")::text, routine_type, format('SELECT cat_tools.routine__type(%L::"char")', prokind))
  FROM routine_kinds
;

SELECT is(cat_tools.routine__type(prokind::"char")::text, routine_type, format('SELECT cat_tools.routine__type(%L)', prokind))
  FROM routine_kinds
;

\i test/pgxntool/finish.sql

-- vi: expandtab ts=2 sw=2