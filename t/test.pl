# Long test functions that could conceivably be used in multiple .t files.

package Test;

use strict;
use warnings FATAL => 'all';

use Carp qw(croak);
use Cwd;
use Test::More;

require './t/util.pl';
require './t/repo.pl';

# Run autofixup() with each of the given strictness levels.
sub autofixup_strict {
    my %args = @_;
    my $strict_levels = $args{strict} or croak "strictness levels not given";
    delete $args{strict};
    my $autofixup_opts = $args{autofixup_opts} || [];
    if (grep /^(--strict|-s)/, @{$autofixup_opts}) {
        croak "strict option already given";
    }
    my $name = $args{name} || croak "name not given";
    for my $strict (@{$strict_levels}) {
        $args{name} = "$name, strict=$strict";
        $args{autofixup_opts} = ['-s' => $strict, @{$autofixup_opts}];
        autofixup(%args);
    }
}

# autofixup initializes a git repo in a tempdir, creates given "upstream" and
# "topic" commits, applies changes to the working directory, runs autofixup,
# and compares wanted `git log` and `git diff` outputs to actual ones.
#
# Arguments are given as a hash:
# name: test name or description
# upstream_commits: sub or hash refs that must not be fixed up
# topic_commits: sub or hash refs representing commits that can be fixed up
# unstaged: sub or hashref of working directory changes
# staged: sub or hashref of index changes
# log_want: expected log output for new fixup commited
# staged_want: expected log output for the staging area
# unstaged_want: expected diff output for the working tree
# autofixup_opts: command-line options to pass thru to autofixup
# git_config: hashref of git config key/value pairs
#
# The upstream_commits and topic_commits arguments are heterogeneous lists of
# sub and hash refs. Hash refs are interpreted as being maps of filenames to
# contents to be written. If more flexibility is needed a subref can be given
# to manipulate the working directory.
sub autofixup {
    my %args = @_;
    my $name = defined($args{name}) ? $args{name}
             : croak "no test name given";
    my $upstream_commits = $args{upstream_commits} || [];
    my $topic_commits = $args{topic_commits} || [];
    my $unstaged = defined($args{unstaged}) ? $args{unstaged}
                 : croak "no unstaged changes given";
    my $staged = $args{staged};
    my $log_want = defined($args{log_want}) ? $args{log_want}
                 : croak "wanted log output not given";
    my $staged_want = $args{staged_want};
    my $unstaged_want = $args{unstaged_want};
    my $exit_code_want = $args{exit_code};
    my $autofixup_opts = $args{autofixup_opts} || [];
    push @{$autofixup_opts}, '--exit-code';
    my $git_config = $args{git_config} || {};
    if (!$upstream_commits && !$topic_commits) {
        croak "no upstream or topic commits given";
    }
    if (exists $args{strict}) {
        croak "strict key given; use test_autofixup_strict instead";
    }

    local $ENV{GIT_CONFIG_COUNT} = scalar keys %$git_config;
    my $git_config_env = Util::git_config_env_vars($git_config);
    local (@ENV{keys %$git_config_env});
    for my $k (keys %$git_config_env) {
        $ENV{$k} = $git_config_env->{$k};
    }

    eval {
        my $repo = Repo->new();

        $repo->create_commits(@$upstream_commits);
        my $upstream_rev = $repo->current_commit_sha();

        $repo->create_commits(@$topic_commits);
        my $pre_fixup_rev = $repo->current_commit_sha();

        if (defined($staged)) {
            $repo->write_change($staged);
            # We're at the repo root, so using -A will change everything even
            # in pre-v2 versions of git. See git commit 808d3d717e8.
            Util::run(qw(git add -A));
        }

        $repo->write_change($unstaged);

        Util::run('git', '--no-pager',  'log', "--format='%h %s'", "${upstream_rev}..");
        my $exit_code_got = $repo->autofixup(@{$autofixup_opts}, $upstream_rev);

        my $ok = Util::exit_code_ok(want => $exit_code_want, got => $exit_code_got);
        my $wants = {
            fixup_log => $log_want,
            staged => $staged_want,
            unstaged => $unstaged_want,
        };
        $ok &&= Util::repo_state_ok($repo, $pre_fixup_rev, $wants);
        ok($ok, $name);
    };
    if ($@) {
        diag($@);
        fail($name);
    }
    return;
}

