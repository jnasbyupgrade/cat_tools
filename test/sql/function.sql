\set ECHO none

\i test/setup.sql

\set s cat_tools

SELECT plan(
  1 -- regprocedure permission check
  + 1 -- regprocedure()
  + 4 -- deprecated function__arg_types() wrappers
  + 2 -- security definer checks for _cat_tools helpers
);

SET LOCAL ROLE :no_use_role;

SELECT throws_ok(
  format($$SELECT %I.%I( 'x', 'x' )$$, :'s', 'regprocedure')
  , '42501'
  , NULL
  , 'Verify public has no perms'
);

/*
 * Deprecated wrappers call through to routine__parse_arg_types, which has a
 * security check that throws when current_user != session_user.  SET SESSION
 * AUTHORIZATION satisfies that check for the rest of this file.
 */
SET SESSION AUTHORIZATION :use_role;

SELECT is(
  :s.regprocedure('array_length', 'anyarray, integer')
  , 'array_length(anyarray,integer)'::regprocedure
  , 'Verify regprocedure()'
);

-- Test deprecated wrapper functions still work
\set VERBOSITY terse
SELECT is(
  :s.function__arg_types($$IN in_int int, INOUT inout_int_array int[], OUT out_char "char", anyelement, boolean DEFAULT false$$)
  , '{int,int[],anyelement,boolean}'::regtype[]
  , 'Verify function__arg_types() with INOUT and OUT'
);

SELECT is(
  :s.function__arg_types($$int, text$$)
  , '{int,text}'::regtype[]
  , 'Verify function__arg_types() with simple args'
);

SELECT is(
  :s.function__arg_types_text($$IN in_int int, INOUT inout_int_array int[], OUT out_char "char", anyelement, boolean DEFAULT false$$)
  , 'integer, integer[], anyelement, boolean'
  , 'Verify function__arg_types_text() with INOUT and OUT'
);

SELECT is(
  :s.function__arg_types_text($$int, text$$)
  , 'integer, text'
  , 'Verify function__arg_types_text() with simple args'
);

/*
 * CRITICAL SECURITY TESTS: Helper functions must NOT be SECURITY DEFINER.
 * If they were, they could be exploited for SQL injection since they execute
 * dynamic SQL.
 */

\set f function__arg_to_regprocedure
\set args_text 'text, text, text'
SELECT string_to_array(:'args_text', ', ') AS args \gset
SELECT isnt_definer('_cat_tools', :'f', :'args'::name[]);

\set f function__drop_temp
\set args_text 'regprocedure, text'
SELECT string_to_array(:'args_text', ', ') AS args \gset
SELECT isnt_definer('_cat_tools', :'f', :'args'::name[]);

\i test/pgxntool/finish.sql

-- vi: expandtab ts=2 sw=2
