\set ECHO none

\i test/setup.sql

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

CREATE TEMP VIEW volatilities AS
  SELECT
      (cat_tools.enum_range('cat_tools.routine_volatility'))[gs] AS volatility
      , (cat_tools.enum_range('cat_tools.routine_provolatile'))[gs] AS provolatile
    FROM generate_series(
      1
      , greatest(
        array_upper(cat_tools.enum_range('cat_tools.routine_volatility'), 1)
        , array_upper(cat_tools.enum_range('cat_tools.routine_provolatile'), 1)
      )
    ) gs
;

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
    (1 + 2 + 3 * (SELECT count(*)::int FROM routine_kinds)) -- routine__type
  + (1 + 2 + 3 * (SELECT count(*)::int FROM argument_modes)) -- routine__argument_mode
  + (1 + 2 + 3 * (SELECT count(*)::int FROM volatilities)) -- routine__volatility
  + (1 + 2 + 3 * (SELECT count(*)::int FROM parallel_safeties)) -- routine__parallel_safety
);

-- routine__type
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

-- routine__argument_mode
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

-- routine__volatility
SELECT is(
  (SELECT count(*)::int FROM volatilities)
  , 3
  , 'Verify count from volatilities'
);

SELECT is(
  cat_tools.routine__volatility('i')
  , 'immutable'
  , 'Simple sanity check of routine__volatility()'
);

SELECT is(
  cat_tools.routine__volatility('i'::cat_tools.routine_provolatile)
  , 'immutable'
  , 'Simple sanity check of routine__volatility() with enum'
);

SELECT is(cat_tools.routine__volatility(provolatile::cat_tools.routine_provolatile)::text, volatility, format('SELECT cat_tools.routine__volatility(%L::cat_tools.routine_provolatile)', provolatile))
  FROM volatilities
;

SELECT is(cat_tools.routine__volatility(provolatile::"char")::text, volatility, format('SELECT cat_tools.routine__volatility(%L::"char")', provolatile))
  FROM volatilities
;

SELECT is(cat_tools.routine__volatility(provolatile::"char")::text, volatility, format('SELECT cat_tools.routine__volatility(%L)', provolatile))
  FROM volatilities
;

-- routine__parallel_safety
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
