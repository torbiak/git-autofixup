#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);
use Test::More;

require './git-autofixup';

if ($OSNAME eq 'MSWin32') {
    plan skip_all => "Windows isn't supported, except with msys or Cygwin";
}
plan tests => 3;

sub test_capture {
    my %args = @_;
    my @cmd = ref $args{cmd} ? @{$args{cmd}} : ($args{cmd});
    my $got = Autofixup::capture(@cmd);
    is_deeply($got, $args{want}, $args{name});
}

test_capture(
    name => 'capture stdout, stderr, and exit_code',
    cmd => q(perl -e 'print STDERR "stderr\n"; print "stdout\n"; exit 3'),
    want => ["stdout\n", "stderr\n", 3],
);

test_capture(
    name => 'capture echo command given as list',
    cmd => [qw(echo stdout)],
    want => ["stdout\n", '', 0],
);

test_capture(
    name => 'capture echo with redirection',
    cmd => "echo stderr 1>&2",
    want => ['', "stderr\n", 0],
);
