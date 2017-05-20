#!/bin/perl
package Git::AutoFixup;
use 5.008;  # In accordance with Git's CodingGuidelines.
use strict;
use warnings FATAL => 'all';
use Getopt::Long qw(GetOptionsFromArray :config bundling);

# TODO: remove
use Data::Dumper;
$Data::Dumper::Terse = 1;
$Data::Dumper::Useqq = 1;

our $VERSION = 0.001000; # X.00Y00Z

my ($verbose, $strict);

my $usage =<<'END';
usage: git-autofixup [<options>] <upstream-revision>

-h, --help     show help
--version      show version
-v, --verbose  increase verbosity (use up to 2 times)
--strict       require added lines to be surrounded by the target commit
END

# Parse hunks out of `git diff` output. Return an array of hunk hashrefs.
sub parse_hunks {
    my $fh = shift;
    my ($file_a, $file_b);
    my @hunks;
    while (my $line = <$fh>) {
        if ($line =~ /^--- (.*)/) {
            $file_a = $1;
        } elsif ($line =~ /^\+\+\+ (.*)/) {
            $file_b = $1;
        } elsif ($line =~ /^@@ -(\d+)(?:,(\d+))? \+\d+(?:,\d+)? @@/) {
            my $header = $line;

            for ($file_a, $file_b) {
                s#^[ab]/##;
            }

            next if $file_a ne $file_b; # Ignore creations and deletions.

            my $lines = [];
            while (1) {
                $line = <$fh>;
                if (!defined($line) || $line =~ /^[^ +-]/) {
                    last;
                }
                push @{$lines}, $line;
            }

            push(@hunks, {
                file => $file_a,
                start => $1,
                count => $2 // 1,
                header => $header,
                lines => $lines,
            });
            # The next line after a hunk could be a header for the next commit
            # or hunk.
            redo if defined($line);
        }
    }
    return @hunks;
}

sub get_summary_for_commits {
    my $rev = shift;
    my %commits;
    for (qx(git log --no-merges --format=%H:%s $rev..)) {
        chomp;
        my ($sha, $msg) = split ':', $_, 2;
        $commits{$sha} = $msg;
    }
    return \%commits;
}

# Return targets of fixup!/squash! commits.
sub get_sha_aliases {
    my $summary_for = shift;
    my %aliases;
    while (my ($sha, $summary) = each(%{$summary_for})) {
        next if $summary !~ /^(?:fixup|squash)! (.*)/;
        my $prefix = $1;
        if ($prefix =~ /^(?:(?:fixup|squash)! ){2}/) {
            die "fixup commits for fixup commits aren't supported: $sha";
        }
        my @matches = grep {startswith($summary_for->{$_}, $prefix)} keys(%{$summary_for});
        if (@matches > 1) {
            die "ambiguous fixup commit target: multiple commit summaries start with: $prefix\n";
        } elsif (@matches == 0) {
            die "no fixup target: $sha";
        } elsif (@matches == 1) {
            $aliases{$sha} = $matches[0];
        }
    }
    return \%aliases;
}

sub get_fixup_sha {
    my ($hunk, $blame, $sha_set, $sha_aliases) = @_;
    my $blame_indexes = get_blame_indexes($hunk);
    my $target;
    if ($verbose > 1) {
        print_hunk_blamediff(*STDERR, $hunk, $sha_set, $blame, $blame_indexes);
    }

    my $is_valid_target = sub {
        my $sha = shift;
        return if !exists($sha_set->{$sha});
        $target //= $sha;
        if ($sha ne $target) {
            if ($verbose) {
                print STDERR "multiple fixup targets for $hunk->{file}, $hunk->{header}";
            }
            return;
        }
        return 1;
    };

    my $resolve = sub {
        my $sha = shift;
        return '' if !$sha;
        return $sha_aliases->{$sha} // $sha;
    };

    my $diff = $hunk->{lines};
    for (my $di = 0; $di < @$diff; $di++) { # diff index
        my $bi = $blame_indexes->[$di];
        my $line = $diff->[$di];
        if (startswith($line, '-')) {
            my $sha = &$resolve($blame->{$bi}{sha});
            &$is_valid_target($sha) or return;
        } elsif (startswith($line, '+')) {
            my $above = &$resolve($blame->{$bi-1}{sha});
            my $below = &$resolve($blame->{$bi}{sha});
            if ($sha_set->{$above} && $sha_set->{$below}) {
                $above eq $below or return;
                &$is_valid_target($above) or return;
            } elsif (!$strict && $sha_set->{$above}) {
                &$is_valid_target($above) or return;
            } elsif (!$strict && $sha_set->{$below}) {
                &$is_valid_target($below) or return;
            }
            while ($di < @$diff-1 && startswith($diff->[$di+1], '+')) {
                $di++;
            }
        }
    }
    if (!$target) {
        $verbose && print STDERR "no fixup targets found for $hunk->{file}, $hunk->{header}";
    }
    return $target;
}

