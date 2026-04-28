#!/usr/bin/perl
use strict;
use warnings;

# check-object-names.pl — Static name-presence check for upgrade drift.
#
# Compares object names between an old and new cat_tools install script,
# then verifies the upgrade script covers all additions and removals.
#
# Usage:
#   perl check-object-names.pl \
#       --old  sql/cat_tools--0.2.2.sql.in \
#       --new  sql/cat_tools.sql.in \
#       --upgrade sql/cat_tools--0.2.2--0.3.0.sql.in
#
# Exit 0 if no gaps found; exit 1 if gaps exist.

my ($old_file, $new_file, $upgrade_file);
while (@ARGV) {
    my $arg = shift @ARGV;
    if    ($arg eq '--old')     { $old_file     = shift @ARGV }
    elsif ($arg eq '--new')     { $new_file     = shift @ARGV }
    elsif ($arg eq '--upgrade') { $upgrade_file = shift @ARGV }
    else  { die "Unknown argument: $arg\n" }
}
die "Usage: $0 --old OLD.sql.in --new NEW.sql.in --upgrade UPGRADE.sql.in\n"
    unless $old_file && $new_file && $upgrade_file;

# Read a file and strip @generated@ section-boundary markers.
sub slurp {
    my ($path) = @_;
    open my $fh, '<', $path or die "Cannot open $path: $!\n";
    my $content = do { local $/ = undef; <$fh> };
    close $fh;
    $content =~ s/\@generated\@//g;
    return $content;
}

# Extract named objects from a sql.in file.
#
# Returns a hash whose keys are:
#   function:<qualified_name>       — from __cat_tools.create_function(...)
#   ddl:<qualified_name>            — from CREATE [OR REPLACE] TYPE/VIEW/TABLE/SCHEMA
#   enum:<type_name>:<value>        — individual values inside AS ENUM (...)
#
sub extract_objects {
    my ($content) = @_;
    my %objs;

    # Functions registered via the create_function wrapper.
    # The first argument (the function name) appears before any dollar-quoting.
    while ($content =~ /__cat_tools\.create_function\(\s*'([^']+)'/gsm) {
        $objs{"function:$1"} = 1;
    }

    # Plain DDL: TYPE, VIEW, TABLE, SCHEMA.
    # Stop the name capture at whitespace, semicolon, or open-paren.
    while ($content =~ /\bCREATE\s+(?:OR\s+REPLACE\s+)?(?:TYPE|VIEW|TABLE|SCHEMA)\s+([^\s;(]+)/gsmi) {
        my $name = $1;
        next if $name =~ /^%/;  # skip format-string placeholders (%s etc.)
        $objs{"ddl:$name"} = 1;
    }

    # ENUM value lists.
    # Track per-type values so we can detect additions and removals.
    # The ENUM body is everything between the outer ( and ) — no semicolons
    # or nested parens appear there, so [^)]+ is unambiguous.
    while ($content =~ /\bCREATE\s+TYPE\s+(\S+)\s+AS\s+ENUM\s*\(([^)]+)\)/gsmi) {
        my ($type_name, $body) = ($1, $2);
        while ($body =~ /'([^']+)'/g) {
            $objs{"enum:$type_name:$1"} = 1;
        }
    }

    return %objs;
}

my %old = extract_objects(slurp($old_file));
my %new = extract_objects(slurp($new_file));

my @added   = sort grep { !exists $old{$_} } keys %new;
my @removed = sort grep { !exists $new{$_} } keys %old;

my $upgrade = slurp($upgrade_file);
my (@gaps_added, @gaps_removed);

# Check that each added object is mentioned in the upgrade script.
for my $obj (@added) {
    my $check_name;
    if ($obj =~ /^(?:function|ddl):(.+)$/) {
        $check_name = $1;
    } elsif ($obj =~ /^enum:([^:]+):/) {
        # For ENUM changes the upgrade touches the type, not individual values.
        # Check that the type name appears (e.g. in ALTER TYPE ... ADD VALUE).
        $check_name = $1;
    }
    push @gaps_added, $obj if index($upgrade, $check_name) < 0;
}

# Check that each removed function/DDL object is explicitly DROPped.
# Individual ENUM values cannot be dropped in PostgreSQL; skip them.
for my $obj (@removed) {
    next if $obj =~ /^enum:/;
    my ($check_name) = ($obj =~ /^(?:function|ddl):(.+)$/);
    push @gaps_removed, $obj
        unless $upgrade =~ /\bDROP\b[^\n]*\Q$check_name\E/smi;
}

# ---- Report ----------------------------------------------------------------

my $ok = 1;

if (@added) {
    printf "=== Added in new version (%d objects) ===\n", scalar @added;
    print  "  $_\n" for @added;
    print  "\n";
}

if (@removed) {
    printf "=== Removed from old version (%d objects) ===\n", scalar @removed;
    print  "  $_\n" for @removed;
    print  "\n";
}

if (@gaps_added) {
    $ok = 0;
    printf "=== GAPS: Added objects not mentioned in upgrade script (%d) ===\n",
        scalar @gaps_added;
    print  "  $_\n" for @gaps_added;
    print  "\n";
}

if (@gaps_removed) {
    $ok = 0;
    printf "=== GAPS: Removed objects with no DROP in upgrade script (%d) ===\n",
        scalar @gaps_removed;
    print  "  $_\n" for @gaps_removed;
    print  "\n";
}

print $ok
    ? "OK: upgrade script covers all added and removed objects.\n"
    : "FAIL: upgrade script has gaps (see above).\n";

exit($ok ? 0 : 1);
