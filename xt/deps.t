#!/usr/bin/perl

# Check that the dependencies in Makefile.PL match what we can extract from the
# code.

use strict;
use warnings FATAL => 'all';

use Test::More tests => 2;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

my @ignore = qw(App::Git::Autofixup);

# Try to find dependencies brought in with `use` in the given files and return
# them as a hashref in MakeMaker format, {<module> => <version>, ...}.
#
# scan_deps() deosn't try to extract `require` statements, on the assumption
# that if you're using require you're already thinking carefully about
# dependencies and will add the required module to the dependency list as
# appropriate. Dealing with every special case isn't feasible here.
sub scan_deps {
    my %deps;
    for my $filename (@_) {
        open my $fh, '<', $filename or die "scan $filename: $!";
        for my $line (<$fh>) {
            if ($line =~ /^\s*use\s+([a-zA-Z]\S+)(?:\s*)?([v0-9]\S*)?.*;$/) {
                my ($module, $version) = ($1, $2);
                $deps{$module} = defined($version) ? $version : 0;
            }
        }
    }
    for my $k (@ignore) {
        delete $deps{$k};
    }
    return \%deps;
}

sub is_hashes_equal {
    my ($h_a, $h_b) = @_;
    for my $k (keys %$h_a, keys %$h_b) {
        if (!exists($h_a->{$k}) || !exists($h_b->{$k})) {
            return 0;
        }

        # Convert to strings.
        my $a = '' . $h_a->{$k};
        my $b = '' . $h_b->{$k};
        if ($a ne $b) {
            return 0;
        }
    }
    return 1;
}

sub get_deps {
    return scan_deps(qw(git-autofixup lib/App/Git/Autofixup.pm));
}

sub get_test_deps {
    my $deps = get_deps();
    my $test_deps = scan_deps(glob('t/*.t t/*.pl xt/*.t xt/*.pl'));
    for my $k (keys %$deps) {
        delete $test_deps->{$k};
    }
    return $test_deps;
}


require './Makefile.PL';

{
    my $want = get_deps();
    $want->{'Pod::Usage'} = 0;

    my $got = Makefile::get_deps();

    my $ok = is_hashes_equal($got, $want);
    if (!$ok) {
        diag("got: " . Dumper($got));
        diag("want " . Dumper($want));
    }
    ok($ok, 'Makefile.PL dependencies seem accurate');
}

{
    my $want = get_test_deps();
    $want->{'Test::Pod'} = '1.00';

    my $got = Makefile::get_test_deps();

    my $ok = is_hashes_equal($got, $want);
    if (!$ok) {
        diag("got: " . Dumper($got));
        diag("want " . Dumper($want));
    }
    ok($ok, 'Makefile.PL test dependencies seem accurate');
}
