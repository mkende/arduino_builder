package App::ArduinoBuilder;

use 5.022;
use strict;
use warnings;
use utf8;

use App::ArduinoBuilder::Builder 'build_archive', 'build_object_files', 'link_executable', 'run_hook';
use App::ArduinoBuilder::Config 'get_os_name';
use App::ArduinoBuilder::FilePath 'find_latest_revision_dir', 'list_sub_directories', 'find_all_files_with_extensions';
use App::ArduinoBuilder::Logger;

use Cwd;
use File::Spec::Functions;
use Getopt::Long;
use List::Util 'any', 'none';
use Pod::Usage;

our $VERSION = '0.01';

sub Run {
  my $project_dir;
  my $build_dir;

  my (@skip, @force, @only);
  GetOptions(
      'help|h' => sub { pod2usage(-exitval => 0, -verbose => 2)},
      'project_dir|project|p=s' => \$project_dir,
      'build_dir|build|b=s' => \$build_dir,
      'log_level|l=s' => sub { App::ArduinoBuilder::Logger::set_log_level($_[1]) },
      'skip=s@' => sub { push @skip, split /,/, $_[1] },  # skip this step
      'force=s@' => sub { push @force, split /,/, $_[1] },  # even if it would be skipped by the dependency checker
      'only=s@' => sub { push @only, split /,/, $_[1] },  # run only these steps (skip all others)
    ) or pod2usage(-exitval => 2, -verbose =>0);

  my $project_dir_is_cwd = 0;
  if (!$project_dir) {
    $project_dir_is_cwd = 1;
    $project_dir = getcwd();
  }

  my $config = App::ArduinoBuilder::Config->new(
      files => [catfile($project_dir, 'arduino_builder.local'),
                catfile($project_dir, 'arduino_builder.config')],
      allow_missing => 1,
      resolve => 1);

  if (!$build_dir) {
    if ($config->exists('builder.default_build_dir')) {
      $build_dir = catdir($project_dir, $config->get('builder.default_build_dir'));
    } elsif (!$project_dir_is_cwd) {
      $build_dir = getcwd();
    } else {
      fatal 'No builder.default_build_dir config and --build_dir was not passed when building from the project directory.';
    }
  }


  my $package_path = $config->get('builder.package.path');
  my $hardware_dir = catdir($package_path, 'hardware');
  if (!$config->exists('builder.package.arch')) {
    my @arch_dirs = list_sub_directories($hardware_dir);
    if (@arch_dirs == 1) {
      debug "Using arch '${arch_dirs[0]}'";
      $config->set('builder.package.arch' => $arch_dirs[0]);
    } else {
      fatal 'The builder.package.arch config is not set and more than one arch is present in the package: '.$hardware_dir;
    }
  }
  my $hardware_path = find_latest_revision_dir(catdir($hardware_dir, $config->get('builder.package.arch')));

  debug "Project config: \n%s", sub { $config->dump('  ') };

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
    fatal "Board '${board_name}' not found in boards.txt." if $board->empty();
    $config->merge($board);
  } else {
    warning "Could not find boards.txt file.";
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
    debug "Found tool: $t";
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

  $builder->run_hook('prebuild');

  $config->append('includes', '"-I'.$config->get('build.core.path').'"');
  $config->append('includes', '"-I'.$config->get('build.variant.path').'"');

  my $run_step = sub {
    my ($step) = @_;
    return (none { $_ eq $step } @skip) && (!@only || any { $_ eq $step } @only);
  };
  my $force = sub {
    my ($step) = @_;
    return any { $_ eq $step } @force;
  };

  my $built_something = 0;

  if ($run_step->('core')) {
    info 'Building core...';
    $builder->run_hook('core.prebuild');
    my $built_core = $builder->build_archive([$config->get('build.core.path'), $config->get('build.variant.path')], catdir($build_dir, 'core'), 'core.a', $force->('core'));
    info ($built_core ? '  Success' : '  Already up-to-date');
    $built_something |= $built_core;
    $builder->run_hook('core.postbuild');
  }


  $config->append('includes', '"-I'.$config->get('build.source.path').'"');


  if ($run_step->('sketch')) {
    info 'Building sketch...';
    $builder->run_hook('sketch.prebuild');
    my $built_sketch = $builder->build_object_files($config->get('build.source.path'), catdir($build_dir, 'sketch'), [$build_dir], $force->('sketch'));
    info ($built_sketch ? '  Success' : '  Already up-to-date');
    $built_something |= $built_sketch;
    $builder->run_hook('sketch.postbuild');
  }
  # Bug: there is a similar bug to the one in build_archive: if a source file is
  # removed, we won’t remove it’s object file. I guess we could try to detect it.
  # Meanwhile it’s probably acceptable to ask for a cleanup from time to time.
  my @object_files = find_all_files_with_extensions(catdir($build_dir, 'sketch'), ['o']);
  debug 'Object files: '.join(', ', @object_files);

  info 'Linking binary...';
  if (($built_something && $run_step->('link')) || $force->('link')) {
    $built_something = 1;
    $builder->run_hook('linking.prelink');
    $builder->link_executable(\@object_files, 'core.a');
    $builder->run_hook('linking.postlink');
    info '  Success';
  } else {
    info '  Already up-to-date';
  }

  info 'Extracting binary data';
  if (($built_something && $run_step->('objcopy')) || $force->('objcopy')) {
    $builder->run_hook('objcopy.preobjcopy');
    $builder->objcopy();
    $builder->run_hook('objcopy.postobjcopy');
    info '  Success';
  } else {
    info '  Already up-to-date';
  }

  info 'Success!';
}

1;
