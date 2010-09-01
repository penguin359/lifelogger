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

require 'common.pl';

my $name = "GPX Data";
my $source = 0;
my $verbose = 0;
my $out = "gps-out.gpx";
my $result = GetOptions("name=s" => \$name,
	   "source=i" => \$source,
	   "Verbose" => \$verbose,
	   "out=s" => \$out);

my $rssFile = "log.gpx";
$rssFile = shift if @ARGV;

my $self = init();
$self->{verbose} = $verbose;
lockKml($self);

open(my $fd, "<", $rssFile) or die "Failed to open KML for reading";
binmode $fd;
my $parser = new XML::LibXML;
my $rssDoc = $parser->parse_fh($fd);
close $fd;
my $xc = loadXPath($self);
my @items = $xc->findnodes('/gpx:gpx/gpx:trk/gpx:trkseg/gpx:trkpt', $rssDoc);

print "List:\n";
my $entries = [];
foreach my $item (@items) {
	my $entry = {};
	$entry->{key}       = $source;
	$entry->{label}     = $name;
	$entry->{latitude}  = ${$xc->findnodes('@lat', $item)}[0]->nodeValue;
	$entry->{longitude} = ${$xc->findnodes('@lon', $item)}[0]->nodeValue;
	$entry->{altitude}  = ${$xc->findnodes('gpx:ele/text()', $item)}[0]->nodeValue;
	$entry->{speed}     = ${$xc->findnodes('gpx:extensions/gpx:speed/text()', $item)}[0]->nodeValue;
	$entry->{heading}   = "";
	my $time            = ${$xc->findnodes('gpx:time/text()', $item)}[0]->nodeValue;
	$entry->{timestamp} = parseIsoTime($self, $time);
	#$entry->{timestamp} = 0;

	#print "[UTF8] " if utf8::is_utf8($descr);
	#print "[VALID] " if utf8::valid($descr);
	#print "I: '", $latitude, "' - $longitude - $timestamp\n";
	push @$entries, $entry;
}

writeDataFile($self, $entries, $out);
