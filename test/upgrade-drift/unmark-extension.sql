/*
 * Generate ALTER EXTENSION cat_tools DROP ... statements for every object
 * currently owned by the extension.  Executing these statements causes
 * pg_dump to treat those objects as ordinary user objects and emit their
 * full DDL instead of a bare "belonging to extension cat_tools" marker.
 *
 * Execute with:
 *   psql -tA -f unmark-extension.sql | psql -v ON_ERROR_STOP=1 -f -
 *
 * pg_identify_object is available PG 9.3+.  The .identity field returns
 * the canonical object identity string suitable for use in ALTER EXTENSION
 * DROP syntax (e.g. "cat_tools.some_func(integer, text)" for functions).
 */
SELECT format(
    'ALTER EXTENSION cat_tools DROP %s %s;',
    (pg_identify_object(classid, objid, 0)).type,
    (pg_identify_object(classid, objid, 0)).identity
)
FROM pg_depend
WHERE refobjid = (SELECT oid FROM pg_extension WHERE extname = 'cat_tools')
  AND deptype = 'e'
  AND classid != 'pg_extension'::regclass
  /*
   * Skip types that PostgreSQL creates automatically and that cannot be
   * individually removed from extension membership via ALTER EXTENSION DROP:
   *
   * 1. Array types (typelem != 0): every user-defined type gets a companion
   *    array type automatically; it is dropped when the base type is dropped.
   *
   * 2. Relation row types (typrelid != 0 AND relkind != 'c'): every table,
   *    view, materialized view, etc. has an associated composite row type
   *    recorded as an extension member.  ALTER EXTENSION DROP only accepts the
   *    relation itself (e.g. DROP VIEW); the row type cannot be targeted
   *    directly.  We exclude relkind = 'c' (standalone composite types created
   *    with CREATE TYPE ... AS (...)) because those ARE directly droppable.
   */
  AND NOT (
      classid = 'pg_type'::regclass
      AND EXISTS (
          SELECT 1 FROM pg_type t
          LEFT JOIN pg_class c ON c.oid = t.typrelid
          WHERE t.oid = objid
            AND (
                t.typelem  != 0                        -- auto-created array type
                OR (t.typrelid != 0 AND c.relkind != 'c')  -- relation row type (not standalone composite)
            )
      )
  );
