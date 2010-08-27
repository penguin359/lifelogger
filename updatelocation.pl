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
use Getopt::Long;
use HTTP::Request;
use LWP::UserAgent;
use Data::Dumper;

require 'common.pl';

my $slow = 0;
my $noMark = 0;
my $verbose = 0;
my $result = GetOptions(
	"slow" => \$slow,
	"no-mark" => \$noMark,
	"Verbose" => \$verbose);
die "Usage: $0 [-n | -s] [file.csv]" if !$result || @ARGV > 1;

my $self = init();
lockKml($self);

$self->{verbose} = $verbose;

my $newEntries = [];
if(defined($ARGV[0])) {
	print "Loading CSV file.\n" if $self->{verbose};
	open(my $fd, $ARGV[0]) or die "Can't load file";
	my @lines = <$fd>;
	($newEntries) = parseData($self, \@lines);
} else {
	my $sources = $self->{sources};
	my $apiKey = $sources->[0]->{apiKey};
	my $lastTimestamp = lastTimestamp($self, $sources->[0]->{id});
	$lastTimestamp++;

	print "Downloading InstaMapper data.\n" if $self->{verbose};
	my $request = HTTP::Request->new(GET => "http://www.instamapper.com/api?action=getPositions&key=$apiKey&num=100&from_ts=$lastTimestamp");
	my $ua = LWP::UserAgent->new;
	my $response = $ua->request($request);
	if($response->is_success) {
		my @lines = split /\n/, $response->decoded_content;
		($newEntries) = parseData($self, \@lines);
	} else {
		print STDERR $response->status_line, "\n";
	}
}

my $doc = loadKml($self);
my $xc = new XML::LibXML::XPathContext $doc;
$xc->registerNs('k', "http://www.opengis.net/kml/2.2");
my @locationBase = $xc->findnodes("/k:kml/k:Document/k:Folder[k:name='Locations']");

die "Can't find base for location" if @locationBase != 1;

print "Saving location data.\n" if $self->{verbose};
appendData($self, $newEntries);

print "Adding placemarks.\n" if $self->{verbose} && @$newEntries && !$noMark;
my $kmlEntries = [];
push @$kmlEntries, pop @$newEntries if @$newEntries && !$noMark;
push @$newEntries, @$kmlEntries;
foreach my $entry (@$kmlEntries) {
	next if !defined($entry->{latitude}) or $entry->{latitude} == 0;
	my $mark = createPlacemark($doc);
	addTimestamp($doc, $mark, $entry->{timestamp});
	addStyle($doc, $mark, 'icon');
	addPoint($doc, $mark, $entry->{longitude}, $entry->{latitude}, $entry->{altitude});
	addExtendedData($doc, $mark, {
	    speed => $entry->{speed} . " m/s",
	    heading => $entry->{heading}});
	addPlacemark($doc, $locationBase[0], $mark);
}

print "Updating path.\n" if $self->{verbose};
my $coordStr = "";
foreach my $entry (@$newEntries) {
	next if !defined($entry->{latitude}) or $entry->{latitude} == 0;
	$coordStr .= "\n$entry->{longitude},$entry->{latitude},$entry->{altitude}";
}
my @lineNode = $xc->findnodes('/k:kml/k:Document/k:Placemark/k:LineString/k:coordinates/text()');
$lineNode[0]->appendData($coordStr);

print "Updating my location.\n" if $self->{verbose};
my $currentPosition = pop @$newEntries;
if(defined($currentPosition)) {
	my $positionNode = ${$xc->findnodes("/k:kml/k:Document/k:Placemark[k:styleUrl='#position']/k:Point/k:coordinates/text()")}[0];
	$positionNode->setData("$currentPosition->{longitude},$currentPosition->{latitude},$currentPosition->{altitude}");
}

saveKml($self, $doc);

#openDB($self);
#insertDB($self);
