#!/usr/bin/env perl
#
# compare-dumps.pl -- normalize and diff two pg_dump --schema-only outputs
#
# Usage: compare-dumps.pl <fresh.sql> <upgraded.sql>
#
# Exits 0 if the schemas are equivalent after normalization; exits 1 and
# prints a unified diff to stdout if they differ.
#
use strict;
use warnings;
use File::Temp qw(tempfile);

die "Usage: compare-dumps.pl <fresh.sql> <upgraded.sql>\n" unless @ARGV == 2;

my ($file1, $file2) = @ARGV;

sub normalize {
    my ($file) = @_;
    open my $fh, '<', $file or die "Cannot open $file: $!\n";
    my $content = do { local $/; <$fh> };
    close $fh;

    my @kept;
    for my $line (split /\n/, $content) {
        # Strip SET statements (search_path, lock_timeout, etc.)
        next if $line =~ /^SET \S/;

        # Strip SELECT pg_catalog.set_config(...) emitted between objects
        next if $line =~ /^SELECT pg_catalog\.set_config\(/;

        # Strip bare '--' separator lines used by pg_dump as section dividers
        next if $line eq '--';

        # Strip pg_dump section header comment lines:
        #   -- Name: foo; Type: FUNCTION; Schema: cat_tools; Owner: postgres
        next if $line =~ /^-- Name: /;

        # Strip pg_dump file-level boilerplate header lines
        next if $line =~ /^-- PostgreSQL database dump/;
        next if $line =~ /^-- Dumped (?:from|by) /;

        # Strip CREATE EXTENSION and COMMENT ON EXTENSION lines — the
        # extension record itself is always identical after both paths and
        # its presence would add noise without signal.
        next if $line =~ /^CREATE EXTENSION /;
        next if $line =~ /^COMMENT ON EXTENSION /;
        next if $line =~ /^ALTER EXTENSION /;

        push @kept, $line;
    }

    # Rejoin, split into per-object blocks on blank lines, drop empty blocks
    my $text   = join("\n", @kept);
    my @blocks = grep { /\S/ } split /\n{2,}/, $text;

    # Normalize trailing whitespace within each block
    @blocks = map {
        (my $b = $_) =~ s/[ \t]+$//mg;
        $b =~ s/^\n+|\n+$//g;
        $b
    } @blocks;

    return join("\n\n", sort @blocks) . "\n";
}

my $norm1 = normalize($file1);
my $norm2 = normalize($file2);

if ($norm1 eq $norm2) {
    exit 0;
}

# Write normalized outputs to temp files so diff can produce a unified diff
my ($tmp1, $tmp1name) = tempfile('drift-fresh-XXXXXX',    TMPDIR => 1, UNLINK => 1);
my ($tmp2, $tmp2name) = tempfile('drift-upgraded-XXXXXX', TMPDIR => 1, UNLINK => 1);
print $tmp1 $norm1;
print $tmp2 $norm2;
close $tmp1;
close $tmp2;

print STDERR "[drift-test] FAIL: schemas differ. Diff (fresh vs upgraded):\n";
system('diff', '-u', '--label', 'fresh', '--label', 'upgraded', $tmp1name, $tmp2name);
exit 1;
