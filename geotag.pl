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

my $descrText = "";

&scanEntity('$ARGV[0]');
exit 0;
sub scanEntity {
	my($file, $entity, $self, $doc, $base) = @_;

	my $exif = new Image::ExifTool;
	$exif->Options({PrintConv => 0});
	my $info = $exif->ImageInfo($file);
	my $timestamp = 0;
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
	print "Original Comment: $info->{Comment}\n" if exists($info->{Comment});
	my $commentTag = "Photo taken by John Doe!";
	$exifTool->SetNewValue($UserComment, $commentTag);
	print "New Comment: $exifTool->GetDescription($UserComment)\n";
exit 0;

	print "GPSAltitude: $info->{GPSAltitude}\n" if exists($info->{GPSAltitude});
	print "GPSAltitudeRef: $info->{GPSAltitudeRef}\n" if exists($info->{GPSAltitudeRef});
	print "GPSAreaInformation: $info->{GPSAreaInformation}\n" if exists($info->{GPSAreaInformation});
	print "GPSDestBearing: $info->{GPSDestBearing}\n" if exists($info->{GPSDestBearing});
	print "GPSDestBearingRef: $info->{GPSDestBearingRef}\n" if exists($info->{GPSDestBearingRef});
	print "GPSDestDistance: $info->{GPSDestDistance}\n" if exists($info->{GPSDestDistance});
	print "GPSDestDistanceRef: $info->{GPSDestDistanceRef}\n" if exists($info->{GPSDestDistanceRef});
	print "GPSDestLatitude: $info->{GPSDestLatitude}\n" if exists($info->{GPSDestLatitude});
	print "GPSDestLongitude: $info->{GPSDestLongitude}\n" if exists($info->{GPSDestLongitude});
	print "GPSDifferential: $info->{GPSDifferential}\n" if exists($info->{GPSDifferential});
	print "GPSDOP: $info->{GPSDOP}\n" if exists($info->{GPSDOP});
	print "GPSImgDirection: $info->{GPSImgDirection}\n" if exists($info->{GPSImgDirection});
	print "GPSImgDirectionRef: $info->{GPSImgDirectionRef}\n" if exists($info->{GPSImgDirectionRef});
	print "GPSLatitude: $info->{GPSLatitude}\n" if exists($info->{GPSLatitude});
	print "GPSLongitude: $info->{GPSLongitude}\n" if exists($info->{GPSLongitude});
	print "GPSMapDatum: $info->{GPSMapDatum}\n" if exists($info->{GPSMapDatum});
	print "GPSMeasureMode: $info->{GPSMeasureMode}\n" if exists($info->{GPSMeasureMode});
	print "GPSProcessingMethod: $info->{GPSProcessingMethod}\n" if exists($info->{GPSProcessingMethod});
	print "GPSSatellites: $info->{GPSSatellites}\n" if exists($info->{GPSSatellites});
	print "GPSSpeed: $info->{GPSSpeed}\n" if exists($info->{GPSSpeed});
	print "GPSSpeedRef: $info->{GPSSpeedRef}\n" if exists($info->{GPSSpeedRef});
	print "GPSStatus: $info->{GPSStatus}\n" if exists($info->{GPSStatus});
	print "GPSDateTime: $info->{GPSDateTime}\n" if exists($info->{GPSDateTime});
	print "GPSTrack: $info->{GPSTrack}\n" if exists($info->{GPSTrack});
	print "GPSTrackRef: $info->{GPSTrackRef}\n" if exists($info->{GPSTrackRef});
	print "GPSVersionID: $info->{GPSVersionID}\n" if exists($info->{GPSVersionID});
exit 0;

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
	#addName($doc, $mark, $self->{subject});
	#addDescription($doc, $mark, "<p><b>$self->{subject}</b></p><p>$descrText</p><a href=\"http://www.example.org/images/$filename\"><img src=\"http://www.example.org/images/160/$filename\"></a>");
	#addRssEntry($self->{rssFeed}, $self->{subject}, "http://www.example.org/images/$filename", "<p><b>$self->{subject}</b></p><p>$descrText</p><a href=\"http://www.example.org/images/$filename\"><img src=\"http://www.example.org/images/160/$filename\"></a>");
	#addAtomEntry($self->{atomFeed}, $self->{subject}, "http://www.example.org/images/$filename", "<p><b>$self->{subject}</b></p><p>$descrText</p><a href=\"http://www.example.org/images/$filename\"><img src=\"http://www.example.org/images/160/$filename\"></a>");
	#addTimestamp($doc, $mark, $timestamp);
	#addStyle($doc, $mark, 'photo');
	#addPoint($doc, $mark, $latitude, $longitude);
	#addPlacemark($doc, $base, $mark);
#}

sub myToUtf8 {
	my($data, $charset) = @_;
	decode($charset, $data);
}

sub myFromRaw {
	my($data, $charset) = @_;
	decode('us-ascii', $data);
}

umask 0022;
open(my $lockFd, $kmlFile) or die "Can't open kml file for locking";
flock($lockFd, LOCK_EX) or die "Can't establish file lock";

my $parser = new XML::DOM::Parser;
my $doc = $parser->parsefile($kmlFile);
#my @base = $doc->findnodes('/kml/Document');
my @messageBase = $doc->findnodes("/kml/Document/Folder[name='Messages']");
my @photoBase = $doc->findnodes("/kml/Document/Folder[name='Photos']");

die "Can't find base for photos" if @photoBase != 1;
die "Can't find base for messages" if @messageBase != 1;

$parser = new MIME::Parser;
$parser->output_under("/tmp");
binmode STDIN;
my $entity = $parser->parse(\*STDIN);
#$entity->parts(1)->print_body;
#$entity->dump_skeleton;
#$entity->head->decode;
my $self = {};


my $subject = $entity->head->get('Subject');
chomp($subject);
#print "S: '", $subject, "'\n";
$self->{subject} = $subject;


$self->{rssFeed} = loadRssFeed();
$self->{atomFeed} = loadAtomFeed();
$self->{date} = parseDate($entity->head->get('Date'));
$self->{matched} = 0;
#exit 0;
scanEntity($entity, $self, $doc, $photoBase[0]);
if(!$self->{matched}) {
	my $mark = createPlacemark($doc);
	my $entry = closestEntry($self, $self->{date});
	addName($doc, $mark, $self->{subject});
	addDescription($doc, $mark, "<p><b>$self->{subject}</b></p><p>$descrText</p>");
	addStyle($doc, $mark, 'text');
	addPoint($doc, $mark, $entry->{latitude}, $entry->{longitude}, $entry->{altitude});
	addPlacemark($doc, $messageBase[0], $mark);
	my $uuid = `uuidgen`;
	chomp($uuid);
	addRssEntry($self->{rssFeed}, $self->{subject}, "urn:uuid:$uuid", "<p><b>$self->{subject}</b></p><p>$descrText</p>");
	addAtomEntry($self->{atomFeed}, $self->{subject}, "urn:uuid:$uuid", "<p><b>$self->{subject}</b></p><p>$descrText</p>");
}
open(my $outFd, ">$kmlFile") or die "Failed to open KML for writing";
$doc->printToFileHandle($outFd);
#$doc->printToFile($kmlFile);
saveRssFeed($self->{rssFeed});
saveAtomFeed($self->{atomFeed});
