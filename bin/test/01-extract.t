#!/usr/bin/env perl
#
# What bin/update_lint extracts from a single file, asserted independently of
# any diff.
#
# The all-forms fixture below is the load-bearing case: it pins the EXACT set,
# not a count. A count still passes when an object is recorded under the wrong
# identity, and a set additionally catches over-extraction -- phantom objects
# invented out of function bodies, comments and format() templates, which is
# the failure mode that makes a lint noisy and then ignored.

use strict;
use warnings;
use Test::More;
use lib do { require File::Basename; File::Basename::dirname(__FILE__) };
use TestLint;

# -- Empty input -------------------------------------------------------------

is_deeply(objects('/dev/null'), [], 'an empty file yields no objects');

# -- The exact object set of the all-forms fixture ---------------------------

my @expected = (
    "acl\tfunction:lt.describe/2",
    "acl\tfunction:lt.internal/0",
    "acl\trelation:lt.thing_v",
    "acl\tschema:lt",
    "acl\ttype:lt.color",
    "acl\ttype:lt.pair",
    "acl\ttype:lt.positive",
    "attr\tlt.pair.first_name",
    "attr\tlt.pair.second_name",
    "attr\tlt.thing.id",
    "attr\tlt.thing.shade",
    "cast\tchar=>lt.color",
    "comment\tfunction:lt.describe/2",
    "comment\ttype:lt.color",
    "constraint\tlt.thing.thing__pk",
    "data\tlt.thing",
    "enumval\tlt.color:blue",
    "enumval\tlt.color:green",
    "enumval\tlt.color:red",
    "enumval\tlt.color:ultraviolet",
    "function\tlt.describe/2",
    "function\tlt.internal/0",
    "index\tlt.thing__shade",
    "relation\tlt.thing",
    "relation\tlt.thing_seq",
    "relation\tlt.thing_v",
    "relation\tlt.thing_v2",
    "role\tlt__usage",
    "schema\tlt",
    "type\tlt.color",
    "type\tlt.pair",
    "type\tlt.positive",
);
is_deeply(objects(fixture('all-forms.sql.in')), \@expected,
    'all-forms.sql.in yields exactly the hand-authored object set');

# The scaffolding assertion is worth calling out on its own: it is a decision
# (created and dropped in one file cancels), not an accident of the fixture.
is_deeply([ grep { /__cat_tools/ } @{ objects(fixture('all-forms.sql.in')) } ], [],
    '__cat_tools scaffolding is excluded from the object set');

{
    my $objs = objects(fixture('all-forms.sql.in'));
    is_deeply($objs, [ sort @$objs ], '--list-objects output is sorted');
}

# -- Dollar quoting ----------------------------------------------------------

{
    # Verbatim shape of __cat_tools.create_function in sql/cat_tools.sql.in: a
    # function body holding format() templates. A scanner that recurses into
    # dollar quotes unconditionally invents four objects here.
    my $f = write_tmp(<<'SQL');
CREATE FUNCTION s.outer_fn(
  a text
  , b text
) RETURNS void LANGUAGE plpgsql AS $body$
DECLARE
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
  comment_template CONSTANT text := $template$
COMMENT ON FUNCTION %s(
%s
) IS %L;
$template$
  ;
BEGIN
  PERFORM 1;
END
$body$;
SQL
    is_deeply(objects($f), ["function\ts.outer_fn/2"],
        'a nested dollar quote inside a function body yields only the outer function');
}

# -- create_function() gateway ----------------------------------------------

{
    my $f = write_tmp(<<'SQL');
SELECT __cat_tools.create_function(
  'cat_tools.foo'
  , 'a int
    , b text
    , c boolean'
  , 'int LANGUAGE sql'
  , $body$
SELECT 1
$body$
  , 'cat_tools__usage'
  , 'Does a thing'
);
SQL
    is_deeply(
        objects($f),
        [ "acl\tfunction:cat_tools.foo/3",
          "comment\tfunction:cat_tools.foo/3",
          "function\tcat_tools.foo/3" ],
        'a multi-line create_function() call yields the function, its ACL and its comment'
    );
}

