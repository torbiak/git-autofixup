#!/usr/bin/perl
use strict;
use warnings FATAL => 'all';

use Test::More tests => 42;

require './t/util.pl';
require './git-autofixup';

Util::check_test_deps();

Util::test_autofixup_strict(
    name => "single-line change gets autofixed",
    strict => [0..2],
    topic_commits => [{a => "a1\n"}],
    unstaged => {a => "a2\n"},
    exit_code => 0,
    log_want => <<'EOF'
fixup! commit0

diff --git a/a b/a
index da0f8ed..c1827f0 100644
--- a/a
+++ b/a
@@ -1 +1 @@
-a1
+a2
EOF
);

Util::test_autofixup_strict(
    name => "adjacent change gets autofixed",
    strict => [0..1],
    upstream_commits => [{a => "a3\n"}],
    topic_commits => [{a => "a1\na3\n"}],
    unstaged => {a => "a1\na2\na3\n"},
    exit_code => 0,
    log_want => <<'EOF'
fixup! commit1

diff --git a/a b/a
index 76642d4..2cdcdb0 100644
--- a/a
+++ b/a
@@ -1,2 +1,3 @@
 a1
+a2
 a3
EOF
);

Util::test_autofixup(
    name => "adjacent change doesn't get autofixed if strict=2",
    upstream_commits => [{a => "a3\n"}],
    topic_commits => [{a => "a1\na3\n"}],
    unstaged => {a => "a1\na2\na3\n"},
    log_want => '',
    autofixup_opts => ['-s2'],
    exit_code => 2,
);

Util::test_autofixup(
    name => 'fixups are created for additions surrounded by topic commit lines when strict=2',
    topic_commits => [{a => "a1\na3\n", b => "b1\n", c => "c2\n"}],
    unstaged => {a => "a1\na2\na3\n", b => "b1\nb2\n", c => "c1\nc2\n"},
    autofixup_opts => ['-s2'],
    exit_code => 0,
    log_want => <<'EOF'
fixup! commit0

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
EOF
);

Util::test_autofixup_strict(
    name => "removed file doesn't get autofixed",
    strict => [0..2],
    topic_commits => [sub { Util::write_file(a => "a1\n"); }],
    unstaged => sub { unlink 'a'; },
    exit_code => 3,
    log_want => '',
);

Util::test_autofixup_strict(
    name => "re-added file doesn't get autofixed",
    strict => [0..2],
    topic_commits => [
        sub { Util::write_file(a => "a1\n"); },
        sub { unlink 'a'; },
    ],
    unstaged => sub { Util::write_file(a => "a1a\n"); },
    exit_code => 3,
    log_want => '',
);

Util::test_autofixup_strict(
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
    exit_code => 0,
    unstaged => {a => "a1\na2\n"},
    log_want => <<'EOF'
fixup! commit0

diff --git a/a b/a
index da0f8ed..0016606 100644
--- a/a
+++ b/a
@@ -1 +1,2 @@
 a1
+a2
EOF
);

Util::test_autofixup_strict(
    name => "removed lines get autofixed",
    strict => [0..2],
    topic_commits => [{a => "a1\n", b => "b1\nb2\n"}],
    unstaged => {a => "", b => "b2\n"},
    exit_code => 0,
    log_want => <<'EOF'
fixup! commit0

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
EOF
);

Util::test_autofixup_strict(
    name => 'no fixups are created for upstream commits',
    strict => [0..2],
    upstream_commits => [{a => "a1\n"}],
    unstaged => {a => "a1a\n"},
    exit_code => 2,
    log_want => '',
);

Util::test_autofixup(
    name => 'fixups are created for hunks changing lines blamed by upstream if strict=0',
    # This depends on the number of context lines kept when creating diffs. git
    # keeps 3 by default.
    upstream_commits => [{a => "a1\na2\na3\n"}],
    topic_commits => [{a => "a1\na2a\na3a\n"}],
    unstaged => {a => "a1b\na2b\na3b\n"},
    exit_code => 0,
    log_want => <<'EOF'
fixup! commit1

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
EOF
);
Util::test_autofixup_strict(
    name => 'no fixups are created for hunks changing lines blamed by upstream if strict > 0',
    # This depends on the number of context lines kept when creating diffs. git
    # keeps 3 by default.
    strict => [1..2],
    upstream_commits => [{a => "a1\na2\na3\n"}],
    topic_commits => [{a => "a1\na2a\na3a\n"}],
    unstaged => {a => "a1b\na2b\na3b\n"},
    exit_code => 2,
    log_want => '',
);

