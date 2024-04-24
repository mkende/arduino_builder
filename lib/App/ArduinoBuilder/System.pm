package App::ArduinoBuilder::System;

use strict;
use warnings;
use utf8;

use Cwd;
use Exporter 'import';
use File::Spec::Functions 'catdir', 'rel2abs', 'canonpath';
use List::Util 'first';
use Log::Any::Simple ':default';

our @EXPORT_OK = qw(find_arduino_dir system_cwd system_canonpath execute_cmd);

sub find_arduino_dir {
  my @tests;
  if ($^O eq 'MSWin32' || $^O eq 'cygwin' || $^O eq 'msys') {
    if (exists $ENV{LOCALAPPDATA}) {
      push @tests, catdir($ENV{LOCALAPPDATA}, 'Arduino15');
    }
  }
  if ($^O ne 'MSWin32') {
    push @tests, '/usr/share/arduino', '/usr/local/share/arduino';
    if (`which arduino 2>/dev/null` =~ m{^(.*)/bin/arduino}) {
      push @tests, catdir($1, 'share/arduino');
    }
  }
  return first { -d } @tests;
}

sub system_cwd {
  my $cwd = getcwd();
  # Todo: we could have a "use_native_cygwin" option somewhere in the improbable
  # case of a native toolchain to deactivate this logic (as well as using
  # /dev/null instal of nul in the builder).
  if ($^O eq 'cygwin') {
    $cwd = `cygpath -w '${cwd}'`;
    chomp($cwd);
  }
  return $cwd;
}

# Canonicalize a file path to be used to compare file paths (can’t be fed to
# external utilities).
sub system_canonpath {
  my ($path) = @_;
  my $canon = canonpath(rel2abs($path));
  if ($^O eq 'cygwin') {
    $canon = `cygpath '$canon'`;
    chomp($canon);
  }
  return $canon;
}

sub execute_cmd {
  my ($cmd, %options) = @_;
  trace $cmd;
  if (exists $options{capture_output}) {
    my $out = `${cmd}`;
    fatal "Can’t execute the following command: $!\n\t${cmd}" unless defined $out;
    ${$options{capture_output}} = $out;
  } else {
    system($cmd) and fatal "Can’t execute the following command: $!\n\t${cmd}";
  }
  return 1;
}
