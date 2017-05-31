use Test::More tests => 2;
use File::Temp;
use App::Git::Autofixup;
require 'git-autofixup';

is($VERSION, $App::Git::Autofixup::VERSION, "versions agree");

$tmp = File::Temp->new();
$tmp_name = $tmp->filename();
system("perldoc -u git-autofixup >$tmp_name");
system("diff -u $tmp_name README.pod");
ok($? == 0, 'README.pod is up-to-date');