Util::test_autofixup_strict(
    name => "hunks blamed on a fixup! commit are assigned to that fixup's target",
    strict => [0..2],
    topic_commits => [
        {a => "a1\n"},
        sub {
            Util::write_file(a => "a2\n");
            Util::run(qw(git commit -a --fixup=HEAD));
        },
    ],
    exit_code => 0,
    unstaged => {a => "a2\na3\n"},
    log_want => <<'EOF'
fixup! commit0

diff --git a/a b/a
index c1827f0..b792f74 100644
--- a/a
+++ b/a
@@ -1 +1,2 @@
 a2
+a3
EOF
);

Util::test_autofixup(
    name => "removed line gets autofixed when context=0",
    topic_commits => [{a => "a1\na2\n"}],
    unstaged => {a => "a1\n"},
    autofixup_opts => ['-c' => 0],
    exit_code => 0,
    log_want => <<'EOF'
fixup! commit0

diff --git a/a b/a
index 0016606..da0f8ed 100644
--- a/a
+++ b/a
@@ -1,2 +1 @@
 a1
-a2
EOF
);

Util::test_autofixup(
    name => "added line is ignored when context=0",
    topic_commits => [{a => "a1\n"}],
    unstaged => {a => "a1\na2\n"},
    autofixup_opts => ['-c' => 0],
    exit_code => 2,
    log_want => '',
);

Util::test_autofixup(
    name => "ADJACENCY assignment is used as a fallback for multiple context targets",
    topic_commits => [
        {a => "a1\n"},
        {a => "a1\na2\n"},
    ],
    exit_code => 0,
    unstaged => {a => "a1\na2a\n"},
    log_want => <<'EOF'
fixup! commit1

diff --git a/a b/a
index 0016606..a0ef52c 100644
--- a/a
+++ b/a
@@ -1,2 +1,2 @@
 a1
-a2
+a2a
EOF
);

Util::test_autofixup(
    name => "Works when run in a subdir of the repo root",
    topic_commits => [
        sub {
            mkdir 'sub' or die $!;
            chdir 'sub' or die $!;
            Util::write_file("a", "a1\n");
        }
    ],
    exit_code => 0,
    unstaged => {'a' => "a1\na2\n"},
    log_want => <<'EOF'
fixup! commit0

diff --git a/sub/a b/sub/a
index da0f8ed..0016606 100644
--- a/sub/a
+++ b/sub/a
@@ -1 +1,2 @@
 a1
+a2
EOF
);

Util::test_autofixup(
    name => "file without newline at EOF gets autofixed",
    topic_commits => [{a => "a1\na2"}],
    unstaged => {'a' => "a1\na2\n"},
    exit_code => 0,
    log_want => <<'EOF'
fixup! commit0

diff --git a/a b/a
index c928c51..0016606 100644
--- a/a
+++ b/a
@@ -1,2 +1,2 @@
 a1
-a2
\ No newline at end of file
+a2
EOF
);

Util::test_autofixup(
    name => "multiple hunks in the same file get autofixed",
    topic_commits => [
        {a => "a1.0\na2\na3\na4\na5\na6\na7\na8\na9.0\n"},
        {a => "a1.0\na2\na3\na4\na5\na6\na7\na8\na9.1\n"},
        {a => "a1.2\na2\na3\na4\na5\na6\na7\na8\na9.1\n"},
    ],
    unstaged => {'a' =>  "a1.3\na2\na3\na4\na5\na6\na7\na8\na9.3\n"},
    exit_code => 0,
    log_want => <<'EOF'
fixup! commit1

diff --git a/a b/a
index d9f44da..5b9ebcd 100644
--- a/a
+++ b/a
@@ -6,4 +6,4 @@ a5
 a6
 a7
 a8
-a9.1
+a9.3
fixup! commit2

diff --git a/a b/a
index 50de7e8..d9f44da 100644
--- a/a
+++ b/a
@@ -1,4 +1,4 @@
-a1.2
+a1.3
 a2
 a3
 a4
EOF
);

Util::test_autofixup(
    name => "single-line change gets autofixed when mnemonic prefixes are enabled",
    topic_commits => [{a => "a1\n"}],
    unstaged => {a => "a2\n"},
    autofixup_opts => ['-g', '-c', '-g', 'diff.mnemonicPrefix=true'],
    exit_code => 0,
    log_want => <<'EOF'
fixup! commit0

diff --git a/a b/a
index da0f8ed..c1827f0 100644
--- a/a
+++ b/a
@@ -1 +1 @@
-a1
+a2
EOF
);

Util::test_autofixup(
    name => "single-line change gets autofixed when diff.external is set",
    topic_commits => [{a => "a1\n"}],
    unstaged => {a => "a2\n"},
    autofixup_opts => ['-g', '-c', '-g', 'diff.external=vimdiff'],
    exit_code => 0,
    log_want => <<'EOF'
fixup! commit0

diff --git a/a b/a
index da0f8ed..c1827f0 100644
--- a/a
+++ b/a
@@ -1 +1 @@
-a1
+a2
EOF
);

