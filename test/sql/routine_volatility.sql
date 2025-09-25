\set ECHO none

\i test/setup.sql

-- test_role is set in test/deps.sql

SET LOCAL ROLE :use_role;
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

SELECT plan(
  1
  + 2 -- Simple is() tests
  + 3 * (SELECT count(*)::int FROM volatilities)
);

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

\i test/pgxntool/finish.sql

-- vi: expandtab ts=2 sw=2