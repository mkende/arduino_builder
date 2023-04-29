package App::ArduinoBuilder::CommandRunner;

use strict;
use warnings;
use utf8;

use App::ArduinoBuilder::Logger ':all_logger';
use Exporter 'import';
use POSIX ':sys_wait_h';
use Time::HiRes 'usleep';

our @EXPORT_OK = qw(default_runner);
our @EXPORT = @EXPORT_OK;

my %children;

$SIG{CHLD} = sub {
  local ($!, $?);
  while( (my $pid = waitpid( -1, &WNOHANG)) > 0 ) {
    if ($?) {
      debug "Child process failed, waiting for all other child processes";
      undef while wait() != -1;
      fatal 'Child command failed' if $?;
    }
    usleep(1000) until exists $children{$pid};
    $children{$pid}{current_tasks}--;
    full_debug "waitpid == $pid --> current tasks == $children{$pid}{current_tasks}";
    delete $children{pid};
  }
};

sub new {
  my ($class, %options) = @_;
  my $this =
    bless {
      max_parallel_tasks => $options{max_parallel_tasks} // 1,
      parallelize => $options{parallelize} // 1,
      current_tasks => 0,
    }, $class;
  return $this;
}

my $default_runner = App::ArduinoBuilder::CommandRunner->new();
sub default_runner {
  return $default_runner;
}

sub execute {
  my ($this, $sub, %options) = @_;
  %options = (%{$this}, %options);
  if ($options{max_parallel_tasks} > 1 && $options{parallelize}) {
    usleep(1000) until $this->{current_tasks} < $this->{max_parallel_tasks};
    my $pid = fork();
    fatal "Cannot fork a sub-process" unless defined $pid;
    if ($pid == 0) {
      $sub->();
      exit 0;
    } else {
      $this->{current_tasks}++;
      full_debug "Started child task with pid == ${pid}";
      $children{$pid} = $this;
    }
  } else {
      $sub->();
  }
}

sub wait {
  my ($this) = @_;
  my $c = $this->{current_tasks};
  return unless $c;
  debug "Waiting for ${c} running tasks...";
  usleep(1000) until $this->{current_tasks} == 0;
}

sub set_max_parallel_tasks {
  my ($this, $max_parallel_tasks) = @_;
  $this->{max_parallel_tasks} = $max_parallel_tasks;
}
