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
use Time::Local;
use XML::DOM;
use XML::DOM::XPath;
use Image::ExifTool;
use Data::Dumper;

require 'common.pl';

my $verbose = 0;
my $result = GetOptions("Verbose" => \$verbose);

my $self = init();
lockKml($self);

$self->{verbose} = $verbose;

sub addImage {
	my($path, $self, $doc, $base) = @_;

	my $website = $self->{settings}->{website};

	return if ! -f $path || ! -s $path;
	print "Processing $path\n" if $self->{verbose};
	my $exif = new Image::ExifTool;
	open(my $fd, '<:bytes', $path) or die "Can't open file $path";
	binmode($fd);
	my $info = $exif->ImageInfo($fd);
	close $fd;
	#print Dumper($info);
	my $filename = $path;
	$filename =~ s:.*/::;
	$filename =~ s:\.[jJ][pP][eE]?[gG]$:.jpg:;
	print "Renaming '$path' to 'images/$filename'\n" if $self->{verbose};
	rename($path, "images/$filename") or die "Failed rename(): $!";
	createThumbnails($self, "images/$filename");

	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	    $atime,$mtime,$ctime,$blksize,$blocks) = stat("images/$filename");

	my $timestamp = $mtime;
	die "Failed to stat $path: $!" if(!defined($timestamp) || $timestamp == 0);
	if(exists $info->{DateTimeOriginal}) {
		$info->{DateTimeOriginal} =~ /(\d+):(\d+):(\d+)\s+(\d+):(\d+):(\d+)/;
		my $year = $1;
		my $mon = $2;
		my $mday = $3;
		my $hour = $4;
		my $min = $5;
		my $sec = $6;
		my $tzoffset = (-7*60 + 0)*60;
		$tzoffset *= -1;
		#print "SD: $mday $mon $year  $hour:$min:$sec\n";
		$timestamp = timegm($sec, $min, $hour, $mday, $mon-1, $year-1900) + $tzoffset;
	}
	my $latitude;
	my $longitude;
	my $altitude;
	if(exists $info->{GPSPosition}) {
		$info->{GPSPosition} =~ /(\d+)\s*deg\s*(?:(\d+)'\s*(?:(\d+(?:\.\d*)?)")?)?\s*([NS]),\s*(\d+)\s*deg\s*(?:(\d+)'\s*(?:(\d+(?:\.\d*)?)")?)?\s*([EW])/;
		#print "Loc: $1° $2' $3\" $4, $5° $6' $7\" $8\n";
		$latitude = $1 + ($2 + $3/60)/60;
		$latitude *= -1 if $4 eq "S";
		$longitude = $5 + ($6 + $7/60)/60;
		$longitude *= -1 if $8 eq "W";
	} else {
		my $entry = closestEntry($self, $timestamp);
		$latitude = $entry->{latitude};
		$longitude = $entry->{longitude};
		$altitude = $entry->{altitude};
	}
	#print "$longitude,$latitude\n";

	my $mark = createPlacemark($doc);
	addName($doc, $mark, $filename);
	addDescription($doc, $mark, "<p><b>$filename</b></p><a href=\"$website/images/$filename\"><img src=\"$website/images/160/$filename\"></a>");
	addRssEntry($self, $self->{rssFeed}, $filename, "$website/images/$filename", "<p><b>$filename</b></p><a href=\"$website/images/$filename\"><img src=\"$website/images/160/$filename\"></a>");
	addAtomEntry($self, $self->{atomFeed}, $filename, "$website/images/$filename", "<p><b>$filename</b></p><a href=\"$website/images/$filename\"><img src=\"$website/images/160/$filename\"></a>");
	addTimestamp($doc, $mark, $timestamp);
	addStyle($doc, $mark, 'photo');
	addPoint($doc, $mark, $latitude, $longitude);
	addPlacemark($doc, $base, $mark);
}

my $doc = loadKml($self);
#my @base = $doc->findnodes('/kml/Document');
my @base = $doc->findnodes("/kml/Document/Folder[name='Unsorted Photos']");

die "Can't find base for unsorted photos" if @base != 1;


$self->{rssFeed} = loadRssFeed($self);
$self->{atomFeed} = loadAtomFeed($self);
if(!@ARGV) {
	addImage($_, $self, $doc, $base[0])
	    foreach glob "uploads/*.[jJ][pP][gG] uploads/*.[jJ][pP][eE][gG]";
} else {
	addImage($_, $self, $doc, $base[0])
	    foreach @ARGV;
}
saveKml($self, $doc);
saveRssFeed($self, $self->{rssFeed});
saveAtomFeed($self, $self->{atomFeed});
