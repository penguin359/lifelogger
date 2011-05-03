#!/usr/bin/perl
#
# Copyright (c) 2009, Loren M. Lang
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 
#     * Redistributions of source code must retain the above copyright
#	notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above
#	copyright notice, this list of conditions and the following
#	disclaimer in the documentation and/or other materials provided
#	with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#


use 5.008_001;
use strict;
use warnings;

use utf8;
use open ':utf8', ':std';
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/lib";

require 'common.pl';

my $usage = "[-name name] [-source source] [-out gps.csv] gps.gpx";
my $name = "GPX Data";
my $source = 0;
my $out = "gps-log.csv";

my $self = init($usage, {"name=s" => \$name,
			 "source=i" => \$source,
			 "out=s" => \$out});
die $self->{usage} if @ARGV > 1;
lockKml($self);

my $gpxFile = "gps-log.gpx";
$gpxFile = shift if @ARGV;

my $parser = new XML::LibXML;
my $gpxDoc = $parser->parse_file($gpxFile);
my $xc = loadXPath($self);

my $entries = [];
my $id = 1;
my $seg = 1;
my $track = 1;
my @tracks = $xc->findnodes('/gpx:gpx/gpx:trk', $gpxDoc);
foreach(@tracks) {
	my @segs = $xc->findnodes('gpx:trkseg', $_);
	foreach(@segs) {
		my @points = $xc->findnodes('gpx:trkpt', $_);
		foreach(@points) {
			my $entry = {};
			$entry->{id}        = $id;
			$entry->{seg}       = $seg;
			$entry->{track}     = $track;
			$entry->{source}    = $source;
			$entry->{label}     = $name;
			$entry->{latitude}  = getNodeText($xc, $_, '@lat');
			$entry->{longitude} = getNodeText($xc, $_, '@lon');
			$entry->{altitude}  = getNodeText($xc, $_, 'gpx:ele/text()');
			$entry->{speed}     = getNodeText($xc, $_, 'gpx:extensions/gpx:speed/text()');
			$entry->{heading}   = getNodeText($xc, $_, 'gpx:extensions/gpx:heading/text()');
			my $time            = getNodeText($xc, $_, 'gpx:time/text()');
			$entry->{timestamp} = parseIsoTime($self, $time);

			if($entry->{latitude} eq "" ||
			   $entry->{longitude} eq "" ||
			   $entry->{timestamp} == 0) {
				warn "Missing required attributes, skipping";
				next;
			}

			push @$entries, $entry;
			$id++;
		}
		$seg++;
	}
	$track++;
}

my $fieldsGPX = [
    "source",
    "label",
    "id",
    "seg",
    "track",
    "timestamp",
    "latitude",
    "longitude",
    "altitude",
    "speed",
    "heading"];

writeDataPC($self, $entries, $out, $fieldsGPX);
