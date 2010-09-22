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
use Image::ExifTool;

require 'common.pl';

my $verbose = 0;
my $result = GetOptions("Verbose" => \$verbose);

my $self = init();
$self->{verbose} = $verbose;
lockKml($self);

sub addImageScan {
	my($path, $self, $doc, $base) = @_;

	return if ! -f $path || ! -s $path;
	print "Processing $path\n" if $self->{verbose};
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

	my $title = $filename;
	$title =~ s/\.jpg$//;
	addImage($filename, $self, $doc, $base, $title);
}

sub addImage {
	my($filename, $self, $doc, $base, $title, $description) = @_;

	my $path = "images/$filename";
	my $exif = new Image::ExifTool;
	open(my $fd, '<:bytes', $path) or die "Can't open file $path";
	binmode($fd);
	my $info = $exif->ImageInfo($fd);
	close $fd;

	my $website = $self->{settings}->{website};

	my $timestamp;
	if(exists $info->{DateTimeOriginal}) {
		$timestamp = parseExifDate($info->{DateTimeOriginal});
	}
	my $latitude;
	my $longitude;
	my $altitude;
	if(!exists $info->{GPSPosition}) {
		print STDERR "No GPS location to add image to.\n";
		return;
	}
	$info->{GPSPosition} =~ /(\d+)\s*deg\s*(?:(\d+)'\s*(?:(\d+(?:\.\d*)?)")?)?\s*([NS]),\s*(\d+)\s*deg\s*(?:(\d+)'\s*(?:(\d+(?:\.\d*)?)")?)?\s*([EW])/;
	#print "Loc: $1° $2' $3\" $4, $5° $6' $7\" $8\n";
	$latitude = $1 + ($2 + $3/60)/60;
	$latitude *= -1 if $4 eq "S";
	$longitude = $5 + ($6 + $7/60)/60;
	$longitude *= -1 if $8 eq "W";

	my $url = "$website/images/$filename";
	my $thumbnailUrl = "$website/images/160/$filename";
	my $html = "";
	my $mark = createPlacemark($doc);
	if(defined($title)) {
		$html .= '<p><b>' . escapeText($self, $title) . '</b></p>';
		addName($doc, $mark, $title);
	}
	if(defined($description)) {
		$html .= '<p>' . escapeText($self, $description) . '</p>';
	}
	$html .= '<a href="'  . escapeText($self, $url) . '">' .
		 '<img src="' . escapeText($self, $thumbnailUrl) . '">' .
		 '</a>';
	addDescription($doc, $mark, $html);
	addRssEntry($self,  $self->{rssFeed},  $title, $url, $html);
	addAtomEntry($self, $self->{atomFeed}, $title, $url, $html);
	addTimestamp($doc, $mark, $timestamp) if defined($timestamp);
	addStyle($doc, $mark, 'photo');
	addPoint($doc, $mark, $latitude, $longitude, $altitude);
	addPlacemark($doc, $base, $mark);
}

my $doc = loadKml($self);
my $xc = loadXPath($self);
my @base = $xc->findnodes("/kml:kml/kml:Document/kml:Folder[kml:name='Unsorted Photos']", $doc);

die "Can't find base for unsorted photos" if @base != 1;


$self->{rssFeed} = loadRssFeed($self);
$self->{atomFeed} = loadAtomFeed($self);
if(!@ARGV) {
	addImageScan($_, $self, $doc, $base[0])
	    foreach glob "$self->{settings}->{cwd}/uploads/*.[jJ][pP][gG] uploads/*.[jJ][pP][eE][gG]";
} else {
	addImageScan($_, $self, $doc, $base[0])
	    foreach @ARGV;
}
saveKml($self, $doc);
saveRssFeed($self, $self->{rssFeed});
saveAtomFeed($self, $self->{atomFeed});
