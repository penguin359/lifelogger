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
use POSIX qw(strftime);
use XML::DOM;
use XML::DOM::XPath;
use HTTP::Request;
use Data::Dumper;

require 'common.pl';

my $slow = 0;
my $makeMark = 1;
if(defined($ARGV[0])) {
	if($ARGV[0] eq "-s") {
		$slow = 1;
	} elsif($ARGV[0] eq "-n") {
		$makeMark = 0;
	} else {
		die "Usage: $0 [-n | -s]";
	}
}

my $self = init();
lockKml($self);

my $apiKey = $self->{settings}->{apiKey};

my $entries = loadData($self);
my $lastTimestamp = lastTimestamp($self);
$lastTimestamp++;
#print strftime("%FT%TZ", gmtime($lastTimestamp)), "\n";

#print Dumper($entries);
#print "TS: '$lastTimestamp'\n";

#my $request = HTTP::Request->new(GET => "http://www.instamapper.com.ipv6.sixxs.org/api?action=getPositions&key=$apiKey&num=100&from_ts=$lastTimestamp");
#my $ua = LWP::UserAgent->new;
#my $response = $ua->request($request);
my $newEntries = [];
#if($response->is_success) {
#	#print "R: '" . $response->decoded_content . "'\n";
#	@lines = split /\n/, $response->decoded_content;
#	($newEntries) = parseData(\@lines);
#	#print Dumper($newEntries);
#} else {
#	print STDERR $response->status_line, "\n";
#}
#print "wget -O - 'http://www.instamapper.com.ipv6.sixxs.org/api?action=getPositions&key=$apiKey&num=100&from_ts=$lastTimestamp'\n";
#exit 0;
#open(my $wgetFd, "wget -q -O - 'http://www.instamapper.com.ipv6.sixxs.org/api?action=getPositions&key=$apiKey&num=100&from_ts=$lastTimestamp'|") or die "failed to retrieve InstaMapper data";
#print "wget -q -O - 'http://www.instamapper.com/api?action=getPositions&key=$apiKey&num=100&from_ts=$lastTimestamp'\n";
open(my $wgetFd, "wget -q -O - 'http://www.instamapper.com/api?action=getPositions&key=$apiKey&num=100&from_ts=$lastTimestamp'|") or die "failed to retrieve InstaMapper data";
my @lines = <$wgetFd>;
close $wgetFd;
#print Dumper(\@lines);
($newEntries) = parseData($self, \@lines);

my $doc = loadKml($self);
my @locationBase = $doc->findnodes("/kml/Document/Folder[name='Locations']");

die "Can't find base for location" if @locationBase != 1;

#push @$entries, @$newEntries;
appendData($self, $newEntries);
#print Dumper($newEntries);
#exit 0;
#unlink($dataFile);
#rename("$dataFile.bak", $dataFile);

#print <<EOF;
#<kml xmlns="http://www.opengis.net/kml/2.2"
# xmlns:gx="http://www.google.com/kml/ext/2.2">'
#EOF
#
#print <<EOF;
#</kml>
#EOF

my $kmlEntries = [];
push @$kmlEntries, pop @$newEntries if @$newEntries && $makeMark;
push @$newEntries, @$kmlEntries;
foreach my $entry (@$kmlEntries) {
	next if !defined($entry->{latitude}) or $entry->{latitude} == 0;
	my $mark = $doc->createElement('Placemark');
	my $timestamp = $doc->createElement('TimeStamp');
	my $when = $doc->createElement('when');
	my $text = $doc->createTextNode(strftime("%FT%TZ", gmtime($entry->{timestamp})));
	$when->appendChild($text);
	$timestamp->appendChild($when);
	$mark->appendChild($timestamp);
	my $style = $doc->createElement('styleUrl');
	$text = $doc->createTextNode('#icon');
	$style->appendChild($text);
	$mark->appendChild($style);
	my $point = $doc->createElement('Point');
	my $coord = $doc->createElement('coordinates');
	$text = $doc->createTextNode("$entry->{longitude},$entry->{latitude},$entry->{altitude}");
	$coord->appendChild($text);
	$point->appendChild($coord);
	$mark->appendChild($point);
	my $extData = $doc->createElement('ExtendedData');
	my $data = $doc->createElement('Data');
	$data->setAttribute('name', 'speed');
	my $value = $doc->createElement('value');
	$text = $doc->createTextNode($entry->{speed} . " m/s");
	$value->appendChild($text);
	$data->appendChild($value);
	$extData->appendChild($data);
	$data = $doc->createElement('Data');
	$data->setAttribute('name', 'heading');
	$value = $doc->createElement('value');
	$text = $doc->createTextNode($entry->{heading});
	$value->appendChild($text);
	$data->appendChild($value);
	$extData->appendChild($data);
	$mark->appendChild($extData);
	$locationBase[0]->appendChild($mark);
	$text = $doc->createTextNode("\n");
	$locationBase[0]->appendChild($text);
}

my $coordStr = "";
foreach my $entry (@$newEntries) {
	next if !defined($entry->{latitude}) or $entry->{latitude} == 0;
	$coordStr .= "\n$entry->{longitude},$entry->{latitude},$entry->{altitude}";
}
my @lineNode = $doc->findnodes('/kml/Document/Placemark/LineString/coordinates');
#print "XML:\n";
#print Dumper(\@lineNode);
$lineNode[0]->addText($coordStr);

my $currentPosition = pop @$newEntries;
if(defined($currentPosition)) {
	my $positionNode = ${$doc->findnodes("/kml/Document/Placemark[styleUrl='#position']/Point/coordinates/text()")}[0];
	$positionNode->setNodeValue("$currentPosition->{longitude},$currentPosition->{latitude},$currentPosition->{altitude}");
}

saveKml($self, $doc);

#openDB($self);
#insertDB($self);
