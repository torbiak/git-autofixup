use strict;
use warnings FATAL => 'all';

use Test::More tests => 2;
use File::Temp;
use App::Git::Autofixup;
require './git-autofixup';

{
    my $script_version = $Autofixup::VERSION;
    my $stub_module_version = $App::Git::Autofixup::VERSION;
    is($script_version, $stub_module_version, "versions agree");
}

{
    my $tmp = File::Temp->new();
    my $tmp_name = $tmp->filename();
    system("perldoc -u git-autofixup >$tmp_name");
    system("diff -u $tmp_name README.pod");
    ok($? == 0, 'README.pod is up-to-date');
}
