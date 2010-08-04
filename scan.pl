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
use POSIX qw(mktime strftime);
use Fcntl ':flock';
use XML::DOM;
use XML::DOM::XPath;
use Image::ExifTool;
use Encode;
use Data::Dumper;

require 'common.pl';

my $self = init();
lockKml($self);

sub addImage {
	my($path, $self, $doc, $base) = @_;

	return if ! -f $path || ! -s $path;
	my $exif = new Image::ExifTool;
	open(my $fd, $path) or die "Can't open file $path";
	my $info = $exif->ImageInfo($fd);
	#print Dumper($info);
	my $filename = $path;
	$filename =~ s:.*/::;
	$filename =~ s:\.[jJ][pP][gG]$:.jpg:;
	rename($path, "images/$filename");
	system('convert','-geometry','160x160',"images/$filename","images/160/$filename");
	system('convert','-geometry','32x32',"images/$filename","images/32/$filename");

	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
	    $atime,$mtime,$ctime,$blksize,$blocks) = stat("images/$filename");

	my $timestamp = $mtime;
	die "Failed to stat $path" if(!defined($timestamp) || $timestamp == 0);
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
		$timestamp = mktime($sec, $min, $hour, $mday, $mon-1, $year-1900) + $tzoffset;
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
		my $entry = closestEntry($timestamp);
		$latitude = $entry->{latitude};
		$longitude = $entry->{longitude};
		$altitude = $entry->{altitude};
	}
	#print "$longitude,$latitude\n";

	my $mark = createPlacemark($doc);
	addName($doc, $mark, $filename);
	addDescription($doc, $mark, "<p><b>$filename</b></p><a href=\"http://www.example.org/images/$filename\"><img src=\"http://www.example.org/images/160/$filename\"></a>");
	addRssEntry($self->{rssFeed}, $filename, "http://www.example.org/images/$filename", "<p><b>$filename</b></p><a href=\"http://www.example.org/images/$filename\"><img src=\"http://www.example.org/images/160/$filename\"></a>");
	addAtomEntry($self->{atomFeed}, $filename, "http://www.example.org/images/$filename", "<p><b>$filename</b></p><a href=\"http://www.example.org/images/$filename\"><img src=\"http://www.example.org/images/160/$filename\"></a>");
	addTimestamp($doc, $mark, $timestamp);
	addStyle($doc, $mark, 'photo');
	addPoint($doc, $mark, $latitude, $longitude);
	addPlacemark($doc, $base, $mark);
}

my $doc = loadKml($self);
#my @base = $doc->findnodes('/kml/Document');
my @base = $doc->findnodes("/kml/Document/Folder[name='Unsorted Photos']");

die "Can't find base for unsorted photos" if @base != 1;


$self->{rssFeed} = loadRssFeed();
$self->{atomFeed} = loadAtomFeed();
foreach(@ARGV) {
	addImage($_, $self, $doc, $base[0]);
}
saveKml($self, $doc);
saveRssFeed($self->{rssFeed});
saveAtomFeed($self->{atomFeed});
