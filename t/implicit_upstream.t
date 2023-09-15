#!/usr/bin/perl

# Test finding "upstream" commits. When making fixups we want to minimize the
# number of commits we need to look at, and avoid making "fixups" (ie fixup
# commits) for commits that could be reasonably expected to be pushed or for
# commits that are likely to be considered outside of the topic branch.

use strict;
use warnings FATAL => 'all';

use Test::More;

require './t/util.pl';
require './t/repo.pl';
require './git-autofixup';

Util::check_test_deps(4);
plan tests => 4;

# fast-forward from upstream
#
# Probably the most common case.
#
# o  upstream
#  \
#   o--o  topic
#
{
    my $name = 'fast-forward from upstream';

    my $wants = {
        fixup_log => <<'EOF',
fixup! commit1

diff --git a/a b/a
index 8737a60..ba81a56 100644
--- a/a
+++ b/a
@@ -1,3 +1,3 @@
-a1.1
-a2
+a1
+a2.1
 a3
EOF
        staged => '',
        unstaged => '',
    };

    eval {
        my $repo = Repo->new();

        $repo->create_commits({a => "a1\na2\na3\n"});
        my $upstream = $repo->current_commit_sha();

        $repo->switch_to_downstream_branch('topic');
        $repo->create_commits({a => "a1.1\na2\na3\n"});
        my $topic = $repo->current_commit_sha();

        $repo->write_change({a => "a1\na2.1\na3\n"});

        my $upstreams = Autofixup::find_merge_bases();
        my $ok = Util::upstreams_ok(want => [$upstream], got => $upstreams);

        if ($ok) {
            my $exit_code = $repo->autofixup();
            $ok &&= Util::exit_code_ok(want => 0, got => $exit_code);
            $ok &&= Util::repo_state_ok($repo, $topic, $wants);
        }

        ok($ok, $name);
    };
    if ($@) {
        diag($@);
        fail($name);
    }
}


# interactive rebase onto upstream, making a fixup from B for A
#
# o  upstream
#  \
#   A--B--C  topic
#
{
    my $name = 'interactive rebase onto upstream';

    my $wants = {
        fixup_log => <<'EOF',
fixup! commit1

diff --git a/a b/a
index 8737a60..ba81a56 100644
--- a/a
+++ b/a
@@ -1,3 +1,3 @@
-a1.1
-a2
+a1
+a2.1
 a3
EOF
        staged => '',
        unstaged => '',
    };

    eval {
        my $repo = Repo->new();

        # upstream (commit0)
        $repo->create_commits({a => "a1\na2\na3\n"});
        my $upstream = $repo->current_commit_sha();

        # A (commit1)
        $repo->switch_to_downstream_branch('topic');
        $repo->create_commits({a => "a1.1\na2\na3\n"});
        my $topic = $repo->current_commit_sha();

        # B (commit2)
        $repo->create_commits({a => "a1\na2.1\na3\n"});

        # C
        $repo->create_commits({b => "b1\n"});

        # Start an interactive rebase to edit commit B (which'll have commit2
        # in its message).
        local $ENV{GIT_SEQUENCE_EDITOR} = q(perl -i -pe "/commit2/ && s/^pick/edit/");
        Util::run("git rebase -q -i $upstream 2>/dev/null");
        Util::run(qw(git reset HEAD^));

        my $upstreams = Autofixup::find_merge_bases();
        my $ok = Util::upstreams_ok(want => [$upstream], got => $upstreams);

        if ($ok) {
            my $exit_code = $repo->autofixup();
            $ok &&= Util::exit_code_ok(want => 0, got => $exit_code);
            $ok &&= Util::repo_state_ok($repo, $topic, $wants);
        }

        ok($ok, $name);
    };
    if ($@) {
        diag($@);
        fail($name);
    }
}


