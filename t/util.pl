package Util;

use strict;
use warnings FATAL => 'all';

use Carp qw(croak);
use Cwd;
use English qw(-no_match_vars);
use Test::More;

require './t/repo.pl';
require './git-autofixup';

sub check_test_deps {
    if ($OSNAME eq 'MSWin32') {
        plan skip_all => "Windows isn't supported, except with msys or Cygwin";
    } elsif (!has_git()) {
        plan skip_all => 'git version 1.7.4+ required';
    } elsif ($OSNAME eq 'cygwin' && is_git_for_windows()) {
        plan skip_all => "Can't use Git for Windows with a perl for Cygwin";
    }
}

# Return true if git version 1.7.4+ is available.
sub has_git {
    my $stdout = qx{git --version};
    return if $? != 0;
    my ($x, $y, $z) = $stdout =~ /(\d+)\.(\d+)(?:\.(\d+))?/;
    defined $x or die "unexpected output from git: $stdout";
    $z = defined $z ? $z : 0;
    my $cmp = $x <=> 1 || $y <=> 7 || $z <=> 4;
    return $cmp >= 0;
}

sub is_git_for_windows {
    my $version = qx{git --version};
    return $version =~ /\.(?:windows|msysgit)\./i;
}

# Convert a hashref of git config key-value pairs to a hashref of
# GIT_CONFIG_{KEY,VALUE}_<i> pairs suitable for setting as environment
# variables.
#
# For example:
#
#     > git_config_env_vars({'diff.mnemonicPrefix' => 'true'})
#     {
#         GIT_CONFIG_KEY_0 => 'diff.mnemonicPrefix',
#         GIT_CONFIG_VALUE_0 => 'true',
#     }
sub git_config_env_vars {
    my $git_config = shift;
    my %env = ();
    my $i = 0;
    for my $k (sort(keys %$git_config)) {
        $env{"GIT_CONFIG_KEY_$i"} = $k;
        $env{"GIT_CONFIG_VALUE_$i"} = $git_config->{$k};
        $i++;
    }
    return \%env;
}

# Take wanted and actual autofixup exit codes as a hash with keys ('want',
# 'got') and return true if want and got are equal or if want is undefined.
# Print a TAP diagnostic if they aren't ok.
#
# eg: exit_code_got(want => 3, got => 2)
#
# Params are taken as a hash since the order matters and it seems difficult to
# get the order right if the args aren't named.
sub exit_code_ok {
    my %args = @_;
    defined $args{got} or croak "got exit code is undefined";
    if (defined $args{want} && $args{want} != $args{got}) {
        diag("exit_code_want=$args{want},exit_code_got=$args{got}");
        return 0;
    }
    return 1;
}

# Take wanted and actual listrefs of upstream SHAs as a hash with keys ('want',
# 'got') and return true if want and got are equal. Print a TAP diagnostic if
# they aren't ok.
#
# eg: exit_code_got(want => 3, got => 2)
sub upstreams_ok {
    my %args = @_;
    defined $args{want} or croak 'wanted upstream list must be given';
    defined $args{got} or croak 'actual upstream list must be given';
    my @wants = @{$args{want}};
    my @gots = @{$args{got}};
    my $max_len = @wants > @gots ? @wants : @gots;
    my $ok = 1;
    for my $i (0..$max_len - 1) {
        my $want = defined $wants[$i] ? $wants[$i] : '';
        my $got = defined $gots[$i] ? $gots[$i] : '';
        if (!$want || !$got || $want ne $got) {
            diag("upstream mismatch,i=$i,want=$want,got=$got");
            $ok = 0;
        }
    }
    return $ok;
}

# Return whether the repo state is as desired and print TAP diagnostics if not.
#
# Parameters:
# - a Repo object
# - a SHA for the last topic branch commit before any fixups were made
# - a hashref of `git log` outputs, for `fixups`, `staged`, and `unstaged`. If
#   `staged` isn't given, then it's assumed that there shouldn't be any staged
#   changes.
sub repo_state_ok {
    my ($repo, $pre_fixup_rev, $wants) = @_;
    my $ok = 1;

    for my $key (qw(fixup_log staged unstaged)) {
        next if (!defined $wants->{$key});

        my $want = $wants->{$key};

        my $got;
        if ($key eq 'fixup_log') {
            $got = $repo->log_since($pre_fixup_rev);
        } elsif ($key eq 'staged') {
            $got = $repo->diff('--cached');
        } elsif ($key eq 'unstaged') {
            $got = $repo->diff('HEAD');
        }

        if ($got ne $want) {
            diag("${key}_got=<<EOF\n${got}EOF\n${key}_want=<<EOF\n${want}EOF\n");
            $ok = 0;
        }
    }

    if (!defined($wants->{staged})) {
        my $got = $repo->diff('--cached');
        if ($got) {
            diag("staged_got=<<EOF\n${got}EOF\nno staged changes expected\n");
            $ok = 0;
        }
    }

    return $ok;
}

# Run a command for its side effects, and print the command as a TAP
# diagnostic.
sub run {
    print '# ', join(' ', @_), "\n";
    system(@_) == 0 or croak "command " . child_error_desc($?);
}

# Return a description of what $? means.
sub child_error_desc {
    my $err = shift;
    if ($err == -1) {
        return "failed to execute: $!";
    } elsif ($err & 127) {
        return "died with signal " . ($err & 127);
    } else {
        return "exited with " . ($err >> 8);
    }
}

sub write_file {
    my ($filename, $contents) = @_;
    open(my $fh, '>', $filename) or croak "$!";
    print {$fh} $contents or croak "$!";
    close $fh or croak "$!";
}

1;
