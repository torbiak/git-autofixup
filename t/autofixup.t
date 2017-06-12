#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use Carp qw(croak);
use Cwd;
use English qw(-no_match_vars);
use File::Temp qw(tempdir);

use Test::More;
if ($OSNAME eq 'MSWin32') {
    plan skip_all => 'Run from Cygwin or Git Bash on Windows'
} elsif (!has_git()) {
    plan skip_all => 'git required'
} else {
    plan tests => 31;
}

require './git-autofixup';

$ENV{GIT_AUTHOR_NAME} = 'A U Thor';
$ENV{GIT_AUTHOR_EMAIL} = 'author@example.com';
$ENV{GIT_COMMITTER_NAME} = 'C O Mitter';
$ENV{GIT_COMMITTER_EMAIL} = 'committer@example.com';


sub has_git {
    qx{git --version};
    return $? != -1;
}

sub test_autofixup_strict {
    my $params = shift;
    my $strict_levels = $params->{strict} or croak "strictness levels not given";
    delete $params->{strict};
    my $autofixup_opts = $params->{autofixup_opts} || [];
    if (grep /^(--strict|-s)/, @{$autofixup_opts}) {
        croak "strict option already given";
    }
    my $name = $params->{name} || croak "name not given";
    for my $strict (@{$strict_levels}) {
        $params->{name} = "$name, strict=$strict";
        $params->{autofixup_opts} = ['-s' => $strict, @{$autofixup_opts}];
        test_autofixup($params);
    }
}

# test_autofixup initializes a git repo in a tempdir, creates given "upstream"
# and "topic" commits, applies changes to the working directory, runs
# autofixup, and compares the git log of the fixup commits to an expected log.
#
# The upstream_commits and topic_commits arguments are heterogeneous lists of
# sub and hash refs. Hash refs are interpreted as being maps of filenames to
# contents to be written. If more flexibility is needed a subref can be given
# to manipulate the working directory.
#
# Arguments given in a hashref:
# upstream_commits: sub or hash refs that must not be fixed up
# topic_commits: sub or hash refs representing commits that can be fixed up
# unstaged: sub or hash ref of working directory changes
# log_want: expected log output
# autofixup_opts: command-line options to pass thru to autofixup
sub test_autofixup {
    my ($args) = shift;
    my $name = defined($args->{name}) ? $args->{name}
             : croak "no test name given";
    my $upstream_commits = $args->{upstream_commits} || [];
    my $topic_commits = $args->{topic_commits} || [];
    my $unstaged = defined($args->{unstaged}) ? $args->{unstaged}
                 : croak "no unstaged changes given";
    my $log_want = defined($args->{log_want}) ? $args->{log_want}
                 : croak "wanted log output not given";
    my $autofixup_opts = $args->{autofixup_opts} || [];
    if (!$upstream_commits && !$topic_commits) {
        croak "no upstream or topic commits given";
    }
    if (exists $args->{strict}) {
        croak "strict key given; use test_autofixup_strict instead";
    }

    my $log_got;
    my $orig_dir = getcwd();
    my $dir = File::Temp::tempdir(CLEANUP => 1);
    chdir $dir or die "$!";
    eval {

        init_repo();

        my $i = 0;

        for my $commit (@{$upstream_commits}) {
            apply_change($commit);
            commit_if_dirty("commit$i");
            $i++;
        }
        my $upstream_rev = get_revision_sha();

        for my $commit (@{$topic_commits}) {
            apply_change($commit);
            commit_if_dirty("commit$i");
            $i++;
        }
        my $pre_fixup_rev = get_revision_sha();

        apply_change($unstaged);

        run("git --no-pager log --format='%h %s' ${upstream_rev}..");
        autofixup(@{$autofixup_opts}, $upstream_rev);
        $log_got = get_git_log($pre_fixup_rev);
    };
    my $err = $@;
    chdir $orig_dir or die "$!";
    if ($err) {
        diag($err);
        fail($name);
        return;
    }
    is($log_got, $log_want, $name);
}

sub init_repo {
    run('git init');
    # git-autofixup needs a commit to exclude, since it uses the REVISION..
    # syntax. This is that commit.
    my $filename = 'README';
    write_file($filename, "init\n");
    run("git add $filename");
    run(qw(git commit -m), "add $filename");
    return get_revision_sha();
}

