#!/usr/bin/env perl
#
# The diff and coverage half of bin/update_lint: given two install scripts and
# an update script, which objects are reported as unhandled.
#
# Findings are matched by identifier only, never by message wording, so that
# rephrasing the report does not turn into a test edit.

use strict;
use warnings;
use Test::More;
use lib do { require File::Basename; File::Basename::dirname(__FILE__) };
use TestLint;

# Objects the extra fixture adds on top of all-forms, hand-listed so the
# expectation does not come from the tool being tested.
my @delta = (
    'acl:function:lt.measure/1',
    'acl:relation:lt.thing_v3',
    'acl:type:lt.size',
    'comment:type:lt.size',
    'enumval:lt.size:large',
    'enumval:lt.size:small',
    'function:lt.measure/1',
    'relation:lt.thing_v3',
    'type:lt.size',
);

my $base     = fixture('all-forms.sql.in');
my $extended = concat_tmp($base, fixture('all-forms-extra.sql.in'));

# -- A file against itself ---------------------------------------------------

{
    my ($rc, $out) = run($base, $base, '/dev/null');
    is($rc, 0, 'a file against itself with no update script is clean');
    like($out, qr/0 object\(s\) added, 0 removed/, 'no objects added or removed');
}

# -- The delta, uncovered ----------------------------------------------------

{
    my ($rc, $out, $err) = run($base, $extended, '/dev/null');
    is($rc, 1, 'an empty update script leaves the whole delta unhandled');
    is_deeply(findings($out, 'added'), [@delta], 'every added object is reported');
    is_deeply(findings($out, 'removed'), [], 'nothing is reported as removed');
    like($err, qr/^FAIL:/m, 'the summary goes to stderr');
}

# -- The delta, reversed -----------------------------------------------------

{
    my ($rc, $out) = run($extended, $base, '/dev/null');
    is($rc, 1, 'the reversed pair is equally unhandled');
    is_deeply(findings($out, 'removed'), [@delta], 'the same delta appears on the removal side');
    is_deeply(findings($out, 'added'), [], 'nothing is reported as added');
}

# -- The delta, covered ------------------------------------------------------

{
    my ($rc, $out) = run($base, $extended, fixture('update-covers-all.sql.in'));
    is($rc, 0, 'an update script covering the delta is clean');
    like($out, qr/9 object\(s\) added, 0 removed/, 'all nine added objects are seen');
}

# -- Coverage is set membership, not substring search ------------------------

{
    # cat_tools.column is a substring of _cat_tools.column, so a substring
    # search would call the second one covered by the first.
    my $old = write_tmp("CREATE SCHEMA s;\n");
    my $new = write_tmp("CREATE SCHEMA s;\nCREATE VIEW _s.thing AS SELECT 1;\nCREATE VIEW s.thing AS SELECT 1;\n");
    my $upd = write_tmp("CREATE VIEW s.thing AS SELECT 1;\n");
    my ($rc, $out) = run($old, $new, $upd);
    is($rc, 1, 'a similarly-named object does not stand in for the real one');
    is_deeply(findings($out, 'added'), ['relation:_s.thing'],
        'only the genuinely uncovered object is reported');
}

{
    # A name that appears only in a comment is not coverage. This is the
    # silent-false-negative direction: the lint says handled, nothing was done.
    my $old = write_tmp("CREATE SCHEMA s;\n");
    my $new = write_tmp("CREATE SCHEMA s;\nCREATE VIEW s.v AS SELECT 1;\n");
    my $upd = write_tmp("-- TODO: create s.v here\n/* s.v */\n");
    my ($rc, $out) = run($old, $new, $upd);
    is($rc, 1, 'a mention inside a comment is not coverage');
    is_deeply(findings($out, 'added'), ['relation:s.v'], 's.v is still reported');
}