sub startswith {
    my ($haystack, $needle) = @_;
    return index($haystack, $needle, 0) == 0;
}

# Map lines in a hunk's diff to the corresponding `git blame HEAD` output.
sub get_blame_indexes {
    my $hunk = shift;
    my @indexes;
    my $bi = $hunk->{start};
    for (my $di = 0; $di < @{$hunk->{lines}}; $di++) {
        push @indexes, $bi;
        my $first = substr($hunk->{lines}[$di], 0, 1);
        if ($first eq '-' or $first eq ' ') {
            $bi++;
        }
        # Don't increment $bi for added lines.
    }
    return \@indexes;
}

sub print_hunk_blamediff {
    my ($fh, $hunk, $sha_set, $blame, $blame_indexes) = @_;
    my $format = "%-8.8s|%4.4s|%-30.30s|%-30.30s\n";
    print {$fh} "hunk blamediff: $hunk->{file}, $hunk->{header}";
    for (my $i = 0; $i < @{$hunk->{lines}}; $i++) {
        my $line = $hunk->{lines}[$i];
        my $bi = $blame_indexes->[$i];
        my $sha = $blame->{$bi}{sha};
        my $display_sha = $sha;
        if (startswith($line, '+')) { #!defined($sha)) {
            $display_sha = ''; # For added lines.
        } elsif (!exists($sha_set->{$sha})) {
            # For lines from before the given upstream revision.
            $display_sha = '^';
        }
        if (startswith($line, '+')) {
            printf {$fh} $format, $display_sha, '', '', rtrim($line);
        } else {
            printf {$fh} $format, $display_sha, $bi, rtrim($blame->{$bi}{text}), rtrim($line);
        }
    }
    print {$fh} "\n";
    return;
}

sub rtrim {
    my $s = shift;
    $s =~ s/\s+\z//;
    return $s;
}

sub blame {
    my $hunk = shift;
    my @cmd = (
        'git', 'blame', '--porcelain',
        '-L' => "$hunk->{start},+$hunk->{count}",
        'HEAD',
        "$hunk->{file}");
    my %blame;
    my ($sha, $line_num);
    open(my $fh, '-|', @cmd) or die "git blame: $!\n";
    while (my $line = <$fh>) {
        if ($line =~ /^([0-9a-f]{40}) \d+ (\d+)/) {
             ($sha, $line_num) = ($1, $2);
        }
        if (startswith($line, "\t")) {
            $blame{$line_num} = {sha => $sha, text => substr($line, 1)};
        }
    }
    close($fh) or die "git blame: non-zero exit code";
    return \%blame;
}

sub get_diff_hunks {
    my @cmd = qw(git diff --ignore-submodules);
    open(my $fh, '-|', @cmd) or die $!;
    my @hunks = parse_hunks($fh, keep_lines => 1);
    close($fh) or die "git diff: non-zero exit code";
    return wantarray ? @hunks : \@hunks;
}

sub commit_fixup {
    my ($sha, $hunks) = @_;
    open my $fh, '|-', 'git apply --cached -' or die "git apply: $!\n";
    for my $hunk (@{$hunks}) {
        print({$fh}
            "--- a/$hunk->{file}\n",
            "+++ a/$hunk->{file}\n",
            $hunk->{header},
            @{$hunk->{lines}},
        );
    }
    close $fh or die "git apply: non-zero exit code\n";
    system('git', 'commit', "--fixup=$sha") == 0 or die "git commit: $!\n";
    return;
}