# fork-point and merge-base are different
#
# Here the upstream commit that topic originally diverged from is different
# from the first ancestor that currently belongs to both topic and upstream,
# due to upstream being rewound and rebuilt. We don't want to make fixups for
# the fork-point since the user probably doesn't consider it part of the topic
# branch at a conceptual level and by default `git rebase` excludes the
# fork-point from the set of commits to be rewritten.
#
# B1--o  upstream
#  \
#   B0  fork-point: was previously part of upstream
#    \
#     T0  topic
#
{
    my $name = 'fork-point and merge-base are different';

    my $wants = {
        fixup_log => <<'EOF',
fixup! commit2

diff --git a/a b/a
index 8737a60..472f448 100644
--- a/a
+++ b/a
@@ -1,3 +1,3 @@
 a1.1
-a2
+a2.1
 a3
EOF
        staged => '',
        unstaged => '',
    };

    eval {
        my $repo = Repo->new();

        # upstream
        #
        # Create a commit to use as the fork-point for the topic branch, save
        # the SHA, then amend it so that the fork-point is no longer reachable
        # from master and create another commit on top.
        $repo->create_commits({a => "a1\na2\na3\n"});
        my $fork_point = $repo->current_commit_sha();
        Util::run(qw(git commit --amend -m), 'commit0, reworded');  # B1
        $repo->create_commits({b => "b1\n"});  # o (commit1)

        # topic
        Util::run(qw(git checkout -q -b topic), $fork_point);
        Util::run(qw(git branch --set-upstream-to master));
        $repo->create_commits({a => "a1.1\na2\na3\n"});

        $repo->write_change({a => "a1.1\na2.1\na3\n"});
        my $topic = $repo->current_commit_sha();

        my $upstreams = Autofixup::find_merge_bases();
        my $ok = Util::upstreams_ok(want => [$fork_point], got => $upstreams);

        if ($ok) {
            my $exit_code = $repo->autofixup();
            $ok &&= Util::exit_code_ok(want => 0, got => $exit_code);
            $ok &&= Util::repo_state_ok($repo, $topic, $wants);
        }

        ok($ok, $name);
    };
    if ($@) {
        diag($@);
        fail($name);
    }
}


# criss-cross merge and gc'd fork-point reflog
#
# Here's one way to get a criss-cross merge. If you have two branches (A and B,
# here) that include the same merge commit, M0:
#
# C1-M0  A, B
#   /
# C2
#
# And then you amend that merge commit from one of the branches (A, in this
# case), creating M1, you get the following topology. The important implication
# for us is that commits 1 and 2 are both equally good merge bases of A and B,
# and we don't want to create fixups for either of them or their ancestors.
# (Here 'X' represents overlapping graph edges, not another commit.)
#
# C1---M1  A
#   \ /
#    X
#   / \
# C2---M0  B
#
# For this test we'll also amend B's merge commit and garbage-collect the
# reflog so that M0 isn't simply used as B's fork-point from its tracking
# branch A, forcing git-autofixup to fall back on the merge-bases C1 and C2.
#
# C1---M1  A
#   \ /
#    X
#   / \
# C2---M2---o  B
#
{
    my $name = "criss-cross merge and gc'd fork point reflog";

    my $wants = {
        fixup_log => <<'EOF',
fixup! commit2

diff --git a/a b/a
index 8737a60..472f448 100644
--- a/a
+++ b/a
@@ -1,3 +1,3 @@
 a1.1
-a2
+a2.1
 a3
diff --git a/b b/b
index 0ef8a8e..b1710a1 100644
--- a/b
+++ b/b
@@ -1,3 +1,3 @@
 b1.1
-b2
+b2.1
 b3
EOF
        staged => '',
        unstaged => '',
    };

    eval {
        my $repo = Repo->new();

        # C1
        Util::run(qw(git checkout -q -b A));
        $repo->create_commits({a => "a1\na2\na3\n"});
        my $c1 = $repo->current_commit_sha();

        # C2
        Util::run(qw(git checkout -q -b B master));
        Util::run(qw(git branch --set-upstream-to A));
        $repo->create_commits({b => "b1\nb2\nb3\n"});
        my $c2 = $repo->current_commit_sha();

        # Merge A and B, so they're both pointing to the same merge commit.
        Util::run(qw(git merge --no-ff), '-m' => 'Merge A into B', 'A');  # M0
        Util::run(qw(git checkout -q A));
        Util::run(qw(git merge --ff-only B));  # fast-forward to M0

        # Then ammend the merge commits for both branches and gc the reflog so
        # git can't tell what the original fork-point of B from A is.
        Util::run(qw(git commit --amend -m), 'Merge A into B, reworded for A');  # M1
        Util::run(qw(git checkout -q B));
        Util::run(qw(git commit --amend -m), 'Merge A into B, reworded for B');  # M2
        Util::run('git -c gc.reflogExpire=now gc 2>/dev/null');

        # topic
        $repo->create_commits({a => "a1.1\na2\na3\n", b => "b1.1\nb2\nb3\n"});
        my $topic = $repo->current_commit_sha();

        $repo->write_change({a => "a1.1\na2.1\na3\n", b => "b1.1\nb2.1\nb3\n"});

        my @upstreams_got = sort(Autofixup::find_merge_bases());
        my @upstreams_want = sort $c1, $c2;
        my $ok = Util::upstreams_ok(want => \@upstreams_want, got => \@upstreams_got);

        if ($ok) {
            my $exit_code = $repo->autofixup();
            $ok &&= Util::exit_code_ok(want => 0, got => $exit_code);
            $ok &&= Util::repo_state_ok($repo, $topic, $wants);
        }

        ok($ok, $name);
    };
    if ($@) {
        diag($@);
        fail($name);
    }
}
