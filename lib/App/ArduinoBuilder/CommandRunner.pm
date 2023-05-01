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
  full_debug "Received SIGCHLD";
  while( (my $pid = waitpid( -1, &WNOHANG)) > 0 ) {
    if ($?) {
      debug "Child process (pid == ${pid}) failed, waiting for all other child processes";
      undef while wait() != -1;
      fatal 'Child command failed';
    }
    my $task = delete $children{$pid};
    unless (defined $task) {
      full_debug "Got SIGCHLD for unknown children with pid == ${pid}";
      return;
    }
    $task->{runner}{current_tasks}-- unless $task->{untracked};
    $task->{running} = 0;
    full_debug "Child pid == ${pid} returned (task id == $task->{task_id}) --> current tasks == $task->{runner}{current_tasks}";
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

my $task_count = 0;

sub _fork_and_run {
  my ($this, $sub, %options) = @_;
  %options = (%{$this}, %options);
  pipe my $fi, my $fo;
  my $task_id = $task_count++;
  my $pid = CORE::fork();
  fatal "Cannot fork a sub-process" unless defined $pid;
  if ($pid == 0) {
    close $fo;
    scalar(<$fi>);
    close $fi;
    full_debug "Starting child task (id == ${task_id}) in process ${$}";
    $sub->();
    full_debug "Exiting child task (id == ${task_id}) in process ${$}";
    exit 0;
  } else {
    full_debug "Started child task (id == ${task_id}) with pid == ${pid}";
    close $fi;
    my $task = {
      untracked => $options{untracked},
      task_id => $task_id,
      runner => $this,
      running => 1,
    };
    $children{$pid} = $task;
    print $fo "ignored\n";
    close $fo;
    if ($options{wait}) {
      full_debug "Waiting for child $pid to exit (task id == ${task_id})";
      usleep(1000) while $task->{running};
      full_debug "Ok, child $pid exited (task id == ${task_id})";
    }
  }
}

# Same as execute but does not limit the parallelism and block until the command
# has executed.
sub run_forked {
  my ($this, $sub, %options) = @_;
  $this->_fork_and_run($sub, %options, untracked => 1, wait => 1);
}

sub execute {
  my ($this, $sub, %options) = @_;
  %options = (%{$this}, %options);
  if ($options{max_parallel_tasks} > 1 && $options{parallelize}) {
    usleep(1000) until $this->{current_tasks} < $this->{max_parallel_tasks};
    $this->_fork_and_run($sub, %options);
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

1;
