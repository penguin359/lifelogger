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


use 5.008;
use warnings;
use strict;

use utf8;
use open ':utf8', ':std';
use Encode;
use Getopt::Long;
use Image::ExifTool;

require 'common.pl';

my $verbose = 0;
my $result = GetOptions("Verbose" => \$verbose);

my $self = init();
$self->{verbose} = $verbose;
lockKml($self);

my $fourSquareFile = $self->{settings}->{fourSquareFeed};
$fourSquareFile = shift if @ARGV;

my $doc = loadKml($self);
my $xc = loadXPath($self);
my @base = $xc->findnodes("/kml:kml/kml:Document/kml:Folder[kml:name='FourSquare']", $doc);
my $parser = new XML::LibXML;
my $fourSquareDoc = $parser->parse_file($fourSquareFile);
my @items = $xc->findnodes('/checkins/checkin', $fourSquareDoc);

die "Can't find base for FourSquare" if @base != 1;

sub getNode {
	my($xc, $node, $path) = @_;

	my @nodeList = $xc->findnodes($path, $node);
	warn "Multiple nodes for '$path' on " . $node->nodeName
	    if @nodeList > 1;
	return $nodeList[0] if @nodeList == 1;
	return;
}

sub getTextNode {
	my($xc, $node, $path) = @_;

	$node = getNode($xc, $node, $path . "/text()");
	return $node->nodeValue if defined($node);
	return;
}

my $newEntries = [];
my %style;
print "List:\n" if $self->{verbose};
foreach my $item (reverse @items) {
	my $id        = getTextNode($xc, $item, 'id');
	my $created   = getTextNode($xc, $item, 'created');
	my $venue     = getNode($xc, $item, 'venue');
	my $shout     = getTextNode($xc, $item, 'shout');
	my $name;
	my $iconPath  = 'None';
	my $iconUrl   = 'http://foursquare.com/img/categories/none.png';
	my $latitude;
	my $longitude;
	my $altitude;
	if($venue) {
		$name      = getTextNode($xc, $venue, 'name');
		my $category = getNode($xc, $venue, 'primarycategory');
		if($category) {
			$iconPath  = getTextNode($xc, $category, 'fullpathname');
			$iconUrl   = getTextNode($xc, $category, 'iconurl');
		}
		$latitude  = getTextNode($xc, $venue, 'geolat');
		$longitude = getTextNode($xc, $venue, 'geolong');
		$altitude = getTextNode($xc, $venue, 'geoalt');
	} else { die "Shout!" }
	my $display     = getTextNode($xc, $item, 'display');
	if(!defined($created)) {
		warn "FourSquare check-in with missing created time";
		next;
	}
	my $timestamp = parseDate($created);
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
	if(defined($latitude) && defined($longitude)) {
		$entry->{latitude} = $latitude;
		$entry->{longitude} = $longitude;
		$entry->{key} = 1;
		$entry->{label} = 'FourSquare';
		$entry->{timestamp} = $timestamp;
		$entry->{altitude} = $altitude;
		$entry->{speed} = '';
		$entry->{heading} = '';
		$entry->{altitude} = '' if !defined($entry->{altitude});
		push @$newEntries, $entry;
	} else {
		$entry = closestEntry($self, $timestamp);
	}
	addName($doc, $mark, $name);
	$name = escapeText($self, $name);
	$descr = escapeText($self, $descr) if defined($descr);
	my $fullDescription = "<p><b>$name</b></p>";
	$fullDescription .= "<p>$descr</p>" if defined($descr);
	addDescription($doc, $mark, $fullDescription);
	addTimestamp($doc, $mark, $timestamp);
	addStyle($doc, $mark, $iconStyle);
	addExtendedData($doc, $mark, { checkinId => $id });
	addPoint($doc, $mark, $entry->{latitude}, $entry->{longitude});
	addPlacemark($doc, $base[0], $mark);
}

print "Saving location data.\n" if $self->{verbose};
appendData($self, $newEntries);

saveKml($self, $doc);
