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
use XML::DOM;
use XML::DOM::XPath;

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

require 'common.pl';

my $self = init();
lockKml($self);

my $parser = new XML::DOM::Parser;
my $rssDoc = $parser->parsefile($rssFile);
my @items = $rssDoc->findnodes('/gpx/trk/trkseg/trkpt');

print "List:\n";
my $entries = [];
foreach my $item (@items) {
	my $entry = {};
	$entry->{key}       = $source;
	$entry->{label}     = $name;
	$entry->{latitude}  = ${$item->findnodes('@lat')}[0]->getNodeValue();
	$entry->{longitude} = ${$item->findnodes('@lon')}[0]->getNodeValue();
	$entry->{altitude}  = ${$item->findnodes('ele/text()')}[0]->getNodeValue();
	$entry->{speed}     = ${$item->findnodes('extensions/speed/text()')}[0]->getNodeValue();
	$entry->{heading}   = "";
	my $time            = ${$item->findnodes('time/text()')}[0]->getNodeValue();
	$entry->{timestamp} = parseIsoTime($self, $time);
	#$entry->{timestamp} = 0;

	#print "[UTF8] " if utf8::is_utf8($descr);
	#print "[VALID] " if utf8::valid($descr);
	#print "I: '", $latitude, "' - $longitude - $timestamp\n";
	push @$entries, $entry;
}

writeDataFile($self, $entries, $out);
