\set ECHO none

\i test/setup.sql

-- test_role is set in test/deps.sql

SET LOCAL ROLE :use_role;
CREATE TEMP VIEW argument_modes AS
  SELECT
      (cat_tools.enum_range('cat_tools.routine_argument_mode'))[gs] AS argument_mode
      , (cat_tools.enum_range('cat_tools.routine_proargmode'))[gs] AS proargmode
    FROM generate_series(
      1
      , greatest(
        array_upper(cat_tools.enum_range('cat_tools.routine_argument_mode'), 1)
        , array_upper(cat_tools.enum_range('cat_tools.routine_proargmode'), 1)
      )
    ) gs
;

SELECT plan(
  1
  + 2 -- Simple is() tests
  + 3 * (SELECT count(*)::int FROM argument_modes)
);

SELECT is(
  (SELECT count(*)::int FROM argument_modes)
  , 5
  , 'Verify count from argument_modes'
);

SELECT is(
  cat_tools.routine__argument_mode('i')
  , 'in'
  , 'Simple sanity check of routine__argument_mode()'
);

SELECT is(
  cat_tools.routine__argument_mode('i'::cat_tools.routine_proargmode)
  , 'in'
  , 'Simple sanity check of routine__argument_mode() with enum'
);


SELECT is(cat_tools.routine__argument_mode(proargmode::cat_tools.routine_proargmode)::text, argument_mode, format('SELECT cat_tools.routine__argument_mode(%L::cat_tools.routine_proargmode)', proargmode))
  FROM argument_modes
;

SELECT is(cat_tools.routine__argument_mode(proargmode::"char")::text, argument_mode, format('SELECT cat_tools.routine__argument_mode(%L::"char")', proargmode))
  FROM argument_modes
;

SELECT is(cat_tools.routine__argument_mode(proargmode::"char")::text, argument_mode, format('SELECT cat_tools.routine__argument_mode(%L)', proargmode))
  FROM argument_modes
;

\i test/pgxntool/finish.sql

-- vi: expandtab ts=2 sw=2