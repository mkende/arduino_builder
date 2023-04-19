package App::ArduinoBuilder::Config;

use strict;
use warnings;
use utf8;

use Exporter 'import';

our @EXPORT_OK = qw(get_os_name);

# Reference for the whole configuration interpretation:
# https://arduino.github.io/arduino-cli/0.32/platform-specification

sub new {
  my ($class, %options) = @_;
  my $me = bless {}, $class;
  $me->read_file($options{file}) if $options{file};
  for my $f (@{$options{files}}) {
    $me->read_file($f, %options);
  }
  $me->resolve(%options) if $options{resolve};
  return $me;
}

sub read_file {
  my ($this, $file_name, %options) = @_;
  open my $fh, '<', $file_name or die "Can’t open '${file_name}': $!\n";
  while (my $l = <$fh>) {
    next if $l =~ m/^\s*(?:#.*)?$/;  # Only whitespace or comment
    die "Unparsable line in ${file_name}: ${l}\n" unless $l =~ m/^\s*([-0-9a-z_.]+?)\s*=\s*(.*?)\s*$/i;
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
  my $v = $this->{config}{$key};
  die "Key '$key' does not exist in the configuration.\n" unless defined $v;
  die "Key '$key' has unresolved reference to value '$1'.\n" if $v =~ m/\{([^}]+)\}/ && !$options{allow_partial};
  return $v;
}

sub set {
  my ($this, $key, $value, %options) = @_;
  die "Key '$key' already exists.\n" if exists $this->{config}{$key} && !$options{allow_override};
  $this->{config}{$key} = $value;
  return;
}

sub _resolve_key {
  my ($key, $config, %options) = @_;
  my $value = \$config->{$key};
  while ($$value =~ m/\{([^{}}]+)\}/g) {
    my $new_key = $1;
    if (exists $config->{$new_key}) {
      my $match_start = $-[0];
      my $match_len = $+[0] - $-[0];
      my $l = 2 + length($new_key);
      my $new_value = _resolve_key($new_key, $config, %options);
      substr $$value, $match_start, $match_len, $new_value;
    } elsif (!$options{allow_partial}) {
      die "Can’t resolve key '${new_key}' in the configuration.\n";
    }
  }
  return $$value;
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
  my $config = $this->{config};
  my $os_name = $options{force_os_name} // get_os_name();
  for my $k (keys %$config) {
    $config->{$1} = $config->{$k} if $k =~ m/^(.*)\.$os_name$/;
  }
  for my $k (keys %$config) {
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
  for my $k (sort(keys %$c)) {
    my $v = $c->{$k};
    $out .= "${p}${k}=${v}\n";
  }
  return $out;
}

1;
