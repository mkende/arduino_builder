package App::ArduinoBuilder::Logger;

use strict;
use warnings;
use utf8;

use Carp qw(confess);
use Data::Dumper;
use Exporter 'import';
use Log::Log4perl;
use Log::Log4perl::Level ();

our @EXPORT = qw(fatal error warning info debug full_debug dump dump_long dump_short);
our @EXPORT_OK = (@EXPORT, qw(log_cmd set_log_level is_logged set_prefix print_stack_on_fatal_error dump dump_short));
our %EXPORT_TAGS = (default => [@EXPORT], all => [@EXPORT_OK], all_logger => [@EXPORT, 'log_cmd']);

my $LEVEL_FATAL = 0;  # Fatal errors, abort the program.
my $LEVEL_ERROR = 1;  # Recoverable errors (almost unused).
my $LEVEL_WARN = 2;  # Warnings about possible mis-configuration.
my $LEVEL_INFO = 3;  # Info about the main steps of the program.
my $LEVEL_DEBUG = 4;  # Any possibly lengthy debugging information.
my $LEVEL_CMD = 5;  # Command lines being executed (log method not exported by default).
my $LEVEL_FULL_DEBUG = 6;  # Any possibly very-lengthy debugging information.

my $default_level = $ENV{ARDUINO_BUILDER_LOG_LEVEL} // $LEVEL_INFO;
my $current_level = $default_level;
my $die_with_stack_trace = 0;

sub _level_to_log4perl_level {
  my ($level) = @_;
  return Log::Log4perl::Level::to_priority("FATAL") if $level == $LEVEL_FATAL;
  return Log::Log4perl::Level::to_priority("ERROR") if $level == $LEVEL_ERROR;
  return Log::Log4perl::Level::to_priority("WARNING") if $level == $LEVEL_WARN;
  return Log::Log4perl::Level::to_priority("INFO") if $level == $LEVEL_INFO;
  return Log::Log4perl::Level::to_priority("DEBUG") if $level == $LEVEL_DEBUG;
  return Log::Log4perl::Level::to_priority("CMD") if $level == $LEVEL_CMD;
  return Log::Log4perl::Level::to_priority("TRACE") if $level == $LEVEL_FULL_DEBUG;
  error("Unknown log level: ${level}");
  return $Log::Log4perl::Level::ERROR;
}

sub _stringify {
  my ($s) = @_;
  $s = $s->() if ref $s eq 'CODE';
  return $s unless ref $s;
  local $Data::Dumper::Indent = 2;
  local $Data::Dumper::Pad = '    ';
  local $Data::Dumper::Terse = 1;
  local $Data::Dumper::Sortkeys = 1;
  local $Data::Dumper::Sparseseen = 1;
  return Dumper($s);
}

# sub _stringify_short {
#   my ($s) = @_;
#   $s = $s->() if ref $s eq 'CODE';
#   return $s unless ref $s;
#   local $Data::Dumper::Indent = 0;
#   local $Data::Dumper::Pad = '';
#   local $Data::Dumper::Terse = 1;
#   local $Data::Dumper::Sortkeys = 1;
#   local $Data::Dumper::Sparseseen = 1;
#   return Dumper($s);
# }


sub _log {
  my ($level, $message, @args) = @_;
  my $calling_pkg = caller(2);
  my $logger = Log::Log4perl->get_logger($calling_pkg);
  my $req_level = _level_to_log4perl_level($level);
  if (Log::Log4perl::Level::isGreaterOrEqual($logger->level(), $req_level)) {
    @args = map { _stringify($_) } @args;
    my $msg = sprintf $message, @args;
    $logger->log($req_level, $msg);
  }
  if ($level == $LEVEL_FATAL) {
    @args = map { _stringify($_) } @args;
    my $msg = sprintf $message, @args;
    if ($die_with_stack_trace) {
      confess $msg."\nDied";  # Will print "message\nDied at foo.pm line 45\n..."
    } else {
      die $msg."\n";
    }
  }
  return;
}

# printf style method, you can also pass code reference they will be called
# and their return value used in the print command (useful to avoid expensive)
# method calls when not printing them.
sub fatal { _log($LEVEL_FATAL, @_) }
sub fatal_trace { _log($LEVEL_FATAL, @_) }
sub error { _log($LEVEL_ERROR, @_) }
sub warning { _log($LEVEL_WARN, @_) }
sub info { _log($LEVEL_INFO, @_) }
sub debug { _log($LEVEL_DEBUG, @_) }
sub log_cmd { _log($LEVEL_CMD, @_) }
sub full_debug { _log($LEVEL_FULL_DEBUG, @_) }

sub _string_to_level {
  my ($level) = @_; 
  return $LEVEL_FATAL if $level =~ m/^FATAL$/i;
  return $LEVEL_ERROR if $level =~ m/^ERR(?:OR)?$/i;
  return $LEVEL_WARN if $level =~ m/^WARN(:?ING)?$/i;
  return $LEVEL_INFO if $level =~ m/^INFO?$/i;
  return $LEVEL_DEBUG if $level =~ m/^(?:DBG|DEBUG)$/i;
  return $LEVEL_CMD if $level =~ m/^(?:CMD|COMMAND)S?$/i;
  return $LEVEL_FULL_DEBUG if $level =~ m/^FULL(:?_?(?:DBG|DEBUG))?$/i;
  error "Unknown log level: ${level}";
  return $default_level;
}

sub set_log_level {
  my ($str_level) = @_;
  Log::Log4perl->get_logger("")->level(_level_to_log4perl_level(_string_to_level($str_level)));
  return;
}

sub is_logged {
  my ($level) = @_;
  my $calling_pkg = caller(1);
  my $logger = Log::Log4perl->get_logger($calling_pkg);
  return Log::Log4perl::Level::isGreaterOrEqual($logger->level(), _level_to_log4perl_level($level));
}

sub print_stack_on_fatal_error {
  $die_with_stack_trace = $_[0];
}

1;
