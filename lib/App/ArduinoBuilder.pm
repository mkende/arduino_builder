package App::ArduinoBuilder;

use 5.022;
use strict;
use warnings;
use utf8;

use App::ArduinoBuilder::Builder 'build_archive', 'build_object_files', 'link_executable', 'run_hook';
use App::ArduinoBuilder::Config 'get_os_name';
use App::ArduinoBuilder::FilePath 'find_latest_revision_dir', 'list_sub_directories';

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

  my $menu_config = $config->filter('builder.menu');

  my $boards_config_path = catfile($hardware_path, 'boards.txt');
  if (-f $boards_config_path) {
    my $board_name = $config->get('builder.package.board');
    my $board = App::ArduinoBuilder::Config->new(file => $boards_config_path, resolve => 1, allow_partial => 1)->filter($board_name);
    die "Board '${board_name}' not found in boards.txt.\n" if $board->empty();
    $config->merge($board);
  } else {
    warn "Could not find boards.txt file.\n";
  }

  my $board_menu = $config->filter('menu');
  for my $m ($menu_config->keys()) {
    my $v = $menu_config->get($m);
    $config->merge($board_menu->filter("${m}.${v}"));
  }

  # TODO: Handles core, variant and tools references:
  # https://arduino.github.io/arduino-cli/0.32/platform-specification/#core-reference

  my @package_config_files = grep { -f } map { catfile($hardware_path, $_) } qw(platform.local.txt platform.txt programmers.local.txt programmers.txt);
  map { $config->read_file($_) } @package_config_files;

  # https://arduino.github.io/arduino-cli/0.32/platform-specification/#global-predefined-properties
  $config->set('runtime.platform.path' => $hardware_path);
  # Unclear what the runtime.hardware.path variable is supposed to point to.
  $config->set('runtime.os' => get_os_name());
  $config->set('runtime.ide.version' => '2.0.4');  # The version that we are emulating currently.
  $config->set('software' => 'ARDUINO');
  # todo: name, _id, build.fqbn
  $config->set('build.source.path' => $project_dir);
  $config->set('sketch_path' => $project_dir);
  $config->set('build.path' => $build_dir);
  $config->set('build.project_name' => $config->get('builder.project_name'));
  $config->set('build.arch' => $config->get('builder.package.arch'));
  $config->set('build.core.path', catdir($hardware_path, 'cores', $config->get('build.core')));
  $config->set('build.system.path', catdir($hardware_path, 'system'));
  $config->set('build.variant.path', catdir($hardware_path, 'variants', $config->get('build.variant')));

  my $tools_dir = catdir($package_path, 'tools');
  my @tools = list_sub_directories($tools_dir);
  for my $t (@tools) {
    print "Found tool: $t\n";
    my $tool_path = catdir($tools_dir, $t);
    my $latest_tool_path = find_latest_revision_dir($tool_path);
    $config->set("runtime.tools.${t}.path", $latest_tool_path);
    for my $v (list_sub_directories($tools_dir)) {
      $config->set("runtime.tools.${t}-${v}.path", catdir($tool_path, $v));
    }
  }

  # TODO: we should create config for all the tools defined by all the other
  # platform (not overriding the existing definitions). There are some other
  # considerations that we are not handling yet from:
  # https://arduino.github.io/arduino-cli/0.32/package_index_json-specification/#how-a-tools-path-is-determined-in-platformtxt

  # TODO: we should probably never call resolve because variables can change
  # but the config could have a cache of resolved values with invalidation on
  # the right variable change.
  $config->resolve(allow_partial => 1);

  my $builder = App::ArduinoBuilder::Builder->new($config);

  #$builder->run_hook('prebuild', $config);

  $config->append('includes', '"-I'.$config->get('build.core.path').'"');
  $config->append('includes', '"-I'.$config->get('build.variant.path').'"');
  #$builder->run_hook('core.prebuild', $config);
  #$builder->build_archive([$config->get('build.core.path'), $config->get('build.variant.path')], catdir($build_dir, 'core'), 'core.a', $config);
  #$builder->run_hook('core.postbuild', $config);

  $config->append('includes', '"-I'.$config->get('build.source.path').'"');
  $builder->run_hook('sketch.prebuild', $config);
  my @object_files = $builder->build_object_files($config->get('build.source.path'), catdir($build_dir, 'sketch'), [$build_dir], $config);
  $builder->run_hook('sketch.postbuild', $config);

  print 'Object files: '.join(', ', @object_files)."\n";

  $builder->run_hook('linking.prelink', $config);
  $builder->link_executable(\@object_files, 'core.a', $config);
  $builder->run_hook('linking.postlink', $config);
}

1;
