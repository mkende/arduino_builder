package App::ArduinoBuilder::System;

use strict;
use warnings;
use utf8;

use Exporter 'import';
use File::Spec::Functions;
use List::Util 'first';

our @EXPORT_OK = qw(find_arduino_dir);

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
