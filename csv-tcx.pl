#!/usr/bin/perl

# This script generates training activity files in TCX XML format from
# CSV data.
#
# The CSV input data must be in the format produced or expected by the
# online tool at http://garmin.kiesewetter.nl/.
#
# The script attempts to incorporate all trackpoint data from the
# input CSV file, but eliminates data points that seem ill-formed
# (altitude or distance represented as integers rather than decimals)
# or whose latitude/longitude is too far (currently 1 degree or more)
# from the previous point.
#
# If you have a garbled FIT file (e.g., because your Garmin or Wahoo
# GPS unit failed on you in the middle of a ride or run), then you can
# try to:
#
# 1. Convert the FIT file to CSV using http://garmin.kiesewetter.nl or the 
#    FIT SDK available at https://www.thisisant.com/resources/fit.
#
# 2. Run this script. On a Unix-like system:
#    perl csv-tcx.pl [-tz_offset N] my-ride.csv > my-ride.tcx
#
#    The -tz_offset flag lets you specify the offset of your local
#    timezone from UTC, in seconds. For example, if the activity was
#    recorded in CEST (UTC+2h), you want -tz_offset 7200.
#    
# 3. Upload my-ride.tcx to an online service like Strava or RideWithGPS.

use strict;
use warnings;
use DateTime;
use Getopt::Long qw(GetOptions);
 
my $tz_offset = 0;
GetOptions('tz_offset=i' => \$tz_offset);
my $sc_convert = (2**31)/180; # from semicircles to degrees

sub print_header() {
    print <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.garmin.com/xmlschemas/ProfileExtension/v1 http://www.garmin.com/xmlschemas/UserProfilePowerExtensionv1.xsd http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd http://www.garmin.com/xmlschemas/UserProfile/v2 http://www.garmin.com/xmlschemas/UserProfileExtensionv2.xsd">
  <Activities>
EOF
}

sub print_footer() {
    print <<EOF 
  </Activities>
</TrainingCenterDatabase>
EOF
}

sub read_track() {
    my @points = ();
    while (<>) {
	# The handling of decimals for the altitude and distance
	# fields in this regexp filters out garbage data when a device
	# is stopped, at least in the case of the Wahoo Elemnt.
	if (/data,0,(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+),(\d+),(\d+),\d+,(\d+\.\d+),[\d\.]+,(\d+\.\d+),(\d+),([\d\.]+)?,?(\d+)?/) {
	    my $dt = DateTime->new(year => $1, month => $2, day => $3, hour => $4,
				   minute => $5, second => $6, time_zone  => 'UTC');
	    $dt = $dt - DateTime::Duration->new(seconds => $tz_offset);
	    my ($latsc, $lonsc) = ($7, $8);
	    my $alt = $9;
	    my $dist = $10;
	    my $hr = $11;
	    my $temp = $12;
	    my $lat = $latsc/$sc_convert;
	    my $lon = $lonsc/$sc_convert;
	    if ($#points < 0 ||
		(abs($lat - $points[$#points]->[1]) < 1.0 &&
		 abs($lon - $points[$#points]->[2]) < 1.0)) {
		# Filter out spurious data, e.g., from inside long tunnels.
		push @points, [ $dt, $lat, $lon, $alt, $dist, $hr, $temp ];
	    }
	}
    }
    return \@points;
}

sub print_activity($) {
    my ($points) = @_;
    if ($#$points < 1) {
	return;
    }
    my $p0 = $points->[0];
    my $p1 = $points->[$#$points];
    my $tot_time = $p1->[0]->epoch - $p0->[0]->epoch;
    my $tot_dist = $p1->[4];

    print <<EOF
    <Activity Sport="Biking">
      <Id>$p0->[0]Z</Id>
      <Lap StartTime="$p0->[0]Z">
        <TotalTimeSeconds>$tot_time</TotalTimeSeconds>
        <DistanceMeters>$tot_dist</DistanceMeters>
        <Calories>0</Calories>
        <Intensity>Active</Intensity>
        <TriggerMethod>Manual</TriggerMethod>
        <Track>
EOF
;
    foreach my $p (@$points) {
	print <<"EOF"
          <Trackpoint>
            <Time>$p->[0]Z</Time>
            <Position>
              <LatitudeDegrees>$p->[1]</LatitudeDegrees>
              <LongitudeDegrees>$p->[2]</LongitudeDegrees>
            </Position>
            <AltitudeMeters>$p->[3]</AltitudeMeters>
            <DistanceMeters>$p->[4]</DistanceMeters>
EOF
;
	if ($p->[5]) {
	    print <<"EOF"
            <HeartRateBpm>
              <Value>$p->[5]</Value>
            </HeartRateBpm>
EOF
;
	}
	print <<EOF
          </Trackpoint>
EOF
;
    }
    print <<EOF
        </Track>
      </Lap>
    </Activity>
EOF
;
}


print_header();
print_activity(read_track());
print_footer();
