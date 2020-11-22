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
    plan skip_all => 'git version 1.7.4+ required'
} else {
    plan tests => 39;
}

require './git-autofixup';

$ENV{GIT_AUTHOR_NAME} = 'A U Thor';
$ENV{GIT_AUTHOR_EMAIL} = 'author@example.com';
$ENV{GIT_COMMITTER_NAME} = 'C O Mitter';
$ENV{GIT_COMMITTER_EMAIL} = 'committer@example.com';


sub has_git {
    my $stdout = qx{git --version};
    return if $? != 0;
    my ($x, $y, $z) = $stdout =~ /(\d+)\.(\d+)(?:\.(\d+))?/;
    defined $x or die "unexpected output from git: $stdout";
    $z = defined $z ? $z : 0;
    my $cmp = $x <=> 1 || $y <=> 7 || $z <=> 4;
    return $cmp >= 0;
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
# staged: sub or hash ref of index changes
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
    my $staged = $args->{staged};
    my $log_want = defined($args->{log_want}) ? $args->{log_want}
                 : croak "wanted log output not given";
    my $unstaged_want = $args->{unstaged_want};
    my $exit_code_want = $args->{exit_code};
    my $autofixup_opts = $args->{autofixup_opts} || [];
    push @{$autofixup_opts}, '--exit-code';
    if (!$upstream_commits && !$topic_commits) {
        croak "no upstream or topic commits given";
    }
    if (exists $args->{strict}) {
        croak "strict key given; use test_autofixup_strict instead";
    }

    my $exit_code_got;
    my $log_got;
    my $unstaged_got;
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

        if (defined($staged)) {
            apply_change($staged);
            # We're at the repo root, so using -A will change everything even
            # in pre-v2 versions of git. See git commit 808d3d717e8.
            run("git add -A");
        }

        apply_change($unstaged);

        run("git --no-pager log --format='%h %s' ${upstream_rev}..");
        $exit_code_got = autofixup(@{$autofixup_opts}, $upstream_rev);
        $log_got = git_log(${pre_fixup_rev});
        if (defined($unstaged_want)) {
            $unstaged_got = diff('HEAD');
        }
    };
    my $err = $@;
    chdir $orig_dir or die "$!";
    if ($err) {
        diag($err);
        fail($name);
        return;
    }

    my $failed = 0;
    if ($log_got ne $log_want) {
        diag("log_got=<<EOF\n${log_got}EOF\nlog_want=<<EOF\n${log_want}EOF\n");
        $failed = 1;
    }

    if (defined($unstaged_want) && $unstaged_want ne $unstaged_got) {
        diag("unstaged_got=<<EOF\n${unstaged_got}EOF\nunstaged_want=<<EOF\n${unstaged_want}EOF\n");
        $failed = 1;
    }

    if (defined($exit_code_want) && $exit_code_got != $exit_code_want) {
        diag("exit_code_want=$exit_code_want,exit_code_got=$exit_code_got");
        $failed = 1;
    }

    if ($failed) {
        fail($name);
    } else {
        pass($name);
    }
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

sub git_log {
    my $revision = shift;
    my $log = qx{git -c diff.noprefix=false log -p --format=%s ${revision}..};
    if ($? != 0) {
        croak "git log: $?\n";
    }
    return $log;
}

sub diff {
    my $revision = shift;
    my $diff = qx{git -c diff.noprefix=false diff ${revision}};
    if ($? != 0) {
        croak "git diff $?\n";
    }
    return $diff;
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
    print "# git-autofixup ", join(' ', @ARGV), "\n";
    return main();
}


test_autofixup_strict({
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
});

test_autofixup_strict({
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
});

test_autofixup({
    name => "adjacent change doesn't get autofixed if strict=2",
    upstream_commits => [{a => "a3\n"}],
    topic_commits => [{a => "a1\na3\n"}],
    unstaged => {a => "a1\na2\na3\n"},
    log_want => '',
    autofixup_opts => ['-s2'],
    exit_code => 2,
});

test_autofixup({
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
});

test_autofixup_strict({
    name => "removed file doesn't get autofixed",
    strict => [0..2],
    topic_commits => [sub { write_file(a => "a1\n"); }],
    unstaged => sub { unlink 'a'; },
    exit_code => 3,
    log_want => '',
});

test_autofixup_strict({
    name => "re-added file doesn't get autofixed",
    strict => [0..2],
    topic_commits => [
        sub { write_file(a => "a1\n"); },
        sub { unlink 'a'; },
    ],
    unstaged => sub { write_file(a => "a1a\n"); },
    exit_code => 3,
    log_want => '',
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
});

test_autofixup_strict({
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
});

test_autofixup_strict({
    name => 'no fixups are created for upstream commits',
    strict => [0..2],
    upstream_commits => [{a => "a1\n"}],
    unstaged => {a => "a1a\n"},
    exit_code => 2,
    log_want => '',
});

test_autofixup({
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
});
test_autofixup_strict({
    name => 'no fixups are created for hunks changing lines blamed by upstream if strict > 0',
    # This depends on the number of context lines kept when creating diffs. git
    # keeps 3 by default.
    strict => [1..2],
    upstream_commits => [{a => "a1\na2\na3\n"}],
    topic_commits => [{a => "a1\na2a\na3a\n"}],
    unstaged => {a => "a1b\na2b\na3b\n"},
    exit_code => 2,
    log_want => '',
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
});

test_autofixup({
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
});

test_autofixup({
    name => "added line is ignored when context=0",
    topic_commits => [{a => "a1\n"}],
    unstaged => {a => "a1\na2\n"},
    autofixup_opts => ['-c' => 0],
    exit_code => 2,
    log_want => '',
});

test_autofixup({
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
});

test_autofixup({
    name => "Works when run in a subdir of the repo root",
    topic_commits => [
        sub {
            mkdir 'sub' or die $!;
            chdir 'sub' or die $!;
            write_file("a", "a1\n");
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
});

test_autofixup({
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
});

test_autofixup({
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
});

test_autofixup({
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
});

test_autofixup({
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
});

test_autofixup({
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
});

test_autofixup({
    name => "multiple hunks to the same commit",
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
}});

test_autofixup({
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
});

test_autofixup({
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
});
