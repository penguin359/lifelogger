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

require 'common.pl';

my $id;
my $verbose = 0;
my $result = GetOptions(
	"id=i" => \$id,
	"verbose" => \$verbose);
die "Usage: $0 [-i id] [-v] [file.csv]" if !$result || @ARGV > 1;

my $self = init();
$self->{verbose} = $verbose;
lockKml($self);

my $rssFile = $self->{settings}->{rssFeed};
$rssFile = shift if @ARGV;

my $source = findSource($self, "RSS", $id);

my $doc = loadKml($self);
my $xc = loadXPath($self);
my $locationPath = "/kml:kml/kml:Document/kml:Folder[kml:name='Twitter']";
my $locationId = $source->{kml}->{location};
$locationPath = "//kml:Folder[\@id='$locationId']" if defined($locationId);
my @base = $xc->findnodes($locationPath, $doc);
my $parser = new XML::LibXML;
my $rssDoc = $parser->parse_file($rssFile);
my @items = $xc->findnodes('/rss/channel/item', $rssDoc);

die "Can't find base for RSS" if @base != 1;

my $newEntries = [];
#print "List:\n";
foreach my $item (reverse @items) {
	my $title     = ${$xc->findnodes('title/text()', $item)}[0]->nodeValue;
	my $descr     = ${$xc->findnodes('description/text()', $item)}[0]->nodeValue;
	my $pubDate   = ${$xc->findnodes('pubDate/text()', $item)}[0]->nodeValue;
	my $guid      = ${$xc->findnodes('guid/text()', $item)}[0]->nodeValue;
	my $link      = ${$xc->findnodes('link/text()', $item)}[0]->nodeValue;
	my $point     = ${$xc->findnodes('georss:point/text()', $item)}[0];
	$point        = $point->nodeValue if defined($point);
	my $timestamp = parseDate($pubDate);

	my @guidMatches = $xc->findnodes("kml:Placemark/kml:ExtendedData/kml:Data[\@name='guid']/kml:value[text()='$guid']/text()", $base[0]);
	if(@guidMatches) {
		die "Duplicate GUIDs" if @guidMatches > 1;
		#my $kmlGuid = $guidMatches[0]->getNodeValue;
		#print "Matching GUID: '$kmlGuid'\n";
		next;
	}
	#print "[UTF8] " if utf8::is_utf8($descr);
	#print "[VALID] " if utf8::valid($descr);
	#print "I: '", $descr, "' - $link - $timestamp\n";
	#next;

	$descr = escapeText($self, $descr);
	$guid  = escapeText($self, $guid);
	$link  = escapeText($self, $link);

	my $mark = createPlacemark($doc);
	my $entry = {};
	if(defined($point) && $point =~ /^\s*(-?\d+(?:.\d*)?)\s+(-?\d+(?:.\d*)?)\s*$/) {
		($entry->{latitude}, $entry->{longitude}) = ($1, $2);
		$entry->{key} = 0;
		$entry->{label} = 'Twitter';
		$entry->{timestamp} = $timestamp;
		$entry->{altitude} = '';
		$entry->{speed} = '';
		$entry->{heading} = '';
		push @$newEntries, $entry;
	} else {
		$entry = closestEntry($self, $timestamp);
	}
	addName($doc, $mark, $title);
	addDescription($doc, $mark, "<p>$descr</p><a href=\"$link\">Link</a>");
	addTimestamp($doc, $mark, $timestamp);
	addStyle($doc, $mark, 'twitter');
	addExtendedData($doc, $mark, { guid => $guid });
	addPoint($doc, $mark, $entry->{latitude}, $entry->{longitude}, $entry->{altitude});
	addPlacemark($doc, $base[0], $mark);
}

print "Saving location data.\n" if $self->{verbose};
appendData($self, $newEntries);

saveKml($self, $doc);
