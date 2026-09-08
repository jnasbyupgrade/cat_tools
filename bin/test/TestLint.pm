package TestLint;
#
# Shared plumbing for the bin/update_lint test suite: run the script with a
# known working directory and capture its two streams separately, since which
# stream a line lands on is part of what is being asserted.

use strict;
use warnings;
use Exporter 'import';
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);
use Cwd qw(abs_path);
use Test::More;

our @EXPORT = qw(run run_in repo_root sql_dir fixture write_tmp concat_tmp
                 objects findings usage_exit);

my $TEST_DIR  = abs_path(dirname(__FILE__));
my $REPO_ROOT = abs_path(File::Spec->catdir($TEST_DIR, '..', '..'));
my $SCRIPT    = File::Spec->catfile($REPO_ROOT, 'bin', 'update_lint');
my $TMP       = tempdir(CLEANUP => 1);

sub repo_root { return $REPO_ROOT }
sub sql_dir   { return File::Spec->catdir($REPO_ROOT, 'sql') }
sub fixture   { return File::Spec->catfile($TEST_DIR, 'fixtures', $_[0]) }

sub run { return run_in($REPO_ROOT, @_) }

sub run_in {
    my ($dir, @args) = @_;
    my $out = File::Spec->catfile($TMP, 'stdout');
    my $err = File::Spec->catfile($TMP, 'stderr');
    my $cmd = join ' ', map { "'" . do { my $s = $_; $s =~ s/'/'\\''/g; $s } . "'" }
        ($^X, $SCRIPT, @args);
    system("cd '$dir' && $cmd > '$out' 2> '$err'");
    my $rc = $? >> 8;
    return ($rc, _slurp($out), _slurp($err));
}

sub _slurp {
    my ($p) = @_;
    open my $fh, '<', $p or return '';
    local $/;
    my $t = <$fh>;
    close $fh;
    return defined $t ? $t : '';
}

# Assert that @args is rejected with the usage exit code. There are enough of
# these that spelling out the whole run-and-compare each time buries the
# arguments, which are the only thing that differs between them.
sub usage_exit {
    my ($what, @args) = @_;
    my ($rc) = run(@args);
    is($rc, 2, "$what exits 2");
}

my $seq = 0;

# Write $content to a uniquely named .sql.in under the suite's temp dir.
sub write_tmp {
    my ($content) = @_;
    my $p = File::Spec->catfile($TMP, 'snippet' . ++$seq . '.sql.in');
    open my $fh, '>', $p or die "cannot write $p: $!";
    print $fh $content;
    close $fh;
    return $p;
}

# Concatenate existing files into one new temp file.
sub concat_tmp {
    my @parts = map { _slurp($_) } @_;
    return write_tmp(join "\n", @parts);
}

# The --list-objects output of $file as a list of lines. Fails loudly rather
# than returning an empty set, so a parse error can never read as "no objects".
sub objects {
    my ($file) = @_;
    my ($rc, $out, $err) = run('--list-objects', $file);
    die "update_lint --list-objects $file exited $rc:\n$err" if $rc != 0;
    return [ split /\n/, $out ];
}

# The keys reported as unhandled in $out, sorted. Report lines read
# "  added, never created:   <key>"; pass $which ('added' or 'removed') to take
# one side only, since which side a key lands on is itself asserted.
sub findings {
    my ($out, $which) = @_;
    my $side = defined $which ? quotemeta($which) : '\w+';
    return [ sort($out =~ /^  $side, never \w+:\s+(\S+)$/mg) ];
}

1;
