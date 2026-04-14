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

ALTER DEFAULT PRIVILEGES IN SCHEMA cat_tools GRANT USAGE ON TYPES TO cat_tools__usage;

/*
 * Recreate _cat_tools.pg_class_v with dynamic column list to handle PG12+ oid visibility.
 * WARNING: CASCADE will drop cat_tools.pg_class_v, _cat_tools.pg_attribute_v,
 * _cat_tools.column, and cat_tools.column. Any user-defined views depending on
 * cat_tools.pg_class_v or cat_tools.column must be recreated after this upgrade.
 */
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

CREATE OR REPLACE VIEW cat_tools.pg_class_v AS
  SELECT *
    FROM _cat_tools.pg_class_v
    WHERE NOT pg_is_other_temp_schema(relnamespace)
      AND relkind IN( 'r', 'v', 'f' )
;
GRANT SELECT ON cat_tools.pg_class_v TO cat_tools__usage;

/*
 * Recreate pg_attribute_v (dropped via pg_class_v CASCADE above).
 * On PG11+, pg_attribute gained attmissingval (pseudo-type anyarray, not usable in views).
 * Always include it as text[] — NULL on PG10 (column absent), real value on PG11+.
 * This ensures consistent view schema across all PG versions.
 */
SELECT __cat_tools.exec(format($fmt$
CREATE OR REPLACE VIEW _cat_tools.pg_attribute_v AS
  SELECT %s
      , %s AS attmissingval
      , c.*
      , t.oid AS typoid
      , %s
    FROM pg_attribute a
      LEFT JOIN _cat_tools.pg_class_v c ON ( c.reloid = a.attrelid )
      LEFT JOIN pg_type t ON ( t.oid = a.atttypid )
;
$fmt$
  , __cat_tools.omit_column('pg_catalog.pg_attribute', array['attmissingval'])
  , CASE WHEN EXISTS(
      SELECT 1 FROM pg_catalog.pg_attribute
       WHERE attrelid = 1249  -- OID of pg_catalog.pg_attribute, always 1249
         AND attname = 'attmissingval'
    ) THEN 'a.attmissingval::text::text[]'
      ELSE 'NULL::text[]'
    END
  , __cat_tools.omit_column('pg_catalog.pg_type')
));
REVOKE ALL ON _cat_tools.pg_attribute_v FROM public;

-- Recreate _cat_tools.column (dropped by pg_class_v CASCADE above).
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

-- Recreate cat_tools.column (dropped by pg_class_v CASCADE above).
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

-- Fix cat_tools.pg_extension_v for PG12+ oid visibility.
-- CASCADE is required: pg_extension__get(name) depends on pg_extension_v's row type.
DROP VIEW IF EXISTS cat_tools.pg_extension_v CASCADE;
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

-- Recreate cat_tools.pg_extension__get (dropped by the CASCADE above).
SELECT __cat_tools.create_function(
  'cat_tools.pg_extension__get'
  , 'extension_name name'
  , $$cat_tools.pg_extension_v LANGUAGE plpgsql$$
  , $body$
DECLARE
  r cat_tools.pg_extension_v;
BEGIN
  SELECT INTO STRICT r
      *
    FROM cat_tools.pg_extension_v
    WHERE extname = extension_name
  ;
  RETURN r;
EXCEPTION WHEN no_data_found THEN
  RAISE 'extension "%" does not exist', extension_name
    USING ERRCODE = 'undefined_object'
  ;
END
$body$
  , 'cat_tools__usage'
);

-- Drop temporary helper objects
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
