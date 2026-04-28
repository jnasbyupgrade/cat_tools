#!/usr/bin/perl
use strict;
use warnings;

# normalize-pgdump-diff.pl — Compare two pg_dump --schema-only outputs.
#
# Strips pg_dump noise, splits into per-object blocks, sorts them for
# stable comparison, normalizes whitespace, then diffs the two sets.
#
# Usage:
#   perl normalize-pgdump-diff.pl --old OLD.pgdump --new NEW.pgdump
#
# Exit 0 if schemas are identical after normalization; exit 1 if they differ.

my ($file_old, $file_new);
while (@ARGV) {
    my $arg = shift @ARGV;
    if    ($arg eq '--old') { $file_old = shift @ARGV }
    elsif ($arg eq '--new') { $file_new = shift @ARGV }
    else  { die "Unknown argument: $arg\n" }
}
die "Usage: $0 --old FILE --new FILE\n" unless $file_old && $file_new;

sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "Cannot open $path: $!\n";
    my $content = do { local $/ = undef; <$fh> };
    close $fh;
    return $content;
}

# Remove pg_dump header lines, SET statements, and section-comment headers
# that vary between dumps (timestamps, dependency lists, etc.).
sub strip_noise {
    my ($content) = @_;

    # Timestamp and dump-metadata comments
    $content =~ s/^--\s+PostgreSQL database dump[^\n]*\n//mg;
    $content =~ s/^--\s+Dumped from database version[^\n]*\n//mg;
    $content =~ s/^--\s+Dumped by pg_dump version[^\n]*\n//mg;

    # Per-object section headers emitted by pg_dump
    # e.g. "-- Name: foo; Type: FUNCTION; Schema: cat_tools; Owner: -"
    $content =~ s/^--\s+Name:[^\n]*;\s*Type:[^\n]*\n//mg;

    # Dependency-list comments
    $content =~ s/^--\s+Dependencies:[^\n]*\n//mg;

    # SET / SELECT pg_catalog.set_config statements (session-local, not schema)
    $content =~ s/^SET\s+[^\n]+\n//mg;
    $content =~ s/^SELECT pg_catalog\.set_config\b[^\n]*\n//mg;

    # "-- PostgreSQL database dump complete" footer
    $content =~ s/^--\s+PostgreSQL database dump complete[^\n]*\n//mg;

    return $content;
}

# Normalize whitespace within a single block:
#   - collapse runs of spaces/tabs to a single space
#   - strip trailing whitespace from every line
#   - trim leading and trailing blank lines
sub normalize_block {
    my ($block) = @_;
    $block =~ s/[ \t]+/ /g;
    $block =~ s/ $//mg;
    $block =~ s/^\n+//;
    $block =~ s/\n+$//;
    return $block;
}

# Split stripped content into per-object blocks.
# pg_dump separates objects with one or more blank lines.
# Returns a list of normalized, non-empty block strings.
sub split_blocks {
    my ($content) = @_;
    # paragraph mode: split on sequences of 2+ newlines
    my @raw = split /\n{2,}/, $content;
    my @blocks;
    for my $block (@raw) {
        $block = normalize_block($block);
        push @blocks, $block if $block =~ /\S/;
    }
    return @blocks;
}

my @blocks_old = split_blocks(strip_noise(slurp($file_old)));
my @blocks_new = split_blocks(strip_noise(slurp($file_new)));

# Build sets (hash of block_content => 1) for membership tests.
my %set_old = map { $_ => 1 } @blocks_old;
my %set_new = map { $_ => 1 } @blocks_new;

my @only_old = sort grep { !exists $set_new{$_} } keys %set_old;
my @only_new = sort grep { !exists $set_old{$_} } keys %set_new;

if (!@only_old && !@only_new) {
    print "OK: schemas are identical after normalization.\n";
    exit 0;
}

if (@only_old) {
    printf "=== Only in OLD (%s) — %d block(s) ===\n", $file_old, scalar @only_old;
    for my $block (@only_old) {
        print "---\n$block\n";
    }
    print "\n";
}

if (@only_new) {
    printf "=== Only in NEW (%s) — %d block(s) ===\n", $file_new, scalar @only_new;
    for my $block (@only_new) {
        print "---\n$block\n";
    }
    print "\n";
}

print "DIFF: schemas differ (see above).\n";
exit 1;
