package App::ArduinoBuilder::FilePath;

use strict;
use warnings;
use utf8;

use Exporter 'import';
use File::Spec::Functions;
use List::Util 'min';

our @EXPORT_OK = qw(find_latest_revision_dir);

sub _compare_version_string {
  my @la = split /\./, $a;
  my @lb = split /\./, $b;
  for my $i (0..min($#la, $#lb)) {
    my $c = $la[$i] <=> $lb[$i];
    return $c if $c;
  }
  return $#la <=> $#lb;
}

sub  _pick_highest_version_string {
  return (sort _compare_version_string @_)[-1];
}

# find_latest_revision('/path/to/dir') --> '/path/to/dir/9.8.2'
# Returns the input if there are no sub-directories looking like revisions in
# the given directory.
sub find_latest_revision_dir {
  my ($dir) = @_;
  opendir my $dh, $dir or die "Can’t open dir '$dir': $!\n";
  my @revs_dir = grep { -d catdir($dir, $_) && m/^\d+(?:\.\d+)?/ } readdir($dh);
  closedir $dh;
  return $dir unless @revs_dir;
  return catdir($dir, _pick_highest_version_string(@revs_dir));
}
