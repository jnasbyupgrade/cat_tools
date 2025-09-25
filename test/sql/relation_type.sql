\set ECHO none

\i test/setup.sql

-- test_role is set in test/deps.sql

SET LOCAL ROLE :use_role;
CREATE TEMP VIEW kinds AS
  SELECT
      (cat_tools.enum_range('cat_tools.relation_type'))[gs] AS kind
      , (cat_tools.enum_range('cat_tools.relation_relkind'))[gs] AS relkind
    FROM generate_series(
      1
      , greatest(
        array_upper(cat_tools.enum_range('cat_tools.relation_type'), 1)
        , array_upper(cat_tools.enum_range('cat_tools.relation_relkind'), 1)
      )
    ) gs
;

SELECT plan(
  1
  + 2 -- Simple is() tests
  + 2 * (SELECT count(*)::int FROM kinds)
);

SELECT is(
  (SELECT count(*)::int FROM kinds)
  , 10 
  , 'Verify count from kinds'
);

SELECT is(
  cat_tools.relation__kind('r')
  , 'table'
  , 'Simple sanity check of relation__kind()'
);
SELECT is(
  cat_tools.relation__relkind('table')
  , 'r'
  , 'Simple sanity check of relation__relkind()'
);


SELECT is(cat_tools.relation__relkind(kind)::text, relkind, format('SELECT cat_tools.relation_relkind(%L)', kind))
  FROM kinds
;

SELECT is(cat_tools.relation__kind(relkind)::text, kind, format('SELECT cat_tools.relation_type(%L)', relkind))
  FROM kinds
;

\i test/pgxntool/finish.sql

-- vi: expandtab ts=2 sw=2
