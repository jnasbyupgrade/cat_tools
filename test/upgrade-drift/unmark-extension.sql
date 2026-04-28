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
   * Skip types that cannot be individually removed from extension membership:
   *
   * 1. Implicitly-created array types (typcategory = 'A'): PostgreSQL creates
   *    one automatically alongside every user-defined type; it is dropped
   *    automatically when the base type is dropped.
   *
   * 2. Row types of relations (tables, views, materialized views): PostgreSQL
   *    records the composite row type as an extension member, but ALTER
   *    EXTENSION DROP only accepts the relation itself (e.g. DROP VIEW), not
   *    the associated row type.  The relation entry in pg_depend handles it.
   */
  AND NOT (
      classid = 'pg_type'::regclass
      AND EXISTS (
          SELECT 1 FROM pg_type t
          WHERE t.oid = objid
            AND (
                t.typcategory = 'A'
                OR EXISTS (
                    SELECT 1 FROM pg_class c WHERE c.reltype = t.oid
                )
            )
      )
  );