for my $n (3, 7) {
    # Everything create_function() reads is positional, so a wrong argument
    # count silently reads the wrong argument as the name or the signature.
    my $args = join "\n  , ", map { "'a$_'" } 1 .. $n;
    my ($rc) = run('--list-objects',
        write_tmp("SELECT __cat_tools.create_function(\n  $args\n);\n"));
    is($rc, 3, "create_function() with $n arguments exits 3");
}

{
    # OUT parameters do not count toward the signature, and neither do DEFAULT
    # clauses -- a later DROP writes neither, and both keys must still match.
    my $f = write_tmp(<<'SQL');
CREATE FUNCTION s.f(
  a int
  , OUT b text
  , c name[] DEFAULT array['x']
) RETURNS void LANGUAGE sql AS $$SELECT$$;
DROP FUNCTION s.f(
  a int
  , OUT b text
  , c name[]
);
SQL
    is_deeply(objects($f), [],
        'a DROP derives the same key as its CREATE despite OUT and DEFAULT');
}

{
    my $f = write_tmp("SELECT 1;\n");
    my ($rc, undef, $err) = run('--list-objects', $f);
    is($rc, 3, 'a top-level SELECT that is not a known gateway is unanalyzable');
    like($err, qr/SELECT/, 'the error names the offending statement');
}

# -- exec() gateway ----------------------------------------------------------

{
    my $f = write_tmp(<<'SQL');
SELECT __cat_tools.exec(format($fmt$
CREATE OR REPLACE VIEW s.v AS
  SELECT %s FROM s.t
;
$fmt$
  , 'a, b'
));
SQL
    is_deeply(objects($f), ["relation\ts.v"],
        'DDL inside exec() is extracted, and the format() placeholder is not');
}

# -- Enum labels -------------------------------------------------------------

{
    my $f = write_tmp(<<'SQL');
CREATE TYPE s.e AS ENUM(
  'one', 'two' -- two on one line
  /* interleaved
     block comment */
  , 'three'
  , 'four' -- SED: REQUIRES 9.5!
  , 'five' -- SED: PRIOR TO 12!
);
SQL
    is_deeply(
        objects($f),
        [ "enumval\ts.e:four", "enumval\ts.e:one",
          "enumval\ts.e:three", "enumval\ts.e:two", "type\ts.e" ],
        'enum labels survive leading commas and both comment styles; the PRIOR TO branch is dropped'
    );
}

# -- Preprocessing -----------------------------------------------------------

{
    # sql.mk turns the bare @generated@ marker into a comment; so does the
    # scanner, including one buried in a function body.
    my $f = write_tmp(<<'SQL');
@generated@ VERSIONED FILE!

CREATE SCHEMA s;

CREATE FUNCTION s.f() RETURNS void LANGUAGE plpgsql AS $body$
DECLARE
  x int;
@generated@
BEGIN
  x := 1;
END
$body$;

@generated@
SQL
    is_deeply(objects($f), [ "function\ts.f/0", "schema\ts" ],
        '@generated@ markers are inert wherever they appear');
}

# -- Identity edge cases -----------------------------------------------------

{
    my $a = write_tmp("CREATE OR REPLACE VIEW s.v AS SELECT 1;\n");
    my $b = write_tmp("CREATE VIEW s.v AS SELECT 1;\n");
    is_deeply(objects($a), objects($b),
        'CREATE VIEW and CREATE OR REPLACE VIEW are the same identity');
}

{
    my $f = write_tmp(qq{CREATE CAST ("char" AS s.k) WITH INOUT AS IMPLICIT;\n});
    is_deeply(objects($f), ["cast\tchar=>s.k"],
        'a quoted source type in CREATE CAST is unquoted in the key');
}

# -- Unknown statement forms are a hard error --------------------------------

{
    # Deliberately a form that can never become real SQL, so this test cannot
    # collide with a statement type added to the script later. The known list
    # is not restated here -- keeping it in one place is the point.
    my $f = write_tmp("CREATE SCHEMA s;\n\nCREATE FOO BAR baz;\n");
    my ($rc, undef, $err) = run('--list-objects', $f);
    is($rc, 3, 'an unrecognized CREATE exits 3');
    like($err, qr/:3:/,          'the error names the line number');
    like($err, qr/CREATE FOO BAR baz/, 'the error quotes the offending text');
}

