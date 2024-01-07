#!/usr/bin/perl

# Check that test files and test libs are using string and warnings.

use strict;
use warnings FATAL => 'all';

use Test::More;

sub is_strict_and_warn {
    my $filename = shift;
    my ($is_strict, $is_warn);
    open my $fh, '<', $filename or die "check $filename: $!";
    for (<$fh>) {
        m/^use strict;/ and $is_strict = 1;
        m/^use warnings/ and $is_warn = 1;
        if ($is_strict && $is_warn) {
            return 1;
        }
    }
    return 0;
}

my @filenames = glob('t/*.t t/*.pl xt/*.t xt/*.pl');
plan tests => scalar(@filenames);
for my $fn (@filenames) {
    ok(is_strict_and_warn($fn), "$fn is using strict and warnings");
}
