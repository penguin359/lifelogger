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

# This is a wrapper for LibXML allowing it to pull from URLs as well as
# from files.  This was shamelessly stolen from XML::DOM.
sub loadXML {
	my($url) = @_;
	my $parser = new XML::LibXML;

	# Any other URL schemes?
	if($url =~ /^(https?|ftp|wais|gopher|file):/) {
		# Read the file from the web with LWP.
		#
		# Note that we read in the entire file, which may not be ideal
		# for large files. LWP::UserAgent also provides a callback style
		# request, which we could convert to a stream with a fork()...

		my $result;
		eval {
			use LWP::UserAgent;

			my $ua = LWP::UserAgent->new;

			# Load proxy settings from environment variables, i.e.:
			# http_proxy, ftp_proxy, no_proxy etc. (see LWP::UserAgent(3))
			# You need these to go thru firewalls.
			$ua->env_proxy;
			my $req = new HTTP::Request 'GET', $url;
			my $response = $ua->request($req);

			# Parse the result of the HTTP request
			$result = $parser->parse_string($response->content);
		};
		if($@) {
			die "Couldn't parsefile [$url] with LWP: $@";
		}
		return $result;
	} else {
		return $parser->parse_file($url);
	}
}

my $doc = loadKml($self);
my $xc = loadXPath($self);
my @base = $xc->findnodes("/kml:kml/kml:Document/kml:Folder[kml:name='Twitter']", $doc);
my $rssDoc = loadXML($rssFile);
my @items = $xc->findnodes('/rss/channel/item', $rssDoc);

die "Can't find base for twitter" if @base != 1;

#print "List:\n";
foreach my $item (@items) {
	my $title     = ${$xc->findnodes('title/text()', $item)}[0]->nodeValue;
	my $descr     = ${$xc->findnodes('description/text()', $item)}[0]->nodeValue;
	my $pubDate   = ${$xc->findnodes('pubDate/text()', $item)}[0]->nodeValue;
	my $guid      = ${$xc->findnodes('guid/text()', $item)}[0]->nodeValue;
	my $link      = ${$xc->findnodes('link/text()', $item)}[0]->nodeValue;
	my $timestamp = parseDate($pubDate);

	my @guidMatches = $xc->findnodes("/kml:kml/kml:Document/kml:Folder/kml:Placemark/kml:ExtendedData/kml:Data[\@name='guid']/kml:value[text()='$guid']/text()", $doc);
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
