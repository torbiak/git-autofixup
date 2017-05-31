use 5.008004;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'App::Git::Autofixup',
    VERSION_FROM     => 'lib/App/Git/Autofixup.pm',
    ABSTRACT_FROM    => 'lib/App/Git/Autofixup.pm',
    AUTHOR           => 'Jordan Torbiak',
    LICENSE          => 'artistic_2',
    MIN_PERL_VERSION => '5.008004',
    EXE_FILES        => ['git-autofixup'],
    (eval { ExtUtils::MakeMaker->VERSION(6.46) } ? (META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                url  => 'https://github.com/torbiak/git-autofixup.git',
                web  => 'https://github.com/torbiak/git-autofixup',
            },
        }})
        : ()
    ),
);
