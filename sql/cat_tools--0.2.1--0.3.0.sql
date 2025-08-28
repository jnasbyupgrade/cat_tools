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
