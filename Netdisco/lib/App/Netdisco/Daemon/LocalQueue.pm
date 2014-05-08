package App::Netdisco::Daemon::LocalQueue;

use Dancer qw/:moose :syntax :script/;
use Dancer::Plugin::DBIC 'schema';

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/ add_jobs capacity_for take_jobs reset_jobs scrub_jobs /;
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

schema('daemon')->deploy;
my $queue = schema('daemon')->resultset('Admin');

sub add_jobs {
  my (@jobs) = @_;
  info sprintf "adding %s jobs to local queue", scalar @jobs;
  schema('daemon')->dclone($_)->insert for @jobs;
}

sub capacity_for {
  my ($type) = @_;
  debug "checking local capacity for worker type $type";

  my $setting = setting('workers')->{ setting('job_type_keys')->{$type} };
  my $current = $queue->search({type => $type})->count;
  return ($current < $setting);
}

sub take_jobs {
  my ($wid, $type, $max) = @_;
  $max ||= 1;

  # asking for more jobs means the current ones are done
  scrub_jobs($wid);

  debug "searching for $max new jobs for worker $wid (type $type)";
  my $rs = $queue->search(
    {type => $type, wid => 0},
    {rows => $max},
  );

  my @rows = $rs->all;
  return [] if scalar @rows == 0;

  debug sprintf "booking out %s jobs to worker %s", (scalar @rows), $wid;
  $queue->search({job => { -in => [map {$_->job} @rows] }})
        ->update({wid => $wid});

  return \@rows;
}

sub reset_jobs {
  my ($wid) = @_;
  debug "resetting jobs owned by worker $wid to be available";
  return unless $wid > 1;
  $queue->search({wid => $wid})
        ->update({wid => 0});
}

sub scrub_jobs {
  my ($wid) = @_;
  debug "deleting dangling jobs owned by worker $wid";
  return unless $wid > 1;
  $queue->search({wid => $wid})->delete;
}

1;