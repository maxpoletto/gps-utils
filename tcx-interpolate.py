#!/opt/local/bin/python3

# This script generates trackpoints for a TCX activity based on
# trackpoints in a TCX course.
#
# Given a start time, an end time, and a course with n trackpoints, it
# generates an activity with n trackpoints where the time of each
# trackpoint is linearly interpolated between the start and end
# time. The optional distance argument can be used to specify a
# distance offset for the first point.
#
# Notes:
#
# 1. Since timestamps are interpolated, this is only useful for short
#    activities where speed is relatively constant.
#
# 2. The script only generates <Track><Trackpoint></Trackpoint><Track>
#    elements, not the full activity file.
#
# Example:
#
# Say (entirely hypothetical) that your GPS bike computer resets
# itself at km 351.0 of your endurance ride and stops recording
# between 2019-06-28 09:21:43 UTC and 2019-06-28 09:28:40 UTC.
#
# You can generate an activity for the missing minutes like so:
#
# 1. Draw the course section with a tool like Strava or RideWithGPS
#    and export it to a TCX file, e.g., course.tcx.
#
# 2. tcx-interpolate.py -i course.tcx -o activity.tcx \
#      -s 2019-06-28T09:21:43Z -e 2019-06-28T09:28:40Z -d 351.0
#
# 3. Paste the trackpoints in activity.tcx into the TCX file for the
#    rest of the activity, or simply wrap them in a TCX XML header to
#    create a separate activity.

import argparse
import dateutil.parser

from io import BytesIO
from lxml import etree
from lxml import objectify

parser = argparse.ArgumentParser(description="Generate a TCX track from a TCX course.")
parser.add_argument("-i", "--input", help="input TCX course file")
parser.add_argument("-o", "--output", help="output TCX track file")
parser.add_argument("-s", "--start_time", help="ISO-8601 start time for track")
parser.add_argument("-e", "--end_time", help="ISO-8601 end time for track")
parser.add_argument("-d", "--start_dist", help="distance (in meters) of first trackpoint", type=float)
args = parser.parse_args()

# Parse time and dist args.
start_dist = 0
if args.start_dist is not None:
    start_dist = args.start_dist
try:
    start_time = dateutil.parser.parse(args.start_time)
    end_time = dateutil.parser.parse(args.end_time)
except Exception as e:
    print(e)
    exit(1)

# Parse input file.
parser = etree.XMLParser(ns_clean=True, remove_blank_text=True)
try:
    tree = etree.parse(args.input, parser)
except Exception as e:
    print(e)
    exit(1)
root = tree.getroot()

# Strip namespaces (to keep matching simple below).
for e in root.getiterator():
    if not isinstance(e.tag, str): continue
    i = e.tag.find('}')
    if i > -1:
        e.tag = e.tag[i+1:]
objectify.deannotate(root, cleanup_namespaces=True)

# Process trackpoints, adjusting distance and time.
trackpoints = root.xpath("//Trackpoint")
track = trackpoints[0].getparent()
dist_delta = None
time_delta = 0
if len(trackpoints) > 1:
    time_delta = (end_time - start_time) / (len(trackpoints)-1)

for i, p in enumerate(trackpoints):
    ed = p.find("DistanceMeters")
    if dist_delta is None:
        dist_delta = start_dist - float(ed.text)
    ed.text = str(float(ed.text) + dist_delta)
    et = p.find("Time")
    et.text = str(start_time + i*time_delta)
    
# Pretty-print the output.
try:
    etree.ElementTree(track).write(args.output, pretty_print=True)
except Exception as e:
    print(e)
    exit(1)