{
    # ... while a name inside a string literal IS coverage, because that is
    # where create_function() keeps the objects it builds.
    my $old = write_tmp("CREATE SCHEMA s;\n");
    my $new = write_tmp("CREATE SCHEMA s;\nCREATE FUNCTION s.f(a int) RETURNS void LANGUAGE sql AS \$\$SELECT\$\$;\n");
    my $upd = write_tmp(<<'SQL');
SELECT __cat_tools.create_function(
  's.f'
  , 'a int'
  , 'void LANGUAGE sql'
  , $body$SELECT$body$
);
SQL
    my ($rc) = run($old, $new, $upd);
    is($rc, 0, 'an object built through create_function() counts as coverage');
}

# -- Coverage has a direction -------------------------------------------------
#
# The two halves below are the same object and the same update script, run the
# two ways round: a DROP is not coverage for an addition, nor a CREATE for a
# removal. Getting this wrong is silent -- the report says the update script
# handled the object, when what it did was the opposite.

{
    my $old  = write_tmp("CREATE SCHEMA s;\n");
    my $new  = write_tmp("CREATE SCHEMA s;\nCREATE VIEW s.v AS SELECT 1;\n");
    my $create = "CREATE VIEW s.v AS SELECT 1;\n";
    my $drop   = "DROP VIEW IF EXISTS s.v;\n";

    my ($rc, $out) = run($old, $new, write_tmp($drop));
    is($rc, 1, 'a DROP is not coverage for an added object');
    is_deeply(findings($out, 'added'), ['relation:s.v'], 'the addition is still reported');

    my ($rrc, $rout) = run($new, $old, write_tmp($create));
    is($rrc, 1, 'a CREATE is not coverage for a removed object');
    is_deeply(findings($rout, 'removed'), ['relation:s.v'], 'the removal is still reported');

    # The rebuild pattern an update script really uses must stay covered.
    my ($brc) = run($old, $new, write_tmp($drop . $create));
    is($brc, 0, 'a DROP followed by a CREATE covers the addition');
}

{
    # An added enum label is created by ALTER TYPE, never by a CREATE, so the
    # rule cannot be "the update script must contain a CREATE".
    my $old = write_tmp("CREATE TYPE s.e AS ENUM( 'a' );\n");
    my $new = write_tmp("CREATE TYPE s.e AS ENUM( 'a', 'b' );\n");
    my ($rc) = run($old, $new, write_tmp("ALTER TYPE s.e ADD VALUE 'b';\n"));
    is($rc, 0, 'ALTER TYPE ... ADD VALUE covers an added label');
}

{
    # ACLs and comments are presence keys: a REVOKE is how you remove a grant,
    # so both directions count as having been dealt with.
    my $old = write_tmp("CREATE VIEW s.v AS SELECT 1;\nGRANT SELECT ON s.v TO r;\n");
    my $new = write_tmp("CREATE VIEW s.v AS SELECT 1;\n");
    my ($rc, $out) = run($old, $new, write_tmp("REVOKE SELECT ON s.v FROM r;\n"));
    is($rc, 0, 'a REVOKE covers a removed ACL') or diag($out);
}

# -- A function grant with no argument list ----------------------------------

{
    # PostgreSQL accepts the bare name where it is unambiguous, so the grant it
    # writes has to be matched against whatever arity the function has.
    my $old = write_tmp("CREATE SCHEMA s;\n");
    my $new = write_tmp(<<'SQL');
CREATE SCHEMA s;
CREATE FUNCTION s.f(a int) RETURNS void LANGUAGE sql AS $$SELECT$$;
GRANT EXECUTE ON FUNCTION s.f(a int) TO r;
SQL
    my $upd = write_tmp(<<'SQL');
CREATE FUNCTION s.f(a int) RETURNS void LANGUAGE sql AS $$SELECT$$;
GRANT EXECUTE ON FUNCTION s.f TO r;
SQL
    my ($rc, $out) = run($old, $new, $upd);
    is($rc, 0, 'a grant with no argument list covers the arity that exists')
        or diag($out);
}

