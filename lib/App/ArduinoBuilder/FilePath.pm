package App::ArduinoBuilder::FilePath;

use strict;
use warnings;
use utf8;

use App::ArduinoBuilder::Logger;
use Exporter 'import';
use File::Find;
use File::Spec::Functions 'catdir', 'rel2abs';
use List::Util 'min', 'any';

our @EXPORT_OK = qw(find_latest_revision_dir list_sub_directories find_all_files_with_extensions);

sub _compare_version_string {
  my @la = split /\.|-/, $a;
  my @lb = split /\.|-/, $b;
  for my $i (0..min($#la, $#lb)) {
    # Let’s try to handle things like: 1.5.0-b
    my $c = $la[$i] <=> $lb[$i] || $la[$i] cmp $lb[$i];
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
  opendir my $dh, $dir or fatal "Can’t open dir '$dir': $!";
  my @revs_dir = grep { -d catdir($dir, $_) && m/^\d+(?:\.\d+)?(?:-.*)?/ } readdir($dh);
  closedir $dh;
  return $dir unless @revs_dir;
  return catdir($dir, _pick_highest_version_string(@revs_dir));
}

sub list_sub_directories {
  my ($dir) = @_;
  opendir my $dh, $dir or fatal "Can’t open dir '$dir': $!";
  my @sub_dirs = grep { -d catdir($dir, $_) && ! m/^\./ } readdir($dh);
  closedir $dh;
  return @sub_dirs;
}

sub find_all_files_with_extensions {
  my ($dir, $exts, $excluded_dirs) = @_;
  my $exts_re = join('|', @{$exts});
  my @excluded_dirs = map { rel2abs($_) } @{$excluded_dirs // []};
  my @found;
  find(sub { push @found, $File::Find::name if -f && m/\.(?:$exts_re)$/;
             if (-d) {
               my $a = rel2abs($_);
               $File::Find::prune = any { $_ eq $a || /^\./ } @excluded_dirs;
             }
           }, $dir);
  return @found;
}

1;
