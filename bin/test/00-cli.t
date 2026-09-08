#!/usr/bin/env perl
#
# Argument handling and exit codes for bin/update_lint.
#
# The exit codes carry the meaning here, so they are what is asserted; message
# wording is deliberately not, apart from the one substring a caller would grep
# for. 2 (usage) versus 0 matters most: an unreadable file that parsed as "zero
# objects" would turn a typo into a green run.

use strict;
use warnings;
use Test::More;
use lib do { require File::Basename; File::Basename::dirname(__FILE__) };
use TestLint;

# -- Help and malformed invocations -------------------------------------------

{
    my ($rc, $out, $err) = run('--help');
    is($rc, 2, '--help exits 2');
    like($err, qr/usage:/, '--help prints usage to stderr');
    is($out, '', '--help prints nothing to stdout');
}

usage_exit('unknown option', '--bogus');
usage_exit('two positionals (not three)', 'a', 'b');
usage_exit('four positionals', 'a', 'b', 'c', 'd');
usage_exit('--versions with one version', '--versions', '0.2.0');
usage_exit('--versions combined with positionals',
    '--versions', '0.2.0', '0.2.1', 'x', 'y', 'z');
usage_exit('--list-objects combined with positionals',
    '--list-objects', '/dev/null', 'x', 'y', 'z');
usage_exit('--list-objects combined with --versions',
    '--list-objects', '/dev/null', '--versions', '0.2.0', '0.2.1');
usage_exit('--sql-dir with no value', '--sql-dir');

# -- Unreadable input is a usage error, never a silent empty parse ------------

usage_exit('--list-objects on a missing file', '--list-objects', '/nonexistent/nope.sql');
usage_exit('missing OLD_INSTALL', '/nonexistent/old.sql', '/dev/null', '/dev/null');
usage_exit('missing UPDATE_SCRIPT', '/dev/null', '/dev/null', '/nonexistent/upd.sql');
usage_exit('--versions naming a nonexistent version',
    '--versions', '0.0.0', '0.0.1', '--sql-dir', sql_dir());

# A directory opens and reads as the empty string, which is the same shape as
# an unreadable file: nothing parsed, everything clean.
usage_exit('a directory as UPDATE_SCRIPT', '/dev/null', '/dev/null', sql_dir());
usage_exit('--list-objects on a directory', '--list-objects', sql_dir());

# -- Degenerate but legal input ----------------------------------------------

{
    my ($rc, $out) = run('--list-objects', '/dev/null');
    is($rc, 0, '--list-objects /dev/null exits 0');
    is($out, '', '--list-objects /dev/null prints nothing');
}

{
    my ($rc, $out) = run('/dev/null', '/dev/null', '/dev/null');
    is($rc, 0, 'three empty files compare clean');
    like($out, qr/^OK:/m, 'success prints an OK line');
}

# -- Default mode ------------------------------------------------------------

{
    my ($rc, $out) = run_in(repo_root());
    is($rc, 0, 'default mode is clean on the current source');
    like($out, qr/^OK:/m, 'default mode prints an OK line');
}

{
    # Default mode reads <ext>.control relative to the working directory, so it
    # is a usage error anywhere else rather than a guess at the repo layout.
    my ($rc) = run_in(sql_dir());
    is($rc, 2, 'default mode outside the extension root exits 2');
}

done_testing();
