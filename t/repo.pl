package Repo;

use Carp qw(croak);

require './t/util.pl';

# Return a new Repo, which is a git repo initialized in a temp dir.
#
# By default the temp dir will be removed when it goes out of scope, so if you
# want to be able to inspect a repo after a test fails, give `cleanup => 0`.
sub new {
    my ($class, %args) = @_;
    my $self = {};
    $self->{cleanup} = defined($args{cleanup}) ? $args{cleanup} : 1;

    bless $self, $class;

    $self->_init_env();
    $self->_init_repo();

    return $self;
}

sub _init_env {
    my $self = shift;

    my $orig_dir = Cwd::getcwd();
    my $dir = File::Temp::tempdir(CLEANUP => self->{cleanup});
    chdir $dir or die "$!";

    my %env = (
        # Avoid loading user or global git config, since lots of options can
        # break our tests.
        HOME => $dir,
        XDG_CONFIG_HOME => $dir,
        GIT_CONFIG_NOSYSTEM => 'true',

        # In order to make commits, git requires an author identity.
        GIT_AUTHOR_NAME => 'A U Thor',
        GIT_AUTHOR_EMAIL => 'author@example.com',
        GIT_COMMITTER_NAME => 'C O Mitter',
        GIT_COMMITTER_EMAIL => 'committer@example.com',
    );
    my %orig_env = ();
    for my $key (keys %env) {
        my $val = $env{$key};
        $orig_env{$key} = $ENV{$key};
        $ENV{$key} = $val;
    }

    $self->{dir} = $dir;
    $self->{orig_dir} = $orig_dir;
    $self->{orig_env} = \%orig_env;
}

sub _init_repo {
    my $self = shift;
    $self->{n_commits} = 0;  # Number of commits created using create_commits()
    local $ENV{GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME} = 'master';
    Util::run('git init');
    # git-autofixup needs a commit to exclude, since it uses the REVISION..
    # syntax. This is that commit.
    my $filename = 'README';
    Util::write_file($filename, "init\n");
    Util::run("git add $filename");
    Util::run(qw(git commit -m), "add $filename");
}

# File::Temp will take care of cleaning tempdirs up at the end of the test
# script.
sub DESTROY {
    local $!;
    my $self = shift;

    chdir $self->{orig_dir} or die "change to orig working dir: $!";

    for my $key (keys %{$self->{orig_env}}) {
        my $val = $self->{orig_env}{key};
        $ENV{$key} = $val;
    }
}

sub create_commits {
    my ($self, @commits) = @_;
    for my $commit (@commits) {
        $self->write_change($commit);
        $self->commit_if_dirty("commit" . $self->{n_commits});
        $self->{n_commits} += 1;
    }
}

sub write_change {
    my ($self, $change) = @_;
    if (ref $change eq 'HASH') {
        while (my ($file, $contents) = each %{$change}) {
            Util::write_file($file, $contents);
        }
    } elsif (ref $change eq 'CODE') {
        &{$change}();
    }
}

sub commit_if_dirty {
    my ($self, $msg) = @_;
    my $is_dirty = qx(git status -s);
    if ($is_dirty) {
        Util::run('git add -A');
        Util::run(qw(git commit -am), $msg);
    }
}

sub log_since {
    my ($self, $revision) = @_;
    my $log = qx{git -c diff.noprefix=false log -p --format=%s ${revision}..};
    if ($? != 0) {
        croak "git log: $!\n";
    }
    return $log;
}

sub diff {
    my ($self, $revision) = @_;
    my $diff = qx{git -c diff.noprefix=false diff ${revision}};
    if ($? != 0) {
        croak "git diff $!\n";
    }
    return $diff;
}

sub current_commit_sha {
    my ($self, $dir) = @_;
    my $revision = qx{git rev-parse HEAD};
    $? == 0 or croak "git rev-parse: $!";
    chomp $revision;
    return $revision;
}

sub autofixup {
    my $self = shift;
    local @ARGV = @_;
    print "# git-autofixup ", join(' ', @ARGV), "\n";
    return Autofixup::main();
}

sub switch_to_downstream_branch {
    my ($self, $branch) = @_;
    my $tracking_branch = qx(git rev-parse --abbrev-ref HEAD)
        or croak "get tracking branch: $!";
    chomp $tracking_branch;
    Util::run(qw(git checkout -q -b), $branch, '--track', $tracking_branch);
}

1;