# -- Unterminated constructs -------------------------------------------------
#
# The worst failure this script can have: with no closing delimiter the rest of
# the file holds no statement boundary, fuses onto the statement in progress,
# and every object in it disappears -- reported as a clean "0 added, 0
# removed". Each construct is followed here by objects that must not be lost
# silently, so a regression shows up as exit 0 rather than as a wrong count.

my $swallowed = <<'SQL';
CREATE TABLE s.t(i int);
CREATE VIEW s.v AS SELECT 1;
CREATE FUNCTION s.g() RETURNS void LANGUAGE sql AS $$SELECT$$;
GRANT SELECT ON s.v TO r;
SQL

{
    my $f = write_tmp(<<"SQL");
CREATE FUNCTION s.f() RETURNS void LANGUAGE plpgsql AS \$body\$
BEGIN
  PERFORM 1;
END
\$bodyX\$;
$swallowed
SQL
    my ($rc, undef, $err) = run('--list-objects', $f);
    is($rc, 3, 'a dollar quote with no closing tag exits 3');
    like($err, qr/:1:/, 'the error names the line the dollar quote opened on');
}

{
    my $f = write_tmp("COMMENT ON SCHEMA s IS 'oops;\n$swallowed");
    my ($rc, undef, $err) = run('--list-objects', $f);
    is($rc, 3, 'a string literal with no closing quote exits 3');
    like($err, qr/:1:/, 'the error names the line the literal opened on');
}

{
    my $f = write_tmp("CREATE SCHEMA s;\n/* oops\n$swallowed");
    my ($rc, undef, $err) = run('--list-objects', $f);
    is($rc, 3, 'a block comment with no closing delimiter exits 3');
    like($err, qr/:2:/, 'the error names the line the comment opened on');
}

