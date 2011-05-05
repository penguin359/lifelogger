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
use Common;
use Net::OAuth::Local;
use HTTP::Request;
use LWP::UserAgent 5.810;
use HTTP::Request::Common;
use JSON;

my $usage = "[-id id] [-no-mark | -slow] [-latitude] [-www] [file.csv]";
my $id;
my $noMark = 0;
my $slow = 0;
my $latitude = 0;
my $www = 0;

my $self = init($usage, {"id=i" => \$id,
			 "no-mark" => \$noMark,
			 "slow" => \$slow,
			 "latitude" => \$latitude,
			 "www" => \$www});
die $self->{usage} if @ARGV > 1;
lockKml($self);

sub updateLatitudeLocation {
	my($source, $entry) = @_;

	print "Updating Google Latitude.\n" if $self->{verbose};

	my $url = 'https://www.googleapis.com/latitude/v1/currentLocation';

	my $ua = LWP::UserAgent->new;

	my $oauthData = {
		protocol => "oauth 1.0a",
		app => 'Google',
		type => "Access",
		params => {
			token => $source->{token},
			token_secret => $source->{tokenSecret},
			request_url => $url,
			request_method => 'POST',
		},
	};

	my $oauth = requestSign($oauthData);

	my $location = {
		data => {
			kind => 'latitude#location',
			timestampMs => $entry->{timestamp}*1000,
			latitude => $entry->{latitude},
			longitude => $entry->{longitude},
		}
	};
	$location->{data}->{altitude} = $entry->{altitude} if defined($entry->{altitude}) && $entry->{altitude} ne "";

	my $json = new JSON;
	$json->utf8(1);

	my $req = POST $url, Authorization => $oauth->{authorization}, Content_Type => 'application/json', Content => $json->encode($location);
	#print Dumper($req);
	my $response = $ua->request($req);
	die "Bad request ".$response->status_line if !$response->is_success;

	# Parse the result of the HTTP request
	#print Dumper($json->decode($response->content));
	print "Successfully updated Google Latitude.\n" if $self->{verbose};
}

my $source;
my $newEntries = [];
if($latitude) {
	$source = findSource($self, "Latitude", $id);
	print "Loading Google Latitude.\n" if $self->{verbose};

	my $url = 'https://www.googleapis.com/latitude/v1/location';

	my $ua = LWP::UserAgent->new;

	my $oauthData = {
		protocol => "oauth 1.0a",
		app => 'Google',
		type => "Access",
		params => {
			token => $source->{token},
			token_secret => $source->{tokenSecret},
			request_url => $url,
			request_method => 'GET',
		},
	};

	my $oauth = requestSign($oauthData);

	my $req = GET $url, Authorization => $oauth->{authorization};
	#print Dumper($req);
	my $response = $ua->request($req);
	die "Bad request ".$response->status_line if !$response->is_success;

	my $last = lastTimestamp($self, $source->{id});
	# Parse the result of the HTTP request
	#print $response->content, "\n";
	my $json = new JSON;
	$json->utf8(1);
	my $obj = $json->decode($response->content);
	#print Dumper($obj);
	die "Not a location feed" if $obj->{data}->{kind} ne 'latitude#locationFeed';
	foreach(reverse @{$obj->{data}->{items}}) {
		next if $_->{kind} ne 'latitude#location';
		$_->{timestamp} = int($_->{timestampMs} / 1000);
		#print Dumper([$_, $last]);
		next if $_->{timestamp} <= $last->{timestamp};
		#next if $_->{latitude} > 60 || $_->{latitude} < 10;
		#next if $_->{longitude} > -30 || $_->{longitude} < -150;
		next if $_->{latitude} > 70 || $_->{latitude} < 10;
		next if $_->{longitude} > 30 || $_->{longitude} < -150;
		$_->{source} = $source->{id};
		$_->{label} = $source->{name};
		$_->{altitude} = 0;
		push @$newEntries, $_;
	}
	print Dumper($newEntries);
} elsif(defined($ARGV[0])) {
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

if(!@$newEntries) {
	print "No new data, nothing to do.\n" if $self->{verbose};
	exit 0;
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
	$$kmlEntries[0] = $$newEntries[-1] if @$newEntries && !$noMark;
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
my $currentPosition = $$newEntries[-1];
if(defined($currentPosition)) {
	my $positionPath = "/kml:kml/kml:Document/kml:Placemark[kml:styleUrl='#position']/kml:Point/kml:coordinates/text()";
	my $positionId = $source->{kml}->{position};
	$positionPath = "//kml:Placemark[\@id='$positionId']/kml:Point/kml:coordinates/text()" if defined($positionId);
	my @positionNode = $xc->findnodes($positionPath, $doc);
	warn "No position node found.\n" if @positionNode < 1;
	$positionNode[0]->setData("$currentPosition->{longitude},$currentPosition->{latitude},$currentPosition->{altitude}");

	if(defined($source->{updateLatitudeSource}) &&
	   $source->{updateLatitudeSource} ne "") {
		eval {
			my $latitudeSource =
			    findSource($self, "Latitude",
				       $source->{updateLatitudeSource});
			updateLatitudeLocation($latitudeSource, $currentPosition);
		};
		warn $@ if $@;
	}
}

print "Saving location data.\n" if $self->{verbose};
appendData($self, $newEntries);

saveKml($self, $doc);
