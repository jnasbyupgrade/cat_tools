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

ALTER TYPE cat_tools.relation_type ADD VALUE 'partitioned table';
ALTER TYPE cat_tools.relation_type ADD VALUE 'partitioned index';

ALTER TYPE cat_tools.relation_relkind ADD VALUE 'p';
ALTER TYPE cat_tools.relation_relkind ADD VALUE 'I';

ALTER TYPE cat_tools.object_type ADD VALUE 'partitioned table' AFTER 'foreign table';
ALTER TYPE cat_tools.object_type ADD VALUE 'partitioned index' AFTER 'partitioned table';


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

CREATE CAST ("char" AS cat_tools.routine_prokind)    WITH INOUT AS IMPLICIT;
CREATE CAST ("char" AS cat_tools.routine_proargmode)  WITH INOUT AS IMPLICIT;
CREATE CAST ("char" AS cat_tools.routine_provolatile) WITH INOUT AS IMPLICIT;
CREATE CAST ("char" AS cat_tools.routine_proparallel) WITH INOUT AS IMPLICIT;

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