sub apply_change {
    my ($change, $commit_num) = @_;
    if (ref $change eq 'HASH') {
        while (my ($file, $contents) = each %{$change}) {
            write_file($file, $contents);
        }
    } elsif (ref $change eq 'CODE') {
        &{$change}();
    }
}

sub commit_if_dirty {
    my $msg = shift;
    my $is_dirty = qx(git status -s);
    if ($is_dirty) {
        run('git add -A');
        run(qw(git commit -am), $msg);
    }
}

sub run {
    print '# ', join(' ', @_), "\n";
    system(@_) == 0 or croak "$?";
}

sub write_file {
    my ($filename, $contents) = @_;
    open(my $fh, '>', $filename) or croak "$!";
    print {$fh} $contents or croak "$!";
    close $fh or croak "$!";
}

sub get_git_log {
    my $revision = shift;
    my $log = qx{git log -p --format=%s ${revision}..};
    if ($? != 0) {
        croak "git log: $?\n";
    }
    return $log;
}

sub get_revision_sha {
    my $dir = shift;
    my $revision = qx{git rev-parse HEAD};
    $? == 0 or croak "git rev-parse: $?";
    chomp $revision;
    return $revision;
}

sub autofixup {
    local @ARGV = @_;
    print "# git-autofixup\n";
    main() == 0 or die "git-autofixup: nonzero exit";
}


test_autofixup_strict({
    name => "single-line change gets autofixed",
    strict => [0..2],
    topic_commits => [{a => "a1\n"}],
    unstaged => {a => "a2\n"},
    log_want => q{fixup! commit0

diff --git a/a b/a
index da0f8ed..c1827f0 100644
--- a/a
+++ b/a
@@ -1 +1 @@
-a1
+a2
}});

test_autofixup_strict({
    name => "adjacent change gets autofixed",
    strict => [0..1],
    upstream_commits => [{a => "a3\n"}],
    topic_commits => [{a => "a1\na3\n"}],
    unstaged => {a => "a1\na2\na3\n"},
    log_want => q{fixup! commit1

diff --git a/a b/a
index 76642d4..2cdcdb0 100644
--- a/a
+++ b/a
@@ -1,2 +1,3 @@
 a1
+a2
 a3
}});

test_autofixup({
    name => "adjacent change doesn't get autofixed if strict=2",
    upstream_commits => [{a => "a3\n"}],
    topic_commits => [{a => "a1\na3\n"}],
    unstaged => {a => "a1\na2\na3\n"},
    log_want => q{},
    autofixup_opts => ['-s2'],
});

test_autofixup({
    name => 'fixups are created for additions surrounded by topic commit lines when strict=2',
    topic_commits => [{a => "a1\na3\n", b => "b1\n", c => "c2\n"}],
    unstaged => {a => "a1\na2\na3\n", b => "b1\nb2\n", c => "c1\nc2\n"},
    autofixup_opts => ['-s2'],
    log_want => q{fixup! commit0

diff --git a/a b/a
index 76642d4..2cdcdb0 100644
--- a/a
+++ b/a
@@ -1,2 +1,3 @@
 a1
+a2
 a3
diff --git a/b b/b
index c9c6af7..9b89cd5 100644
--- a/b
+++ b/b
@@ -1 +1,2 @@
 b1
+b2
diff --git a/c b/c
index 16f9ec0..d0aaf97 100644
--- a/c
+++ b/c
@@ -1 +1,2 @@
+c1
 c2
}});

test_autofixup_strict({
    name => "removed file doesn't get autofixed",
    strict => [0..2],
    topic_commits => [sub { write_file(a => "a1\n"); }],
    unstaged => sub { unlink 'a'; },
    log_want => q{},
});

test_autofixup_strict({
    name => "re-added file doesn't get autofixed",
    strict => [0..2],
    topic_commits => [
        sub { write_file(a => "a1\n"); },
        sub { unlink 'a'; },
    ],
    unstaged => sub { write_file(a => "a1a\n"); },
    log_want => q{},
});

