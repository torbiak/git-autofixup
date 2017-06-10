use strict;
use warnings FATAL => 'all';

use Test::More tests => 2;
use File::Temp;
use App::Git::Autofixup;
require './git-autofixup';

our $VERSION;
is($VERSION, $App::Git::Autofixup::VERSION, "versions agree");

my $tmp = File::Temp->new();
my $tmp_name = $tmp->filename();
system("perldoc -u git-autofixup >$tmp_name");
system("diff -u $tmp_name README.pod");
ok($? == 0, 'README.pod is up-to-date');
