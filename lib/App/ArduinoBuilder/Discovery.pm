package App::ArduinoBuilder::Discovery;

use strict;
use warnings;
use utf8;

use App::ArduinoBuilder::Config;
use App::ArduinoBuilder::Logger ':all_logger';
use File::Spec::Functions;
use IPC::Open2;
use JSON::PP;
use Time::HiRes 'usleep';

# Specification of the discovery protocol.
# https://arduino.github.io/arduino-cli/0.32/pluggable-discovery-specification/
sub _run_one_discovery {
  my ($toolname, $cmd) = @_;

  # Let’s just hope that we don’t have running CommandRunner tasks...
  # Otherwise we could have an actual handler that redirec to the CommandRunner
  # one.
  local $SIG{CHLD} = 'DEFAULT';
  log_cmd $cmd;
  my $pid = open2(my $chld_out, my $chld_in, $cmd);
  fatal "Can’t execute the following command: $!\n\t${cmd}" unless defined $pid;
  print $chld_in "HELLO 1 \"App::ArduinoBuilder 1.0.0\"\n";
  # Some monitor don’t report a list if the commands are emitted too soon.
  # Ideally we would check the output of the tool but it’s slightly difficult to
  # do correctly without risking a deadlock.
  usleep(5000);
  print $chld_in "START\n";
  usleep(5000);
  print $chld_in "LIST\n";
  usleep(5000);
  print $chld_in "QUIT\n";
  close $chld_in;

  my $json;
  while (my $l = <$chld_out>) {
    $json .= $l;
  }
  close $chld_out;
  $json =~ s/\}\s*\{/},{/g;

  full_debug "Command output:\n%s", \$json;  # Using a ref to force the Data::Dumper padding.

  my $data = eval { decode_json "[${json}]" };
  fatal "Could not parse pluggable discovery output: $@" if $@;
  fatal "Invalid pluggable discovery data (ref($data) ne 'ARRAY') for ${toolname}: %s", ref($data) unless ref($data) eq 'ARRAY';
  fatal "Invalid pluggable discovery data (@$data != 4) for ${toolname}: %d", scalar(@{$data}) unless @{$data} == 4;
  fatal "Invalid pluggable discovery data (ref($data->[2]) ne 'HASH') for ${toolname}: %s", ref($data->[2]) unless ref($data->[2]) eq 'HASH';
  fatal "Invalid pluggable discovery data ($data->[2]{eventType} ne 'list') for ${toolname}: %s", $data->[2]{eventType} unless $data->[2]{eventType} eq 'list';
  debug "Pluggable discovery for ${toolname} found:\n%s", sub { $data->[2]{ports} };
  return @{$data->[2]{ports}};
}

# See: https://arduino.github.io/arduino-cli/0.32/platform-specification/#properties-from-pluggable-discovery
sub _port_to_config {
  my ($config, $port) = @_;

  my $port_config = App::ArduinoBuilder::Config->new(base => $config);
  $port_config->parse_perl($port, prefix => 'upload.port');
  if ($port_config->exists('upload.port.address')) {
    $port_config->set('serial.port' => $port_config->get('upload.port.address'));
  }
  if ($port_config->get('upload.port.protocol', default => '') eq 'serial') {
    $port_config->set('serial.port.file' => $port_config->get('upload.port.label'));
  }

  return $port_config;
}

# For _some_ documentation, see:
# https://arduino.github.io/arduino-cli/0.32/platform-specification/#pluggable-discovery
sub discover {
  my ($config) = @_;
  my $discovery_config = $config->filter('pluggable_discovery');
  if ($discovery_config->filter('required')->empty()) {
    $discovery_config->set('required.0' => 'builtin:serial-discovery');
    $discovery_config->set('required.1' => 'builtin:mdns-discovery');
  }

  # There is no real documentation of how to use the 'VENDOR_ID:DISCOVERY_NAME'
  # references. For now, we just assume that there is a tool with that discovery
  # name (we ignore the vendor ID) and we expect a binary of the same name in
  # the tool directory (this is the format used by the builtin tools).

  my @discovered_ports;
  for my $k ($discovery_config->keys()) {
    if ($k =~ m/^(.*)\.pattern$/) {
      push @discovered_ports, _run_one_discovery($1, $discovery_config->get($k));
    } elsif ($k =~ m/required(?:\.\d+)?/) {
      if ($discovery_config->get($k) =~ m/^([^:]+):(.*)$/) {
        # Note: for now we’re ignoring the vendor ID part.
        my $tool = $2;
        my $tool_key = "runtime.tools.${tool}.path";
        if (!$config->exists($tool_key)) {
          error "Pluggable discovery references unknown tool: ${tool}";
          next;
        }
        my $tool_dir = $config->get($tool_key);
        my $cmd = catfile($tool_dir, $tool);
        $cmd .= '.exe' if $^O eq 'MSWin32';
        push @discovered_ports, _run_one_discovery($tool, $cmd);
      } else {
        error "Invalid pluggable discovery reference format: %s", $discovery_config->get($k);
      }
    } else {
      error "Invalid pluggable discovery key: %s => %s", $k, $discovery_config->get($k);
    }
  }

  return map { _port_to_config($config, $_) } @discovered_ports;
}

1;
