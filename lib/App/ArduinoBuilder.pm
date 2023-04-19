package App::ArduinoBuilder;

use 5.022;
use strict;
use warnings;
use utf8;

use App::ArduinoBuilder::Config 'get_os_name';
use App::ArduinoBuilder::FilePath 'find_latest_revision_dir';

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

  my $package_path = $config->get('builder.package.path');
  my $hardware_path = find_latest_revision_dir(catdir($package_path, 'hardware', $config->get('builder.package.arch')));

  print "Project config: \n".$config->dump('  ');

  my $boards_local_config_path = catfile($hardware_path, 'boards.local.txt');
  if (-f $boards_local_config_path) {
    my $board_name = $config->get('builder.package.board');
    my $board = App::ArduinoBuilder::Config->new(file => $boards_local_config_path, resolve => 1, allow_partial => 1)->filter($board_name);
    $config->merge($board);
  }

  my $boards_config_path = catfile($hardware_path, 'boards.txt');
  if (-f $boards_config_path) {
    my $board_name = $config->get('builder.package.board');
    my $board = App::ArduinoBuilder::Config->new(file => $boards_config_path, resolve => 1, allow_partial => 1)->filter($board_name);
    die "Board '${board_name}' not found in boards.txt.\n" if $board->empty();
    $config->merge($board);
  } else {
    warn "Could not find boards.txt file.\n";
  }

  # TODO: Handles core, variant and tools references:
  # https://arduino.github.io/arduino-cli/0.32/platform-specification/#core-reference

  my @package_config_files = grep { -f } map { catfile($hardware_path, $_) } qw(platform.txt programmers.txt);
  map { $config->read_file($_) } @package_config_files;

  # https://arduino.github.io/arduino-cli/0.32/platform-specification/#global-predefined-properties
  $config->set('runtime.platform.path' => $hardware_path);
  # Unclear what the runtime.hardware.path variable is supposed to point to.
  $config->set('runtime.os' => get_os_name());
  $config->set('software' => 'ARDUINO');
  # todo: name, _id, build.fqbn
  $config->set('build.source.path' => $project_dir);
  $config->set('build.path' => $build_dir);
  $config->set('build.project_name' => $config->get('builder.project_name'));
  $config->set('build.arch' => $config->get('builder.package.arch'));
  $config->set('build.core.path', catdir($hardware_path, 'cores', $config->get('build.core')))
  $config->set('build.system.path', catdir($hardware_path, 'system'))
  $config->set('build.variant.path', catdir($hardware_path, 'variants', $config->get('build.variant')))

  $config->resolve(allow_partial => 1);

  print "Complete config: \n".$config->dump('  ');
}

1;
