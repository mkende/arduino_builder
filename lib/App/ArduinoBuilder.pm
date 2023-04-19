package App::ArduinoBuilder;

use 5.022;
use strict;
use warnings;
use utf8;

use App::ArduinoBuilder::Config;

use Cwd;
use File::Spec::Functions;
use Getopt::Long;
use Pod::Usage;

our $VERSION = '0.01';

sub Run {
  my $project_dir;
  my $build_dir;

  GetOptions(
      'help|h' => sub { pod2usage(-exitval => 0, -verbose => 2)},
      'project|p=s' => \$project_dir,
      'build|b=s' => \$build_dir,
    ) or pod2usage(-exitval => 2, -verbose =>0);

  if ($project_dir && !$build_dir) {
    $build_dir = getcwd();
  } elsif (!$project_dir) {
    $project_dir = getcwd();
    if (!$build_dir) {
      $build_dir = catdir($project_dir, '_build');
    }
  }

  my $config = App::ArduinoBuilder::Config->new(
      files => [catfile($project_dir, 'arduino_builder.local'),
                catfile($project_dir, 'arduino_builder.config')],
      resolve => 1);
  print $config->dump();
}

1;
