#!/bin/perl
use 5.008;  # In accordance with Git's CodingGuidelines.
use strict;
use warnings FATAL => 'all';
use Getopt::Long qw(:config bundling);

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

sub get_commits {
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
    my ($hunk, $sha_set, $sha_aliases) = @_;
    my $blame = blame($hunk);
    my $blame_indexes = get_blame_indexes($hunk);
    my $target;
    if ($verbose > 1) {
        print_hunk_blamediff($hunk, $sha_set, $blame, $blame_indexes);
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
        $verbose && print "no fixup targets found for $hunk->{file}, $hunk->{header}";
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
    my ($hunk, $sha_set, $blame, $blame_indexes) = @_;
    my $format = "%-8.8s|%4.4s|%-30.30s|%-30.30s\n";
    print STDERR "hunk blamediff: $hunk->{file}, $hunk->{header}";
    for (my $i = 0; $i < @{$hunk->{lines}}; $i++) {
        my $line = $hunk->{lines}[$i];
        my $bi = $blame_indexes->[$i];
        my $sha = $blame->{$bi}{sha};
        my $display_sha = $sha;
        if (!defined($sha)) {
            $display_sha = ''; # For added lines.
        } elsif (!exists($sha_set->{$sha})) {
            # For lines from before the given upstream revision.
            $display_sha = '^';
        }
        if (startswith($line, '+')) {
            printf STDERR $format, $display_sha, '', '', rtrim($line);
        } else {
            printf STDERR $format, $display_sha, $bi, rtrim($blame->{$bi}{text}), rtrim($line);
        }
    }
    print STDERR "\n";
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
    my ($sha, $line);
    open(my $fh, '-|', @cmd) or die "git blame: $!\n";
    while (<$fh>) {
        if (/^([0-9a-f]{40}) \d+ (\d+)/) {
             ($sha, $line) = ($1, $2);
        }
        if (startswith($_, "\t")) {
            $blame{$line} = {sha => $sha, text => substr($_, 1)};
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
    return @hunks;
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
    while (<$fh>) {
        if (/^[^?! ]/) {
            $dirty = 1;
            last;
        }
    }
    close $fh or die "git status: non-zero exit code\n";
    return $dirty;
}

sub main {
    my ($help, $show_version);
    GetOptions(
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

    scalar @ARGV == 1 or die "No upstream revision given.\n";
    my $upstream = shift @ARGV;
    qx(git rev-parse --verify ${upstream}^{commit});
    $? == 0 or die "Bad revision.\n";

    if (is_index_dirty()) {
        die "There are staged changes. Clean up the index and try again.\n";
    }

    my @hunks = get_diff_hunks();
    print Dumper(\@hunks);
    my $sha2summary = get_commits($upstream);
    print Dumper($sha2summary);
    my $sha_aliases = get_sha_aliases($sha2summary);
    print Dumper($sha_aliases);
    my %sha2hunks;
    for my $hunk (@hunks) {
        my $sha = get_fixup_sha($hunk, $sha2summary, $sha_aliases);
        next if !$sha;
        push @{$sha2hunks{$sha}}, $hunk;
    }
    print Dumper(\%sha2hunks);
    for my $sha (keys %sha2hunks) {
        commit_fixup($sha, $sha2hunks{$sha});
    }

    return 0;
}

if (!caller()) {
    exit main();
}
1;