{
    my $f = write_tmp(qq{CREATE TABLE s."oops(i int);\n$swallowed});
    my ($rc, undef, $err) = run('--list-objects', $f);
    is($rc, 3, 'a quoted identifier with no closing quote exits 3');
    like($err, qr/:1:/, 'the error names the line the identifier opened on');
}

{
    # The outer scan steps over a gateway payload as one literal, so the
    # payload needs a check of its own.
    my $f = write_tmp("SELECT __cat_tools.exec(\$f\$CREATE VIEW s.v AS SELECT 1; /* oops \$f\$);\n");
    my ($rc) = run('--list-objects', $f);
    is($rc, 3, 'an unterminated construct inside an exec() payload exits 3');
}

# -- DO blocks ---------------------------------------------------------------

{
    # All on one line, so nothing is found by looking at line starts.
    my $f = write_tmp("DO \$\$BEGIN CREATE ROLE r1 NOLOGIN; CREATE ROLE r2 NOLOGIN; END\$\$;\n");
    is_deeply(objects($f), [ "role\tr1", "role\tr2" ],
        'DDL sharing a line with a plpgsql keyword is still found');
}

{
    my $f = write_tmp(<<'SQL');
DO $do$
DECLARE
  n int;
  m text := 'x';
BEGIN
  IF NOT EXISTS (SELECT 1) THEN
    RETURN;
  END IF;
  EXECUTE 'CREATE VIEW s.v AS SELECT 1';
END
$do$;
SQL
    is_deeply(objects($f), ["relation\ts.v"],
        'a DECLARE section, an IF and an EXECUTE yield only the executed DDL');
}

{
    my $f = write_tmp("DO \$\$BEGIN x := 1; END\$\$;\n");
    my ($rc, undef, $err) = run('--list-objects', $f);
    is($rc, 3, 'a statement form unknown inside a DO block exits 3');
    like($err, qr/x := 1/, 'the error quotes the offending statement');
}

{
    # PERFORM gets the SELECT rules: a call that is not a known gateway could
    # be creating anything.
    my $f = write_tmp("DO \$\$BEGIN PERFORM frobnicate(); END\$\$;\n");
    my ($rc) = run('--list-objects', $f);
    is($rc, 3, 'PERFORM of an unknown function inside a DO block exits 3');
}

{
    my $f = write_tmp("DO \$\$DECLARE t text; BEGIN EXECUTE t; END\$\$;\n");
    my ($rc) = run('--list-objects', $f);
    is($rc, 3, 'EXECUTE of a payload that is not resolvable DDL exits 3');
}

# A control header is peeled off the statement it guards, so anything hidden
# inside one would never be looked at.

{
    my $f = write_tmp(
        "DO \$\$BEGIN FOR r IN EXECUTE 'CREATE VIEW s.hidden AS SELECT 1' LOOP NULL; END LOOP; END\$\$;\n");
    my ($rc, undef, $err) = run('--list-objects', $f);
    is($rc, 3, 'a gateway inside a FOR ... LOOP header exits 3');
    like($err, qr/header/, 'the error says where it was');
}

{
    my $f = write_tmp(
        "DO \$\$BEGIN IF __cat_tools.exec('CREATE VIEW s.hidden AS SELECT 1') THEN NULL; END IF; END\$\$;\n");
    my ($rc) = run('--list-objects', $f);
    is($rc, 3, 'a gateway inside an IF ... THEN header exits 3');
}

# -- exec() payloads ---------------------------------------------------------

{
    # Every real call site keeps its explanatory comment just outside the
    # SELECT, so a comment moved one line inward must not lose the statement.
    my $f = write_tmp(<<'SQL');
SELECT __cat_tools.exec($fmt$
-- rebuild the view
CREATE OR REPLACE VIEW s.v AS SELECT 1;
$fmt$);
SQL
    is_deeply(objects($f), ["relation\ts.v"],
        'a comment ahead of the DDL in an exec() template does not hide it');
}

{
    my $f = write_tmp("SELECT __cat_tools.exec(format('%s', 'x'));\n");
    my ($rc) = run('--list-objects', $f);
    is($rc, 3, 'an exec() whose payload resolves to no DDL exits 3');
}

{
    # Only format()'s FIRST argument is the template. A value that opens with a
    # DDL keyword is data; parsing it would cancel the table it names.
    my $f = write_tmp(<<'SQL');
CREATE TABLE s.t(i int);
SELECT __cat_tools.exec(format($fmt$
CREATE OR REPLACE VIEW s.w AS SELECT %s FROM s.t
$fmt$
  , 'DROP TABLE s.t'
));
SQL
    is_deeply(objects($f),
        [ "attr\ts.t.i", "relation\ts.t", "relation\ts.w" ],
        'a format() value that reads as DDL does not cancel a real object');
}

# -- A gateway whose object list resolves at run time ------------------------
#
# The fail-open shape: the fragment is DDL, so the zero-DDL guard is satisfied,
# but every object it names was concatenated in at run time. A handler that
# only loops over the pieces records no key and returns clean.

{
    my $f = write_tmp(
        "CREATE SCHEMA s;\n"
      . "SELECT __cat_tools.exec('GRANT USAGE ON SCHEMA ' || quote_ident('s') || ' TO r');\n");
    my ($rc, undef, $err) = run('--list-objects', $f);
    is($rc, 3, 'an exec() GRANT with no object left in it exits 3');
    like($err, qr/GRANT/, 'the error names the statement');
}

{
    my $f = write_tmp(
        "DO \$\$BEGIN EXECUTE 'GRANT USAGE ON SCHEMA ' || quote_ident(s) || ' TO r'; END\$\$;\n");
    my ($rc) = run('--list-objects', $f);
    is($rc, 3, 'a DO-block EXECUTE GRANT with no object left in it exits 3');
}

{
    my $f = write_tmp("DO \$\$BEGIN EXECUTE 'DROP FUNCTION ' || f; END\$\$;\n");
    my ($rc, undef, $err) = run('--list-objects', $f);
    is($rc, 3, 'a DROP with no object left in it exits 3');
    like($err, qr/DROP/, 'the error names the statement');
}

# -- ALTER DEFAULT PRIVILEGES ------------------------------------------------

{
    # TABLES and SEQUENCES are separate default-privilege categories that
    # share the `relation` key kind, so the sequence must come out ungranted.
    my $f = write_tmp(<<'SQL');
CREATE SCHEMA s;
ALTER DEFAULT PRIVILEGES IN SCHEMA s GRANT SELECT ON TABLES TO r;
CREATE TABLE s.t(i int);
CREATE SEQUENCE s.q;
SQL
    is_deeply(objects($f),
        [ "acl\trelation:s.t", "attr\ts.t.i",
          "relation\ts.q", "relation\ts.t", "schema\ts" ],
        'a default privilege on TABLES reaches the table and not the sequence');
}

{
    my $f = write_tmp(<<'SQL');
CREATE SCHEMA s;
ALTER DEFAULT PRIVILEGES IN SCHEMA s GRANT EXECUTE ON FUNCTIONS TO r;
CREATE FUNCTION s.f(a int) RETURNS void LANGUAGE sql AS $$SELECT$$;
SQL
    is_deeply(objects($f),
        [ "acl\tfunction:s.f/1", "function\ts.f/1", "schema\ts" ],
        'a default privilege on FUNCTIONS reaches a later function');
}

{
    my $f = write_tmp(<<'SQL');
CREATE SCHEMA s;
ALTER DEFAULT PRIVILEGES IN SCHEMA s GRANT USAGE ON TYPES TO r;
ALTER DEFAULT PRIVILEGES IN SCHEMA s REVOKE USAGE ON TYPES FROM r;
CREATE TYPE s.e AS ENUM( 'a' );
SQL
    is_deeply(objects($f), [ "enumval\ts.e:a", "schema\ts", "type\ts.e" ],
        'a REVOKE clears the flag, so a later type gets no synthesized grant');
}

{
    my $f = write_tmp("ALTER DEFAULT PRIVILEGES IN SCHEMA s GRANT USAGE ON SCHEMAS TO r;\n");
    my ($rc) = run('--list-objects', $f);
    is($rc, 3, 'a default-privilege category with no model here exits 3');
}

# -- Keys that name more than a bare identifier ------------------------------

{
    my $f = write_tmp("CREATE SCHEMA AUTHORIZATION bob;\n");
    is_deeply(objects($f), ["schema\tbob"],
        'CREATE SCHEMA AUTHORIZATION names the schema after the role');
}

{
    # An index lives in its table's schema, and only a schema-qualified key can
    # meet the qualified name a DROP INDEX writes.
    my $f = write_tmp("CREATE INDEX ix ON s.t(a);\nDROP INDEX s.ix;\n");
    is_deeply(objects($f), [],
        'an index key carries the schema its table is in');
}

{
    my $f = write_tmp("CREATE INDEX ON s.t(a);\n");
    my ($rc) = run('--list-objects', $f);
    is($rc, 3, 'an index with no name exits 3, its generated name being unknown');
}

for my $stmt ('CREATE TRIGGER trg AFTER INSERT ON s.t EXECUTE FUNCTION s.f()',
              'CREATE POLICY p ON s.t USING (true)',
              'CREATE RULE rr AS ON INSERT TO s.t DO NOTHING',
              'CREATE OPERATOR s.+ (LEFTARG = int, RIGHTARG = int, FUNCTION = s.f)')
{
    my ($rc) = run('--list-objects', write_tmp("$stmt;\n"));
    my ($what) = $stmt =~ /\ACREATE (\w+)/;
    is($rc, 3, "$what is refused rather than keyed by its name alone");
}

{
    my $f = write_tmp("CREATE FUNCTION s.f(a int) RETURNS void LANGUAGE sql AS \$\$SELECT\$\$;\nCOMMENT ON FUNCTION s.f IS 'x';\n");
    my ($rc) = run('--list-objects', $f);
    is($rc, 3, 'COMMENT ON FUNCTION with no argument list exits 3');
}

# -- Cancellation reaches an object's dependents ------------------------------

{
    my $f = write_tmp(<<'SQL');
CREATE SCHEMA scaf;
CREATE TYPE scaf.e AS ENUM( 'a', 'b' );
COMMENT ON TYPE scaf.e IS 'scratch';
GRANT USAGE ON TYPE scaf.e TO r;
CREATE TABLE scaf.t(id int CONSTRAINT t__pk PRIMARY KEY);
INSERT INTO scaf.t VALUES(1);
DROP TYPE scaf.e;
DROP TABLE scaf.t;
DROP SCHEMA scaf;
SQL
    is_deeply(objects($f), [],
        'dropping an object cancels its labels, ACL, comment and constraints too');
}

{
    my $f = write_tmp(<<'SQL');
CREATE SCHEMA scaf;
CREATE TYPE scaf.e AS ENUM( 'a' );
CREATE FUNCTION scaf.f(a int) RETURNS void LANGUAGE sql AS $$SELECT$$;
DROP SCHEMA scaf CASCADE;
SQL
    is_deeply(objects($f), [],
        'DROP SCHEMA ... CASCADE cancels the schema contents');
}

{
    my $f = write_tmp(<<'SQL');
CREATE FUNCTION s.f(a int, b int) RETURNS void LANGUAGE sql AS $$SELECT$$;
DROP FUNCTION s.f;
SQL
    is_deeply(objects($f), [],
        'a DROP FUNCTION with no argument list cancels whatever arity exists');
}

{
    # Cancellation is ORDER-sensitive: the same two statements the other way
    # round are the idempotent rebuild an update script really writes, and
    # cancelling that would lose the view and its ACL from the diff entirely.
    my $f = write_tmp(<<'SQL');
CREATE SCHEMA s;
DROP VIEW IF EXISTS s.v;
CREATE VIEW s.v AS SELECT 1;
GRANT SELECT ON s.v TO r;
SQL
    is_deeply(objects($f),
        [ "acl\trelation:s.v", "relation\ts.v", "schema\ts" ],
        'a DROP before the CREATE it precedes cancels nothing');

    my $g = write_tmp(<<'SQL');
CREATE SCHEMA s;
CREATE VIEW s.v AS SELECT 1;
GRANT SELECT ON s.v TO r;
DROP VIEW s.v;
SQL
    is_deeply(objects($g), ["schema\ts"],
        'the same statements as scaffolding still cancel');
}

# -- Columns and composite-type attributes -----------------------------------
#
# Both sides of every diff are fresh install scripts, which state a relation's
# final column list in the CREATE and never with an ALTER. Without keys from
# the CREATE, a column added by editing one is not an object at all and its
# missing ALTER TABLE ADD COLUMN could not be reported.

{
    my $f = write_tmp(<<'SQL');
CREATE TABLE s.t(
  id int
    CONSTRAINT t__pk PRIMARY KEY
  , amount numeric(10,2) NOT NULL DEFAULT 0
  , tags text[] DEFAULT array['a', 'b']
  , CONSTRAINT t__positive CHECK( amount > 0 )
  , UNIQUE (id, amount)
);
SQL
    is_deeply(objects($f),
        [ "attr\ts.t.amount", "attr\ts.t.id", "attr\ts.t.tags",
          "constraint\ts.t.t__pk", "constraint\ts.t.t__positive",
          "relation\ts.t" ],
        'CREATE TABLE yields a key per column, and none for its constraint clauses');
}

{
    my $f = write_tmp("CREATE TYPE s.c AS (a int, b numeric(10,2), c text[]);\n");
    is_deeply(objects($f),
        [ "attr\ts.c.a", "attr\ts.c.b", "attr\ts.c.c", "type\ts.c" ],
        'a composite CREATE TYPE yields a key per attribute');
}

{
    # RANGE and the plain domain form both keep a keyword between AS and the
    # parenthesis, so neither reads as a composite.
    my $f = write_tmp(
        "CREATE TYPE s.r AS RANGE (SUBTYPE = int);\n"
      . "CREATE DOMAIN s.d AS numeric(10,2) CHECK( VALUE > 0 );\n");
    is_deeply(objects($f), [ "type\ts.d", "type\ts.r" ],
        'a range type and a domain contribute no attributes');
}

{
    # ADD COLUMN takes IF NOT EXISTS, which is not the column's name.
    my $f = write_tmp(<<'SQL');
CREATE TABLE s.t(i int);
ALTER TABLE s.t ADD COLUMN IF NOT EXISTS j int;
ALTER TABLE s.t DROP COLUMN IF EXISTS i;
SQL
    is_deeply(objects($f), [ "attr\ts.t.j", "relation\ts.t" ],
        'IF NOT EXISTS is not mistaken for the column being added');
}

# -- Quoted identifiers ------------------------------------------------------

{
    # A `;` inside a name is not a statement boundary, so the splitter must not
    # cut the name in half.
    my $f = write_tmp(qq{CREATE TABLE s."odd;name"(i int);\nCREATE VIEW s.v AS SELECT 1;\n});
    is_deeply(objects($f),
        [ "attr\ts.odd;name.i", "relation\ts.odd;name", "relation\ts.v" ],
        'a semicolon inside a quoted identifier does not split the statement');
}

done_testing();
