use strict;
use warnings;
use utf8;

use Test2::V0;
use Test2::Tools::Exception;

use App::ArduinoBuilder::Config;

use FindBin;

my $config = App::ArduinoBuilder::Config->new();

my $simple_config_path = "${FindBin::Bin}/data/simple_config.txt";
my $simple_config_resolved = <<~EOF;
  not.yet.here=tada {undef.value}
  test.last=tada {undef.value} and this is a value and more!
  test.other=this is a value and more
  test.value=this is a value
  EOF

is(ref $config, 'App::ArduinoBuilder::Config');
ok($config->read_file($simple_config_path));
ok($config->resolve(allow_partial => 1));
is($config->dump(), $simple_config_resolved);
is($config->filter('test')->dump(), <<~EOF);
  last=tada {undef.value} and this is a value and more!
  other=this is a value and more
  value=this is a value
  EOF


is(App::ArduinoBuilder::Config->new(files=>[$simple_config_path], resolve => 1, allow_partial => 1)->dump(), $simple_config_resolved);

like(dies { App::ArduinoBuilder::Config->new(files=>[$simple_config_path], resolve => 1) }, qr/Can’t resolve key 'undef.value'/);

done_testing;
