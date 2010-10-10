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

my $newEntries = [];
#print "List:\n";
foreach my $item (reverse @items) {
	my $id        = ${$xc->findnodes('id/text()', $item)}[0]->nodeValue;
	my $created   = ${$xc->findnodes('created/text()', $item)}[0]->nodeValue;
	my $name      = ${$xc->findnodes('venue/name/text()', $item)}[0];
	next if !defined($name);
	$name  = $name->nodeValue;
	my $iconPath  = ${$xc->findnodes('venue/primarycategory/fullpathname/text()', $item)}[0];
	next if !defined($iconPath);
	$iconPath  = $iconPath->nodeValue;
	my $iconUrl   = ${$xc->findnodes('venue/primarycategory/iconurl/text()', $item)}[0]->nodeValue;
	my $latitude  = ${$xc->findnodes('venue/geolat/text()', $item)}[0]->nodeValue;
	my $longitude = ${$xc->findnodes('venue/geolong/text()', $item)}[0]->nodeValue;
	my $descr     = ${$xc->findnodes('display/text()', $item)}[0]->nodeValue;
	my $timestamp = parseDate($created);

	my @guidMatches = $xc->findnodes("/kml:kml/kml:Document/kml:Folder/kml:Placemark/kml:ExtendedData/kml:Data[\@name='checkinId']/kml:value[text()='$id']/text()", $doc);
	if(@guidMatches) {
		die "Duplicate GUIDs" if @guidMatches > 1;
		#my $kmlGuid = $guidMatches[0]->getNodeValue;
		#print "Matching GUID: '$kmlGuid'\n";
		next;
	}
	#print "[UTF8] " if utf8::is_utf8($descr);
	#print "[VALID] " if utf8::valid($descr);
	print "I: '", $descr, "' - $name - $timestamp\n";
	#next;

	my $iconStyle = 'foursquare_' . $iconPath;
	$iconStyle =~ s/:/_/g;
	my @styleNode = $xc->findnodes("kml:Style[\@id='$iconStyle']", $doc);
	if(@styleNode < 1) {
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
	}

	$descr = escapeText($self, $descr);

	my $mark = createPlacemark($doc);
	my $entry = {};
	#if(defined($point) && $point =~ /^\s*(-?\d+(?:.\d*)?)\s+(-?\d+(?:.\d*)?)\s*$/) {
		$entry->{latitude} = $latitude;
		$entry->{longitude} = $longitude;
		$entry->{key} = 1;
		$entry->{label} = 'FourSquare';
		$entry->{timestamp} = $timestamp;
		$entry->{altitude} = '';
		$entry->{speed} = '';
		$entry->{heading} = '';
		push @$newEntries, $entry;
	#} else {
	#	$entry = closestEntry($self, $timestamp);
	#}
	addName($doc, $mark, $name);
	addDescription($doc, $mark, "<b>$name</b><p>$descr</p>");
	addTimestamp($doc, $mark, $timestamp);
	addStyle($doc, $mark, $iconStyle);
	addExtendedData($doc, $mark, { checkinId => $id });
	addPoint($doc, $mark, $entry->{latitude}, $entry->{longitude});
	addPlacemark($doc, $base[0], $mark);
}

print "Saving location data.\n" if $self->{verbose};
appendData($self, $newEntries);

saveKml($self, $doc);
