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
use Time::Local;
use XML::DOM;
use XML::DOM::XPath;
use Image::ExifTool;
use Data::Dumper;

require 'common.pl';

if(!defined($ARGV[0])) {
	die "Usage: $0 image.jpg";
}
my $file = $ARGV[0];
my $fileSize = -s $file; 
my $utcTime = 0;

my $self = init();
lockKml($self);

my $exif = new Image::ExifTool;
$exif->Options({PrintConv => 0});
my $info = $exif->ImageInfo($file);
#$exif->ExtractInfo($file);
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
	$timestamp = timegm($sec, $min, $hour, $mday, $mon-1, $year-1900) + $tzoffset;

#Goal below is to set GPSTimeStamp to UTC time on line 112;
	$utcTime = $hour = $tzoffset.":".$min.":".$sec;

}
if($timestamp <= 981119752) {
	die "Image timestamp is out of bounds!"
}
my $entry = closestEntry($self, $timestamp);
print Dumper($entry);
if(abs($entry->{timestamp} - $timestamp) > 600) {
	die "Image timestamp ($timestamp) not close to any GPS entry ($entry->{timestamp}) offset is:  " . abs(($timestamp - $entry->{timestamp})/60) . " minutes.";
}
my $longitude = $entry->{longitude};
my $longitudeRef = "E";
if ($longitude < 0) {
	$longitude *= -1;
	$longitudeRef = "W";
}
my $latitude = $entry->{latitude};
my $latitudeRef = "N";
if ($latitude < 0) {
	$latitude *= -1;
	$latitudeRef = "S";
}

my $altitude = $entry->{altitude};
my $altitudeRef = "Above Sea Level";
if ($altitude < 0) {
	$altitude *= -1;
	$altitudeRef = "Below Sea Level";
}

#Remove Thumbnail:
$exifTool->SetNewValue('IFD1:*');

#Mangle Photo using jpegtran:
	system("jpegtran -optimize -progressive -copy all -v $file");

#Rotate image to match sensor data & reset EXIF rotation option:
#Obviously rewrite in perl, we can't do a system(); on an entire script!  (;
	for i
	do
	 case `$exifTool->GetValue('Orientation')` in
	 1) transform="";;
	 2) transform="-flip horizontal";;
	 3) transform="-rotate 180";;
	 4) transform="-flip vertical";;
	 5) transform="-transpose";;
	 6) transform="-rotate 90";;
	 7) transform="-transverse";;
	 8) transform="-rotate 270";;
	 *) transform="";;
	 esac
	 if test -n "$transform"; then
	  echo Executing: jpegtran -copy all $transform $i
	  jpegtran -copy all $transform "$i" > tempfile
	  if test $? -ne 0; then
	   echo Error while transforming $i - skipped.
	  else
	   rm "$i"
	   mv tempfile "$i"
#	   $exifTool->SetNewValue('Orientation',"1");
	   $exifTool->SetNewValue('Orientation#' => 1);
	  fi
	 fi
	done
	

#Set GeoTagged EXIF data:
$exif->SetNewValue('UserComment', 'Original Filename: '.$file.', Original Filesize: '.$fileSize.'.');
$exif->SetNewValue('Copyright', 'Copyright © 2010 John Doe, All Rights Reserved');

$exif->SetNewValue('GPSLatitudeRef', $latitudeRef);
$exif->SetNewValue('GPSLatitude', $latitude);
$exif->SetNewValue('GPSLongitudeRef', $longitudeRef);
$exif->SetNewValue('GPSLongitude', $longitude);
$exif->SetNewValue('GPSAltitudeRef', $altitudeRef);
$exif->SetNewValue('GPSAltitude', $altitude);
$exif->SetNewValue('GPSTimeStamp', $utcTime);

my $success = $exif ->WriteInfo($file);
$info = $exif->ImageInfo($file);
print "New UserComment: $info->{UserComment}\n" if exists($info->{UserComment});;
print "New Copyright: $info->{Copyright}\n" if exists($info->{Copyright});;
print "New GPSLatitude: $info->{GPSLatitude}\n" if exists($info->{GPSLatitude});;
print "New GPSLongitude: $info->{GPSLongitude}\n" if exists($info->{GPSLongitude});;
print "New GPSAltitude: $info->{GPSAltitude}\n" if exists($info->{GPSAltitude});;
print "New GPSAltitudeRef: $info->{GPSAltitudeRef}\n" if exists($info->{GPSAltitudeRef});;


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
