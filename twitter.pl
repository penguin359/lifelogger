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
use LWP::UserAgent;
use HTTP::Headers;
use HTTP::Request;
use HTTP::Request::Common;

require 'common.pl';

my $id;
my $verbose = 0;
my $result = GetOptions(
	"id=i" => \$id,
	"verbose" => \$verbose);
die "Usage: $0 [-id id] [-verbose] [twitter.xml]" if !$result || @ARGV > 1;

my $self = init();
$self->{verbose} = $verbose;
lockKml($self);

my $source;
my $twitterFile = $self->{settings}->{twitterFeed};
$twitterFile = shift if @ARGV;

if(defined($twitterFile)) {
	$source = {
		id => 12,
		name => "Twitter",
		deviceKey => 12,
		file => $twitterFile
	};
} else {
	$source = findSource($self, "Twitter", $id);
	$twitterFile = $source->{file};
	$twitterFile = 'http://api.twitter.com/1/statuses/user_timeline.rss'
	    if !defined($twitterFile);
}

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

			my $oauthData = {
				protocol => 'oauth 1.0a',
				app => 'Twitter',
				type => 'Resource',
				params => {
					token => $source->{token},
					token_secret => $source->{tokenSecret},
					request_url => $url,
					request_method => 'GET',
				},
			};

			my $headers = new HTTP::Headers;
			$headers->header('Authorization', requestSign($oauthData));
			# Load proxy settings from environment variables, i.e.:
			# http_proxy, ftp_proxy, no_proxy etc. (see LWP::UserAgent(3))
			# You need these to go thru firewalls.
			$ua->env_proxy;
			my $req = new HTTP::Request 'GET', $url, $headers;
			#print Dumper($req);
			my $response = $ua->request($req);
			die "Bad request ".$response->status_line if !$response->is_success;

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
my $containerPath = "/kml:kml/kml:Document/kml:Folder[kml:name='Twitter']";
my $containerId = $source->{kml}->{container};
$containerPath = "//kml:Folder[\@id='$containerId']" if defined($containerId);
my @base = $xc->findnodes($containerPath, $doc);
#my $parser = new XML::LibXML;
#my $twitterDoc = $parser->parse_file($twitterFile);
my $twitterDoc = loadXML($twitterFile);
my @items = $xc->findnodes('/rss/channel/item', $twitterDoc);

die "Can't find container for Twitter" if @base != 1;

#print "List:\n";
foreach my $item (reverse @items) {
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
