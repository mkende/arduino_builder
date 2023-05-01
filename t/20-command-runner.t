use strict;
use warnings;
use utf8;

use Test2::V0;

use App::ArduinoBuilder::CommandRunner;

use FindBin;

sub new {
  return App::ArduinoBuilder::CommandRunner->new(@_);
}

{
  pipe my $fi1, my $fo1;  # from parent to child
  pipe my $fi2, my $fo2;  # from child to parent
  new(max_parallel_tasks => 4)->execute(sub {
    close $fo1;
    close $fi2;
    my $v = <$fi1>;
    die "Invalid value: -->${v}<--" unless $v eq "signal\n";
    close $fi1;
    print $fo2 "test\n";
    close $fo2;
  });
  close $fi1;
  close $fo2;
  print $fo1 "signal\n";
  close $fo1;
  my $r = <$fi2>;
  close $fi2;
  is($r, "test\n");
}

{
  pipe my $fi, my $fo;  # from child to parent
  new()->run_forked(sub {
    close $fi;
    print $fo "test\n";
    close $fo;
  });
  close $fo;
  my $r = <$fi>;
  close $fi;
  is($r, "test\n");
}

done_testing;
