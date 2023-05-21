package App::ArduinoBuilder::JsonTool;

# Package that implement bi-directionnal communication with a tool talking
# JSON (like the Arduino pluggable discovery and monitor tools).

use strict;
use warnings;
use utf8;

use App::ArduinoBuilder::CommandRunner;
use App::ArduinoBuilder::Logger ':all_logger';
use IO::Pipe;
use JSON::PP;

sub new {
  my ($class, $cmd) = @_;

  my $mosi = IO::Pipe->new();  # from parent to child
  my $miso = IO::Pipe->new();  # from child to parent

  # Custom re-implementation of open2 (but using our CommandRunner so that we
  # don’t have to mess again with $SIG{CHLD}).
  my $task = default_runner()->execute(sub {
    log_cmd $cmd;
    $mosi->reader();
    $miso->writer;
    close STDIN;
    close STDOUT;
    open STDIN, '<&', $mosi or fatal "Can’t reopen STDIN";
    open STDOUT, '>&', $miso or fatal "Can’t reopen STDOUT";
    $mosi->close();
    $miso->close();
    # Maybe we could call system instead of exec, so that we can do some cleanup
    # task at the end (and be notified here if the tool terminate abruptly while
    # we are still trying to communicate with it).
    exec $cmd;
  });

  $mosi->writer();
  $miso->reader();
  # Make our out-channel be unbuffered (binmode($fh, ':unix') with a real filehandle)
  $mosi->autoflush(1);

  my $this = bless {
    task => $task,
    out => $mosi,
    in => $miso,
  }, $class;

  return $this;
}

sub DESTROY {
  local($., $@, $!, $^E, $?);
  my ($this) = @_;
  $this->{out}->close();
  $this->{in}->close();
  full_debug "Waiting for tool to stop";
  $this->{task}->wait();
  return;
}

sub send {
  my ($this, $msg) = @_;

  full_debug "Sending message to tool: ${msg}";
  $this->{out}->print($msg);

  my $json;
  my $braces = 0;
  while (1) {
    my $count = $this->{in}->read(my $char, 1);
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
        my $data = eval { decode_json ${json} };
        full_debug "Received following JSON:\n%s", $json;
        fatal "Could not parse JSON from tool output: $@" if $@;
        return $data;
      }
    }
  }
}

1;
