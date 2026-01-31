#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);
use Test::More;

require './t/test.pl';
require './t/util.pl';
require './t/repo.pl';
require './git-autofixup';

Util::check_test_deps();
plan tests => 4;

# Test Case 1: -- present with --strict 2 and an explicit revision
# Command line: git-autofixup --strict 2 <revision> -- a
{
    my $name = '-- present, --strict 2, with explicit revision';
    
    my $wants = {
        fixup_log => <<'EOF',
fixup! commit1

diff --git a a
index 76642d4..2cdcdb0 100644
--- a
+++ a
@@ -1,2 +1,3 @@
 a1
+a2
 a3
EOF
        staged => '',
        unstaged => <<'EOF',  # File b changes should remain unstaged
diff --git b b
index c9c6af7..9b89cd5 100644
--- b
+++ b
@@ -1 +1,2 @@
 b1
+b2
EOF
    };

    eval {
        my $repo = Repo->new();

        $repo->create_commits({README => "upstream\n"});
        my $upstream = $repo->current_commit_sha();

        $repo->create_commits({a => "a1\na3\n", b => "b1\n"});
        my $topic = $repo->current_commit_sha();

        $repo->write_change({a => "a1\na2\na3\n", b => "b1\nb2\n"});

        my $exit_code = $repo->autofixup('--exit-code', '-s', '2', $upstream, '--', 'a');
        my $ok = Util::exit_code_ok(want => 0, got => $exit_code);
        $ok &&= Util::repo_state_ok($repo, $topic, $wants);

        ok($ok, $name);
    };
    if ($@) {
        diag($@);
        fail($name);
    }
}

# Test Case 2: -- present with --strict 2 without an explicit revision
# Command line: git-autofixup --strict 2 -- a
{
    my $name = '-- present, --strict 2, no explicit revision';
    
    my $wants = {
        fixup_log => <<'EOF',
fixup! commit1

diff --git a a
index 76642d4..2cdcdb0 100644
--- a
+++ a
@@ -1,2 +1,3 @@
 a1
+a2
 a3
EOF
        staged => '',
        unstaged => <<'EOF',  # File b changes should remain unstaged
diff --git b b
index c9c6af7..9b89cd5 100644
--- b
+++ b
@@ -1 +1,2 @@
 b1
+b2
EOF
    };

    eval {
        my $repo = Repo->new();

        $repo->create_commits({README => "upstream\n"});
        my $upstream = $repo->current_commit_sha();

        $repo->switch_to_downstream_branch('topic');
        $repo->create_commits({a => "a1\na3\n", b => "b1\n"});
        my $topic = $repo->current_commit_sha();

        $repo->write_change({a => "a1\na2\na3\n", b => "b1\nb2\n"});

        # No explicit revision - should find it via tracking branch
        my $exit_code = $repo->autofixup('--exit-code', '-s', '2', '--', 'a');
        my $ok = Util::exit_code_ok(want => 0, got => $exit_code);
        $ok &&= Util::repo_state_ok($repo, $topic, $wants);

        ok($ok, $name);
    };
    if ($@) {
        diag($@);
        fail($name);
    }
}

# Test Case 3: no -- with --strict 2 and an explicit revision
# Command line: git-autofixup --strict 2 <revision>
{
    my $name = 'no --, --strict 2, with explicit revision';
    
    my $wants = {
        fixup_log => <<'EOF',
fixup! commit1

diff --git a a
index 76642d4..2cdcdb0 100644
--- a
+++ a
@@ -1,2 +1,3 @@
 a1
+a2
 a3
diff --git b b
index c9c6af7..9b89cd5 100644
--- b
+++ b
@@ -1 +1,2 @@
 b1
+b2
EOF
        staged => '',
        unstaged => '',
    };

    eval {
        my $repo = Repo->new();

        $repo->create_commits({README => "upstream\n"});
        my $upstream = $repo->current_commit_sha();

        $repo->create_commits({a => "a1\na3\n", b => "b1\n"});
        my $topic = $repo->current_commit_sha();

        $repo->write_change({a => "a1\na2\na3\n", b => "b1\nb2\n"});

        my $exit_code = $repo->autofixup('--exit-code', '-s', '2', $upstream);
        my $ok = Util::exit_code_ok(want => 0, got => $exit_code);
        $ok &&= Util::repo_state_ok($repo, $topic, $wants);

        ok($ok, $name);
    };
    if ($@) {
        diag($@);
        fail($name);
    }
}

# Test Case 4: no -- with --strict 2 without an explicit revision
# Command line: git-autofixup --strict 2
{
    my $name = 'no --, --strict 2, no explicit revision';
    
    my $wants = {
        fixup_log => <<'EOF',
fixup! commit1

diff --git a a
index 76642d4..2cdcdb0 100644
--- a
+++ a
@@ -1,2 +1,3 @@
 a1
+a2
 a3
diff --git b b
index c9c6af7..9b89cd5 100644
--- b
+++ b
@@ -1 +1,2 @@
 b1
+b2
EOF
        staged => '',
        unstaged => '',
    };

    eval {
        my $repo = Repo->new();

        $repo->create_commits({README => "upstream\n"});
        my $upstream = $repo->current_commit_sha();

        $repo->switch_to_downstream_branch('topic');
        $repo->create_commits({a => "a1\na3\n", b => "b1\n"});
        my $topic = $repo->current_commit_sha();

        $repo->write_change({a => "a1\na2\na3\n", b => "b1\nb2\n"});

        # No explicit revision - should find it via tracking branch
        my $exit_code = $repo->autofixup('--exit-code', '-s', '2');
        my $ok = Util::exit_code_ok(want => 0, got => $exit_code);
        $ok &&= Util::repo_state_ok($repo, $topic, $wants);

        ok($ok, $name);
    };
    if ($@) {
        diag($@);
        fail($name);
    }
}
