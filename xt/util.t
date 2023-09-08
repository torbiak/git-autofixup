#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Test::More tests => 1;

require './t/util.pl';

sub test_git_config_env_vars_converts_multiple_pairs {
    my $name = "git_config_env_vars converts multiple pairs";
    my $git_config = {
        'diff.mnemonicPrefix' => 'true',
        'diff.external' => 'vimdiff',
    };
    my $got = Util::git_config_env_vars($git_config);
    my $want = {
        GIT_CONFIG_KEY_0 => 'diff.external',
        GIT_CONFIG_VALUE_0 => 'vimdiff',
        GIT_CONFIG_KEY_1 => 'diff.mnemonicPrefix',
        GIT_CONFIG_VALUE_1 => 'true',
    };
    is_deeply($got, $want, $name)
}
test_git_config_env_vars_converts_multiple_pairs();
