#!/usr/bin/env perl
#
# bin/update_lint against this repo's own released version pairs.
#
# Those files are frozen (SQL file conventions in CLAUDE.md), which makes them a
# stable adversarial oracle no fixture can match: real scripts, real dynamic
# SQL, and one real historical gap. The 0.2.0 and 0.2.1 update paths to 0.2.2
# never granted USAGE on the five enum types that predate 0.2.2, and pinning
# exactly those five here is what proves the check would have caught it.
#
# The current pair is also linted, so a source change that forgets to extend
# the update script fails here as well as in `make update-lint`.

use strict;
use warnings;
use Test::More;
use lib do { require File::Basename; File::Basename::dirname(__FILE__) };
use TestLint;

sub lint_versions {
    my ($old, $new) = @_;
    my ($rc, $out, $err) = run('--versions', $old, $new, '--sql-dir', sql_dir());
    my ($added, $removed) = $out =~ /^  (\d+) object\(s\) added, (\d+) removed$/m;
    return { rc => $rc, added => $added, removed => $removed,
             gaps => findings($out), out => $out, err => $err };
}

# -- Clean pairs -------------------------------------------------------------

for my $case ([ '0.2.0', '0.2.1', 17 ], [ '0.2.3', '0.3.0', 121 ]) {
    my ($old, $new, $n) = @$case;
    my $r = lint_versions($old, $new);
    is($r->{rc},      0,  "$old -> $new is clean");
    is($r->{added},   $n, "$old -> $new adds $n objects");
    is($r->{removed}, 0,  "$old -> $new removes nothing");
}

{
    # The two files differ only inside function bodies, which this check does
    # not look at -- so an empty diff here is the correct answer, not a parse
    # failure that happens to produce one.
    my $r = lint_versions('0.2.2', '0.2.3');
    is($r->{rc},      0, '0.2.2 -> 0.2.3 is clean');
    is($r->{added},   0, '0.2.2 -> 0.2.3 adds nothing');
    is($r->{removed}, 0, '0.2.2 -> 0.2.3 removes nothing');
}

# -- The historical gap ------------------------------------------------------

my @missing_grants = map { "acl:type:cat_tools.$_" }
    qw(constraint_type object_type procedure_type relation_relkind relation_type);

for my $case ([ '0.2.0', '0.2.2', 22 ], [ '0.2.1', '0.2.2', 5 ]) {
    my ($old, $new, $n) = @$case;
    my $r = lint_versions($old, $new);
    is($r->{rc},    1,  "$old -> $new reports a gap");
    is($r->{added}, $n, "$old -> $new adds $n objects");
    is_deeply($r->{gaps}, \@missing_grants,
        "$old -> $new is missing exactly the five pre-0.2.2 enum type grants");
}

# -- The current pair --------------------------------------------------------

{
    my ($rc, $out) = run_in(repo_root());
    is($rc, 0, 'the current version pair is clean')
        or diag($out);
}

done_testing();
