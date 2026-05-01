#!/usr/bin/env perl
#
# compare-dumps.pl -- normalize and diff two pg_dump --schema-only outputs
#
# Usage: compare-dumps.pl <fresh.sql> <upgraded.sql>
#
# Exits 0 if the schemas are equivalent after normalization; exits 1 and
# prints a unified diff to stdout if they differ.
#
# Normalization strategy:
#   pg_dump precedes every object with a 3-line section header:
#       --
#       -- Name: foo; Type: FUNCTION; Schema: cat_tools; Owner: postgres
#       --
#   We use these headers as block boundaries (then discard them).  This is
#   more robust than blank-line splitting because function bodies may contain
#   blank lines, which would otherwise cause spurious block splits.
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

    # Strip \restrict / \unrestrict nonces (random per-dump security tokens,
    # always differ between a fresh install and an upgrade of the same version)
    $content =~ s/^\\restrict \S+\n//mg;
    $content =~ s/^\\unrestrict \S+\n//mg;

    # Strip pg_dump file-level boilerplate (header comment lines)
    $content =~ s/^-- PostgreSQL database dump[^\n]*\n//mg;
    $content =~ s/^-- Dumped (?:from|by) [^\n]*\n//mg;

    # Strip SET statements (search_path, lock_timeout, etc.)
    $content =~ s/^SET [^\n]+\n//mg;

    # Strip SELECT pg_catalog.set_config(...) emitted between objects
    $content =~ s/^SELECT pg_catalog\.set_config\([^\n]*\n//mg;

    # Split into per-object blocks using pg_dump's 3-line section headers as
    # boundaries.  Each object starts with:
    #   --\n-- Name: ...; Type: ...; Schema: ...; Owner: ...\n--\n
    # The header is discarded; only the DDL content of each block is kept.
    my @blocks;
    for my $chunk (split /\n--\n-- Name: [^\n]+\n--\n/, $content) {
        $chunk =~ s/^\s+|\s+$//g;    # strip leading/trailing whitespace
        next unless $chunk =~ /\S/;

        # Skip the extension's own CREATE/COMMENT/ALTER record — the extension
        # record is always identical after both paths but varies only in OID.
        next if $chunk =~ /^(?:CREATE|COMMENT ON|ALTER) EXTENSION\b/;

        # Normalize trailing whitespace per line
        $chunk =~ s/[ \t]+$//mg;

        push @blocks, $chunk;
    }

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
