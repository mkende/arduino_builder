package App::ArduinoBuilder::Config;

use strict;
use warnings;
use utf8;

# Reference for the whole configuration interpretation:
# https://arduino.github.io/arduino-cli/0.32/platform-specification

sub new {
  my ($class, %options) = @_;
  my $me = bless {}, $class;
  for my $f (@{$options{files}}) {
    $me->read_file($f);
  }
  $me->resolve() if $options{resolve};
  return $me;
}

sub read_file {
  my ($this, $file_name) = @_;
  open my $fh, '<', $file_name or die "Can’t open '${file_name}': $!\n";
  while (my $l = <$fh>) {
    next if $l =~ m/^\s*(?:#.*)?$/;  # Only whitespace or comment
    if ($l =~ m/^\s*([a-z.]+?)\s*=\s*(.*?)\s*$/) {
      $this->{config}{$1} = $2;
    }
  }
  return 1;
}

sub _resolve_key {
  my ($key, $config) = @_;
  my $value = \$config->{$key};
  while ($$value =~ m/\{([^}]+)\}/) {
    my $match_start = $-[0];
    my $match_len = $+[0] - $-[0];
    my $new_key = $1;
    my $l = 2 + length($new_key);
    my $new_value = _resolve_key($new_key, $config);
    substr $$value, $match_start, $match_len, $new_value;
  }
  return $$value;
}

sub resolve {
  my ($this) = @_;
  my $config = $this->{config};
  for my $k (keys %$config) {
    _resolve_key($k, $config);
    # It is debattable how we want to treat cygwin and msys. For now we assume
    # that they will be used with a windows native Arduino toolchain.
    if (($^O eq 'MSWin32' || $^O eq 'cygwin' || $^O eq 'msys') && $k =~ m/^(.*)\.windows$/) {
      $config->{$1} = $config->{$k};
    } elsif ($^O eq 'MacOS' && $k =~ m/^(.*)\.macosx$/) {
      $config->{$1} = $config->{$k};
    } elsif ($k =~ m/^(.*)\.linux$/) {
      $config->{$1} = $config->{$k};
    }
  }
  return 1;
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
  my ($this) = @_;
  my $c = $this->{config};
  my $out = '';
  for my $k (sort(keys %$c)) {
    my $v = $c->{$k};
    $out .= "${k}=${v}\n";
  }
  return $out;
}

1;
