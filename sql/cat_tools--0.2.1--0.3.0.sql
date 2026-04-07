CREATE SCHEMA __cat_tools;

CREATE FUNCTION __cat_tools.exec(
  sql text
) RETURNS void LANGUAGE plpgsql AS $body$
BEGIN
  RAISE DEBUG 'sql = %', sql;
  EXECUTE sql;
END
$body$;

CREATE FUNCTION __cat_tools.create_function(
  function_name text
  , args text
  , options text
  , body text
  , grants text DEFAULT NULL
  , comment text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql AS $body$
DECLARE
  c_simple_args CONSTANT text := cat_tools.function__arg_types_text(args);

  create_template CONSTANT text := $template$
CREATE OR REPLACE FUNCTION %s(
%s
) RETURNS %s AS
%L
$template$
  ;

  revoke_template CONSTANT text := $template$
REVOKE ALL ON FUNCTION %s(
%s
) FROM public;
$template$
  ;

  grant_template CONSTANT text := $template$
GRANT EXECUTE ON FUNCTION %s(
%s
) TO %s;
$template$
  ;

  comment_template CONSTANT text := $template$
COMMENT ON FUNCTION %s(
%s
) IS %L;
$template$
  ;

BEGIN
  PERFORM __cat_tools.exec( format(
      create_template
      , function_name
      , args
      , options -- TODO: Force search_path if options ~* 'definer'
      , body
    ) )
  ;
  PERFORM __cat_tools.exec( format(
      revoke_template
      , function_name
      , c_simple_args
    ) )
  ;

  IF grants IS NOT NULL THEN
    PERFORM __cat_tools.exec( format(
        grant_template
        , function_name
        , c_simple_args
        , grants
      ) )
    ;
  END IF;

  IF comment IS NOT NULL THEN
    PERFORM __cat_tools.exec( format(
        comment_template
        , function_name
        , c_simple_args
        , comment
      ) )
    ;
  END IF;
END
$body$;

CREATE FUNCTION __cat_tools.omit_column(
  rel text
  , omit name[] DEFAULT array['oid']
) RETURNS text LANGUAGE sql IMMUTABLE AS $body$
SELECT array_to_string(array(
    SELECT attname
      FROM pg_attribute a
      WHERE attrelid = rel::regclass
        AND NOT attisdropped
        AND attnum >= 0
        AND attname != ANY( omit )
      ORDER BY attnum
    )
  , ', '
)
$body$;

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L23
ALTER DEFAULT PRIVILEGES IN SCHEMA cat_tools GRANT USAGE ON TYPES TO cat_tools__usage;

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L62
-- Recreate _cat_tools.pg_class_v with dynamic column list to handle PG12+ oid visibility.
-- WARNING: CASCADE will drop cat_tools.pg_class_v, _cat_tools.pg_attribute_v,
-- _cat_tools.column, and cat_tools.column. Any user-defined views depending on
-- cat_tools.pg_class_v or cat_tools.column must be recreated after this upgrade.
DROP VIEW IF EXISTS _cat_tools.pg_class_v CASCADE;

SELECT __cat_tools.exec(format($fmt$
CREATE OR REPLACE VIEW _cat_tools.pg_class_v AS
  SELECT c.oid AS reloid
      , %s
      , n.nspname AS relschema
    FROM pg_class c
      LEFT JOIN pg_namespace n ON( n.oid = c.relnamespace )
;
$fmt$
  , __cat_tools.omit_column('pg_catalog.pg_class')
));
REVOKE ALL ON _cat_tools.pg_class_v FROM public;

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L1109
CREATE OR REPLACE VIEW cat_tools.pg_class_v AS
  SELECT *
    FROM _cat_tools.pg_class_v
    WHERE NOT pg_is_other_temp_schema(relnamespace)
      AND relkind IN( 'r', 'v', 'f' )
;
GRANT SELECT ON cat_tools.pg_class_v TO cat_tools__usage;

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L165
CREATE FUNCTION _cat_tools.function__arg_to_regprocedure(
  arguments text
  , function_suffix text
  , api_function_name text
) RETURNS pg_catalog.regprocedure LANGUAGE plpgsql AS $body$
DECLARE
  c_template CONSTANT text := $fmt$CREATE FUNCTION pg_temp.cat_tools__function__%s__temp_function(
    %s
  ) RETURNS %s LANGUAGE plpgsql AS 'BEGIN RETURN; END'
  $fmt$;

  temp_proc pg_catalog.regprocedure;
  sql text;
BEGIN
  IF current_user != session_user THEN
    RAISE EXCEPTION USING
      ERRCODE = '28000'
      , MESSAGE = 'potential use of SECURITY DEFINER detected'
      , DETAIL = format('current_user is %s, session_user is %s', current_user, session_user)
      , HINT = 'Helper functions must not be called from SECURITY DEFINER context.';
  END IF;
  sql := format(
    c_template
    , function_suffix
    , arguments
    , 'void'
  );
  DECLARE
    v_type pg_catalog.regtype;
  BEGIN
    EXECUTE sql;
  EXCEPTION WHEN invalid_function_definition THEN
    v_type := (regexp_matches( SQLERRM, 'function result type must be ([^ ]+) because of' ))[1];
    sql := format(
      c_template
      , function_suffix
      , arguments
      , v_type
    );
    EXECUTE sql;
  END;

  EXECUTE format(
    $$SELECT 'pg_temp.cat_tools__function__%s__temp_function'::pg_catalog.regproc::pg_catalog.regprocedure$$
    , function_suffix
  ) INTO temp_proc;

  RETURN temp_proc;
END
$body$;

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L233
CREATE FUNCTION _cat_tools.function__drop_temp(
  p_regprocedure pg_catalog.regprocedure
  , api_function_name text
) RETURNS void LANGUAGE plpgsql AS $body$
BEGIN
  IF current_user != session_user THEN
    RAISE EXCEPTION USING
      ERRCODE = '28000'
      , MESSAGE = 'potential use of SECURITY DEFINER detected'
      , DETAIL = format('API function %s must not be called from a SECURITY DEFINER function', api_function_name)
      , HINT = 'We detect SECURITY DEFINER context by comparing current_user and session_user, which can cause false positives if SET ROLE is used';
  END IF;

  EXECUTE 'DROP ROUTINE ' || p_regprocedure;
END
$body$;

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L254
GRANT USAGE ON SCHEMA _cat_tools TO cat_tools__usage;
GRANT EXECUTE ON FUNCTION _cat_tools.function__arg_to_regprocedure(text, text, text) TO cat_tools__usage;
GRANT EXECUTE ON FUNCTION _cat_tools.function__drop_temp(pg_catalog.regprocedure, text) TO cat_tools__usage;

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L280
ALTER TYPE cat_tools.relation_type ADD VALUE 'partitioned table';
ALTER TYPE cat_tools.relation_type ADD VALUE 'partitioned index';

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L294
ALTER TYPE cat_tools.relation_relkind ADD VALUE 'p';
ALTER TYPE cat_tools.relation_relkind ADD VALUE 'I';

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L299
CREATE TYPE cat_tools.routine_prokind AS ENUM(
  'f' -- function
  , 'p' -- procedure
  , 'a' -- aggregate
  , 'w' -- window
);
COMMENT ON TYPE cat_tools.routine_prokind IS $$Valid values for `pg_proc.prokind`$$;

CREATE TYPE cat_tools.routine_type AS ENUM(
  'function'
  , 'procedure'
  , 'aggregate'
  , 'window'
);
COMMENT ON TYPE cat_tools.routine_type IS $$Types of routines stored in `pg_proc`$$;

CREATE TYPE cat_tools.routine_proargmode AS ENUM(
  'i' -- in
  , 'o' -- out
  , 'b' -- inout
  , 'v' -- variadic
  , 't' -- table
);
COMMENT ON TYPE cat_tools.routine_proargmode IS $$Valid values for `pg_proc.proargmodes` elements$$;

CREATE TYPE cat_tools.routine_argument_mode AS ENUM(
  'in'
  , 'out'
  , 'inout'
  , 'variadic'
  , 'table'
);
COMMENT ON TYPE cat_tools.routine_argument_mode IS $$Argument modes for function/procedure parameters$$;

CREATE TYPE cat_tools.routine_provolatile AS ENUM(
  'i' -- immutable
  , 's' -- stable
  , 'v' -- volatile
);
COMMENT ON TYPE cat_tools.routine_provolatile IS $$Valid values for `pg_proc.provolatile`$$;

CREATE TYPE cat_tools.routine_volatility AS ENUM(
  'immutable'
  , 'stable'
  , 'volatile'
);
COMMENT ON TYPE cat_tools.routine_volatility IS $$Volatility levels for functions/procedures$$;

CREATE TYPE cat_tools.routine_proparallel AS ENUM(
  's' -- safe
  , 'r' -- restricted
  , 'u' -- unsafe
);
COMMENT ON TYPE cat_tools.routine_proparallel IS $$Valid values for `pg_proc.proparallel`$$;

CREATE TYPE cat_tools.routine_parallel_safety AS ENUM(
  'safe'
  , 'restricted'
  , 'unsafe'
);
COMMENT ON TYPE cat_tools.routine_parallel_safety IS $$Parallel safety levels for functions/procedures$$;

CREATE TYPE cat_tools.routine_argument AS (
  argument_name text
  , argument_type pg_catalog.regtype
  , argument_mode cat_tools.routine_argument_mode
  , argument_default text
);
COMMENT ON TYPE cat_tools.routine_argument IS $$Detailed information about a single function/procedure argument$$;

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L372
SELECT __cat_tools.create_function(
  'cat_tools.relation__kind'
  , 'relkind cat_tools.relation_relkind'
  , 'cat_tools.relation_type LANGUAGE sql STRICT IMMUTABLE'
  , $body$
SELECT CASE relkind
  WHEN 'r' THEN 'table'
  WHEN 'i' THEN 'index'
  WHEN 'S' THEN 'sequence'
  WHEN 't' THEN 'toast table'
  WHEN 'v' THEN 'view'
  WHEN 'c' THEN 'materialized view'
  WHEN 'f' THEN 'composite type'
  WHEN 'm' THEN 'foreign table'
  WHEN 'p' THEN 'partitioned table'
  WHEN 'I' THEN 'partitioned index'
END::cat_tools.relation_type
$body$
  , 'cat_tools__usage'
  , 'Mapping from <pg_class.relkind> to a <cat_tools.relation_type>'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L394
SELECT __cat_tools.create_function(
  'cat_tools.relation__relkind'
  , 'kind cat_tools.relation_type'
  , 'cat_tools.relation_relkind LANGUAGE sql STRICT IMMUTABLE'
  , $body$
SELECT CASE kind
  WHEN 'table' THEN 'r'
  WHEN 'index' THEN 'i'
  WHEN 'sequence' THEN 'S'
  WHEN 'toast table' THEN 't'
  WHEN 'view' THEN 'v'
  WHEN 'materialized view' THEN 'c'
  WHEN 'composite type' THEN 'f'
  WHEN 'foreign table' THEN 'm'
  WHEN 'partitioned table' THEN 'p'
  WHEN 'partitioned index' THEN 'I'
END::cat_tools.relation_relkind
$body$
  , 'cat_tools__usage'
  , 'Mapping from <cat_tools.relation_type> to a <pg_class.relkind> value'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L416
SELECT __cat_tools.create_function(
  'cat_tools.relation__relkind'
  , 'kind text'
  , 'cat_tools.relation_relkind LANGUAGE sql STRICT IMMUTABLE'
  , $body$SELECT cat_tools.relation__relkind(kind::cat_tools.relation_type)$body$
  , 'cat_tools__usage'
  , 'Mapping from <cat_tools.relation_type> to a <pg_class.relkind> value'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L425
SELECT __cat_tools.create_function(
  'cat_tools.relation__kind'
  , 'relkind text'
  , 'cat_tools.relation_type LANGUAGE sql STRICT IMMUTABLE'
  , $body$SELECT cat_tools.relation__kind(relkind::cat_tools.relation_relkind)$body$
  , 'cat_tools__usage'
  , 'Mapping from <cat_tools.relation_type> to a <pg_class.relkind> value'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L434
SELECT __cat_tools.create_function(
  'cat_tools.routine__type'
  , 'prokind cat_tools.routine_prokind'
  , 'cat_tools.routine_type LANGUAGE sql STRICT IMMUTABLE PARALLEL SAFE'
  , $body$
SELECT CASE prokind
  WHEN 'f' THEN 'function'
  WHEN 'p' THEN 'procedure'
  WHEN 'a' THEN 'aggregate'
  WHEN 'w' THEN 'window'
END::cat_tools.routine_type
$body$
  , 'cat_tools__usage'
  , 'Mapping from cat_tools.routine_prokind to cat_tools.routine_type'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L459
CREATE CAST ("char" AS cat_tools.routine_prokind)    WITH INOUT AS IMPLICIT;
CREATE CAST ("char" AS cat_tools.routine_proargmode)  WITH INOUT AS IMPLICIT;
CREATE CAST ("char" AS cat_tools.routine_provolatile) WITH INOUT AS IMPLICIT;
CREATE CAST ("char" AS cat_tools.routine_proparallel) WITH INOUT AS IMPLICIT;

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L463
SELECT __cat_tools.create_function(
  'cat_tools.routine__argument_mode'
  , 'proargmode cat_tools.routine_proargmode'
  , 'cat_tools.routine_argument_mode LANGUAGE sql STRICT IMMUTABLE PARALLEL SAFE'
  , $body$
SELECT CASE proargmode
  WHEN 'i' THEN 'in'
  WHEN 'o' THEN 'out'
  WHEN 'b' THEN 'inout'
  WHEN 'v' THEN 'variadic'
  WHEN 't' THEN 'table'
END::cat_tools.routine_argument_mode
$body$
  , 'cat_tools__usage'
  , 'Mapping from cat_tools.routine_proargmode to cat_tools.routine_argument_mode'
);

SELECT __cat_tools.create_function(
  'cat_tools.routine__volatility'
  , 'provolatile cat_tools.routine_provolatile'
  , 'cat_tools.routine_volatility LANGUAGE sql STRICT IMMUTABLE PARALLEL SAFE'
  , $body$
SELECT CASE provolatile
  WHEN 'i' THEN 'immutable'
  WHEN 's' THEN 'stable'
  WHEN 'v' THEN 'volatile'
END::cat_tools.routine_volatility
$body$
  , 'cat_tools__usage'
  , 'Mapping from cat_tools.routine_provolatile to cat_tools.routine_volatility'
);

SELECT __cat_tools.create_function(
  'cat_tools.routine__parallel_safety'
  , 'proparallel cat_tools.routine_proparallel'
  , 'cat_tools.routine_parallel_safety LANGUAGE sql STRICT IMMUTABLE PARALLEL SAFE'
  , $body$
SELECT CASE proparallel
  WHEN 's' THEN 'safe'
  WHEN 'r' THEN 'restricted'
  WHEN 'u' THEN 'unsafe'
END::cat_tools.routine_parallel_safety
$body$
  , 'cat_tools__usage'
  , 'Mapping from cat_tools.routine_proparallel to cat_tools.routine_parallel_safety'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L502
SELECT __cat_tools.create_function(
  'cat_tools.routine__arg_types'
  , $$func pg_catalog.regprocedure$$
  , $$pg_catalog.regtype[] LANGUAGE sql STABLE$$
  , $body$
SELECT string_to_array(proargtypes::text,' ')::pg_catalog.regtype[]
FROM pg_proc
WHERE oid = $1::pg_catalog.regproc
$body$
  , 'cat_tools__usage'
  , 'Returns all argument types for a function as an array of regtype'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L519
SELECT __cat_tools.create_function(
  'cat_tools.routine__arg_names'
  , $$func pg_catalog.regprocedure$$
  , $$text[] LANGUAGE sql STABLE$$
  , $body$
SELECT
  CASE
    WHEN proargnames IS NULL THEN
      CASE
        WHEN pronargs > 0 THEN
          array_fill(NULL::text, ARRAY[pronargs])
        ELSE
          '{}'::text[]
      END
    WHEN proargmodes IS NULL THEN
      array(
        SELECT CASE WHEN name = '' THEN NULL ELSE name END
        FROM unnest(proargnames) AS name
      )
    ELSE
      array(
        SELECT
          CASE
            WHEN i <= array_length(proargnames, 1) AND proargnames[i] != '' THEN proargnames[i]
            ELSE NULL
          END
        FROM unnest(proargmodes) WITH ORDINALITY AS t(mode, i)
        WHERE mode IN ('i', 'b', 'v')
      )
  END
FROM pg_proc
WHERE oid = $1::pg_catalog.regproc
$body$
  , 'cat_tools__usage'
  , 'Returns all argument names for a function as an array of text. Empty strings are converted to NULL.'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L561
SELECT __cat_tools.create_function(
  'cat_tools.routine__arg_types_text'
  , $$func pg_catalog.regprocedure$$
  , $$text LANGUAGE sql STABLE$$
  , $body$
SELECT array_to_string(cat_tools.routine__arg_types($1), ', ')
$body$
  , 'cat_tools__usage'
  , 'Returns all argument types for a function as a comma-separated text string'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L574
SELECT __cat_tools.create_function(
  'cat_tools.routine__arg_names_text'
  , $$func pg_catalog.regprocedure$$
  , $$text LANGUAGE sql STABLE$$
  , $body$
SELECT array_to_string(cat_tools.routine__arg_names($1), ', ')
$body$
  , 'cat_tools__usage'
  , 'Returns all argument names for a function as a comma-separated text string'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L587
SELECT __cat_tools.create_function(
  'cat_tools.routine__parse_arg_types'
  , $$arguments text$$
  , $$pg_catalog.regtype[] LANGUAGE plpgsql$$
  , $body$
DECLARE
  c_temp_proc CONSTANT pg_catalog.regprocedure := _cat_tools.function__arg_to_regprocedure(arguments, 'arg_types', 'cat_tools.routine__parse_arg_types');
  result pg_catalog.regtype[];
BEGIN
  result := cat_tools.routine__arg_types(c_temp_proc);
  PERFORM _cat_tools.function__drop_temp(c_temp_proc, 'cat_tools.routine__parse_arg_types');
  RETURN result;
END
$body$
  , 'cat_tools__usage'
  , 'Returns argument types for a function argument body as an array. Unlike a
  normal regprocedure cast, this function accepts anything that is valid when
  defining a function.'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L612
SELECT __cat_tools.create_function(
  'cat_tools.routine__parse_arg_names'
  , $$arguments text$$
  , $$text[] LANGUAGE plpgsql$$
  , $body$
DECLARE
  c_temp_proc CONSTANT pg_catalog.regprocedure := _cat_tools.function__arg_to_regprocedure(arguments, 'arg_names', 'cat_tools.routine__parse_arg_names');
  result text[];
BEGIN
  result := cat_tools.routine__arg_names(c_temp_proc);
  PERFORM _cat_tools.function__drop_temp(c_temp_proc, 'cat_tools.routine__parse_arg_names');
  RETURN result;
END
$body$
  , 'cat_tools__usage'
  , 'Returns argument names for a function argument body as an array. Only
  includes IN, INOUT, and VARIADIC arguments (matching routine__parse_arg_types
  behavior). Unnamed arguments appear as NULL in the result array.'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L637
SELECT __cat_tools.create_function(
  'cat_tools.routine__parse_arg_types_text'
  , $$arguments text$$
  , $$text LANGUAGE sql$$
  , $body$
SELECT array_to_string(cat_tools.routine__parse_arg_types($1), ', ')
$body$
  , 'cat_tools__usage'
  , 'Returns argument types for a function argument body as text. Unlike a
  normal regprocedure cast, this function accepts anything that is valid when
  defining a function.'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L653
SELECT __cat_tools.create_function(
  'cat_tools.routine__parse_arg_names_text'
  , $$arguments text$$
  , $$text LANGUAGE sql$$
  , $body$
SELECT array_to_string(cat_tools.routine__parse_arg_names($1), ', ')
$body$
  , 'cat_tools__usage'
  , 'Returns argument names for a function argument body as text. Only
  includes IN, INOUT, and VARIADIC arguments (matching routine__parse_arg_types_text
  behavior). Unnamed arguments appear as empty strings in the result.'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L670
SELECT __cat_tools.create_function(
  'cat_tools.function__arg_types'
  , $$arguments text$$
  , $$pg_catalog.regtype[] LANGUAGE plpgsql$$
  , $body$
BEGIN
  RAISE WARNING 'function__arg_types() is deprecated, use routine__parse_arg_types instead';
  RETURN cat_tools.routine__parse_arg_types(arguments);
END
$body$
  , 'cat_tools__usage'
  , 'DEPRECATED: Use routine__parse_arg_types instead.
  Returns argument types for a function argument body as regtype[]. Only
  includes IN, INOUT, and VARIADIC arguments.'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L689
SELECT __cat_tools.create_function(
  'cat_tools.function__arg_types_text'
  , $$arguments text$$
  , $$text LANGUAGE plpgsql$$
  , $body$
BEGIN
  RAISE WARNING 'function__arg_types_text() is deprecated, use routine__parse_arg_types_text instead';
  RETURN cat_tools.routine__parse_arg_types_text(arguments);
END
$body$
  , 'cat_tools__usage'
  , 'DEPRECATED: Use routine__parse_arg_types_text instead.
  Returns argument types for a function argument body as text. Only
  includes IN, INOUT, and VARIADIC arguments.'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L708
SELECT __cat_tools.create_function(
  'cat_tools.regprocedure'
  , $$
  function_name text
  , arguments text$$
  , $$pg_catalog.regprocedure LANGUAGE sql$$
  , $body$
SELECT format(
  '%s(%s)'
  , $1
  , cat_tools.routine__parse_arg_types_text($2)
)::pg_catalog.regprocedure
$body$
  , 'cat_tools__usage'
  , 'Returns a regprocedure for a given function name and arguments. Unlike a
  normal regprocedure cast, arguments can contain anything that is valid when
  defining a function.'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L742
ALTER TYPE cat_tools.object_type ADD VALUE 'partitioned table' AFTER 'foreign table';
ALTER TYPE cat_tools.object_type ADD VALUE 'partitioned index' AFTER 'partitioned table';

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L890
SELECT __cat_tools.create_function(
  'cat_tools.object__catalog'
  , 'object_type cat_tools.object_type'
  , 'pg_catalog.regclass LANGUAGE sql STRICT IMMUTABLE'
  , $body$
SELECT (
  'pg_catalog.'
  || CASE
    WHEN object_type = ANY( array[
    'table'
    , 'index'
    , 'sequence'
    , 'toast table'
    , 'view'
    , 'materialized view'
    , 'composite type'
    , 'foreign table'
    , 'partitioned table'
    , 'partitioned index'
      ]::cat_tools.object_type[] )
    THEN 'pg_class'
    WHEN object_type = ANY( '{domain constraint,table constraint}'::cat_tools.object_type[] )
      THEN 'pg_constraint'
    WHEN object_type = ANY( '{aggregate,function}'::cat_tools.object_type[] )
      THEN 'pg_proc'
    WHEN object_type::text LIKE '% column'
      THEN 'pg_attribute'
    ELSE CASE object_type
      WHEN 'default value' THEN 'pg_attrdef'
      WHEN 'large object' THEN 'pg_largeobject'
      WHEN 'operator class' THEN 'pg_opclass'
      WHEN 'operator family' THEN 'pg_opfamily'
      WHEN 'operator of access method' THEN 'pg_amop'
      WHEN 'function of access method' THEN 'pg_amproc'
      WHEN 'rule' THEN 'pg_rewrite'
      WHEN 'schema' THEN 'pg_namespace'
      WHEN 'text search parser' THEN 'pg_ts_parser'
      WHEN 'text search dictionary' THEN 'pg_ts_dict'
      WHEN 'text search template' THEN 'pg_ts_template'
      WHEN 'text search configuration' THEN 'pg_ts_config'
      WHEN 'role' THEN 'pg_authid'
      WHEN 'foreign-data wrapper' THEN 'pg_foreign_data_wrapper'
      WHEN 'server' THEN 'pg_foreign_server'
      WHEN 'user mapping' THEN 'pg_user_mapping'
      WHEN 'default acl' THEN 'pg_default_acl'
      WHEN 'event trigger' THEN 'pg_event_trigger'
      WHEN 'access method' THEN 'pg_am'
      ELSE 'pg_' || object_type::text
      END
    END
  )::pg_catalog.regclass
$body$
  , 'cat_tools__usage'
  , 'Returns catalog table that is used to store <object_type> objects'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L1122
-- Recreate pg_attribute_v (dropped via pg_class_v CASCADE above) with omit_column
-- to exclude attmissingval (added in PG11, causes issues with SELECT *).
SELECT __cat_tools.exec(format($fmt$
CREATE OR REPLACE VIEW _cat_tools.pg_attribute_v AS
  SELECT %s
      , c.*
      , t.oid AS typoid
      , %s
    FROM pg_attribute a
      LEFT JOIN _cat_tools.pg_class_v c ON ( c.reloid = a.attrelid )
      LEFT JOIN pg_type t ON ( t.oid = a.atttypid )
;
$fmt$
  , __cat_tools.omit_column('pg_catalog.pg_attribute', array['attmissingval'])
  , __cat_tools.omit_column('pg_catalog.pg_type')
));
REVOKE ALL ON _cat_tools.pg_attribute_v FROM public;

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L1140
CREATE OR REPLACE VIEW _cat_tools.column AS
  SELECT *
    , pg_catalog.format_type(typoid, atttypmod) AS column_type
    , CASE typtype
        WHEN 'd' THEN pg_catalog.format_type(typbasetype, typtypmod)
        WHEN 'e' THEN 'text'
        ELSE pg_catalog.format_type(typoid, atttypmod)
      END AS base_type
    , pk.conkey AS pk_columns
    , ARRAY[attnum] <@ pk.conkey AS is_pk_member
    , (SELECT pg_catalog.pg_get_expr(d.adbin, d.adrelid)
          FROM pg_catalog.pg_attrdef d
          WHERE d.adrelid = a.attrelid
            AND d.adnum = a.attnum
            AND a.atthasdef
        ) AS column_default
    FROM _cat_tools.pg_attribute_v a
      LEFT JOIN pg_constraint pk
        ON ( reloid = pk.conrelid )
          AND pk.contype = 'p'
;
REVOKE ALL ON _cat_tools.column FROM public;

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L1169
-- Recreate pg_extension_v with omit_column to handle PG12+ oid visibility.
DROP VIEW IF EXISTS cat_tools.pg_extension_v;
SELECT __cat_tools.exec(format($fmt$
CREATE OR REPLACE VIEW cat_tools.pg_extension_v AS
  SELECT e.oid
      , %s
      , extnamespace::regnamespace AS extschema
      , extconfig::pg_catalog.regclass[] AS ext_config_tables
    FROM pg_catalog.pg_extension e
      LEFT JOIN pg_catalog.pg_namespace n ON n.oid = e.extnamespace
;
$fmt$
  , __cat_tools.omit_column('pg_catalog.pg_extension')
));
GRANT SELECT ON cat_tools.pg_extension_v TO cat_tools__usage;

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L1185
CREATE OR REPLACE VIEW cat_tools.column AS
  SELECT *
    FROM _cat_tools.column
    WHERE NOT pg_is_other_temp_schema(relnamespace)
      AND attnum > 0
      AND NOT attisdropped
      AND relkind IN( 'r', 'v', 'f' )
      AND (
        pg_has_role(SESSION_USER, relowner, 'USAGE'::text)
        OR has_column_privilege(SESSION_USER, reloid, attnum, 'SELECT, INSERT, UPDATE, REFERENCES'::text)
      )
    ORDER BY relschema, relname, attnum
;
GRANT SELECT ON cat_tools.column TO cat_tools__usage;

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L1202
SELECT __cat_tools.create_function(
  '_cat_tools._pg_sv_column_array'
  , 'OID, SMALLINT[]'
  , 'NAME[] LANGUAGE sql STABLE'
  , $$
    SELECT ARRAY(
        SELECT a.attname
          FROM unnest($2) WITH ORDINALITY AS t(attnum, i)
          JOIN pg_catalog.pg_attribute a ON a.attnum = t.attnum
         WHERE attrelid = $1
         ORDER BY i
    )
$$
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L1582
SELECT __cat_tools.create_function(
  'cat_tools.relation__is_temp'
  , 'relation pg_catalog.regclass'
  , $$boolean LANGUAGE sql STRICT STABLE$$
  , $body$
SELECT relnamespace::pg_catalog.regnamespace::text ~ '^pg_temp'
FROM pg_catalog.pg_class
WHERE oid = $1
$body$
  , 'cat_tools__usage'
  , $$Returns true if the relation is a temporary table (lives in a schema that starts with 'pg_temp').$$
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L1597
SELECT __cat_tools.create_function(
  'cat_tools.relation__is_catalog'
  , 'relation pg_catalog.regclass'
  , $$boolean LANGUAGE sql STRICT STABLE$$
  , $body$
SELECT relnamespace::pg_catalog.regnamespace::text = 'pg_catalog'
FROM pg_catalog.pg_class
WHERE oid = $1
$body$
  , 'cat_tools__usage'
  , 'Returns true if the relation is in the pg_catalog schema.'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L1610
SELECT __cat_tools.create_function(
  'cat_tools.relation__column_names'
  , 'relation pg_catalog.regclass'
  , $$text[] LANGUAGE sql STRICT STABLE$$
  , $body$
SELECT array_agg(quote_ident(attname) ORDER BY attnum)
FROM pg_catalog.pg_attribute
WHERE attrelid = $1
  AND attnum > 0
  AND NOT attisdropped
$body$
  , 'cat_tools__usage'
  , 'Returns an array of quoted column names for a relation in ordinal position order.'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L1702
SELECT __cat_tools.create_function(
  'cat_tools.trigger__parse'
  , $$
  trigger_oid oid
  , OUT trigger_table regclass
  , OUT timing text
  , OUT events text[]
  , OUT defer text
  , OUT row_statement text
  , OUT when_clause text
  , OUT trigger_function regprocedure
  , OUT function_arguments text[]
$$
  , $$record STABLE LANGUAGE plpgsql$$
  , $body$
DECLARE
  r_trigger pg_catalog.pg_trigger;
  v_triggerdef text;
  v_create_stanza text;
  v_on_clause text;
  v_execute_clause text;

  v_work text;
  v_array text[];
BEGIN
  /*
   * Do this first to make sure trigger exists.
   *
   * TODO: After we no longer support < 9.6, test v_triggerdef for NULL instead
   * using the extra block here.
   */
  BEGIN
    SELECT * INTO STRICT r_trigger FROM pg_catalog.pg_trigger WHERE oid = trigger_oid;
  EXCEPTION WHEN no_data_found THEN
    RAISE EXCEPTION 'trigger with OID % does not exist', trigger_oid
      USING errcode = 'undefined_object' -- 42704
    ;
  END;
  trigger_table := r_trigger.tgrelid;
  trigger_function := r_trigger.tgfoid;

  v_triggerdef := pg_catalog.pg_get_triggerdef(trigger_oid, true);

  v_create_stanza := format(
    'CREATE %sTRIGGER %I '
    , CASE WHEN r_trigger.tgconstraint=0 THEN '' ELSE 'CONSTRAINT ' END
    , r_trigger.tgname
  );
  -- Strip CREATE [CONSTRAINT] TRIGGER ... off
  v_work := replace( v_triggerdef, v_create_stanza, '' );

  -- Get BEFORE | AFTER | INSTEAD OF
  timing := split_part( v_work, ' ', 1 );
  timing := timing || CASE timing WHEN 'INSTEAD' THEN ' OF' ELSE '' END;

  -- Strip off timing clause
  v_work := replace( v_work, timing || ' ', '' );

  -- Get array of events (INSERT, UPDATE [OF column, column], DELETE, TRUNCATE)
  v_on_clause := ' ON ' || r_trigger.tgrelid::pg_catalog.regclass || ' ';
  v_array := regexp_split_to_array( v_work, v_on_clause );
  events := string_to_array( v_array[1], ' OR ' );
  -- Get everything after ON table_name
  v_work := v_array[2];
  RAISE DEBUG 'v_work "%"', v_work;

  -- Strip off FROM referenced_table if we have it
  IF r_trigger.tgconstrrelid<>0 THEN
    v_work := replace(
      v_work
      , 'FROM ' || r_trigger.tgconstrrelid::pg_catalog.regclass || ' '
      , ''
    );
  END IF;
  RAISE DEBUG 'v_work "%"', v_work;

  -- Get function arguments
  -- Use a generic pattern rather than the regproc name, since pg_get_triggerdef
  -- may render temp functions as "pg_temp.f" while ::regproc gives "pg_temp_N.f".
  v_execute_clause := E' EXECUTE (FUNCTION|PROCEDURE) \\S+\\(';
  v_array := regexp_split_to_array( v_work, v_execute_clause );
  EXECUTE format(
      CASE WHEN coalesce( rtrim( v_array[2], ')' ), '' ) = ''
        THEN 'SELECT ARRAY[]::text[]'
        ELSE 'SELECT array[ %s ]'
      END
      , rtrim( v_array[2], ')' ) -- Yank trailing )
    )
    INTO function_arguments
  ;
  RAISE DEBUG 'v_array[2] "%"', v_array[2];
  -- Get everything prior to EXECUTE PROCEDURE ...
  v_work := v_array[1];
  RAISE DEBUG 'v_work "%"', v_work;

  row_statement := (regexp_matches( v_work, 'FOR EACH (ROW|STATEMENT)' ))[1];

  -- Get [ NOT DEFERRABLE | [ DEFERRABLE ] { INITIALLY IMMEDIATE | INITIALLY DEFERRED } ]
  v_array := regexp_split_to_array( v_work, 'FOR EACH (ROW|STATEMENT)' );
  RAISE DEBUG 'v_work = "%", v_array = "%"', v_work, v_array;
  defer := rtrim(v_array[1]);

  IF r_trigger.tgqual IS NOT NULL THEN
    when_clause := rtrim(
      (regexp_split_to_array( v_array[2], E' WHEN \\(' ))[2]
      , ')'
    );
  END IF;

  RAISE DEBUG
$$v_create_stanza = "%"
  v_on_clause = "%"
  v_execute_clause = "%"$$
    , v_create_stanza
    , v_on_clause
    , v_execute_clause
  ;

  RETURN;
END
$body$
  , 'cat_tools__usage'
  , 'Provide details about a trigger.'
);

-- https://github.com/jnasbyupgrade/cat_tools/blob/new_functions/sql/cat_tools.sql.in#L1919
DROP FUNCTION __cat_tools.omit_column(
  rel text
  , omit name[] -- DEFAULT array['oid']
);
DROP FUNCTION __cat_tools.exec(
  sql text
);
DROP FUNCTION __cat_tools.create_function(
  function_name text
  , args text
  , options text
  , body text
  , grants text
  , comment text
);
DROP SCHEMA __cat_tools;
