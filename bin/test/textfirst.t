#!/usr/bin/env perl
#
# Prototype-sized test set for bin/update_lint_textfirst: one case per idea the
# sketch is trying to demonstrate, not coverage. Run from the repo root:
#
#     prove bin/test/textfirst.t

use strict;
use warnings;
use Test::More tests => 12;
use File::Temp qw(tempdir);

my $PROG = 'bin/update_lint_textfirst';
my $DIR  = tempdir(CLEANUP => 1);

# Write an OLD/NEW/UPDATE trio and run the linter over it.
sub run_trio {
    my (%f) = @_;
    my @p;
    for my $k (qw(old new update)) {
        my $p = "$DIR/$k.sql";
        open my $fh, '>', $p or die $!;
        print $fh $f{$k} // '';
        close $fh;
        push @p, $p;
    }
    my $out = qx{$^X $PROG @p 2>&1};
    return ($? >> 8, $out);
}

# --- the splitter -----------------------------------------------------------

{
    # A `;` inside a string, a quoted identifier, a comment and a dollar-quoted
    # body must not end a statement. If any did, NEW would hold extra
    # statements OLD lacks and they would be reported as added.
    my $sql = <<'SQL';
SELECT 'a;b';
SELECT "we;ird";
SELECT 1; -- trailing ; comment
CREATE FUNCTION f() RETURNS int LANGUAGE plpgsql AS $body$
BEGIN
  /* nested /* block ; comment */ still in here ; */
  RETURN 1;
END
$body$;
SQL
    my ($rc, $out) = run_trio(old => $sql, new => $sql, update => '');
    is $rc, 0, 'identical files are clean';
    like $out, qr/old \S+ \(4 statements\)/, 'four top-level statements found';
}

# --- rule 4: substring against the whole update file ------------------------

{
    my ($rc, $out) = run_trio(
        old    => "SELECT 1;\n",
        new    => "SELECT 1;\nCREATE TABLE t (a int);\n",
        # Wrapped in a DO block, so it is not a top-level statement over here.
        update => "DO \$\$ BEGIN EXECUTE 'CREATE TABLE t (a int)'; END \$\$;\n",
    );
    is $rc, 0, 'a copy buried in a DO block satisfies the added statement';
    like $out, qr/added 1 \(matched 1, unmatched 0\)/, '... and is counted as matched';
}

{
    my ($rc, $out) = run_trio(
        old    => "SELECT 1;\n",
        new    => "SELECT 1;\nCREATE TABLE t (a int);\n",
        update => "SELECT 2;\n",
    );
    is $rc, 1, 'an added statement with no copy fails';
    like $out, qr/CREATE TABLE t \(a int\)/, '... and is named in the finding';
}

# --- the escape hatch -------------------------------------------------------

{
    my ($rc, $out) = run_trio(
        old    => "SELECT 1;\n",
        new    => "SELECT 1;\nCREATE TABLE t (a int);\n",
        update => "-- update-lint: ok /CREATE TABLE t/ hand-rewritten below\n"
                . "CREATE TABLE t (a int NOT NULL);\n",
    );
    is $rc, 0, 'a waiver suppresses the finding';
    like $out, qr/waived .*hand-rewritten below/, '... and prints its reason';
}

{
    my ($rc, $out) = run_trio(
        old    => "SELECT 1;\n",
        new    => "SELECT 1;\n",
        update => "-- update-lint: ok /nothing matches this/ stale\n",
    );
    is $rc, 0, 'an unused waiver does not fail';
    like $out, qr{UNUSED WAIVER /nothing matches this/}, '... but is reported so it cannot rot';
}

# --- ALTER DEFAULT PRIVILEGES, on the real historical bug -------------------

SKIP: {
    skip 'run from the repo root', 2 unless -e 'sql/cat_tools--0.2.1.sql.in';

    my $out = qx{$^X $PROG --versions 0.2.1 0.2.2 2>&1};
    my @gaps = $out =~ /^\S+: TYPE (\S+) predates/mg;
    is_deeply [sort @gaps], [sort qw(
        cat_tools.constraint_type cat_tools.procedure_type cat_tools.relation_type
        cat_tools.relation_relkind cat_tools.object_type
    )], 'the five enum types that never got GRANT USAGE are flagged';

    # ADP was already in force across this pair, so nothing predates it.
    $out = qx{$^X $PROG --versions 0.2.2 0.2.3 2>&1};
    unlike $out, qr/predates/, 'an ADP present in both installs raises nothing';
}
