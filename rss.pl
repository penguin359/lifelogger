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
use Image::ExifTool;

require 'common.pl';

my $self = init();
lockKml($self);

my $rssFile = $self->{settings}->{rssFeed};
$rssFile = shift if @ARGV;

my $doc = loadKml($self);
my $xc = new XML::LibXML::XPathContext $doc;
$xc->registerNs('k', "http://www.opengis.net/kml/2.2");
my @base = $xc->findnodes("/k:kml/k:Document/k:Folder[k:name='Twitter']");
open(my $fd, "<", $rssFile) or die "Failed to open RSS for reading";
binmode $fd;
my $parser = new XML::LibXML;
my $rssDoc = $parser->parse_fh($fd);
close $fd;
my @items = $xc->findnodes('/rss/channel/item', $rssDoc);

die "Can't find base for twitter" if @base != 1;

#print "List:\n";
foreach my $item (@items) {
	my $title     = ${$xc->findnodes('title/text()', $item)}[0]->data;
	my $descr     = ${$xc->findnodes('description/text()', $item)}[0]->data;
	my $pubDate   = ${$xc->findnodes('pubDate/text()', $item)}[0]->data;
	my $guid      = ${$xc->findnodes('guid/text()', $item)}[0]->data;
	my $link      = ${$xc->findnodes('link/text()', $item)}[0]->data;
	my $timestamp = parseDate($pubDate);

	my @guidMatches = $xc->findnodes("/k:kml/k:Document/k:Folder/k:Placemark/k:ExtendedData/k:Data[\@name='guid']/k:value[text()='$guid']/text()");
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
	my $entry = closestEntry($self, $timestamp);
	#addName($doc, $mark, $self->{subject});
	addDescription($doc, $mark, "<p>$descr</p><a href=\"$link\">Link</a>");
	addTimestamp($doc, $mark, $timestamp);
	addStyle($doc, $mark, 'twitter');
	addPoint($doc, $mark, $entry->{latitude}, $entry->{longitude}, $entry->{altitude});
	addExtendedData($doc, $mark, { guid => $guid });
	addPlacemark($doc, $base[0], $mark);
}
saveKml($self, $doc);
