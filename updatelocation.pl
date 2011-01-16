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
use warnings;
use strict;

use utf8;
use open ':utf8', ':std';
use FindBin;
use lib "$FindBin::Bin", "$FindBin::Bin/lib";
use Getopt::Long;
use HTTP::Request;
use LWP::UserAgent 5.810;

require 'common.pl';

my $id;
my $slow = 0;
my $noMark = 0;
my $www = 0;
my $verbose = 0;
my $result = GetOptions(
	"id=i" => \$id,
	"slow" => \$slow,
	"no-mark" => \$noMark,
	"www" => \$www,
	"verbose" => \$verbose);
die "Usage: $0 [-id id] [-no-mark | -slow] [-verbose] [file.csv]" if !$result || @ARGV > 1;

my $self = init();
$self->{verbose} = $verbose;
lockKml($self);

my $source;
my $newEntries = [];
if(defined($ARGV[0])) {
	my $type = "GPX";
	$type = "WWW" if $www;
	$source = findSource($self, $type, $id);
	print "Loading CSV file.\n" if $self->{verbose};
	open(my $fd, $ARGV[0]) or die "Can't load file '$ARGV[0]'";
	my @lines = <$fd>;
	($newEntries) = parseData($self, \@lines);
} else {
	$source = findSource($self, "InstaMapper", $id);
	my $apiKey = $source->{apiKey};
	my $last = lastTimestamp($self, $source->{id});
	my $lastTimestamp = $last->{timestamp};
	$lastTimestamp++;

	print "Downloading InstaMapper data.\n" if $self->{verbose};
	my $request = HTTP::Request->new(GET => "http://www.instamapper.com/api?action=getPositions&key=$apiKey&num=100&from_ts=$lastTimestamp");
	my $ua = LWP::UserAgent->new;
	my $response = $ua->request($request);
	die $response->status_line, "\n"
	    if !$response->is_success;
	my @lines = split /\n/, $response->decoded_content;
	($newEntries) = parseData($self, \@lines);
}

my $seg = 1;
my $lastTimestamp = lastTimestamp($self);
my $diff = 300;
foreach(@$newEntries) {
	next if !defined($_->{timestamp});
	next if defined($_->{track});
	$seg++ if abs($_->{timestamp} - $lastTimestamp) > $diff;
	$_->{track} = 1;
	$_->{seg} = $seg;
	$lastTimestamp = $_->{timestamp};
}

my $doc = loadKml($self);
my $xc = loadXPath($self);
my $locationPath = "/kml:kml/kml:Document/kml:Folder[kml:name='Locations']";
my $locationId = $source->{kml}->{location};
$locationPath = "//kml:Folder[\@id='$locationId']" if defined($locationId);
my @locationBase = $xc->findnodes($locationPath, $doc);

#die "Can't find base for location" if @locationBase != 1;

if(@locationBase > 1) {
	die "Duplicate base for location";
} elsif(@locationBase == 1) {
	print "Adding placemarks.\n" if $self->{verbose} && @$newEntries && !$noMark;
	my $kmlEntries = [];
	push @$kmlEntries, pop @$newEntries if @$newEntries && !$noMark;
	push @$newEntries, @$kmlEntries;
	foreach my $entry (@$kmlEntries) {
		next if !defined($entry->{latitude}) or $entry->{latitude} == 0;
		my $mark = createPlacemark($doc);
		addTimestamp($doc, $mark, $entry->{timestamp});
		addStyle($doc, $mark, 'icon');
		addExtendedData($doc, $mark, {
		    speed => $entry->{speed} . " m/s",
		    heading => $entry->{heading}});
		addPoint($doc, $mark, $entry->{longitude}, $entry->{latitude}, $entry->{altitude});
		addPlacemark($doc, $locationBase[0], $mark);
	}
}

print "Updating path.\n" if $self->{verbose};
my $coordStr = "";
foreach my $entry (@$newEntries) {
	next if !defined($entry->{latitude}) or $entry->{latitude} == 0;
	$coordStr .= "\n$entry->{longitude},$entry->{latitude},$entry->{altitude}";
}
my $linePath = "/kml:kml/kml:Document/kml:Placemark/kml:LineString/kml:coordinates/text()";
my $lineId = $source->{kml}->{line};
$linePath = "//kml:Placemark[\@id='$lineId']/kml:LineString/kml:coordinates/text()" if defined($lineId);
my @lineNode = $xc->findnodes($linePath, $doc);
$lineNode[0]->appendData($coordStr);

print "Updating my location.\n" if $self->{verbose};
my $currentPosition = pop @$newEntries;
if(defined($currentPosition)) {
	my $positionPath = "/kml:kml/kml:Document/kml:Placemark[kml:styleUrl='#position']/kml:Point/kml:coordinates/text()";
	my $positionId = $source->{kml}->{position};
	$positionPath = "//kml:Placemark[\@id='$positionId']/kml:Point/kml:coordinates/text()" if defined($positionId);
	my @positionNode = $xc->findnodes($positionPath, $doc);
	warn "No position node found.\n" if @positionNode < 1;
	$positionNode[0]->setData("$currentPosition->{longitude},$currentPosition->{latitude},$currentPosition->{altitude}");
}

print "Saving location data.\n" if $self->{verbose};
appendData($self, $newEntries);

saveKml($self, $doc);
