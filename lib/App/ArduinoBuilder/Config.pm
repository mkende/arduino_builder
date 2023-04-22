package App::ArduinoBuilder::Config;

use strict;
use warnings;
use utf8;

use App::ArduinoBuilder::Logger;
use Exporter 'import';

our @EXPORT_OK = qw(get_os_name);

# Reference for the whole configuration interpretation:
# https://arduino.github.io/arduino-cli/0.32/platform-specification

sub new {
  my ($class, %options) = @_;
  my $me = bless {config => {}}, $class;
  $me->read_file($options{file}) if $options{file};
  for my $f (@{$options{files}}) {
    $me->read_file($f, %options);
  }
  $me->resolve(%options) if $options{resolve};
  return $me;
}

sub read_file {
  my ($this, $file_name, %options) = @_;
  open my $fh, '<', $file_name or fatal "Can’t open '${file_name}': $!";
  while (my $l = <$fh>) {
    next if $l =~ m/^\s*(?:#.*)?$/;  # Only whitespace or comment
    fatal "Unparsable line in ${file_name}: ${l}" unless $l =~ m/^\s*([-0-9a-z_.]+?)\s*=\s*(.*?)\s*$/i;
    $this->{config}{$1} = $2 if !(exists $this->{config}{$1}) || $options{allow_override};
  }
  return 1;
}

sub size {
  my ($this) = @_;
  return scalar keys %{$this->{config}};
}

sub empty {
  my ($this) = @_;
  return $this->size() == 0;
}

sub get {
  my ($this, $key, %options) = @_;
  $options{allow_partial} = 1 if $options{no_resolve};
  my $v = _resolve_key($key, $this->{config}, %options, allow_partial => 1);
  return $options{default} if !defined $v && exists $options{default};
  fatal "Key '$key' does not exist in the configuration." unless defined $v;
  fatal "Key '$key' has unresolved reference to value '$1'." if $v =~ m/\{([^}]+)\}/ && !$options{allow_partial};
  return $v;
}

sub keys {
  my ($this, %options) = @_;
  return keys %{$this->{config}};
}

sub exists {
  my ($this, $key) = @_;
  return exists $this->{config}{$key};
}

sub set {
  my ($this, $key, $value, %options) = @_;
  if (exists $this->{config}{$key}) {
    return if $options{ignore_existing};
    fatal "Key '$key' already exists." unless $options{allow_override};
  }
  $this->{config}{$key} = $value;
  return;
}

sub append {
  my ($this, $key, $value) = @_;
  $this->{config}{$key} .= ($this->{config}{$key} ? ' ' : '').$value;
  return;
}

sub _resolve_key {
  my ($key, $config, %options) = @_;
  return $options{with}{$key} if exists $options{with}{$key};
  return $options{base}->get($key, %options{grep { $_ ne 'base'} CORE::keys %options}) if exists $options{base} && $options{base}->exists($key);
  if (not exists $config->{$key}) {
    fatal "Can’t resolve key '${key}' in the configuration." unless $options{allow_partial};
    return;
  }
  my $value = $config->{$key};
  return $value if $options{no_resolve};
  while ($value =~ m/\{([^{}}]+)\}/g) {
    my $new_key = $1;
    my $match_start = $-[0];
    my $match_len = $+[0] - $-[0];
    my $l = 2 + length($new_key);
    my $new_value = _resolve_key($new_key, $config, %options);
    substr $value, $match_start, $match_len, $new_value if defined $new_value;
  }
  # We don’t materialize the resolved value if we’re using temporary values.
  $config->{$key} = $value unless $options{with};
  return $value;
}

# The Arduino OS name, based on the Perl OS name.
sub get_os_name {
  # It is debattable how we want to treat cygwin and msys. For now we assume
  # that they will be used with a windows native Arduino toolchain.
  return 'windows' if $^O eq 'MSWin32' || $^O eq 'cygwin' || $^O eq 'msys';
  return 'macosx' if $^O eq 'MacOS';
  return 'linux';
}

sub resolve {
  my ($this, %options) = @_;
  $options{allow_partial} = 1 if $options{no_resolve};
  my $config = $this->{config};
  my $os_name = $options{force_os_name} // get_os_name();
  for my $k (CORE::keys %$config) {
    $config->{$1} = $config->{$k} if $k =~ m/^(.*)\.$os_name$/;
  }
  for my $k (CORE::keys %$config) {
    _resolve_key($k, $config, %options);
  }
  return 1;
}

# Definition from this are kept and not replaced by those from others.
sub merge {
  my ($this, $other) = @_;
  while (my ($k, $v) = each %{$other->{config}}) {
    $this->{config}{$k} = $v unless exists $this->{config}{$k};
  }
}

sub filter {
  my ($this, $prefix) = @_;
  my $filtered = App::ArduinoBuilder::Config->new();
  while (my ($k, $v) = each %{$this->{config}}) {
    if ($k =~ m/^\Q$prefix\E\./) {
      $filtered->{config}{substr($k, $+[0])} = $v;
    }
  }
  return $filtered;
}

sub dump {
  my ($this, $prefix) = @_;
  my $c = $this->{config};
  my $out = '';
  my $p = $prefix // '';
  for my $k (sort(CORE::keys %$c)) {
    my $v = $c->{$k};
    $out .= "${p}${k}=${v}\n";
  }
  return $out;
}

1;
