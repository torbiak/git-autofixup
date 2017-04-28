#!/bin/perl
use 5.008;  # In accordance with Git's CodingGuidelines.
use strict;
use warnings FATAL => 'all';
use Getopt::Long qw(:config bundling);

# TODO: remove
use Data::Dumper;
$Data::Dumper::Terse = 1;
$Data::Dumper::Useqq = 1;

our $VERSION = 'v0.0.1';

my ($verbose, $strict);

my $usage =<<END;
usage: git-autofixup [<options>] <upstream-revision>

-h, --help     show help
--version      show version
-v, --verbose  show more information
--strict       require added lines to be surrounded by the target commit
END

# Parse hunks out of `git diff` output. Return an array of hunk hashrefs.
sub parse_diffs {
    my $fh = shift;
    my ($file_a, $file_b);
    my @hunks;
    while (<$fh>) {
        if (/^--- (.*)/) {
            $file_a = $1;
            next;
        }
        if (/^\+\+\+ (.*)/) {
            $file_b = $1;
            next;
        }
        if (/^@@ -(\d+)(?:,(\d+))? \+(?:\d+)(?:,(?:\d+))? @@ ?(.*)/) {
            my $header = $_;
            s#^[ab]/## for ($file_a, $file_b);
            # Ignore creations and deletions.
            next if $file_a ne $file_b;
            my $lines = [];
            while (1) {
                $_ = <$fh>;
                if (!defined($_) || /^[^ +-]/) {
                    last;
                }
                push @$lines, $_;
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
            redo if defined($_);
        }
    }
    return @hunks;
}

sub get_commits {
    my $rev = shift;
    my %commits;
    for (qx(git log --format=%H:%s $rev..)) {
        chomp;
        my ($sha, $msg) = split ':', $_, 2;
        $commits{$sha} = $msg;
    }
    return \%commits;
}

# Return targets of fixup!/squash! commits.
sub get_sha_aliases {
    my $commits = shift;
    my %aliases;
    for my $i (keys %$commits) {
        my $msg = $commits->{$i};
        next unless $msg =~ /^(?:fixup|squash)! (.*)/;
        my $prefix = $1;
        if ($prefix =~ /^(?:(?:fixup|squash)! ){2}/) {
            die "fixup commits for fixup commits aren't supported: $i";
        }

        my @matches;
        for my $j (keys %$commits) {
            if (index($commits->{$j}, $1, 0) == 0) {
                push @matches, $j;
            }
        }
        if (@matches > 1) {
            die "ambiguous fixup commit target: multiple commit summaries start with: $prefix\n";
        } elsif (@matches == 0) {
            die "no fixup target: $i";
        } elsif (@matches == 1) {
            $aliases{$i} = $matches[0];
        }
    }
    return \%aliases;
}


sub get_fixup_sha {
    my ($hunk, $sha_set, $sha_aliases) = @_;
    my $blame = blame($hunk);
    my $target;

    print Dumper($blame); # TODO: remove

    my $is_valid_target = sub {
        my $sha = shift;
        unless (exists($sha_set->{$sha})) {
            return undef;
        }
        $target //= $sha;
        if ($sha ne $target) {
            if ($verbose) {
                print STDERR "multiple fixup targets for $hunk->{file}, $hunk->{header}";
            }
            return undef;
        }
        return 1;
    };

    my $resolve = sub {
        my $sha = shift;
        return '' unless $sha;
        return $sha_aliases->{$sha} // $sha;
    };

    my $bi = $hunk->{start}; # blame index
    my $diff = $hunk->{lines};
    for (my $di = 0; $di < @$diff; $di++) { # diff index
        my $line = $diff->[$di];
        if (startswith($line, '-')) {
            my $sha = &$resolve($blame->{$bi});
            &$is_valid_target($sha) or return undef;
            $bi++;
            next;
        } elsif (startswith($line, '+')) {
            my $above = &$resolve($blame->{$bi-1});
            my $below = &$resolve($blame->{$bi});
            if ($sha_set->{$above} and $sha_set->{$below}) {
                $above eq $below or return undef;
                &$is_valid_target($above) or return undef;
            } elsif (!$strict and $sha_set->{$above}) {
                &$is_valid_target($above) or return undef;
            } elsif (!$strict and $sha_set->{$below}) {
                &$is_valid_target($below) or return undef;
            }
            while ($di < @$diff-1 and startswith($diff->[$di+1], '+')) {
                $di++;
            }
            # Added lines don't show up in `git blame HEAD`, so the blame index
            # isn't incremented.
            next;
        } elsif (startswith($line, ' ')) {
            $bi++;
            next;
        } else {
            die "unexpected diff line: $line";
        }
    }
    unless ($target) {
        $verbose and print "no fixup targets found for $hunk->{file}, $hunk->{header}";
    }
    return $target;
}

sub startswith {
    index($_[0], $_[1], 0) == 0;
}

sub blame {
    my $hunk = shift;
    my $cmd = "git blame --porcelain -L $hunk->{start},+$hunk->{count} HEAD $hunk->{file}";
    open(my $fh, '-|', $cmd) or die "git blame: $!\n";
    my %blame;
    while (<$fh>) {
        next unless /^([0-9a-f]{40}) \d+ (\d+)/;
        $blame{$2} = $1;
    }
    close($fh) or die "git blame: non-zero exit code";
    return \%blame;
}

sub get_diff_hunks {
    my @cmd = ('git', 'diff', '--ignore-submodules');
    open(my $fh, '-|', @cmd) or die $!;
    my @hunks = parse_diffs($fh, keep_lines => 1);
    close($fh) or die "git diff: non-zero exit code";
    return @hunks;
}

sub commit_fixup {
    my ($sha, $hunks) = @_;
    open my $fh, '|-', 'git apply --cached -' or die "git apply: $!\n";
    for my $hunk (@$hunks) {
        print($fh
            "--- a/$hunk->{file}\n",
            "+++ a/$hunk->{file}\n",
            $hunk->{header},
            @{$hunk->{lines}},
        );
    }
    close $fh or die "git apply: non-zero exit code\n";
    system(qw(git commit), "--fixup=$sha") == 0 or die "git commit: $!\n";
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
        'verbose|v' => \$verbose,
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

    if (is_index_dirty) {
        die "There are staged changes. Clean up the index and try again.\n";
    }

    my @hunks = get_diff_hunks;
    print Dumper(\@hunks);
    my $sha2summary = get_commits $upstream;
    print Dumper($sha2summary);
    my $sha_aliases = get_sha_aliases $sha2summary;
    print Dumper($sha_aliases);
    my %sha2hunks;
    for my $hunk (@hunks) {
        my $sha = get_fixup_sha $hunk, $sha2summary, $sha_aliases;
        next unless $sha;
        push @{$sha2hunks{$sha}}, $hunk;
    }
    print Dumper(\%sha2hunks);
    for my $sha (keys %sha2hunks) {
        commit_fixup $sha, $sha2hunks{$sha};
    }

    return 0;
}
exit main();