test_autofixup_strict({
    name => "re-added line gets autofixed into the commit blamed for the adjacent context",
    # During rebase the line will just get removed again by the next commit.
    # --strict can be used to avoid creating a fixup in this case, where the
    # added line is adjacent to only one of a topic commit's blamed lines,
    # but not if it's surrounded by them. It seems possible to avoid
    # potentially confusing situations like this by parsing the diffs of the
    # topic commits and tracking changes in files' line numbers, but it's
    # doubtful that it would be worth it.
    strict => [0..2],
    topic_commits => [
        {a => "a1\na2\n"},
        {a => "a1\n"},
    ],
    unstaged => {a => "a1\na2\n"},
    log_want => q{fixup! commit0

diff --git a/a b/a
index da0f8ed..0016606 100644
--- a/a
+++ b/a
@@ -1 +1,2 @@
 a1
+a2
}});

test_autofixup_strict({
    name => "removed lines get autofixed",
    strict => [0..2],
    topic_commits => [{a => "a1\n", b => "b1\nb2\n"}],
    unstaged => {a => "", b => "b2\n"},
    log_want => q{fixup! commit0

diff --git a/a b/a
index da0f8ed..e69de29 100644
--- a/a
+++ b/a
@@ -1 +0,0 @@
-a1
diff --git a/b b/b
index 9b89cd5..e6bfff5 100644
--- a/b
+++ b/b
@@ -1,2 +1 @@
-b1
 b2
}});

test_autofixup_strict({
    name => 'no fixups are created for upstream commits',
    strict => [0..2],
    upstream_commits => [{a => "a1\n"}],
    unstaged => {a => "a1a\n"},
    log_want => q{},
});

test_autofixup({
    name => 'fixups are created for hunks changing lines blamed by upstream if strict=0',
    # This depends on the number of context lines kept when creating diffs. git
    # keeps 3 by default.
    upstream_commits => [{a => "a1\na2\na3\n"}],
    topic_commits => [{a => "a1\na2a\na3a\n"}],
    unstaged => {a => "a1b\na2b\na3b\n"},
    log_want => q{fixup! commit1

diff --git a/a b/a
index 125d560..cc1aa32 100644
--- a/a
+++ b/a
@@ -1,3 +1,3 @@
-a1
-a2a
-a3a
+a1b
+a2b
+a3b
}});
test_autofixup_strict({
    name => 'no fixups are created for hunks changing lines blamed by upstream if strict > 0',
    # This depends on the number of context lines kept when creating diffs. git
    # keeps 3 by default.
    strict => [1..2],
    upstream_commits => [{a => "a1\na2\na3\n"}],
    topic_commits => [{a => "a1\na2a\na3a\n"}],
    unstaged => {a => "a1b\na2b\na3b\n"},
    log_want => q{},
});

test_autofixup_strict({
    name => "hunks blamed on a fixup! commit are assigned to that fixup's target",
    strict => [0..2],
    topic_commits => [
        {a => "a1\n"},
        sub {
            write_file(a => "a2\n");
            run(qw(git commit -a --fixup=HEAD));
        },
    ],
    unstaged => {a => "a2\na3\n"},
    log_want => q{fixup! commit0

diff --git a/a b/a
index c1827f0..b792f74 100644
--- a/a
+++ b/a
@@ -1 +1,2 @@
 a2
+a3
}});

test_autofixup({
    name => "removed line gets autofixed when context=0",
    topic_commits => [{a => "a1\na2\n"}],
    unstaged => {a => "a1\n"},
    autofixup_opts => ['-c' => 0],
    log_want => q{fixup! commit0

diff --git a/a b/a
index 0016606..da0f8ed 100644
--- a/a
+++ b/a
@@ -1,2 +1 @@
 a1
-a2
}});

test_autofixup({
    name => "added line is ignored when context=0",
    topic_commits => [{a => "a1\n"}],
    unstaged => {a => "a1\na2\n"},
    autofixup_opts => ['-c' => 0],
    log_want => q{},
});

test_autofixup({
    name => "ADJACENCY assignment is used as a fallback for multiple context targets",
    topic_commits => [
        {a => "a1\n"},
        {a => "a1\na2\n"},
    ],
    unstaged => {a => "a1\na2a\n"},
    log_want => q{fixup! commit1

diff --git a/a b/a
index 0016606..a0ef52c 100644
--- a/a
+++ b/a
@@ -1,2 +1,2 @@
 a1
-a2
+a2a
}});