sub is_index_dirty {
    open(my $fh, '-|', 'git status --porcelain') or die "git status: $!\n";
    my $dirty;
    while (my $line = <$fh>) {
        if ($line =~ /^[^?! ]/) {
            $dirty = 1;
            last;
        }
    }
    close $fh or die "git status: non-zero exit code\n";
    return $dirty;
}

sub get_fixup_hunks_by_sha {
    my ($hunks, $blame_for, $summary_for) = @_;
    my $alias_for = get_sha_aliases($summary_for);
    my %hunks_for;
    for my $hunk (@{$hunks}) {
        my $blame = $blame_for->{$hunk};
        my $sha = get_fixup_sha($hunk, $blame, $summary_for, $alias_for);
        next if !$sha;
        push @{$hunks_for{$sha}}, $hunk;
    }
    return \%hunks_for;
}

sub main {
    my @args = @_;
    my ($help, $show_version);
    $verbose = 0;
    $strict = undef;
    GetOptionsFromArray(\@args,
        'help|h' => \$help,
        'version' => \$show_version,
        'verbose|v+' => \$verbose,
        'strict' => \$strict,
    ) or return 1;
    if ($help) {
        print $usage;
        return 0;
    }
    if ($show_version) {
        print "$VERSION\n";
        return 0;
    }

    @args == 1 or die "No upstream revision given.\n";
    my $upstream = shift @args;
    qx(git rev-parse --verify ${upstream}^{commit});
    $? == 0 or die "Bad revision.\n";

    if (is_index_dirty()) {
        die "There are staged changes. Clean up the index and try again.\n";
    }

    my $hunks = get_diff_hunks();
    my $summary_for = get_summary_for_commits($upstream);
    my %blame_for = map {$_ => blame($_)} @{$hunks};
    my $hunks_for = get_fixup_hunks_by_sha($hunks, \%blame_for, $summary_for);
    while (my ($sha, $fixup_hunks) = each %{$hunks_for}) {
        commit_fixup($sha, $fixup_hunks);
    }
    return 0;
}

if (!caller()) {
    exit main(@ARGV);
}
1;

=pod

=head1 NAME

git-autofixup - create fixup commits for topic branches

=head1 SYNOPSIS

    git-autofixup [-v|--strict] REVISION

    # If the current branch has a tracking branch:
    git-autofixup @{upstream}

=head1 DESCRIPTION

C<git-autofixup> parses hunks of changes in the working directory out of C<git diff> output and uses C<git blame> to assign those hunks to commits in C<REVISION..HEAD>, which will typically represent a topic branch, and then creates fixup commits to be used with C<git rebase --interactive --autosquash>. [See C<git help revisions> for information about git revision specification syntax.] For a hunk to be included in a fixup commit, the same topic branch commit must be blamed for every removed line and at least one of the lines adjacent to each added line; additionally, added lines must not be adjacent to lines blamed on other topic branch commits.

For example,  the added line in the hunk below is adjacent to lines committed by commits C<99f370af> and C<a1eadbe2>. If these are both topic branch commits then it's ambiguous which commit the added line is "fixing up" and the hunk will be ignored.

    COMMIT  |LINE|HEAD                          |WORKING DIRECTORY
    99f370af|   1|first line                    | first line
            |    |                              |+added line
    a1eadbe2|   2|second line                   | second line

Output similar to this example can be generated by setting verbosity to 2 or greater by using the verbosity option multiple times, eg. C<git-autofixup -vv>, and can be helpful in determining how a hunk will be handled.

C<git-autofixup> is not to be used mindlessly. Always inspect the created fixup commits to ensure hunks have been assigned correctly.

=head2 STRICT HUNK ASSIGNMENT

By default C<git-autofixup> assumes a hunk adjacent to exactly one line blamed on a topic branch commit should fix up that commit. In the below example a fixup commit would be created for C<99f370af>.

    99f370af|   1|first line                    | first line
            |    |                              |+added line
            |   2|second line                   | second line

It's possible that C<added line> shouldn't fixup C<99f370af> and in that case the C<--strict> option can be used so only hunks surrounded by lines blamed on the same topic branch commit get included in a fixup commit. It's assumed that such additions are very likely to be fixups for the surrounding commit.

=head1 BUGS/LIMITATIONS

If a topic branch adds some lines in one commit and subsequently removes some of them in another, a hunk in the working directory that re-adds those lines will be assigned to fixup the first commit, and during rebasing they'll be removed again by the later commit.

=cut
