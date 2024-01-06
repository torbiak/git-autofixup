package Makefile;
use 5.008004;
use strict;
use warnings FATAL => 'all';

use ExtUtils::MakeMaker;

# Return a hashref of dependencies in MakeMaker format.
sub get_deps {
    return {
        'Carp' => 0,
        'File::Copy' => 0,
        'File::Spec' => 0,
        'File::Temp' => 0,
        'Getopt::Long' => 0,
        'IPC::Open3' => 0,
        'Pod::Usage' => 0,
        'strict' => 0,
        'warnings' => 0,
    }
}

# Return a hashref of test dependencies in MakeMaker format.
sub get_test_deps {
    return {
        'Cwd' => 0,
        'Data::Dumper' => 0,
        'English' => 0,
        'Test::More' => 0,
        'Test::Pod' => '1.00',
    }
}


my %args = (
    NAME => 'App::Git::Autofixup',
    VERSION_FROM => 'lib/App/Git/Autofixup.pm',
    ABSTRACT_FROM => 'lib/App/Git/Autofixup.pm',
    AUTHOR => 'Jordan Torbiak',
    LICENSE => 'artistic_2',
    MIN_PERL_VERSION => '5.008004',
    EXE_FILES => ['git-autofixup'],
);


if (eval { ExtUtils::MakeMaker->VERSION(6.46) }) {
    $args{META_MERGE} = {
        'meta-spec' => {version => 2},
        resources => {
            repository => {
                type => 'git',
                url => 'https://github.com/torbiak/git-autofixup.git',
                web => 'https://github.com/torbiak/git-autofixup',
            },
            bugtracker => {
                web => 'https://github.com/torbiak/git-autofixup/issues'
            },
        },
    }
}

my $deps = get_deps();
my $test_deps = get_test_deps();
if (eval { ExtUtils::MakeMaker->VERSION(6.46) }) {
    $args{TEST_REQUIRES} = $test_deps;
    $args{PREREQ_PM} = $deps;
} else {
    $args{PREREQ_PM} = {%$deps, %$test_deps}
}

if (!caller()) {
    WriteMakefile(%args);
}

1;
