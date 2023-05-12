package App::ArduinoBuilder::JsonTool;

# Package that implement bi-directionnal communication with a tool talking
# JSON (like the Arduino pluggable discovery and monitor tools).

use strict;
use warnings;
use utf8;

use App::ArduinoBuilder::CommandRunner;
use App::ArduinoBuilder::Logger ':all_logger';
use JSON::PP;

sub new {
  my ($class, $cmd) = @_;

  pipe my $fi1, my $fo1;  # from parent to child
  pipe my $fi2, my $fo2;  # from child to parent

  # Custom re-implementation of open2 (but using our CommandRunner so that we
  # don’t have to mess again with $SIG{CHLD}).
  my $task = default_runner()->execute(sub {
    log_cmd $cmd;
    close $fo1;
    close $fi2;
    #open my $old_in, '<&', \*STDIN or fatal "Can’t dup STDIN";
    #open my $old_out, '>&', \*STDOUT or fatal "Can’t dup STDOUT";
    close STDIN;
    close STDOUT;
    open STDIN, '<&', $fi1 or fatal "Can’t reopen STDIN";
    open STDOUT, '>&', $fo2 or fatal "Can’t reopen STDOUT";
    close $fi1;
    close $fo2;
    #close $old_in;
    #close $old_out;
    # Maybe we could call system instead of exec, so that we can do some cleanup
    # task at the end.
    exec $cmd;
  });

  close $fi1;
  close $fo2;

  # Make our out-channel be unbuffered.
  binmode($fo1, ':unix');

  my $this = bless {
    task => $task,
    out => $fo1,
    in => $fi2,
  }, $class;

  return $this;
}

sub DESTROY {
  local($., $@, $!, $^E, $?);
  my ($this) = @_;
  close $this->{out};
  close $this->{in};
  full_debug "Waiting for tool to stop";
  $this->{task}->wait();
  return;
}

sub send {
  my ($this, $msg) = @_;

  full_debug "Sending message to tool: ${msg}";
  print { $this->{out} } $msg;

  my $json;
  my $braces = 0;
  while (1) {
    my $count = read $this->{in}, my $char, 1;
    # full_debug "Read from tool: ${content}";
    fatal "An error occured while reading tool output: $!" unless defined $count;
    fatal "Unexpected end of file stream while reading tool output" if $count == 0;
    $json .= $char;
    if ($char eq '{') {
      $braces++;
    } elsif ($char eq '}') {
      $braces--;
      if ($braces == 0) {
        # Here, we could use sysread to check that there is no more any
        # meaningful content in the pipe. But let’s assume that we are talking
        # to correct tools for now.
        my $data = eval { decode_json "${json}" };
        fatal "Could not parse JSON from tool output: $@" if $@;
        return $data;
      }
    }
  }
}

1;
