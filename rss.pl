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
use vars qw($apiKey $cwd);
use POSIX qw(mktime strftime);
use Fcntl ':flock';
use XML::DOM;
use XML::DOM::XPath;
use MIME::Parser;
use MIME::WordDecoder;
use Image::ExifTool;
use Data::Dumper;

require 'settings.pl';

my $rssFile = "twitter.rss";
$rssFile = shift if @ARGV;

require 'common.pl';

my $self = init();
lockKml($self);

my $doc = loadKml($self);
my @base = $doc->findnodes("/kml/Document/Folder[name='Twitter']");
my $parser = new XML::DOM::Parser;
my $rssDoc = $parser->parsefile($rssFile);
my @items = $rssDoc->findnodes('/rss/channel/item');

die "Can't find base for twitter" if @base != 1;

#print "List:\n";
foreach my $item (@items) {
	my $title = ${$item->findnodes('title/text()')}[0]->getNodeValue();
	my $descr = ${$item->findnodes('description/text()')}[0]->getNodeValue();
	my $pubDate = ${$item->findnodes('pubDate/text()')}[0]->getNodeValue();
	my $guid = ${$item->findnodes('guid/text()')}[0]->getNodeValue();
	my $link = ${$item->findnodes('link/text()')}[0]->getNodeValue();
	my $timestamp = parseDate($pubDate);

	my @guidMatches = $doc->findnodes("/kml/Document/Folder/Placemark/ExtendedData/Data[\@name='guid']/value[text()='$guid']/text()");
	if(@guidMatches) {
		die "Duplicate GUIDs" if @guidMatches > 1;
		#my $kmlGuid = $guidMatches[0]->getNodeValue;
		#print "Matching GUID: '$kmlGuid'\n";
		next;
	}
	#print "I: '", $descr, "' - $link - $timestamp\n";
	#next;

	$descr =~ s/&/&amp;/g;
	$descr =~ s/"/&quot;/g;
	$descr =~ s/</&lt;/g;
	$descr =~ s/>/&gt;/g;
	$guid =~ s/&/&amp;/g;
	$guid =~ s/"/&quot;/g;
	$guid =~ s/</&lt;/g;
	$guid =~ s/>/&gt;/g;
	$link =~ s/&/&amp;/g;
	$link =~ s/"/&quot;/g;
	$link =~ s/</&lt;/g;
	$link =~ s/>/&gt;/g;

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
