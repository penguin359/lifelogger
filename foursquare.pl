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
use LWP::UserAgent;
use HTTP::Headers;
use HTTP::Request;
use HTTP::Request::Common;
#use Net::OAuth::Local;
use JSON;

my $usage = "[-id id] [foursquare.xml]";
my $id;

my $self = init($usage, {"id=s" => \$id});
die $self->{usage} if @ARGV > 1;
lockKml($self);

my $source;
my $fourSquareFile = $self->{settings}->{fourSquareFeed};
$fourSquareFile = shift if @ARGV;

if(defined($fourSquareFile)) {
	$source = {
		id => 11,
		name => "FourSquare",
		type => "FourSquare",
		deviceKey => 11,
		file => $fourSquareFile,
	};
} else {
	$source = findSource($self, "FourSquare", $id);
	$fourSquareFile = $source->{file};
	my $oauthToken = "";
	$oauthToken = "?oauth_token=" . $source->{tokenSecret}
	    if defined $source->{tokenSecret};
	$fourSquareFile = 'https://api.foursquare.com/v2/users/self/checkins'.$oauthToken
	    if !defined($fourSquareFile);
}

my $doc = loadKml($self);
my $xc = loadXPath($self);
my $containerPath = "/kml:kml/kml:Document/kml:Folder[kml:name='FourSquare']";
my $containerId = $source->{kml}->{container};
$containerPath = "//kml:Folder[\@id='$containerId']" if defined($containerId);
my @base = $xc->findnodes($containerPath, $doc);

my $ua = new LWP::UserAgent;
my $req = new HTTP::Request 'GET', $fourSquareFile;
my $response = $ua->request($req);
die "Bad request ".$response->status_line if !$response->is_success;
#print Dumper($response);

my $json = new JSON;
$json->utf8(1);
my $result = $json->decode($response->content);
die "Failed to get FourSquare check-ins: ". $result->{meta}->{code} ." - ". $result->{meta}->{errorType} if $result->{meta}->{code} ne 200;

#print Dumper($result);
#exit 0;

my $items = $result->{response}->{checkins}->{items};

die "Can't find container for FourSquare" if @base != 1;

my $last = lastTimestamp($self, $source->{id});
my $nextId = $last->{id} + 1;

my $newEntries = [];
my %style;
print "List:\n" if $self->{verbose};
foreach my $item (reverse @$items) {
	my $id        = $item->{id};
	my $created   = $item->{createdAt};
	my $venue     = $item->{venue};
	my $shout     = $item->{shout};
	my $name;
	my $iconPath  = 'None';
	my $iconUrl   = 'http://foursquare.com/img/categories/none.png';
	my $latitude;
	my $longitude;
	my $altitude;
	if($venue) {
		$name      = $venue->{name};
		my $category = $venue->{categories}->[0];
		if($category) {
			$iconPath  = (join '/', @{$category->{parents}}) . "/" . $category->{name};
			$iconUrl   = $category->{icon};
		}
		$latitude  = $venue->{location}->{lat};
		$longitude = $venue->{location}->{lng};
		#$altitude = $venue->{location}->{lat};
	} else { die "Shout!" }
	#my $display     = getTextNode($xc, $item, 'display');
	if(!defined($created)) {
		warn "FourSquare check-in with missing created time";
		next;
	}
	my $timestamp = $created;
	my $descr = $shout;

	my @guidMatches = $xc->findnodes("kml:Placemark/kml:ExtendedData/kml:Data[\@name='checkinId']/kml:value[text()='$id']/text()", $base[0]);
	if(@guidMatches) {
		die "Duplicate GUIDs" if @guidMatches > 1;
		#my $kmlGuid = $guidMatches[0]->getNodeValue;
		#print "Matching GUID: '$kmlGuid'\n";
		next;
	}
	my $descrTest = $descr;
	$descrTest = '' if !defined($descrTest);
	#print "[UTF8] " if utf8::is_utf8($descrTest);
	#print "[VALID] " if utf8::valid($descrTest);
	print "I: '", $descrTest, "' - $name - $timestamp\n" if $self->{verbose};
	#next;

	my $iconStyle = 'foursquare_' . $iconPath;
	$iconStyle =~ s/[^[:alnum:]]/_/g;
	my @styleNode = $xc->findnodes("//kml:Style[\@id='$iconStyle']", $doc);
	if(!defined($style{$iconStyle}) && @styleNode < 1) {
		my $style = $doc->createElement('Style');
		$style->setAttribute('id', $iconStyle);
		my $node = $doc->createElement('IconStyle');
		my $icon = $doc->createElement('Icon');
		my $href = $doc->createElement('href');
		my $url = $doc->createTextNode($iconUrl);
		$href->appendChild($url);
		$icon->appendChild($href);
		$node->appendChild($icon);
		$style->appendChild($node);
		my $docNode = ${$xc->findnodes("/kml:kml/kml:Document", $doc)}[0];
		$docNode->appendChild($style);
		my $textNode = $doc->createTextNode("\n");
		$docNode->appendChild($textNode);
		$style{$iconStyle} = 1;
	} elsif(@styleNode > 1) {
		warn "Duplicate style node '$iconStyle'\n";
	}

	my $mark = createPlacemark($doc);
	my $entry = {};
	eval {
	if(defined($latitude) && defined($longitude)) {
		$entry->{latitude} = $latitude;
		$entry->{longitude} = $longitude;
		$entry->{altitude} = $altitude;
		$entry->{key} = $source->{deviceKey};
		$entry->{source} = $source->{id};
		$entry->{label} = $source->{name};
		$entry->{timestamp} = $timestamp;
		$entry->{id} = $nextId++;
		push @$newEntries, $entry;
	} else {
		$entry = closestEntry($self, $source, $timestamp);
	}
	addName($doc, $mark, $name);
	my $escapedName = escapeText($self, $name);
	my $escapedDescr = escapeText($self, $descr) if defined($descr);
	my $fullDescription = "<p><b>$escapedName</b></p>";
	$fullDescription .= "<p>$escapedDescr</p>" if defined($escapedDescr);
	addDescription($doc, $mark, $fullDescription);
	addTimestamp($doc, $mark, $timestamp);
	addStyle($doc, $mark, $iconStyle);
	addExtendedData($doc, $mark, { checkinId => $id });
	addPoint($doc, $mark, $entry->{latitude}, $entry->{longitude}, $entry->{altitude});
	addPlacemark($doc, $base[0], $mark);
	};
	if($@) {
		warn "Failed to add Tweet: $@";
	}
}

print "Saving location data.\n" if $self->{verbose};
appendData($self, $newEntries);

saveKml($self, $doc);