Util::test_autofixup(
    name => 'exit code is 1 when some hunks are assigned',
    upstream_commits => [{a => "a1\n"}],
    topic_commits => [{b => "b1\n"}],
    unstaged => {a => "a1a\n", b => "b2\n"},
    exit_code => 1,
    log_want => <<'EOF'
fixup! commit1

diff --git a/b b/b
index c9c6af7..e6bfff5 100644
--- a/b
+++ b/b
@@ -1 +1 @@
-b1
+b2
EOF
);

Util::test_autofixup(
    name => "multiple hunks to the same commit get autofixed",
    topic_commits => [
        {a => "a1.0\na2\na3\na4\na5\na6\na7\na8\na9.0\n"},
        {b => "b1.0\n"},
    ],
    unstaged => {'a' =>  "a1.1\na2\na3\na4\na5\na6\na7\na8\na9.1\n", b => "b1.1\n"},
    exit_code => 0,
    log_want => q{fixup! commit1

diff --git a/b b/b
index 253a619..6419a9e 100644
--- a/b
+++ b/b
@@ -1 +1 @@
-b1.0
+b1.1
fixup! commit0

diff --git a/a b/a
index 5d11004..0054137 100644
--- a/a
+++ b/a
@@ -1,4 +1,4 @@
-a1.0
+a1.1
 a2
 a3
 a4
@@ -6,4 +6,4 @@ a5
 a6
 a7
 a8
-a9.0
+a9.1
});

Util::test_autofixup(
    name => "only staged hunks get autofixed",
    topic_commits => [{a => "a1\n", b => "b1\n"}],
    staged => {a => "a2\n"},
    unstaged => {b => "b2\n"},
    exit_code => 0,
    log_want => <<'EOF'
fixup! commit0

diff --git a/a b/a
index da0f8ed..c1827f0 100644
--- a/a
+++ b/a
@@ -1 +1 @@
-a1
+a2
EOF
    , unstaged_want => <<'EOF'
diff --git a/b b/b
index c9c6af7..e6bfff5 100644
--- a/b
+++ b/b
@@ -1 +1 @@
-b1
+b2
EOF
);

Util::test_autofixup(
    name => "staged hunks that aren't autofixed remain in index",
    upstream_commits => [{b => "b1\n"}],
    topic_commits => [{a => "a1\n", , c => "c1\n"}],
    staged => {a => "a2\n", b => "b2\n"},
    unstaged => {c => "c2\n"},
    exit_code => 1,
    log_want => <<'EOF'
fixup! commit1

diff --git a/a b/a
index da0f8ed..c1827f0 100644
--- a/a
+++ b/a
@@ -1 +1 @@
-a1
+a2
EOF
    , unstaged_want => <<'EOF'
diff --git a/b b/b
index c9c6af7..e6bfff5 100644
--- a/b
+++ b/b
@@ -1 +1 @@
-b1
+b2
diff --git a/c b/c
index ae93045..16f9ec0 100644
--- a/c
+++ b/c
@@ -1 +1 @@
-c1
+c2
EOF
    , staged_want => <<'EOF'
diff --git a/b b/b
index c9c6af7..e6bfff5 100644
--- a/b
+++ b/b
@@ -1 +1 @@
-b1
+b2
EOF
);

Util::test_autofixup(
    name => "filename with spaces",
    topic_commits => [{"filename with spaces" => "a1\n"}],
    unstaged => {"filename with spaces" => "a2\n"},
    exit_code => 0,
    log_want => <<'EOF'
fixup! commit0

diff --git a/filename with spaces b/filename with spaces
index da0f8ed..c1827f0 100644
--- a/filename with spaces	
+++ b/filename with spaces	
@@ -1 +1 @@
-a1
+a2
EOF
);

Util::test_autofixup(
    name => "filename with unusual characters",
    topic_commits => [{"ff\f nak\025 dq\" hack\\ fei飞.txt" => "a1\n"}],
    unstaged => {"ff\f nak\025 dq\" hack\\ fei飞.txt" => "a2\n"},
    exit_code => 0,
    log_want => <<'EOF'
fixup! commit0

diff --git "a/ff\f nak\025 dq\" hack\\ fei\351\243\236.txt" "b/ff\f nak\025 dq\" hack\\ fei\351\243\236.txt"
index da0f8ed..c1827f0 100644
--- "a/ff\f nak\025 dq\" hack\\ fei\351\243\236.txt"	
+++ "b/ff\f nak\025 dq\" hack\\ fei\351\243\236.txt"	
@@ -1 +1 @@
-a1
+a2
EOF
);