# -- Enum values -------------------------------------------------------------

{
    my $old = write_tmp("CREATE TYPE s.e AS ENUM( 'a', 'b' );\n");
    my $new = write_tmp("CREATE TYPE s.e AS ENUM( 'a', 'b', 'c' );\n");

    my ($rc, $out) = run($old, $new, '/dev/null');
    is($rc, 1, 'a new enum label with no update script is a finding');
    is_deeply(findings($out, 'added'), ['enumval:s.e:c'], 'the new label is named');

    for my $upd ("ALTER TYPE s.e ADD VALUE 'c';\n",
                 "ALTER TYPE s.e ADD VALUE 'c' AFTER 'b';\n",
                 "ALTER TYPE s.e ADD VALUE IF NOT EXISTS 'c' BEFORE 'a';\n")
    {
        my ($crc) = run($old, $new, write_tmp($upd));
        my $label = $upd;
        $label =~ s/\s+/ /g;
        is($crc, 0, "coverage via: $label");
    }
}

# -- ALTER DEFAULT PRIVILEGES ------------------------------------------------

{
    my $adp = "ALTER DEFAULT PRIVILEGES IN SCHEMA s GRANT USAGE ON TYPES TO r;\n";
    my $old = write_tmp("CREATE SCHEMA s;\n$adp");
    my $new = write_tmp("CREATE SCHEMA s;\n$adp" . "CREATE TYPE s.t AS ENUM( 'a' );\n");

    my ($rc) = run($old, $new, write_tmp("CREATE TYPE s.t AS ENUM( 'a' );\n"));
    is($rc, 0, 'default privileges already in force in the old install carry into the update');

    # Without that statement anywhere, the type's ACL is genuinely missing.
    my $old2 = write_tmp("CREATE SCHEMA s;\n");
    my $new2 = write_tmp("CREATE SCHEMA s;\n$adp" . "CREATE TYPE s.t AS ENUM( 'a' );\n");
    my ($rc2, $out2) = run($old2, $new2, write_tmp("CREATE TYPE s.t AS ENUM( 'a' );\n"));
    is($rc2, 1, 'a type created before its schema gains default privileges is uncovered');
    is_deeply(findings($out2, 'added'), ['acl:type:s.t'],
        'the missing grant is what gets reported');
}

# -- Seeded table contents are advisory --------------------------------------

{
    my $old = write_tmp("CREATE TABLE s.t(a int);\n");
    my $new = write_tmp("CREATE TABLE s.t(a int);\nINSERT INTO s.t VALUES(1);\n");
    my ($rc, $out) = run($old, $new, write_tmp("-- nothing\n"));
    is($rc, 0, 'a table populated only by the new install does not fail the check');
    like($out, qr/^WARNING: data:s\.t\b/m, '... but it is reported');
}

# -- Removals ----------------------------------------------------------------

{
    my $old = write_tmp(<<'SQL');
CREATE FUNCTION s.gone(
  rel text
  , omit name[] DEFAULT array['oid']
) RETURNS text LANGUAGE sql AS $$SELECT ''$$;
SQL
    my $new = write_tmp("CREATE SCHEMA s;\n");
    my ($rc, $out) = run($old, $new, '/dev/null');
    is($rc, 1, 'a removed function with no update script is a finding');
    is_deeply(findings($out, 'removed'), ['function:s.gone/2'], 'the removed function is named');

    # The multi-line DROP form this repo actually uses, with the DEFAULT clause
    # absent -- a line-oriented match would not find it.
    my $upd = write_tmp(<<'SQL');
DROP FUNCTION s.gone(
  rel text
  , omit name[]
);
SQL
    my ($rc2) = run($old, $new, $upd);
    is($rc2, 1, 'the removal is covered but the new schema is not');
    my (undef, $out2) = run($old, $new, $upd);
    is_deeply(findings($out2, 'removed'), [], 'a multi-line DROP counts as coverage');
}

done_testing();
